#!/bin/bash
# ============================================================
# OneCloud OpenWrt DIY 脚本 Part 3 (Update feeds 之后)
# 作用：替换第三方 feed 包（golang、xray-core、v2ray-geodata）
# ============================================================

# ---------- 替换为更新版本的包 ----------
# v2ray-geodata（使用第三方更新版本）
rm -rf feeds/packages/net/v2ray-geodata
git clone https://github.com/orgx2812/v2ray-geodata feeds/packages/net/v2ray-geodata

# xray-core（使用第三方更新版本）
rm -rf feeds/packages/net/xray-core
git clone https://github.com/orgx2812/xray-core feeds/packages/net/xray-core

# golang（使用第三方更新版本，避免 ARM32 编译问题）
rm -rf feeds/packages/lang/golang
git clone https://github.com/orgx2812/golang feeds/packages/lang/golang
