#!/bin/bash
# ============================================================
# OneCloud ImmortalWrt DIY 脚本 Part 2 (Install feeds 之后)
# 作用：编译时修改默认配置（ttyd/rpcd/密码/banner）
# 注意：网络/系统/主题/服务等运行时配置统一由 target 的
#       uci-defaults（99-z-bypass-mode、97-enable-packet-steering、98-samba-share）
#       和 sysctl.d/99-amlogic-network.conf 管理，本脚本不再重复。
# ============================================================

# ---------- ttyd 自动登录 root（网页终端免输密码） ----------
sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config 2>/dev/null

# ---------- rpcd 超时延长（30s→60s，防止 LuCI 操作超时） ----------
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config 2>/dev/null

# ---------- 默认密码：无密码登录 ----------
# shadow 密码哈希字段为空，配合 ttyd -f root 实现免密
sed -i 's/root:::0:99999:7:::/root::0:0:99999:7:::/g' package/base-files/files/etc/shadow 2>/dev/null

# ---------- 自定义 Banner ----------
mkdir -p files/etc
cat > files/etc/banner << 'BANNER'
  _______                     ________        __
 |       |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|
 |_______||   __|_____|__|__||________||__|  |____|
          |__|
 -----------------------------------------------------
   OneCloud ImmortalWrt
 -----------------------------------------------------

BANNER

echo "op2.sh 执行完成"
