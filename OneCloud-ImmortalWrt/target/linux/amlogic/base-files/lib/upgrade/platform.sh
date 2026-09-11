REQUIRE_IMAGE_METADATA=0

# Ensure extra binaries needed by platform_do_upgrade are copied to the
# stage2 ramfs environment. The default list in /lib/upgrade/stage2 includes
# tail but NOT head; we use "tail -c +N | head -c N" for byte-accurate
# partition extraction, so head must be explicitly included. df is used for
# the /tmp space check.
RAMFS_COPY_BIN="head df"

# Skip validation (custom eMMC image format, avoids decompressing 300MB+ during LuCI upload)
fwtool_check_signature() {
	[ $# -gt 1 ] && return 1
	return 0
}

fwtool_check_image() {
	[ $# -gt 1 ] && return 1
	return 0
}

# Detect gzip compression and return appropriate decompression command
detect_img_cat() {
	local magic
	magic=$(dd if="$1" bs=2 count=1 2>/dev/null | hexdump -n 2 -e '1/1 "%02x"')
	[ "$magic" = "1f8b" ] && echo "zcat" || echo "cat"
}

# Find eMMC device (prefer type=MMC; fall back to first mmcblk with partitions)
find_emmc_device() {
	local dev fallback=""
	for dev in mmcblk1 mmcblk0; do
		[ -b "/dev/$dev" ] || continue
		[ "$(cat /sys/block/$dev/device/type 2>/dev/null)" = "MMC" ] && { echo "$dev"; return 0; }
		[ -z "$fallback" ] && ls "/dev/${dev}p"* >/dev/null 2>&1 && fallback="$dev"
	done
	[ -n "$fallback" ] && echo "$fallback" && return 0
	return 1
}

platform_check_image() {
	local img_cat magic
	img_cat=$(detect_img_cat "$1")
	# Verify MBR signature (0x55AA at offset 510)
	magic=$($img_cat "$1" 2>/dev/null | dd bs=1 skip=510 count=2 2>/dev/null | hexdump -v -n 2 -e '1/1 "%02x"')
	[ "$magic" = "55aa" ] || { echo "Invalid image format. Expected eMMC disk image (MBR)." >&2; return 1; }
	return 0
}

# Rootfs-only sysupgrade: flash p2 only, preserve boot (p1) with kernel/dtb/boot.scr
platform_do_upgrade() {
	local emmc_dev start_lba num_sectors backup_file img_cat
	local mbr_header="/tmp/mbr_header.img"
	local rootfs_tmp="/tmp/rootfs_partition.img"

	echo "platform_do_upgrade: Starting upgrade (rootfs only, boot preserved)..."

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

	img_cat=$(detect_img_cat "$1")
	echo "platform_do_upgrade: Image is $([ "$img_cat" = "zcat" ] && echo gzip || echo raw)"

	rm -f "$mbr_header" "$rootfs_tmp"

	# Step 1: Extract 1MB header for MBR partition table
	echo "platform_do_upgrade: Extracting MBR header (1MB)..."
	$img_cat "$1" 2>/dev/null | dd of="$mbr_header" bs=1M count=1 2>/dev/null
	if [ ! -s "$mbr_header" ]; then
		echo "ERROR: Failed to extract MBR header"
		return 1
	fi

	# Step 2: Parse MBR for rootfs (p2: start at offset 470, size at 474)
	echo "platform_do_upgrade: Reading MBR partition table..."
	start_lba=$(dd if="$mbr_header" bs=1 skip=470 count=4 2>/dev/null | hexdump -e '1/4 "%d"' 2>/dev/null)
	num_sectors=$(dd if="$mbr_header" bs=1 skip=474 count=4 2>/dev/null | hexdump -e '1/4 "%d"' 2>/dev/null)
	rm -f "$mbr_header"

	if [ -z "$start_lba" ] || [ -z "$num_sectors" ] || [ "$start_lba" = "0" ] || [ "$num_sectors" = "0" ]; then
		echo "ERROR: Failed to parse MBR partition table"
		return 1
	fi

	echo "platform_do_upgrade: Rootfs (p2): start=$start_lba, sectors=$num_sectors ($((num_sectors/2048))MB)"
	echo "platform_do_upgrade: Boot (p1): preserved (not flashed)"

	# Check /tmp space based on actual rootfs partition size + 16MB margin
	local rootfs_kb=$((num_sectors / 2))
	local need_kb=$((rootfs_kb + 16384))
	local tmp_avail=$(df -k /tmp | tail -1 | awk '{print $4}')
	echo "platform_do_upgrade: /tmp available: ${tmp_avail}KB, need: ${need_kb}KB"
	if [ "$tmp_avail" -lt "$need_kb" ]; then
		echo "ERROR: Not enough space in /tmp (need $((need_kb/1024))MB, have $((tmp_avail/1024))MB)"
		return 1
	fi

	# Step 3: Stream-extract rootfs partition directly from image
	# (avoids storing the full raw disk image in /tmp; only rootfs_tmp is buffered)
	# tail -c +N | head -c N is byte-accurate on pipes (unlike dd skip which can
	# misalign on short reads)
	echo "platform_do_upgrade: Extracting rootfs partition (streaming)..."
	local skip_bytes=$((start_lba * 512))
	local rootfs_bytes=$((num_sectors * 512))
	$img_cat "$1" 2>/dev/null | tail -c +$((skip_bytes + 1)) | head -c "$rootfs_bytes" > "$rootfs_tmp"
	if [ ! -s "$rootfs_tmp" ]; then
		echo "ERROR: Failed to extract rootfs partition"
		rm -f "$rootfs_tmp"
		return 1
	fi
	echo "platform_do_upgrade: Extracted rootfs size: $(wc -c < "$rootfs_tmp") bytes"

	local rootfs_magic=$(dd if="$rootfs_tmp" bs=1 skip=1080 count=2 2>/dev/null | hexdump -e '1/1 "%02x"')
	if [ "$rootfs_magic" != "53ef" ]; then
		echo "ERROR: Rootfs is not valid ext4 (magic: $rootfs_magic, expected 53ef)"
		rm -f "$rootfs_tmp"
		return 1
	fi

	# Step 4: Write rootfs partition (p2 only)
	echo "platform_do_upgrade: Writing rootfs partition (p2 only)..."
	sync
	dd if="$rootfs_tmp" of="/dev/${emmc_dev}p2" bs=4M conv=fsync 2>/dev/null
	sync
	rm -f "$rootfs_tmp"
	echo "platform_do_upgrade: Rootfs partition written."

	# Verify written rootfs
	local written_magic=$(dd if="/dev/${emmc_dev}p2" bs=1 skip=1080 count=2 2>/dev/null | hexdump -e '1/1 "%02x"')
	if [ "$written_magic" != "53ef" ]; then
		echo "WARNING: Rootfs verification failed after write (magic: $written_magic)"
	else
		echo "platform_do_upgrade: Rootfs verification passed."
	fi

	# Step 5: Copy config backup to boot partition (p1, not flashed in rootfs-only mode)
	if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
		echo "platform_do_upgrade: Copying config backup to boot partition (p1)..."
		local boot_part="/dev/${emmc_dev}p1"
		if [ -b "$boot_part" ]; then
			mkdir -p /mnt
			if mount -t vfat -o rw,noatime "$boot_part" /mnt 2>/dev/null; then
				cp -af "$backup_file" "/mnt/sysupgrade.tgz" 2>/dev/null
				sync
				umount /mnt 2>/dev/null
				echo "platform_do_upgrade: Config saved to boot partition (p1)"
			else
				echo "WARNING: Failed to mount boot partition, config backup not saved"
			fi
		fi
	fi

	echo "platform_do_upgrade: Upgrade complete (rootfs only, boot preserved)."
	return 0
}

platform_copy_config() {
	return 0
}
