#!/bin/bash
# ============================================================
# OneCloud ImmortalWrt DIY 脚本 Part 1 (Update feeds 之前)
# 作用：添加第三方 feed、获取最新包、内核模块自动加载
# 注意：sysctl 网络优化参数统一由 target 的
#       base-files/etc/sysctl.d/99-bypass.conf 管理，
#       本脚本不再重复注入以避免参数冲突。
# ============================================================

# ---------- 添加 Nikki / Mihomo feed ----------
echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf.default

# ---------- 从 ImmortalWrt master 获取最新 automount/autosamba ----------
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
  repodir=$(basename "$repourl" .git)
  cd "$repodir" && git sparse-checkout set "$@"
  mv -f "$@" ../
  cd .. && rm -rf "$repodir"
}
git_sparse_clone master https://github.com/immortalwrt/immortalwrt package/emortal/automount
git_sparse_clone master https://github.com/immortalwrt/immortalwrt package/emortal/autosamba
cp -rf automount autosamba package/
rm -rf automount autosamba

# ---------- 确保 BBR + fq 模块在 sysctl 之前加载 ----------
mkdir -p files/etc/modules.d
cat > files/etc/modules.d/99-bbr << 'MODEOF'
tcp_bbr
sch_fq
MODEOF

echo "op1.sh 执行完成"
