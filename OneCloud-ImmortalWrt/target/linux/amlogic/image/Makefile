#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

FAT32_BLOCK_SIZE=1024
FAT32_BLOCKS=$(shell echo $$(($(CONFIG_TARGET_KERNEL_PARTSIZE)*1024*1024/$(FAT32_BLOCK_SIZE))))

# boot.scr is shared across all images; build it once.
define Build/boot-script
	mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "boot.scr" -d boot.txt $(KDIR)/boot.scr
endef

# Build the base eMMC disk image (bootloader + FAT boot + ext4 rootfs)
# once and cache it in KDIR.  All three output formats (emmc.img,
# sysupgrade.bin, burn.img) copy from this cache, avoiding triple builds.
define Build/emmc-common
	BASE_IMG="$(KDIR)/onecloud-emmc-base.img"; \
	BASE_STAMP="$$BASE_IMG.stamp"; \
	if [ ! -f "$$BASE_STAMP" ] || \
	   [ "$(IMAGE_ROOTFS)" -nt "$$BASE_STAMP" ] || \
	   [ "$(KDIR)/boot.scr" -nt "$$BASE_STAMP" ]; then \
		$(RM) -f "$$BASE_IMG" "$$BASE_IMG.boot"; \
		$(RM) -rf "$(KDIR)/boot.fat.base"; \
		mkfs.fat -C "$$BASE_IMG.boot" $(FAT32_BLOCKS); \
		mkdir -p "$(KDIR)/boot.fat.base"; \
		$(CP) "$(KDIR)/boot.scr" "$(KDIR)/boot.fat.base/boot.scr"; \
		$(CP) "$(IMAGE_KERNEL)" "$(KDIR)/boot.fat.base/kernel.img"; \
		$(foreach dts,$(DEVICE_DTS),$(CP) $(DTS_DIR)/$(dts).dtb "$(KDIR)/boot.fat.base/dtb.img";) \
		mcopy -i "$$BASE_IMG.boot" -s "$(KDIR)/boot.fat.base"/* ::; \
		$(RM) -rf "$(KDIR)/boot.fat.base"; \
		$(TOPDIR)/target/linux/amlogic/image/gen_aml_emmc_img.sh "$$BASE_IMG" "$$BASE_IMG.boot" "$(IMAGE_ROOTFS)" \
			$(CONFIG_TARGET_KERNEL_PARTSIZE) $(CONFIG_TARGET_ROOTFS_PARTSIZE); \
		touch "$$BASE_STAMP"; \
	fi; \
	$(CP) "$$BASE_IMG" "$@"
endef

# Build/aml-burn-img: convert the base eMMC image into an Amlogic
# USB Burning Tool image.  Input: $@ (emmc.img), output: $@ (burn.img).
define Build/aml-burn-img
	$(TOPDIR)/target/linux/amlogic/image/gen_aml_burn_img.sh $@ $@.new
	mv $@.new $@
endef

### Devices ###
define Device/Default
  FILESYSTEMS := ext4
  IMAGES := emmc.img sysupgrade.bin burn.img
  KERNEL_DEPENDS = $$(wildcard $(DTS_DIR)/$$(DEVICE_DTS).dts)
  KERNEL_LOADADDR := 0x01080000
  KERNEL_NAME := Image
  # Use uncompressed uImage for maximum U-Boot compatibility;
  # gzip compression can be enabled if bootloader supports it:
  # KERNEL := kernel-bin | gzip | uImage gzip
  KERNEL := kernel-bin | uImage none
  PROFILES = Default $$(DEVICE_NAME)
endef

define Device/thunder-onecloud
  DEVICE_DTS := amlogic/meson8b-onecloud
  DEVICE_TITLE := Thunder OneCloud
  KERNEL_LOADADDR := 0x00208000
  # rootfs defaults to 512MB; users can run resize-rootfs to expand to
  # the full eMMC capacity.
  # Three output formats share the same base eMMC image:
  #   emmc.img:       raw disk image (with bootloader), dd-able to eMMC
  #   sysupgrade.bin: online upgrade image (MBR, custom platform.sh flow)
  #   burn.img:       Amlogic USB Burning Tool package (converted from emmc.img)
  IMAGE/emmc.img := boot-script | emmc-common
  IMAGE/sysupgrade.bin := boot-script | emmc-common
  IMAGE/burn.img := boot-script | emmc-common | aml-burn-img
endef
ifeq ($(SUBTARGET),meson8b)
  TARGET_DEVICES += thunder-onecloud
endif

$(eval $(call BuildImage))
