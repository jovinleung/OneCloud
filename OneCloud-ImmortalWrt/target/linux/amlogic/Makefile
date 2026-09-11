# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2013 OpenWrt.org

include $(TOPDIR)/rules.mk

ARCH:=arm
BOARD:=amlogic
BOARDNAME:=Amlogic family
FEATURES:=boot-part ext4 fpu legacy-sdcard squashfs usbgadget rtc
SUBTARGETS:=meson8b

KERNEL_PATCHVER:=6.18

define Target/Description
	Build firmware image for Amlogic Meson SoC devices.
	Currently produces Amlogic Burn Image for OneCloud.
endef

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += \
	e2fsprogs \
	kmod-usb-storage \
	kmod-usb-storage-uas \
	kmod-usb-storage-extras \
	kmod-fs-vfat \
	kmod-fs-exfat \
	kmod-fs-ntfs3 \
	dosfstools \
	kmod-macvlan \
	kmod-dummy \
	losetup \
	automount \
	parted \
	partx-utils \
	resize2fs \
	zram-swap \
	liblz4 \
	ethtool \
	usbutils \
	iperf3 \
	htop \
	curl \
	wget \
	yq \
	openssh-sftp-server \
	ca-certificates \
	ca-bundle \
	firewall4 \
	kmod-sched-core \
	kmod-nf-conntrack-netlink \
	kmod-nft-offload \
	kmod-nft-fullcone \
	kmod-tun \
	wireguard-tools \
	kmod-nft-tproxy \
	kmod-nft-socket \
	kmod-inet-diag \
	nftables-json \
	conntrack \
	ip-full \
	irqbalance \
	luci \
	uhttpd \
	luci-i18n-base-zh-cn \
	luci-i18n-firewall-zh-cn \
	luci-i18n-package-manager-zh-cn \
	luci-i18n-ttyd-zh-cn \
	luci-i18n-diskman-zh-cn \
	luci-i18n-hd-idle-zh-cn \
	luci-theme-argon \
	luci-app-ttyd \
	luci-app-diskman \
	luci-app-hd-idle \
	luci-app-nikki \
	luci-i18n-nikki-zh-cn \
	mihomo-meta

KERNELNAME:=Image dtbs

$(eval $(call BuildTarget))
