# OneCloud ImmortalWrt 优化构建

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 源码，针对玩客云（Amlogic S805 / Cortex-A5 四核 / 1GB RAM / 8GB eMMC）的旁路由场景优化。

## 相比原版 OpenWrt 的优化点

### 内核与网络栈
| 优化项 | 原版 OpenWrt | ImmortalWrt 优化版 |
|--------|-------------|-------------------|
| TCP 拥塞控制 | cubic | **BBR**（代理国际链路吞吐提升明显） |
| 队列调度 | fq_codel | **fq**（配合 BBR 最佳） |
| 网络缓冲区 | 176KB | **16MB**（千兆高并发防丢包） |
| netdev backlog | 1000 | **16384** |
| netdev budget | 默认 | **600** |
| MTU 探测 | 关闭 | **开启**（代理场景防网站打不开） |
| TCP Fast Open | 1 | **3** |
| TCP 连接优化 | 默认 | **fin_timeout=30s / keepalive 优化 / syn_backlog 优化** |
| conntrack 超时 | 默认 | **established=1h / time_wait=30s / udp=30s** |
| Full Cone NAT | 无 | **内置**（P2P/游戏优化） |
| Shortcut-FE | 无 | **内置**（软件流加速） |
| 连接跟踪表 | 自动 | **262144** |
| RPS/XPS 多核 | 关闭 | **开启**（4核网络负载均衡，消除单核瓶颈） |
| BBR 模块加载 | 手动 | **自动**（开机 modules.d 自动加载 tcp_bbr + sch_fq） |

### 系统优化
| 优化项 | 说明 |
|--------|------|
| **irqbalance** | 自动分散网卡中断到多核，避免 CPU0 瓶颈 |
| **中断亲和性** | eth0 中断通过 hotplug 动态优化，RPS/XPS 自动配置 |
| **CPU 调频** | performance 模式（已默认） |
| **编译优化** | `-O2 -march=cortex-a5 -mtune=cortex-a5 -mfpu=neon-vfpv4`（硬件浮点，非软浮点） |
| **服务精简** | 禁用 wpad/odhcpd 等旁路由不需要的服务（samba4 已保留用于网络共享） |
| **ZRAM** | 256MB LZ4 压缩虚拟内存（1GB 内存必备） |

### 旁路由预设
- 默认 IP：`192.168.2.2`
- 默认网关/DNS：`192.168.2.1`（主路由）
- DHCP：已关闭（由主路由分配）
- 默认登录：**无密码**（ttyd 网页终端自动登录 root，SSH 可直接登录）
- 主机名：`OneCloud`
- 时区：Asia/Shanghai

### 预装软件
- **mihomo-meta** + **luci-app-nikki**（透明代理）
- **samba4-server** + **luci-app-samba4**（网络共享盘）
- **luci-app-turboacc**（shortcut-fe + fullconenat 开关）
- **luci-app-ttyd**（网页终端）
- **luci-app-diskman**（磁盘管理）
- **Argon 主题**
- htop / ethtool / iperf3 / curl 等工具

## 文件说明

```
OneCloud-ImmortalWrt/
├── .config              # 编译配置（minimal，make defconfig 自动补全）
├── op1.sh               # DIY 脚本1（feeds 更新前：添加 feed、获取最新包、BBR模块）
├── op2.sh               # DIY 脚本2（feeds 安装后：编译时修改 ttyd/rpcd/密码/banner）
├── README.md            # 本文件
└── target/              # 自定义 amlogic target（玩客云硬件支持）
    └── linux/amlogic/
        ├── Makefile             # target 定义（内核版本、默认包、架构）
        ├── meson8b/
        │   ├── target.mk        # CPU 类型（cortex-a5 / neon-vfpv4）
        │   └── config-6.18      # 内核配置（BBR、ZRAM、网络优化）
        ├── files/arch/arm/boot/dts/amlogic/meson8b-onecloud.dts  # 设备树
        ├── patches-6.18/        # 内核补丁（DTS注册、eMMC、PWM）
        ├── image/
        │   ├── Makefile         # 镜像生成（emmc.img / sysupgrade.bin / burn.img）
        │   ├── gen_aml_emmc_img.sh   # eMMC 磁盘镜像生成（含 bootloader）
        │   ├── gen_aml_burn_img.sh   # Amlogic 线刷包生成
        │   ├── boot.txt          # U-Boot 启动脚本
        │   ├── AmlImg            # Amlogic 镜像打包工具（Linux x86_64）
        │   └── u-boot-onecloud.img  # 玩客云专用 U-Boot
        └── base-files/           # 运行时配置（uci-defaults、sysctl、hotplug、工具脚本）
            ├── 1.sh                   # eMMC rootfs 在线扩容脚本（固件中位于 /1.sh）
            ├── etc/uci-defaults/     # 首次启动自动配置（网络、系统、LED）
            ├── etc/sysctl.d/99-bypass.conf  # 网络性能调优参数
            ├── etc/hotplug.d/net/
            │   ├── 10-fix-mac        # eth0 MAC 固定（从 eMMC CID 派生，避免每次启动随机）
            │   └── 20-rps-rfs        # 网卡热插拔时自动 RPS/XPS 优化
            ├── etc/inittab
            ├── lib/upgrade/platform.sh    # 在线升级流程
            ├── lib/preinit/79_move_config # 配置迁移
            └── usr/bin/
                └── bypass-mode.sh    # 旁路由模式手动切换脚本

.github/workflows/
└── onecloud-immortalwrt.yml   # GitHub Actions 自动构建
```

