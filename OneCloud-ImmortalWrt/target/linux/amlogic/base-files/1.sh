#!/bin/sh
# OneCloud eMMC rootfs online resize script
# Usage: /1.sh [target_size_MB]
# If no size is specified, resize to the end of eMMC (recommended).

# Auto-detect eMMC device (may be mmcblk0 or mmcblk1).
# /sys/block/<dev>/device/type returns "MMC" for eMMC, "SD" for SD card.
find_emmc_device() {
    local dev

    # Prefer a device that reports itself as MMC (eMMC)
    for dev in mmcblk1 mmcblk0; do
        if [ -b "/dev/$dev" ] && [ -d "/sys/block/$dev/device" ]; then
            local type=$(cat "/sys/block/$dev/device/type" 2>/dev/null)
            if [ "$type" = "MMC" ]; then
                echo "$dev"
                return 0
            fi
        fi
    done

    # Fallback: first mmc device with partitions
    for dev in mmcblk1 mmcblk0; do
        if [ -b "/dev/$dev" ] && ls "/dev/${dev}p"* >/dev/null 2>&1; then
            echo "$dev"
            return 0
        fi
    done
    return 1
}

EMMC_DEV_NAME=$(find_emmc_device)
if [ -z "$EMMC_DEV_NAME" ]; then
    echo "ERROR: Cannot auto-detect eMMC device"
    exit 1
fi
EMMC_DEV="/dev/$EMMC_DEV_NAME"
ROOTFS_PART="${EMMC_DEV}p2"
echo "Detected eMMC device: $EMMC_DEV"

# Check root privileges
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: Must be run as root"
    exit 1
fi

# Verify devices
if [ ! -b "$EMMC_DEV" ]; then
    echo "ERROR: eMMC device not found: $EMMC_DEV"
    exit 1
fi

if [ ! -b "$ROOTFS_PART" ]; then
    echo "ERROR: rootfs partition not found: $ROOTFS_PART"
    exit 1
fi

echo "=========================================="
echo "  OneCloud eMMC rootfs resize tool"
echo "=========================================="
echo ""

# Show current partition info
echo "=== Current partition layout ==="
parted -s "$EMMC_DEV" unit MB print 2>/dev/null
echo ""

# Show current filesystem usage
echo "=== Current rootfs usage ==="
df -h "$ROOTFS_PART"
echo ""

# Get rootfs partition start position (MB)
ROOTFS_START=$(parted -s "$EMMC_DEV" unit MB print 2>/dev/null | grep "^ 2 " | awk '{print $2}' | sed 's/MB//')
if [ -z "$ROOTFS_START" ]; then
    echo "ERROR: Cannot determine rootfs partition start position"
    exit 1
fi

echo "rootfs partition start: ${ROOTFS_START}MB"

# Determine target size
if [ -n "$1" ]; then
    TARGET_SIZE="$1"
    echo "Specified target size: ${TARGET_SIZE}MB"
else
    # Resize to end of eMMC (minus 1MB for alignment)
    EMMC_SIZE_MB=$(cat /sys/block/$EMMC_DEV_NAME/size 2>/dev/null | awk '{print int($1 * 512 / 1024 / 1024)}')
    if [ -z "$EMMC_SIZE_MB" ]; then
        EMMC_SIZE_MB=7400
    fi
    TARGET_SIZE=$((EMMC_SIZE_MB - 1))
    echo "eMMC total size: ${EMMC_SIZE_MB}MB"
    echo "Target size: ${TARGET_SIZE}MB (resize to end of eMMC)"
fi

# Safety check: target must be larger than current
CURRENT_SIZE_MB=$(blockdev --getsize64 "$ROOTFS_PART" 2>/dev/null | awk '{print int($1 / 1024 / 1024)}')
if [ -z "$CURRENT_SIZE_MB" ]; then
    CURRENT_SIZE_MB=$(cat /sys/block/${EMMC_DEV_NAME}p2/size 2>/dev/null | awk '{print int($1 * 512 / 1024 / 1024)}')
fi

if [ -n "$CURRENT_SIZE_MB" ] && [ "$TARGET_SIZE" -le "$CURRENT_SIZE_MB" ]; then
    echo "ERROR: Target size (${TARGET_SIZE}MB) must be larger than current size (${CURRENT_SIZE_MB}MB)"
    exit 1
fi

echo ""
echo "About to perform:"
echo "  1. Extend rootfs partition to ${TARGET_SIZE}MB"
echo "  2. Re-read partition table"
echo "  3. Online resize ext4 filesystem"
echo ""
echo "Note: This operation runs online, no reboot required, no data loss."
echo "However, backing up important data is recommended."
echo ""

# Wait for confirmation (skip in non-interactive mode)
if [ -t 0 ]; then
    printf "Continue? [y/N] "
    read -r CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Step 1: Extend partition
echo ""
echo "=== [1/3] Extending rootfs partition ==="
parted -s "$EMMC_DEV" resizepart 2 "${TARGET_SIZE}MB" 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to extend partition"
    exit 1
fi
echo "Partition extended to ${TARGET_SIZE}MB"

# Step 2: Re-read partition table
echo ""
echo "=== [2/3] Re-reading partition table ==="
partx -u "$EMMC_DEV" 2>/dev/null
sleep 2

# Verify partition table updated
NEW_SIZE=$(cat /sys/block/${EMMC_DEV_NAME}p2/size 2>/dev/null | awk '{print int($1 * 512 / 1024 / 1024)}')
echo "New partition size: ${NEW_SIZE}MB"
echo "Partition table updated"

# Step 3: Resize filesystem
echo ""
echo "=== [3/3] Resizing ext4 filesystem ==="
resize2fs "$ROOTFS_PART" 2>&1
if [ $? -ne 0 ]; then
    echo "WARNING: resize2fs returned non-zero, trying forced resize..."
    resize2fs -f "$ROOTFS_PART" 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to resize filesystem"
        echo "You can try rebooting and running this script again"
        exit 1
    fi
fi
echo "Filesystem resized"

# Show results
echo ""
echo "=========================================="
echo "  Resize complete!"
echo "=========================================="
echo ""
echo "=== Final disk usage ==="
df -h | grep -E 'root|mmcblk'
echo ""
echo "=== Filesystem details ==="
tune2fs -l "$ROOTFS_PART" 2>/dev/null | grep -E 'Block count|Block size|Free blocks|Filesystem state' | while read line; do
    echo "  $line"
done

exit 0
