#!/bin/sh
#
# Copyright (C) 2017 OpenWrt.org
#
# Generate an Amlogic eMMC disk image with bootloader, resource,
# boot (FAT32), and rootfs (ext4) partitions.

[ $# -eq 5 ] || {
    echo "SYNTAX: $0 <file> <bootfs image> <rootfs image> <bootfs size> <rootfs size>"
    exit 1
}

OUTPUT="$1"
BOOTFS="$2"
ROOTFS="$3"
BOOTFSSIZE="$4"
ROOTFSSIZE="$5"

# If the rootfs image is actually larger than the configured size
# (e.g. pre-resized offline), use the real size to avoid a mismatch
# between the partition table and the filesystem.
if [ -f "$ROOTFS" ]; then
    ROOTFS_REAL_SIZE=$(wc -c < "$ROOTFS" | tr -d ' ')
    ROOTFS_REAL_SIZE_MB=$((ROOTFS_REAL_SIZE / 1024 / 1024))
    if [ "$ROOTFS_REAL_SIZE_MB" -gt "$ROOTFSSIZE" ]; then
        ROOTFSSIZE="$ROOTFS_REAL_SIZE_MB"
    fi
fi

head=4
sect=2048

# Amlogic OneCloud eMMC layout (matches USB Burning Tool layout):
# - sector 1:     bootloader (Amlogic format)
# - 4MB:          MPT partition (Amlogic manufacturing table, not included)
# - 12MB:         resource partition
# - 16MB:         boot partition (FAT)
# - after boot:   rootfs partition (ext4)
set -- $(ptgen -o $OUTPUT -h $head -s $sect -l 32768 -t c -p ${BOOTFSSIZE}M -t 83 -p ${ROOTFSSIZE}M)

BOOTOFFSET="$(($1 / 512))"
BOOTSIZE="$(($2 / 512))"
ROOTFSOFFSET="$(($3 / 512))"
ROOTFSSIZE="$(($4 / 512))"

dd bs=512 if="$BOOTFS" of="$OUTPUT" seek="$BOOTOFFSET" conv=notrunc
dd bs=512 if="$ROOTFS" of="$OUTPUT" seek="$ROOTFSOFFSET" conv=notrunc

# === Write bootloader and resource ===
# Extract bootloader (4.bootloader.PARTITION) and resource (6.resource.PARTITION)
# from u-boot-onecloud.img.  bootloader goes to sector 1, resource to sector
# 24576 (12MB offset, matching the Amlogic layout).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UBOOT_IMG="$SCRIPT_DIR/u-boot-onecloud.img"
AMLIMG="$SCRIPT_DIR/AmlImg"
EXTRACT_DIR=""

if [ -f "$UBOOT_IMG" ] && [ -x "$AMLIMG" ]; then
    EXTRACT_DIR="$(mktemp -d)"
    if "$AMLIMG" unpack "$UBOOT_IMG" "$EXTRACT_DIR/" >/dev/null 2>&1; then
        # 1. Write bootloader to sector 1 (Amlogic BL1 format)
        if [ -f "$EXTRACT_DIR/4.bootloader.PARTITION" ]; then
            dd bs=512 if="$EXTRACT_DIR/4.bootloader.PARTITION" of="$OUTPUT" seek=1 conv=notrunc 2>/dev/null
        fi
        # 2. Write resource partition to sector 24576 (12MB offset)
        if [ -f "$EXTRACT_DIR/6.resource.PARTITION" ]; then
            dd bs=512 if="$EXTRACT_DIR/6.resource.PARTITION" of="$OUTPUT" seek=24576 conv=notrunc 2>/dev/null
        fi
    fi
    rm -rf "$EXTRACT_DIR"
elif [ -f "$SCRIPT_DIR/bootloader.bin" ]; then
    # Backward compatibility: use separate bootloader.bin
    dd bs=512 if="$SCRIPT_DIR/bootloader.bin" of="$OUTPUT" seek=1 conv=notrunc
    [ -f "$SCRIPT_DIR/resource.bin" ] && dd bs=512 if="$SCRIPT_DIR/resource.bin" of="$OUTPUT" seek=24576 conv=notrunc
fi
