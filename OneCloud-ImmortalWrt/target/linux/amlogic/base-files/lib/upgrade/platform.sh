REQUIRE_IMAGE_METADATA=0

# Find the eMMC block device.
# On OneCloud, eMMC is usually mmcblk1 when an SD card is present (mmcblk0).
# We distinguish eMMC from SD card via /sys/block/<dev>/device/type:
#   eMMC -> "MMC", SD card -> "SD"
find_emmc_device() {
    local dev

    # First pass: prefer a device that reports itself as MMC (eMMC)
    for dev in mmcblk1 mmcblk0; do
        if [ -b "/dev/$dev" ] && [ -d "/sys/block/$dev/device" ]; then
            local type=$(cat "/sys/block/$dev/device/type" 2>/dev/null)
            if [ "$type" = "MMC" ]; then
                echo "$dev"
                return 0
            fi
        fi
    done

    # Second pass: fall back to the first mmc device that has partitions
    for dev in mmcblk1 mmcblk0; do
        if [ -b "/dev/$dev" ] && ls "/dev/${dev}p"* >/dev/null 2>&1; then
            echo "$dev"
            return 0
        fi
    done

    return 1
}

platform_check_image() {
    local magic

    # Verify MBR signature (0x55AA) for eMMC disk image
    magic=$(get_image "$1" | dd bs=1 count=2 skip=510 2>/dev/null | hexdump -v -n 2 -e '1/1 "%02x"')
    [ "$magic" = "55aa" ] && return 0

    # Also accept standard sysupgrade tarball
    magic=$(get_image "$1" | tar -tzf - 2>/dev/null | head -1)
    [ -n "$magic" ] && return 0

    echo "Invalid image format. Expected eMMC disk image (MBR) or sysupgrade tarball."
    return 1
}

platform_do_upgrade() {
    local emmc_dev
    local image_file="/tmp/sysupgrade-image.img"
    local start_lba num_sectors
    local backup_file
    local boot_part

    echo "platform_do_upgrade: Starting upgrade..."

    # Find eMMC device
    emmc_dev=$(find_emmc_device)
    if [ -z "$emmc_dev" ]; then
        echo "ERROR: Cannot find eMMC device for upgrade."
        return 1
    fi
    echo "platform_do_upgrade: eMMC device: /dev/$emmc_dev"

    # Find config backup file
    backup_file=""
    for candidate in "$UPGRADE_BACKUP" "/tmp/sysupgrade.tgz" "/tmp/root/tmp/sysupgrade.tgz"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            backup_file="$candidate"
            echo "platform_do_upgrade: Found config backup: $backup_file ($(wc -c < "$candidate" 2>/dev/null) bytes)"
            break
        fi
    done

    # Save image to temporary file
    echo "platform_do_upgrade: Saving image to $image_file ..."
    get_image "$1" > "$image_file" 2>/dev/null
    if [ ! -f "$image_file" ] || [ ! -s "$image_file" ]; then
        echo "ERROR: Failed to save image to $image_file"
        return 1
    fi
    echo "platform_do_upgrade: Image size: $(wc -c < "$image_file") bytes"

    # Read MBR partition table to find rootfs partition (p2).
    # Partition entry 2 starts at offset 0x1BE + 16 = 0x1CE (462).
    # Starting LBA:  offset 462 + 8  = 470 (4 bytes, little-endian)
    # Sector count:  offset 462 + 12 = 474 (4 bytes, little-endian)
    echo "platform_do_upgrade: Reading MBR partition table..."
    start_lba=$(dd if="$image_file" bs=1 skip=470 count=4 2>/dev/null | hexdump -e '1/4 "%d"' 2>/dev/null)
    num_sectors=$(dd if="$image_file" bs=1 skip=474 count=4 2>/dev/null | hexdump -e '1/4 "%d"' 2>/dev/null)

    if [ -z "$start_lba" ] || [ -z "$num_sectors" ] || [ "$start_lba" = "0" ] || [ "$num_sectors" = "0" ]; then
        echo "WARNING: Failed to parse MBR, falling back to full disk write"
        sync
        dd if="$image_file" of="/dev/$emmc_dev" bs=4M conv=fsync 2>/dev/null
        sync
        rm -f "$image_file"
        echo "platform_do_upgrade: Full disk write complete."
    else
        echo "platform_do_upgrade: Rootfs (p2): start=$start_lba, sectors=$num_sectors ($((num_sectors/2048))MB)"

        # Write only rootfs partition (p2), preserving boot partition
        echo "platform_do_upgrade: Writing rootfs to /dev/${emmc_dev}p2 ..."
        sync
        dd if="$image_file" of="/dev/${emmc_dev}p2" bs=512 skip="$start_lba" count="$num_sectors" conv=fsync 2>/dev/null
        local dd_ret=$?
        sync
        rm -f "$image_file"
        echo "platform_do_upgrade: dd returned: $dd_ret"

        if [ $dd_ret -ne 0 ]; then
            echo "ERROR: Failed to write rootfs partition"
            return 1
        fi
        echo "platform_do_upgrade: Rootfs write complete."
    fi

    # Copy config backup to boot partition.
    # preinit's 79_move_config looks for /mnt/sysupgrade.tgz, moves it to /,
    # and 80_mount_root extracts it.
    if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
        echo "platform_do_upgrade: Copying config backup to boot partition..."
        boot_part="/dev/${emmc_dev}p1"
        if [ -b "$boot_part" ]; then
            mkdir -p /mnt
            if mount -t vfat -o rw,noatime "$boot_part" /mnt 2>/dev/null || mount -o rw,noatime "$boot_part" /mnt 2>/dev/null; then
                cp -af "$backup_file" "/mnt/sysupgrade.tgz" 2>/dev/null
                if [ $? -eq 0 ] && [ -f "/mnt/sysupgrade.tgz" ]; then
                    echo "platform_do_upgrade: Config copied to /mnt/sysupgrade.tgz ($(wc -c < "/mnt/sysupgrade.tgz" 2>/dev/null) bytes)"
                else
                    echo "platform_do_upgrade: WARNING: Failed to copy config to boot partition"
                fi
                sync
                umount /mnt 2>/dev/null
            else
                echo "platform_do_upgrade: WARNING: Failed to mount boot partition $boot_part"
            fi
        else
            echo "platform_do_upgrade: WARNING: Boot partition $boot_part not found"
        fi
    else
        echo "platform_do_upgrade: WARNING: No config backup found, config will not be preserved"
    fi

    echo "platform_do_upgrade: Upgrade complete."
    return 0
}

# platform_copy_config is kept for compatibility; actual work is done in platform_do_upgrade
platform_copy_config() {
    return 0
}
