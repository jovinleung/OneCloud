# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2013 OpenWrt.org

include $(TOPDIR)/rules.mk

ARCH:=arm
BOARD:=amlogic
BOARDNAME:=Amlogic Meson family
FEATURES:=boot-part ext4 fpu legacy-sdcard squashfs usbgadget rtc
SUBTARGETS:=meson8b

KERNEL_PATCHVER:=6.18

define Target/Description
	Build firmware image for Amlogic Meson SoC devices.
	Currently produces Amlogic Burn Image for OneCloud.
endef

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += \
	samba4-server \
	luci-app-samba4 \
	luci-i18n-samba4-zh-cn \
	wsdd2 \
	libnss-mdns \
	e2fsprogs \
	kmod-gpio-button-hotplug \
	kmod-usb-storage \
	kmod-usb-storage-uas \
	kmod-usb-storage-extras \
	kmod-fs-ext4 \
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
	tcpdump \
	htop \
	curl \
	wget \
	yq \
	openssh-sftp-server \
	ca-certificates \
	ca-bundle \
	firewall4 \
	kmod-sched-core \
	kmod-sched-cake \
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
	luci-theme-argon \
	luci-app-ttyd \
	luci-i18n-ttyd-zh-cn \
	luci-app-diskman \
	luci-i18n-diskman-zh-cn \
	luci-app-hd-idle \
	luci-i18n-hd-idle-zh-cn \
	luci-app-nikki \
	luci-i18n-nikki-zh-cn

KERNELNAME:=Image dtbs

$(eval $(call BuildTarget))
