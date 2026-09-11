#!/bin/bash
# ============================================================
# OneCloud OpenWrt DIY 脚本 Part 2 (Install feeds 之后)
# 作用：修改默认 IP、密码、服务精简、RPS/XPS、banner 等
# ============================================================

# ---------- 默认 IP 改为旁路由模式 ----------
# 旁路由模式：192.168.2.2，网关指向主路由 192.168.2.1
sed -i "s/192.168.1.1/192.168.2.2/" package/base-files/files/bin/config_generate

# ---------- 默认密码 ----------
# 无密码登录
sed -i 's/root:::0:99999:7:::/root::0:0:99999:7:::/g' package/base-files/files/etc/shadow

# ---------- 主机名 ----------
sed -i "s/hostname='OpenWrt'/hostname='OneCloud'/g" package/base-files/files/bin/config_generate

# ---------- 时区 ----------
sed -i "s/timezone='UTC'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
sed -i "/timezone='CST-8'/a set system.@system[-1].zonename='Asia/Shanghai'" package/base-files/files/bin/config_generate 2>/dev/null

# ---------- 禁用旁路由不需要的服务 ----------
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-onecloud-optimize << 'UCIEOF'
#!/bin/sh
# 旁路由服务精简
for svc in \
  wpad hostapd odhcpd \
  radius hd-idle gpio_switch \
  openlist2 momo \
  upnpd \
  ddns; do
  /etc/init.d/$svc disable 2>/dev/null
  /etc/init.d/$svc stop 2>/dev/null
done
# 启用 irqbalance
/etc/init.d/irqbalance enable 2>/dev/null
/etc/init.d/irqbalance start 2>/dev/null
uci set dhcp.@dnsmasq[0].port='0' 2>/dev/null
# DHCP 关闭（旁路由由主路由分配 IP）
uci set dhcp.lan.ignore='1'
uci commit dhcp
# 网关和 DNS 指向主路由
uci set network.lan.gateway='192.168.2.1'
uci set network.lan.dns='192.168.2.1'
uci commit network
# 防火墙：关闭 syn_flood
uci set firewall.@defaults[0].syn_flood='0' 2>/dev/null
uci commit firewall
exit 0
UCIEOF
chmod +x files/etc/uci-defaults/99-onecloud-optimize

# ---------- 自定义登录 Banner ----------
mkdir -p files/etc
cat > files/etc/banner << 'BANNER'
  _______                     ________        __
 |       |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|
 |_______||   __|_____|__|__||________||__|  |____|
          |__|
 -----------------------------------------------------
   OneCloud OpenWrt  by TurBoTse
 -----------------------------------------------------

BANNER

# ---------- 网卡中断亲和性 / RPS-XPS 优化 ----------
cat > files/etc/uci-defaults/98-network-optimize << 'NETEOF'
#!/bin/sh
# === IRQ 亲和性：动态查找 eth0 中断并绑定到 CPU1 ===
eth0_irq=$(grep eth0 /proc/interrupts | head -1 | awk -F: '{print $1}' | tr -d ' ')
if [ -n "$eth0_irq" ]; then
  echo 2 > /proc/irq/$eth0_irq/smp_affinity 2>/dev/null
fi

# === RPS/XPS：4核网络负载均衡 ===
for iface in eth0 br-lan; do
  for q in /sys/class/net/$iface/queues/rx-*; do
    [ -w "$q/rps_cpus" ] && echo f > "$q/rps_cpus" 2>/dev/null
    [ -w "$q/rps_flow_cnt" ] && echo 4096 > "$q/rps_flow_cnt" 2>/dev/null
  done
  for q in /sys/class/net/$iface/queues/tx-*; do
    [ -w "$q/xps_cpus" ] && echo f > "$q/xps_cpus" 2>/dev/null
  done
done
exit 0
NETEOF
chmod +x files/etc/uci-defaults/98-network-optimize

echo "op2.sh 执行完成"
