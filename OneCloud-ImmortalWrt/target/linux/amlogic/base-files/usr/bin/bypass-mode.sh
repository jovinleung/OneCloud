#!/bin/sh
# OneCloud bypass router mode setup script
# Usage: bypass-mode.sh <static_ip> <gateway_ip> [netmask]
# Example: bypass-mode.sh 192.168.2.2 192.168.2.1

IP="${1:-192.168.2.2}"
GATEWAY="${2:-192.168.2.1}"
NETMASK="${3:-255.255.255.0}"
PREFIX=$(echo "$NETMASK" | awk -F. '{
  n=0;
  for(i=1;i<=4;i++){
    x=$i;
    while(x>0){ n++; x=int(x/2) }
  }
  print n
}')

echo "=== OneCloud Bypass Router Mode ==="
echo "IP:      $IP/$PREFIX"
echo "Gateway: $GATEWAY"
echo ""

# 1. Configure network - static IP on LAN (CIDR format, IPv6 disabled for bypass)
echo "[1/6] Configuring network interface..."
uci set network.lan.proto='static'
uci delete network.lan.ipaddr 2>/dev/null
uci add_list network.lan.ipaddr="${IP}/${PREFIX}"
uci set network.lan.gateway="$GATEWAY"
uci delete network.lan.dns 2>/dev/null
uci add_list network.lan.dns="$GATEWAY"
# Bypass mode: disable IPv6 prefix delegation to avoid conflict with main router
uci delete network.lan.ip6assign 2>/dev/null
uci set network.lan.multipath='off'
uci commit network

# 2. Disable DHCP server on LAN (bypass router mode)
# ignore=1 disables DHCPv4; dhcpv6/ra disabled to avoid conflict with main router
echo "[2/6] Disabling DHCP server..."
uci set dhcp.lan.ignore='1'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ra='disabled'
uci commit dhcp

# 3. Configure firewall - bypass mode (single arm)
echo "[3/6] Configuring firewall (bypass mode)..."
uci set firewall.@defaults[0].forward='ACCEPT'
uci set firewall.@defaults[0].syn_flood='0'
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='0'
# fullcone NAT requires kmod-nft-fullcone; only set if option exists
if uci -q get firewall.@defaults[0].fullcone >/dev/null 2>&1; then
    uci set firewall.@defaults[0].fullcone='1'
    uci set firewall.@defaults[0].fullcone6='1'
fi
uci delete firewall.wan 2>/dev/null
uci delete firewall.@forwarding[0] 2>/dev/null
uci commit firewall

# 4. Ensure sysctl optimizations are applied (use existing 99-bypass.conf if available)
echo "[4/6] Applying sysctl optimizations..."
if [ ! -f /etc/sysctl.d/99-bypass.conf ]; then
    # Create basic sysctl config if not exists (full version comes from firmware)
    cat > /etc/sysctl.d/99-bypass.conf << 'SYSCTL'
# OneCloud bypass router sysctl optimizations
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.default.forwarding=1
net.ipv4.conf.all.arp_ignore=1
net.ipv4.conf.all.arp_announce=2
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 65536 16777216
net.ipv4.tcp_wmem=4096 32768 16777216
net.ipv4.tcp_fastopen=3
net.netfilter.nf_conntrack_max=262144
vm.swappiness=10
vm.dirty_ratio=10
kernel.panic=3
kernel.panic_on_oops=1
SYSCTL
fi
sysctl -p /etc/sysctl.d/99-bypass.conf 2>/dev/null

# 5. Configure DNS - bypass router mode
#    dnsmasq acts only as local DNS forwarder; Nikki handles DNS hijacking.
#    - DNS redirection disabled (Nikki hijacks port 53 -> 1053)
#    - No public DNS forwarders (upstream comes from resolvfile = main router)
#    - authoritative off (DHCP disabled), rebind protection off
echo "[5/6] Configuring DNS..."
uci delete dhcp.@dnsmasq[0].dns_redir 2>/dev/null
uci delete dhcp.@dnsmasq[0].server 2>/dev/null
uci set dhcp.@dnsmasq[0].domainneeded='1'
uci set dhcp.@dnsmasq[0].boguspriv='1'
uci set dhcp.@dnsmasq[0].localise_queries='1'
uci set dhcp.@dnsmasq[0].rebind_protection='0'
uci set dhcp.@dnsmasq[0].rebind_localhost='0'
uci set dhcp.@dnsmasq[0].local='/lan/'
uci set dhcp.@dnsmasq[0].domain='lan'
uci set dhcp.@dnsmasq[0].expandhosts='1'
uci set dhcp.@dnsmasq[0].authoritative='0'
uci set dhcp.@dnsmasq[0].readethers='1'
uci set dhcp.@dnsmasq[0].leasefile='/tmp/dhcp.leases'
uci set dhcp.@dnsmasq[0].resolvfile='/tmp/resolv.conf.d/resolv.conf.auto'
# Keep localservice=1 for security (only listen on local interfaces)
uci set dhcp.@dnsmasq[0].localservice='1'
uci set dhcp.@dnsmasq[0].nonwildcard='1'
uci commit dhcp

# 6. Restart services
echo "[6/6] Restarting services..."
# dnsmasq still runs as DNS forwarder (DHCP disabled)
/etc/init.d/dnsmasq restart 2>/dev/null
# odhcpd not needed in bypass mode (IPv6 DHCP/RA disabled)
/etc/init.d/odhcpd stop 2>/dev/null
/etc/init.d/odhcpd disable 2>/dev/null
/etc/init.d/firewall restart 2>/dev/null
# Apply network changes
/etc/init.d/network reload 2>/dev/null

echo ""
echo "=== Bypass router mode configured ==="
echo "Device IP:  $IP/$PREFIX"
echo "Gateway:    $GATEWAY"
echo ""
echo "Next steps:"
echo "  1. Set your main router's DHCP gateway and DNS to $IP"
echo "  2. Reconnect client devices to obtain new DHCP lease"
echo "  3. Reboot device if network is unstable: reboot"
echo ""
echo "To restore router mode: firstboot && reboot"
