# OneCloud OpenWrt / ImmortalWrt 自动构建固件

玩客云（Amlogic S805 / meson8b）旁路由固件自动构建项目，基于 GitHub Actions 每周自动编译最新版固件。

## 固件版本

| 版本 | 工作流 | 目录 | 源码 |
|---|---|---|---|
| OpenWrt | `onecloud-openwrt.yml` | `OneCloud-OpenWrt/` | [openwrt/openwrt](https://github.com/openwrt/openwrt) |
| ImmortalWrt | `onecloud-immortalwrt.yml` | `OneCloud-ImmortalWrt/` | [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) |

> **注意**：官方 OpenWrt 24.10+ 和 ImmortalWrt 均已移除 32 位 amlogic/meson8b target，本项目通过自定义 `target/linux/amlogic/` 注入玩客云支持。

## 功能特性

### 网络优化
- **BBR 拥塞控制**：内核编译 TCP BBR 模块，开机自动加载
- **RPS/XPS 多核负载均衡**：4 核 CPU 网络中断分发，提升吞吐量
- **IRQ 亲和性**：动态绑定 eth0 中断到 CPU1，避免单核瓶颈
- **sysctl 深度优化**：43 项网络/内存参数调优（TCP 连接、conntrack 超时、内存水位等）
- **dnsmasq 优化**：旁路由模式关闭 DNS 转发（`port=0`），推荐在路由器上配置缓存 5000 条、并发查询、上游 DNS 223.5.5.5 + 119.29.29.29
- **SQM 流量整形**：cake + fq 调度器
- **shortcut-fe 网络加速**：快速转发引擎

### 代理功能
- **mihomo-meta**：Clash.Meta 核心，支持 TUN 透明代理
- **luci-app-nikki**：mihomo Web 管理界面
- **TUN 模式**：推荐配置 system 栈、全局嗅探、超时 60s（需在 nikki Web UI 中设置）

### 存储与共享
- **Samba4**：文件共享（网络共享盘）
- **自动挂载**：USB 存储自动挂载（automount + autosamba）
- **多文件系统**：ext4 / exFAT / NTFS3 / vfat / F2FS / Btrfs / HFS+ / UDF / XFS
- **磁盘管理**：luci-app-diskman + parted + dosfstools（FAT 分区修复）

### 系统工具
- **ZRAM 虚拟内存**：LZ4 压缩，1GB 内存必备
- **irqbalance**：中断负载均衡
- **htop / iperf3 / ethtool / tcpdump / nmap / mtr**：网络诊断工具
- **tmux / screen / vim / nano / jq**：常用工具
- **ttyd**：网页终端
- **luci-app-commands**：自定义命令

### ImmortalWrt 特有应用
- **udpxy**：UDP 组播转 HTTP
- **网络唤醒（WOL）**
- **nlbwmon**：带宽监控
- **aria2 / transmission**：下载工具
- **minidlna**：媒体服务器
- **ksmbd**：内核级 SMB 服务
- **simple-adblock / adblock**：广告过滤
- **nextdns / https-dns-proxy**：加密 DNS

## 默认配置

| 项目 | OpenWrt 版 | ImmortalWrt 版 |
|---|---|---|
| 管理 IP | 192.168.2.2 | 192.168.2.2 |
| 用户名 | root | root |
| 密码 | 无 | 无 |
| 主机名 | OneCloud | OneCloud |
| 网关/DNS | 192.168.2.1 | 192.168.2.1 |
| DHCP | 禁用（旁路由模式） | 禁用（旁路由模式） |
| 主题 | Argon | Argon |
| 语言 | 简体中文 | 简体中文 |

> 两个版本均默认配置为旁路由模式：关闭 DHCP 和 DNS 转发，网关指向主路由 192.168.2.1。

## 目录结构

```
OneCloud-OpenWrt/
├── .github/workflows/
│   ├── onecloud-openwrt.yml             # OpenWrt 构建工作流
│   └── onecloud-immortalwrt.yml         # ImmortalWrt 构建工作流
├── OneCloud-OpenWrt/                    # OpenWrt 固件配置
│   ├── .config                          # 编译配置（完整）
│   ├── op1.sh                           #  feeds 更新前脚本（sysctl/BBR）
│   ├── op2.sh                           #  feeds 更新后脚本（密码/服务/RPS）
│   ├── op3.sh                           #  编译前脚本
│   └── target/linux/amlogic/            # 自定义 amlogic/meson8b target
│       ├── Makefile
│       ├── base-files/
│       ├── image/
│       ├── patches-6.6/
│       ├── files/arch/arm/boot/dts/amlogic/meson8b-onecloud.dts
│       └── meson8b/
│           ├── config-6.6               # 内核配置（含 BBR）
│           └── target.mk
└── OneCloud-ImmortalWrt/                # ImmortalWrt 固件配置
    ├── .config                          # 编译配置（minimal，defconfig 补全）
    ├── op1.sh                           #  feeds 更新前脚本
    ├── op2.sh                           #  feeds 更新后脚本
    ├── README.md                        # ImmortalWrt 版说明
    └── target/linux/amlogic/            # 自定义 amlogic/meson8b target
```

## 使用方法

### 烧录固件
1. 从 GitHub Releases 下载最新固件
2. 文件名包含 `burn` 的为线刷固件
3. 解压后使用 [Amlogic USB Burning Tool](https://androiddatahost.com/khfj4) 烧录
4. 红灯闪烁表示启动中，蓝灯常亮表示启动完成
5. 首次启动约需 5 分钟

### 旁路由配置（ImmortalWrt 版已默认配置）
1. 网线连接玩客云 LAN 口到主路由 LAN 口
2. 主路由 IP：192.168.2.1，玩客云 IP：192.168.2.2
3. 主路由 DHCP 网关/DNS 指向 192.168.2.2（可选，实现全局代理）
4. 或手动设置设备网关/DNS 为 192.168.2.2

### 代理配置
1. 访问 `http://192.168.2.2:9090/ui`（nikki Web UI）
2. 导入订阅链接
3. 选择节点，启用 TUN 透明代理

## 构建说明

- 每周日早上 5 点自动触发构建
- 也可手动在 Actions 页面触发
- 构建超时：360 分钟
- 使用 ccache 加速重复构建
- 固件上传到 GitHub Releases

## 优化细节

### sysctl 参数（43 项）
- `net.core.netdev_max_backlog = 5000`
- `net.core.netdev_budget = 600`
- `net.ipv4.tcp_max_syn_backlog = 2048`
- `net.ipv4.tcp_fin_timeout = 15`
- `net.ipv4.tcp_keepalive_time = 600`
- `net.netfilter.nf_conntrack_max = 65536`
- `net.netfilter.nf_conntrack_tcp_timeout_established = 7440`
- `vm.swappiness = 10`
- `vm.vfs_cache_pressure = 50`
- 更多参数见 `op1.sh`

### RPS/XPS 配置
- eth0 IRQ 绑定到 CPU1
- br-lan / eth0 RPS 开启 4 核分发（`rps_cpus=f`）
- XPS 开启传输队列分发
- 通过 uci-defaults 脚本 `98-network-optimize` 开机自动配置

### BBR 配置
- 内核配置：`CONFIG_TCP_CONG_BBR=y`
- 模块自动加载：`/etc/modules.d/99-bbr`（tcp_bbr + sch_fq）
- 默认拥塞控制：cubic（可通过 sysctl 切换为 bbr）

## 感谢与参考

- 自动编译工作流改自 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- 玩客云 u-boot [hzyitc/u-boot-onecloud](https://github.com/hzyitc/u-boot-onecloud)
- OpenWrt 源码 [openwrt/openwrt](https://github.com/openwrt/openwrt)
- ImmortalWrt 源码 [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt)
- 线刷包打包工具 [hzyitc/AmlImg](https://github.com/hzyitc/AmlImg)
- amlogic target 参考 [ophub/amlogic-s9xxx-openwrt](https://github.com/ophub/amlogic-s9xxx-openwrt)
- 所有为 OpenWrt / ImmortalWrt 做出贡献的人
