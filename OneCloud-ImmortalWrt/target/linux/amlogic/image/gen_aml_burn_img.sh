#!/bin/sh
#
# gen_aml_burn_img.sh - Generate an Amlogic USB Burning Tool image from an
# ext4-emmc.img disk image.
#
# Usage: gen_aml_burn_img.sh <input.emmc.img> <output.burn.img[.xz]>
#
# Steps:
#   1. Locate or download the AmlImg tool (hzyitc/AmlImg)
#   2. Locate or download the OneCloud u-boot (hzyitc/u-boot-onecloud)
#   3. Read the MBR partition table from the input image
#   4. Extract boot (FAT32) and rootfs (ext4) partitions
#   5. Convert partitions to Android sparse format (.simg)
#   6. Pack into Amlogic .burn.img format with AmlImg
#   7. Optionally compress with xz if output ends in .xz
#
# Dependencies: curl, python3, dd, img2simg, xz (optional)

set -e

# === Argument check ===
INPUT_IMG="$1"
OUTPUT_IMG="$2"

if [ -z "$INPUT_IMG" ] || [ -z "$OUTPUT_IMG" ]; then
    echo "Usage: $0 <input.emmc.img> <output.burn.img[.xz]>"
    echo ""
    echo "Examples:"
    echo "  $0 immortalwrt-amlogic-meson8b-thunder-onecloud-ext4-emmc.img immortalwrt-onecloud.burn.img"
    echo "  $0 immortalwrt-amlogic-meson8b-thunder-onecloud-ext4-emmc.img immortalwrt-onecloud.burn.img.xz"
    exit 1
fi

if [ ! -f "$INPUT_IMG" ]; then
    echo "ERROR: input file not found: $INPUT_IMG"
    exit 1
fi

# === Configuration ===
AMLIMG_VERSION="v0.3.1"
UBOOT_VERSION="build-20221028-0940"
UBOOT_URL="https://github.com/hzyitc/u-boot-onecloud/releases/download/${UBOOT_VERSION}/eMMC.burn.img"

# Working directory (auto-cleaned on exit)
WORKDIR=$(mktemp -d)
cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# === Locate / build AmlImg ===
echo "==> [1/6] Preparing AmlImg tool"

detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  echo "linux_amd64" ;;
        aarch64|arm64) echo "linux_arm64" ;;
        armv7l|arm)    echo "linux_arm" ;;
        i386|i686)      echo "linux_386" ;;
        *)
            echo "ERROR: unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac
}

AMLIMG_ARCH=$(detect_arch)
OS_TYPE=$(uname -s)

# Search order: script dir (self-contained), PATH, STAGING_DIR, cwd
find_amlimg() {
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    if [ -x "$script_dir/AmlImg" ]; then
        echo "$script_dir/AmlImg"
        return 0
    fi
    if command -v AmlImg &>/dev/null; then
        command -v AmlImg
        return 0
    fi
    if [ -n "$STAGING_DIR" ] && [ -x "$STAGING_DIR/host/bin/AmlImg" ]; then
        echo "$STAGING_DIR/host/bin/AmlImg"
        return 0
    fi
    if [ -x "./AmlImg" ]; then
        echo "$(pwd)/AmlImg"
        return 0
    fi
    return 1
}

AMLIMG=$(find_amlimg 2>/dev/null || true)
if [ -z "$AMLIMG" ]; then
    if [ "$OS_TYPE" = "Darwin" ]; then
        # macOS: no prebuilt binaries, build from source with Go
        echo "    macOS detected, building AmlImg from source (requires Go)..."
        if ! command -v go &>/dev/null; then
            echo "ERROR: Go is required to build AmlImg on macOS" >&2
            echo "Install Go: brew install go" >&2
            exit 1
        fi
        MAC_ARCH=$(uname -m)
        case "$MAC_ARCH" in
            arm64) GOARCH=arm64 ;;
            x86_64) GOARCH=amd64 ;;
            *)
                echo "ERROR: unsupported macOS architecture: $MAC_ARCH" >&2
                exit 1
                ;;
        esac
        AMLIMG_SRC_DIR="$WORKDIR/AmlImg-src"
        git clone --depth 1 https://github.com/hzyitc/AmlImg.git "$AMLIMG_SRC_DIR" >/dev/null 2>&1 || {
            echo "ERROR: failed to clone AmlImg source" >&2
            exit 1
        }
        ( cd "$AMLIMG_SRC_DIR" && GOOS=darwin GOARCH=$GOARCH go build -o "$WORKDIR/AmlImg" . ) >/dev/null 2>&1 || {
            echo "ERROR: failed to build AmlImg (GOARCH=$GOARCH)" >&2
            exit 1
        }
        chmod +x "$WORKDIR/AmlImg"
        AMLIMG="$WORKDIR/AmlImg"
    else
        # Linux: download prebuilt binary
        echo "    Downloading AmlImg ${AMLIMG_VERSION} (${AMLIMG_ARCH})..."
        AMLIMG_URL="https://github.com/hzyitc/AmlImg/releases/download/${AMLIMG_VERSION}/AmlImg_${AMLIMG_VERSION}_${AMLIMG_ARCH}"
        curl -sL --fail -o "$WORKDIR/AmlImg" "$AMLIMG_URL" || {
            echo "ERROR: failed to download AmlImg: $AMLIMG_URL" >&2
            exit 1
        }
        chmod +x "$WORKDIR/AmlImg"
        AMLIMG="$WORKDIR/AmlImg"
    fi
fi
echo "    Using AmlImg: $AMLIMG"

