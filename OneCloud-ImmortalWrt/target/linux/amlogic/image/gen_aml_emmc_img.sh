#!/bin/sh
#
# Copyright (C) 2017 OpenWrt.org
#
# Generate Amlogic eMMC disk image:
#   bootloader at sector 1, resource at 12MB, MBR: boot(FAT) + rootfs(ext4)

[ $# -eq 5 ] || {
    echo "SYNTAX: $0 <file> <bootfs image> <rootfs image> <bootfs size> <rootfs size>"
    exit 1
}

OUTPUT="$1"
BOOTFS="$2"
ROOTFS="$3"
BOOTFSSIZE="$4"
ROOTFSSIZE="$5"

# Use real rootfs size if larger
if [ -f "$ROOTFS" ]; then
    ROOTFS_REAL_SIZE=$(wc -c < "$ROOTFS" | tr -d ' ')
    ROOTFS_REAL_SIZE_MB=$((ROOTFS_REAL_SIZE / 1024 / 1024))
    [ "$ROOTFS_REAL_SIZE_MB" -gt "$ROOTFSSIZE" ] && ROOTFSSIZE="$ROOTFS_REAL_SIZE_MB"
fi

head=4
sect=2048

# Generate MBR: p1=FAT(c), p2=Linux(83). Filter ptgen output to pure numbers only.
set -- $(ptgen -o $OUTPUT -h $head -s $sect -l 32768 -t c -p ${BOOTFSSIZE}M -t 83 -p ${ROOTFSSIZE}M | grep -E '^[0-9]+$')

BOOTOFFSET="$(($1 / 512))"
BOOTSIZE="$(($2 / 512))"
ROOTFSOFFSET="$(($3 / 512))"
ROOTFSSIZE="$(($4 / 512))"

echo "    boot partition: offset=$BOOTOFFSET sectors, size=$((BOOTSIZE*512/1024/1024))MB"
echo "    rootfs partition: offset=$ROOTFSOFFSET sectors, size=$((ROOTFSSIZE*512/1024/1024))MB"

# Write partitions
dd bs=512 if="$BOOTFS" of="$OUTPUT" seek="$BOOTOFFSET" conv=notrunc 2>/dev/null
dd bs=512 if="$ROOTFS" of="$OUTPUT" seek="$ROOTFSOFFSET" conv=notrunc 2>/dev/null

# Write Amlogic bootloader (sector 1) and resource (sector 24576 = 12MB)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UBOOT_IMG="$SCRIPT_DIR/u-boot-onecloud.img"
AMLIMG="$SCRIPT_DIR/AmlImg"

if [ -f "$UBOOT_IMG" ] && [ -x "$AMLIMG" ]; then
    EXTRACT_DIR="$(mktemp -d)"
    if "$AMLIMG" unpack "$UBOOT_IMG" "$EXTRACT_DIR/" >/dev/null 2>&1; then
        [ -f "$EXTRACT_DIR/4.bootloader.PARTITION" ] && dd bs=512 if="$EXTRACT_DIR/4.bootloader.PARTITION" of="$OUTPUT" seek=1 conv=notrunc 2>/dev/null && echo "    bootloader: written to sector 1"
        [ -f "$EXTRACT_DIR/6.resource.PARTITION" ] && dd bs=512 if="$EXTRACT_DIR/6.resource.PARTITION" of="$OUTPUT" seek=24576 conv=notrunc 2>/dev/null && echo "    resource: written to sector 24576 (12MB)"
    fi
    rm -rf "$EXTRACT_DIR"
elif [ -f "$SCRIPT_DIR/bootloader.bin" ]; then
    dd bs=512 if="$SCRIPT_DIR/bootloader.bin" of="$OUTPUT" seek=1 conv=notrunc 2>/dev/null
    [ -f "$SCRIPT_DIR/resource.bin" ] && dd bs=512 if="$SCRIPT_DIR/resource.bin" of="$OUTPUT" seek=24576 conv=notrunc 2>/dev/null
fi
