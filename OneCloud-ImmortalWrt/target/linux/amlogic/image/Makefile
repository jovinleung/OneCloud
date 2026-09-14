#
# Copyright (C) 2017 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

FAT32_BLOCK_SIZE=1024
FAT32_BLOCKS=$(shell echo $$(($(CONFIG_TARGET_KERNEL_PARTSIZE)*1024*1024/$(FAT32_BLOCK_SIZE))))

# Build FAT boot partition: kernel.img, dtb.img, boot.scr (per-image temp to avoid races)
define Build/boot-partition
	mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "boot.scr" \
		-d $(TOPDIR)/target/linux/amlogic/image/boot.txt $@.boot.scr
	rm -f $@
	mkfs.fat -C $@ $(FAT32_BLOCKS)
	mlabel -i $@ ::boot
	mcopy -i $@ $@.boot.scr ::boot.scr
	mcopy -i $@ $(IMAGE_KERNEL) ::kernel.img
	$(foreach dts,$(DEVICE_DTS),mcopy -i $@ $(DTS_DIR)/$(dts).dtb ::dtb.img;)
	rm -f $@.boot.scr
endef

# Build complete eMMC disk image: bootloader(sector 1) + resource(12MB) + MBR(boot+rootfs)
define Build/emmc-image
	$(TOPDIR)/target/linux/amlogic/image/gen_aml_emmc_img.sh $@.new \
		$@ $(IMAGE_ROOTFS) \
		$(CONFIG_TARGET_KERNEL_PARTSIZE) $(CONFIG_TARGET_ROOTFS_PARTSIZE)
	mv $@.new $@
endef

# Convert to Amlogic USB Burning Tool format
define Build/aml-burn-img
	$(TOPDIR)/target/linux/amlogic/image/gen_aml_burn_img.sh $@ $@.new
	mv $@.new $@
endef

define Device/Default
  FILESYSTEMS := ext4
  IMAGES := emmc.img sysupgrade.bin burn.img
  KERNEL_DEPENDS = $$(wildcard $(DTS_DIR)/$$(DEVICE_DTS).dts)
  KERNEL_LOADADDR := 0x00208000
  KERNEL_NAME := Image
  KERNEL := kernel-bin | uImage none
  PROFILES = Default $$(DEVICE_NAME)
endef

define Device/thunder-onecloud
  DEVICE_DTS := amlogic/meson8b-onecloud
  DEVICE_TITLE := Thunder OneCloud (Amlogic S805)
  DEVICE_ALT0_NAME := thunder,onecloud
  SUPPORTED_DEVICES := thunder-onecloud thunder,onecloud
  DEVICE_PACKAGES := \
    e2fsprogs \
    dosfstools \
    kmod-fs-ext4 \
    kmod-fs-vfat \
    kmod-usb-storage \
    kmod-usb-storage-uas \
    losetup \
    parted
  IMAGE/emmc.img := boot-partition | emmc-image
  IMAGE/sysupgrade.bin := boot-partition | emmc-image | append-metadata
  IMAGE/burn.img := boot-partition | emmc-image | aml-burn-img
endef

ifeq ($(SUBTARGET),meson8b)
  TARGET_DEVICES += thunder-onecloud
endif

$(eval $(call BuildImage))