# === Obtain u-boot (prefer local file to avoid network dependency) ===
echo "==> [2/6] Obtaining OneCloud u-boot"
UBOOT_IMG="$WORKDIR/uboot.img"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/u-boot-onecloud.img" ]; then
    cp "$SCRIPT_DIR/u-boot-onecloud.img" "$UBOOT_IMG"
    echo "    Using local u-boot: $SCRIPT_DIR/u-boot-onecloud.img"
else
    echo "    Downloading u-boot from GitHub..."
    curl -sL --fail -o "$UBOOT_IMG" "$UBOOT_URL" || {
        echo "ERROR: failed to download u-boot: $UBOOT_URL" >&2
        exit 1
    }
fi
echo "    u-boot size: $(du -h "$UBOOT_IMG" | cut -f1)"

# === Unpack u-boot ===
echo "==> [3/6] Unpacking u-boot base structure"
BURN_DIR="$WORKDIR/burn"
mkdir -p "$BURN_DIR"
"$AMLIMG" unpack "$UBOOT_IMG" "$BURN_DIR/" >/dev/null
echo "    Unpacked: $(ls "$BURN_DIR" | wc -l) files"

# === Read MBR partition table ===
echo "==> [4/6] Reading partition table and extracting partitions"

read_partitions() {
    python3 - "$INPUT_IMG" << 'PYEOF'
import struct, sys

with open(sys.argv[1], "rb") as f:
    # MBR partition table starts at offset 0x1BE, each entry is 16 bytes
    f.seek(0x1BE)
    for i in range(4):
        entry = f.read(16)
        if len(entry) < 16:
            break
        part_type = entry[4]
        lba_start = struct.unpack("<I", entry[8:12])[0]
        num_sectors = struct.unpack("<I", entry[12:16])[0]
        if num_sectors > 0:
            print(f"{i+1} {part_type} {lba_start} {num_sectors}")
PYEOF
}

PARTITIONS=$(read_partitions)
echo "    Partition table:"
echo "$PARTITIONS" | while read idx type start sectors; do
    size_mb=$((sectors * 512 / 1024 / 1024))
    echo "      partition $idx: type=0x$(printf '%02x' $type), start=$start, size=${size_mb}MB"
done

# Extract boot partition (first partition, usually FAT32)
BOOT_INFO=$(echo "$PARTITIONS" | sed -n '1p')
BOOT_START=$(echo "$BOOT_INFO" | awk '{print $3}')
BOOT_SECTORS=$(echo "$BOOT_INFO" | awk '{print $4}')

# Extract rootfs partition (second partition, usually ext4)
ROOTFS_INFO=$(echo "$PARTITIONS" | sed -n '2p')
ROOTFS_START=$(echo "$ROOTFS_INFO" | awk '{print $3}')
ROOTFS_SECTORS=$(echo "$ROOTFS_INFO" | awk '{print $4}')

if [ -z "$BOOT_START" ] || [ -z "$ROOTFS_START" ]; then
    echo "ERROR: unable to read partition table" >&2
    exit 1
fi

# Extract partitions
dd if="$INPUT_IMG" of="$WORKDIR/boot.img" bs=512 skip="$BOOT_START" count="$BOOT_SECTORS" 2>/dev/null
dd if="$INPUT_IMG" of="$WORKDIR/rootfs.img" bs=512 skip="$ROOTFS_START" count="$ROOTFS_SECTORS" 2>/dev/null
echo "    boot partition: $(du -h "$WORKDIR/boot.img" | cut -f1)"
echo "    rootfs partition: $(du -h "$WORKDIR/rootfs.img" | cut -f1)"

# === Convert to sparse format ===
echo "==> [5/6] Converting to Android sparse format"

if ! command -v img2simg &>/dev/null; then
    echo "ERROR: img2simg not found, please install android-tools" >&2
    exit 1
fi

img2simg "$WORKDIR/boot.img" "$BURN_DIR/boot.simg"
img2simg "$WORKDIR/rootfs.img" "$BURN_DIR/rootfs.simg"
echo "    boot.simg: $(du -h "$BURN_DIR/boot.simg" | cut -f1)"
echo "    rootfs.simg: $(du -h "$BURN_DIR/rootfs.simg" | cut -f1)"

# === Append partition commands ===
cat >> "$BURN_DIR/commands.txt" << 'EOF'
PARTITION:boot:sparse:boot.simg
PARTITION:rootfs:sparse:rootfs.simg
EOF

# === Pack ===
echo "==> [6/6] Packing Amlogic burn image"

NEED_XZ=0
FINAL_OUTPUT="$OUTPUT_IMG"
case "$OUTPUT_IMG" in
    *.xz)
        NEED_XZ=1
        FINAL_OUTPUT="$WORKDIR/output.burn.img"
        ;;
esac

"$AMLIMG" pack "$FINAL_OUTPUT" "$BURN_DIR/" >/dev/null
echo "    burn image size: $(du -h "$FINAL_OUTPUT" | cut -f1)"

if [ "$NEED_XZ" -eq 1 ]; then
    echo "    Compressing with xz..."
    xz -6 --threads=0 -c "$FINAL_OUTPUT" > "$OUTPUT_IMG"
    echo "    compressed size: $(du -h "$OUTPUT_IMG" | cut -f1)"
fi

echo ""
echo "Done! Burn image generated: $OUTPUT_IMG"
echo ""
echo "Usage:"
echo "  1. Decompress if .xz: xz -d $OUTPUT_IMG"
echo "  2. Open USB Burning Tool"
echo "  3. File -> Import burn package -> select .burn.img"
echo "  4. Connect device, click Start"
