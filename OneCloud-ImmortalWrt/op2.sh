#!/bin/bash
# ============================================================
# OneCloud ImmortalWrt DIY 脚本 Part 2 (Install feeds 之后)
# 作用：编译时修改默认配置（密码/banner）
# 注意：ttyd 自动登录、rpcd 超时等运行时 uci 配置统一由 target 的
#       uci-defaults（99-z-bypass-mode）管理，本脚本不再重复。
# ============================================================

# ---------- 默认密码：无密码登录 ----------
# shadow 密码哈希字段为空，配合 ttyd -f root 实现免密
sed -i 's/root:::0:99999:7:::/root::0:0:99999:7:::/g' package/base-files/files/etc/shadow 2>/dev/null

echo "op2.sh 执行完成"
