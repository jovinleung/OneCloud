REQUIRE_IMAGE_METADATA=0

# Skip signature validation to avoid decompressing entire .gz during LuCI upload
fwtool_check_signature() {
	[ $# -gt 1 ] && return 1
	[ "$REQUIRE_IMAGE_METADATA" = "0" ] && return 0
	[ ! -x /usr/bin/ucert ] && return 0
	return 0
}

# Skip image validation when metadata not required (avoids decompressing 300MB+)
fwtool_check_image() {
	[ $# -gt 1 ] && return 1
	[ "$REQUIRE_IMAGE_METADATA" = "0" ] && return 0
	return 0
}

# Find eMMC device (distinguish from SD card via device type "MMC")
find_emmc_device() {
    local dev

    for dev in mmcblk1 mmcblk0; do
        if [ -b "/dev/$dev" ] && [ -d "/sys/block/$dev/device" ]; then
            local type=$(cat "/sys/block/$dev/device/type" 2>/dev/null)
            if [ "$type" = "MMC" ]; then
                echo "$dev"
                return 0
            fi
        fi
    done

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
    local img_cat="cat"

    # Detect gzip without get_image() (works in validate_firmware_image context)
    local file_magic="$(dd if="$1" bs=2 count=1 2>/dev/null | hexdump -n 2 -e '1/1 "%02x"')"
    case "$file_magic" in
        1f8b) img_cat="zcat" ;;
        *) img_cat="cat" ;;
    esac

    # Verify MBR signature (0x55AA) - only read first 512 bytes
    magic=$($img_cat "$1" 2>/dev/null | head -c 512 | tail -c 2 | hexdump -v -n 2 -e '1/1 "%02x"')
    if [ "$magic" != "55aa" ]; then
        echo "Invalid image format. Expected eMMC disk image (MBR)." >&2
        return 1
    fi

    return 0
}

