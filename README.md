# N1-OpenWrt（PassWall 单臂旁路由专用）

Fork 自 [nantayo/N1-OpenWrt](https://github.com/nantayo/N1-OpenWrt)，按"纯代理网关"用途裁剪。

## 本机配置

| 项 | 值 |
|---|---|
| 设备 | 斐讯 N1（Amlogic S905D） |
| 模式 | 单臂旁路由，有线，无 WiFi / PPPoE |
| IP | `192.168.6.69/24` |
| 网关 | `192.168.6.1` |
| 上游 DNS | `223.5.5.5` / `119.29.29.29` |
| 账户 | `root` / `password` |
| LAN DHCP | **已关闭**（主路由负责分配地址） |
| IPv6 | **已关闭**（见下） |
| CPU 调频 | `schedutil`，500 MHz – 1512 MHz 按需升降 |
| 时区 | Asia/Shanghai (CST-8) |

## 预装软件

- **luci-app-passwall** —— 核心全开：Xray、sing-box、Hysteria2、NaiveProxy、Shadow-TLS、Shadowsocks-Rust、ShadowsocksR-libev、Simple-Obfs、v2ray-plugin、xray-plugin、v2ray-geodata、Geoview、SmartDNS、Haproxy。核心包取自 [Openwrt-Passwall/openwrt-passwall-packages](https://github.com/Openwrt-Passwall/openwrt-passwall-packages) 上游，不依赖 ImmortalWrt feed 里的滞后版本。
- **luci-app-ttyd** —— 网页终端，LuCI 菜单：服务 → TTYD
- **luci-app-amlogic** —— 晶晨宝盒：写入 eMMC、在线升级、CPU 调频

已移除上游的 `luci-app-dae`（含 eBPF/BTF 内核调试信息）、`luci-app-podman`、`luci-app-samba4`，以及 `odhcp6c`、`odhcpd-ipv6only`、`luci-proto-ipv6`。

## IPv6 与 CPU

**IPv6 关闭方式**：`network.lan.ipv6='0'` 让 netifd 往 `/proc/sys/net/ipv6/conf/eth0/disable_ipv6` 写 `1`，eth0 连 `fe80::` 链路本地地址都不会有；同时不装 DHCPv6 客户端/服务端，LuCI 里也不再出现 6in4/6to4/DHCPv6 这些协议选项。PassWall 自身的 `ipv6_tproxy` 默认就是 `0`、`filter_proxy_ipv6` 默认 `1`，无需另改。

> 内核里的 IPv6 协议栈关不掉——OpenWrt 的 `CONFIG_IPV6` 在 `config/Config-build.in` 里是 `def_bool y`，写 `=n` 会被 `make defconfig` 改回来。上面这套是运行时禁用，效果等价：本机没有任何可用的 IPv6 地址与路由。
>
> **但这管不到客户端。** 如果主路由仍在下发 IPv6，客户端照样能用 IPv6 直连、绕过盒子。显式端口代理（`192.168.6.69:端口`）不受影响；若改用透明网关模式，需要在主路由上把 IPv6 也关掉。

**CPU 调频**：上游默认是 `performance` + `min=max=1512000`，等于 7×24 锁满频。已改成 `schedutil` + `500000`/`1512000`，与 `luci-app-amlogic` 自己的出厂默认一致。频率值若与内核实际 OPP 不符，`/usr/sbin/fixcpufreq.pl` 会在每次开机时自动纠正为最接近的可用值，不会写坏。想改回去：系统 → 晶晨宝盒 → CPU 设置。

## 多端口分别走不同节点

PassWall 原生支持，无需手写配置文件：

**服务 → PassWall → 主要 → 打开 Socks 总开关 → Socks Config 表格**

每行独立设置：`节点`（下拉选，即该端口的固定出口）、`端口`（SOCKS）、`HTTP 端口`（0 = 关闭）。加几行就有几个独立入口，各自起独立进程与配置文件。

> HTTP 端口只有 **sing-box 或 Xray** 核心支持，本固件两者都已编入。
> `bind_local` 保持关闭才会绑 `0.0.0.0`，局域网其他设备才能连进来。

## 编译

GitHub Actions 手动触发（Actions → Build ImmortalWrt-25.12 for armsr_armv8 → Run workflow），或每月 1 日、16 日北京时间 08:00 自动跑。

- 源码：ImmortalWrt `openwrt-25.12`，target `armsr/armv8`
- 打包：`ophub/amlogic-s9xxx-openwrt@main`，`s905d`，flippy 内核 `6.12.y`（来自 `ophub/kernel`）
- 产物：`openwrt_amlogic_s905d_k6.12.x_日期.img.gz`，发布到本仓库 Releases，保留最近 2 个

> **fork 后必须先去 Actions 页手动启用 workflows**，否则 Run workflow 按钮不出现。
>
> `diy.sh` 里有一处 xray-core 的 Go 版本补丁：Xray-core 26.11.9 起 `go.mod` 要求 go ≥ 1.27，而 feed 的 `GO_DEFAULT_VERSION` 写死 1.26。若日后 feed 默认版本追到 1.27 以上，那段可整块删除。

## 刷机

1. 先做一个可启动 U 盘，把 `.img.gz` 解压写入
2. N1 原厂安卓下开启开发者模式 + ADB，`adb connect <盒子IP>` 后执行 `adb shell reboot update`，从 U 盘启动
3. 浏览器进 `http://192.168.6.69`，**系统 → 晶晨宝盒 → 安装 OpenWrt** 写入 eMMC

> 写 eMMC 前请先备份原厂安卓。救砖需要 Amlogic USB Burning Tool + USB 双公头线 + 短接。
> 在线升级已指向本仓库，后缀 `.img.gz`；**不要改动挂载点**，否则无法启动。

## 主路由侧还需设置

固件本身管不到主路由。要让客户端走盒子，二选一：

- 客户端手动把网关/DNS 指向 `192.168.6.69`；或
- 主路由 DHCP 下发的网关/DNS 改成 `192.168.6.69`（全网设备都走盒子）

若客户端只是把盒子当显式代理（`192.168.6.69:端口`）用，则主路由无需任何改动。

## 致谢

- [nantayo/N1-OpenWrt](https://github.com/nantayo/N1-OpenWrt) —— 原始精简结构
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) —— 源码
- [ophub](https://github.com/ophub/amlogic-s9xxx-openwrt) —— 打包脚本与[内核](https://github.com/ophub/kernel/releases/tag/kernel_flippy)
- [Openwrt-Passwall](https://github.com/Openwrt-Passwall/openwrt-passwall) —— PassWall