## 使用方法

### 方式一：GitHub Actions 自动构建（推荐）

1. Fork 本仓库
2. 进入 Actions → 选择 "Build OneCloud ImmortalWrt" → Run workflow
3. 等待约 2-3 小时构建完成
4. 在 Releases 或 Artifacts 下载固件

固件包含三种格式：
- `*-emmc.img.gz`：原始磁盘镜像，可 `dd` 写入 eMMC 或 SD 卡
- `*-sysupgrade.bin`：在线升级镜像，在 LuCI 或命令行中使用 `sysupgrade`
- `*-burn.img.gz`：Amlogic USB Burning Tool 线刷包

### 方式二：本地编译

```bash
# 1. 克隆 ImmortalWrt 源码（使用 master 分支，自定义 target 依赖较新内核）
git clone https://github.com/immortalwrt/immortalwrt -b master --depth 1
cd immortalwrt

# 2. 复制配置、脚本和自定义 target
cp /path/to/OneCloud-ImmortalWrt/.config .config
cp /path/to/OneCloud-ImmortalWrt/op1.sh .
cp /path/to/OneCloud-ImmortalWrt/op2.sh .
cp -r /path/to/OneCloud-ImmortalWrt/target target

# 3. 执行 DIY Part 1（添加 feed、获取最新包）
chmod +x op1.sh op2.sh
./op1.sh

# 4. 更新并安装 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 5. 执行 DIY Part 2（编译时配置修改）
./op2.sh

# 6. 编译
make defconfig
make -j$(nproc)
```

## 刷机

- 文件名含 `burn` 的为线刷固件，使用 Amlogic USB Burning Tool 烧录
- `emmc.img` 可使用 `dd if=xxx.img of=/dev/mmcblkX` 写入 eMMC 或 SD 卡
- 红灯闪 = 启动中，蓝灯常亮 = 启动完成
- 首次启动约 2-5 分钟

## 常用工具脚本

### 在线扩容 rootfs
```bash
# 扩容到 eMMC 末尾（推荐）
/1.sh

# 或指定大小（MB）
/1.sh 4096
```

### 手动切换旁路由模式
```bash
# 使用默认 IP 192.168.2.2 / 网关 192.168.2.1
bypass-mode.sh

# 或自定义
bypass-mode.sh 192.168.1.2 192.168.1.1
```

## 注意事项

1. **网卡 Ring Buffer**：Amlogic stmmac 驱动不支持将 RX/TX 调到 1024（会导致网卡挂死），hotplug 脚本会自动尝试并在失败时保持默认值
2. **eMMC 频率**：设备树默认 52MHz HS MMC（meson8b 不支持 HS200），如遇 eMMC 不稳定可降为 26MHz
3. **分支**：使用 ImmortalWrt `master` 分支（自定义 target 使用内核 6.18，需要较新源码）
4. **网络共享**：建议外接 USB 硬盘，eMMC 8GB 系统占后约 6GB 可用
5. **无密码登录**：默认无密码，首次登录后建议通过 `passwd` 设置密码，或仅在局域网内使用
6. **mihomo 配置**：首次启动后需在 LuCI → Nikki 中导入订阅配置