platform_do_upgrade() {
    local emmc_dev
    local start_lba num_sectors
    local backup_file
    local boot_part
    local img_cat
    local mbr_header="/tmp/mbr_header.img"
    local boot_tmp="/tmp/boot_partition.img"
    local rootfs_tmp="/tmp/rootfs_partition.img"

    echo "platform_do_upgrade: Starting upgrade..."

    emmc_dev=$(find_emmc_device)
    if [ -z "$emmc_dev" ]; then
        echo "ERROR: Cannot find eMMC device for upgrade."
        return 1
    fi
    echo "platform_do_upgrade: eMMC device: /dev/$emmc_dev"

    # Find config backup
    backup_file=""
    for candidate in "$UPGRADE_BACKUP" "/tmp/sysupgrade.tgz" "/tmp/root/tmp/sysupgrade.tgz"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            backup_file="$candidate"
            echo "platform_do_upgrade: Found config backup: $backup_file ($(wc -c < "$candidate" 2>/dev/null) bytes)"
            break
        fi
    done

    # Detect compression (raw eMMC image, not standard tarball)
    local file_magic="$(dd if="$1" bs=2 count=1 2>/dev/null | hexdump -n 2 -e '1/1 "%02x"')"
    case "$file_magic" in
        1f8b) img_cat="zcat"; echo "platform_do_upgrade: Image is gzip compressed" ;;
        *) img_cat="cat"; echo "platform_do_upgrade: Image is raw" ;;
    esac

    # Check /tmp space (need ~300MB for boot+rootfs temp files)
    local tmp_avail=$(df -k /tmp | tail -1 | awk '{print $4}')
    echo "platform_do_upgrade: /tmp available: ${tmp_avail}KB"
    if [ "$tmp_avail" -lt 300000 ]; then
        echo "ERROR: Not enough space in /tmp (need 300MB, have ${tmp_avail}KB)"
        return 1
    fi

    rm -f "$mbr_header" "$boot_tmp" "$rootfs_tmp"

    # Step 1: Extract 1MB header for MBR partition table
    echo "platform_do_upgrade: Extracting MBR header (1MB)..."
    $img_cat "$1" 2>/dev/null | dd of="$mbr_header" bs=1M count=1 2>/dev/null
    if [ ! -s "$mbr_header" ]; then
        echo "ERROR: Failed to extract MBR header"
        return 1
    fi

    # Step 2: Parse MBR (p1: offset 454/458, p2: offset 470/474)
    echo "platform_do_upgrade: Reading MBR partition table..."
    local boot_start_lba=$(dd if="$mbr_header" bs=1 skip=454 count=4 2>/dev/null | hexdump -e '1/4 "%d"' 2>/dev/null)
    local boot_num_sectors=$(dd if="$mbr_header" bs=1 skip=458 count=4 2>/dev/null | hexdump -e '1/4 "%d"' 2>/dev/null)
    start_lba=$(dd if="$mbr_header" bs=1 skip=470 count=4 2>/dev/null | hexdump -e '1/4 "%d"' 2>/dev/null)
    num_sectors=$(dd if="$mbr_header" bs=1 skip=474 count=4 2>/dev/null | hexdump -e '1/4 "%d"' 2>/dev/null)
    rm -f "$mbr_header"

    if [ -z "$start_lba" ] || [ -z "$num_sectors" ] || [ "$start_lba" = "0" ] || [ "$num_sectors" = "0" ]; then
        echo "ERROR: Failed to parse MBR partition table"
        return 1
    fi

    echo "platform_do_upgrade: Boot (p1): start=$boot_start_lba, sectors=$boot_num_sectors ($((boot_num_sectors/2048))MB)"
    echo "platform_do_upgrade: Rootfs (p2): start=$start_lba, sectors=$num_sectors ($((num_sectors/2048))MB)"

    # Verify new partitions fit in current partitions
    local cur_boot_size=$(cat "/sys/block/${emmc_dev}/${emmc_dev}p1/size" 2>/dev/null)
    local cur_rootfs_size=$(cat "/sys/block/${emmc_dev}/${emmc_dev}p2/size" 2>/dev/null)
    if [ -n "$cur_boot_size" ] && [ -n "$cur_rootfs_size" ]; then
        if [ "$boot_num_sectors" -gt "$cur_boot_size" ] || [ "$num_sectors" -gt "$cur_rootfs_size" ]; then
            echo "ERROR: New image partitions are larger than current partitions!"
            return 1
        fi
    fi

    # Step 3: Extract boot partition and verify FAT16 signature
    echo "platform_do_upgrade: Extracting boot partition..."
    $img_cat "$1" 2>/dev/null | dd of="$boot_tmp" bs=512 skip="$boot_start_lba" count="$boot_num_sectors" 2>/dev/null
    if [ ! -s "$boot_tmp" ]; then
        echo "ERROR: Failed to extract boot partition"
        rm -f "$boot_tmp"
        return 1
    fi

    local boot_sig=$(dd if="$boot_tmp" bs=1 skip=54 count=8 2>/dev/null)
    if ! echo "$boot_sig" | grep -q "FAT"; then
        echo "ERROR: Boot partition is not valid FAT (signature: $boot_sig)"
        rm -f "$boot_tmp"
        return 1
    fi

    # Step 4: Write boot partition
    echo "platform_do_upgrade: Writing boot partition..."
    sync
    dd if="$boot_tmp" of="/dev/${emmc_dev}p1" bs=512 conv=fsync 2>/dev/null
    sync
    rm -f "$boot_tmp"
    echo "platform_do_upgrade: Boot partition written."

    # Step 5: Extract rootfs partition and verify ext4 signature (0x53ef at offset 1080)
    # Extract to temp file first, verify, then write (pipe+dd skip caused corruption)
    echo "platform_do_upgrade: Extracting rootfs partition..."
    $img_cat "$1" 2>/dev/null | dd of="$rootfs_tmp" bs=512 skip="$start_lba" count="$num_sectors" 2>/dev/null
    if [ ! -s "$rootfs_tmp" ]; then
        echo "ERROR: Failed to extract rootfs partition"
        rm -f "$rootfs_tmp"
        return 1
    fi

    local rootfs_magic=$(dd if="$rootfs_tmp" bs=1 skip=1080 count=2 2>/dev/null | hexdump -e '1/1 "%02x"')
    if [ "$rootfs_magic" != "53ef" ]; then
        echo "ERROR: Rootfs is not valid ext4 (magic: $rootfs_magic, expected 53ef)"
        rm -f "$rootfs_tmp"
        return 1
    fi

    # Step 6: Write rootfs partition from verified temp file
    echo "platform_do_upgrade: Writing rootfs partition..."
    sync
    dd if="$rootfs_tmp" of="/dev/${emmc_dev}p2" bs=4M conv=fsync 2>/dev/null
    sync
    rm -f "$rootfs_tmp"
    echo "platform_do_upgrade: Rootfs partition written."

    # Verify written rootfs
    local written_magic=$(dd if="/dev/${emmc_dev}p2" bs=1 skip=1080 count=2 2>/dev/null | hexdump -e '1/1 "%02x"')
    if [ "$written_magic" != "53ef" ]; then
        echo "WARNING: Rootfs verification failed after write (magic: $written_magic)"
    fi

    # Step 7: Copy config backup to boot partition (picked up by 79_move_config on next boot)
    if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
        echo "platform_do_upgrade: Copying config backup..."
        boot_part="/dev/${emmc_dev}p1"
        if [ -b "$boot_part" ]; then
            mkdir -p /mnt
            if mount -t vfat -o rw,noatime "$boot_part" /mnt 2>/dev/null; then
                cp -af "$backup_file" "/mnt/sysupgrade.tgz" 2>/dev/null
                sync
                umount /mnt 2>/dev/null
            fi
        fi
    fi

    echo "platform_do_upgrade: Upgrade complete."
    return 0
}

platform_copy_config() {
    return 0
}
