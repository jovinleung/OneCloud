#!/bin/bash
# ============================================================
# OneCloud OpenWrt DIY 脚本 Part 1 (Update feeds 之前)
# 作用：添加第三方 feed、内核参数注入、性能调优
# ============================================================

# ---------- 内核网络优化参数（注入到 sysctl 配置） ----------
SYSCTL_FILE="package/kernel/linux/files/sysctl-nf-conntrack.conf"

cat >> "$SYSCTL_FILE" << 'EOF'

# === OneCloud 网络优化 ===
# TCP 拥塞控制 BBR + fq 队列
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq
# 缓冲区（16MB，适配千兆）
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.tcp_rmem=4096 262144 16777216
net.ipv4.tcp_wmem=4096 262144 16777216
# 高并发 backlog
net.core.netdev_max_backlog=5000
net.core.netdev_budget=600
net.core.netdev_budget_usecs=8000
net.core.dev_weight=64
net.core.gro_normal_batch=16
# MTU 探测（代理/VPN 场景防卡顿）
net.ipv4.tcp_mtu_probing=1
# TCP Fast Open
net.ipv4.tcp_fastopen=3
# TCP 连接优化
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_synack_retries=3
net.ipv4.tcp_syn_retries=4
net.ipv4.tcp_thin_linear_timeouts=1
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_max_tw_buckets=8192
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_moderate_rcvbuf=1
net.ipv4.ip_local_port_range=1024 65535
# 连接跟踪表扩容 + 超时优化
net.netfilter.nf_conntrack_max=131072
net.netfilter.nf_conntrack_tcp_timeout_established=3600
net.netfilter.nf_conntrack_tcp_timeout_time_wait=60
net.netfilter.nf_conntrack_udp_timeout=30
net.netfilter.nf_conntrack_udp_timeout_stream=120
net.netfilter.nf_conntrack_icmp_timeout=10
# 内存优化
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=20
vm.dirty_background_ratio=10
vm.min_free_kbytes=32768
EOF

# ---------- 确保 BBR 模块在 sysctl 之前加载 ----------
mkdir -p files/etc/modules.d
cat > files/etc/modules.d/99-bbr << 'MODEOF'
tcp_bbr
sch_fq
MODEOF

echo "op1.sh 执行完成"
