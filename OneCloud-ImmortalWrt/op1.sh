#!/bin/bash
# ============================================================
# OneCloud ImmortalWrt DIY 脚本 Part 1 (Update feeds 之前)
# 作用：添加第三方 feed、内核模块自动加载
# 注意：sysctl 网络优化参数统一由 target 的
#       base-files/etc/sysctl.d/99-amlogic-network.conf 管理，
#       本脚本不再重复注入以避免参数冲突。
# ============================================================

# ---------- 添加 Nikki / Mihomo feed ----------
echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf.default

# ---------- 确保 BBR + fq 模块在 sysctl 之前加载 ----------
mkdir -p files/etc/modules.d
cat > files/etc/modules.d/99-bbr << 'MODEOF'
tcp_bbr
sch_fq
MODEOF

echo "op1.sh 执行完成"
