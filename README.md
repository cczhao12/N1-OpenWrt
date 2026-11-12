# N1-OpenWrt（PassWall2 单臂旁路由专用）

Fork 自 [nantayo/N1-OpenWrt](https://github.com/nantayo/N1-OpenWrt)，按"纯代理网关"用途裁剪。

## 本机配置

| 项 | 值 |
|---|---|
| 设备 | 斐讯 N1（Amlogic S905D） |
| 模式 | 单臂旁路由，有线，无 WiFi / PPPoE |
| IP | `192.168.6.69/24`（固件默认，换场地在 LuCI 里改） |
| 网关 | `192.168.6.1` |
| 上游 DNS | `223.5.5.5` / `119.29.29.29` |
| 账户 | `root` / `password`（首次开机自动设置，见下） |
| LAN DHCP | **已关闭**（主路由负责分配地址） |
| IPv6 | **已关闭**（见下） |
| CPU 调频 | `schedutil`，500 MHz – 1512 MHz 按需升降 |
| 时区 | Asia/Shanghai (CST-8) |

## 首次启动与登录

OpenWrt 官方镜像的 root 密码是空的，LuCI 和 dropbear 都会直接拒绝登录——"刷完进不去 LuCI" 就是这个原因。本固件在 `/etc/uci-defaults/99-n1-proxy` 里首次开机做了三件事：把 root 密码设成 `password`、打开 dropbear 的密码登录、关掉 LAN/WAN 的 DHCP。`uci-defaults` 只跑一次，之后改密码不会被覆盖。

改自己的密码：LuCI → 系统 → 管理权 → 路由器密码，或 SSH 进去执行 `passwd`。

## 备用管理地址

盒子搬到别的网段、网关又填错的话就再也进不去了。所以固件里有个 hotplug 脚本 `/etc/hotplug.d/iface/99-mgmt-alias`，每次 lan 口 up 时给 eth0 额外挂上这些地址：

`192.168.{0,1,2,3,4,5,6,7,8,10,31,50,68,88,100,123,199}.69/24`

只是管理别名，主地址和默认路由仍由 `/etc/config/network` 决定。换场地时：

1. 插上网线，浏览器依次试 `http://192.168.1.69`、`http://192.168.31.69`、`http://192.168.50.69`……总有一个能进
2. LuCI → 网络 → 接口 → LAN，只改 **IPv4 地址** 和 **IPv4 网关**，保存并应用
3. 之后主地址就是新的，备用别名一直还在

## 预装软件

- **luci-app-passwall2** —— 核心：Xray、sing-box、Hysteria2、NaiveProxy、ShadowsocksR-libev、Simple-Obfs、v2ray-plugin、xray-plugin、v2ray-geodata、Geoview、SmartDNS、Haproxy。核心包取自 [Openwrt-Passwall/openwrt-passwall-packages](https://github.com/Openwrt-Passwall/openwrt-passwall-packages) 上游，不依赖 ImmortalWrt feed 里的滞后版本。PassWall2 的 Makefile 少了几个 `INCLUDE_` 开关，这几个核心改在 `.config` 里直接选包，固件内容与之前一致。
- **luci-app-ttyd** —— 网页终端，LuCI 菜单：服务 → TTYD
- **luci-app-amlogic** —— 晶晨宝盒：写入 eMMC、在线升级、CPU 调频

已移除上游的 `luci-app-dae`（含 eBPF/BTF 内核调试信息）、`luci-app-podman`、`luci-app-samba4`，以及 `odhcp6c`、`odhcpd-ipv6only`、`luci-proto-ipv6`。

**Shadow-TLS 与 Shadowsocks-Rust 暂不编入**：这两个包的 Makefile 要求宿主 rust（`PKG_BUILD_DEPENDS:=rust/host`），而 ImmortalWrt 的 rust 固定从 `ci-artifacts.rust-lang.org` 下载预编译 LLVM——该地址自 2026-11-12 起对所有版本（1.88–1.96）都返回 404，rust 一定构建失败。Shadowsocks 节点改用 Xray / sing-box 核心即可，功能不缺；预检里已加了硬拦截，这两个开关再被打开会当场报错。上游修好后把 `.config` 里这两个开关改回 `=y` 即可。

## IPv6 与 CPU

**IPv6 关闭方式**：`network.lan.ipv6='0'` 让 netifd 往 `/proc/sys/net/ipv6/conf/eth0/disable_ipv6` 写 `1`，eth0 连 `fe80::` 链路本地地址都不会有；同时不装 DHCPv6 客户端/服务端，LuCI 里也不再出现 6in4/6to4/DHCPv6 这些协议选项。PassWall2 自身的 `ipv6_tproxy` 默认就是 `0`（已无 `filter_proxy_ipv6` 开关），无需另改。

> 内核里的 IPv6 协议栈关不掉——OpenWrt 的 `CONFIG_IPV6` 在 `config/Config-build.in` 里是 `def_bool y`，写 `=n` 会被 `make defconfig` 改回来。上面这套是运行时禁用，效果等价：本机没有任何可用的 IPv6 地址与路由。
>
> **但这管不到客户端。** 如果主路由仍在下发 IPv6，客户端照样能用 IPv6 直连、绕过盒子。显式端口代理（`192.168.6.69:端口`）不受影响；若改用透明网关模式，需要在主路由上把 IPv6 也关掉。

**CPU 调频**：上游默认是 `performance` + `min=max=1512000`，等于 7×24 锁满频。已改成 `schedutil` + `500000`/`1512000`，与 `luci-app-amlogic` 自己的出厂默认一致。频率值若与内核实际 OPP 不符，`/usr/sbin/fixcpufreq.pl` 会在每次开机时自动纠正为最接近的可用值，不会写坏。想改回去：系统 → 晶晨宝盒 → CPU 设置。

## 多端口分别走不同节点

PassWall2 原生支持，无需手写配置文件：

**服务 → PassWall 2 → 主要 → 打开 Socks 总开关 → Socks Config 表格**

每行独立设置：`节点`（下拉选，即该端口的固定出口）、`端口`（SOCKS）、`HTTP 端口`（0 = 关闭）。加几行就有几个独立入口，各自起独立进程与配置文件。

> HTTP 端口只有 **sing-box 或 Xray** 核心支持，本固件两者都已编入。
> `bind_local` 保持关闭才会绑 `0.0.0.0`，局域网其他设备才能连进来。

节点可以从 LuCI 手动填，也可以走订阅（节点 → 订阅，或在 SSH/ttyd 里执行 `lua /usr/share/passwall2/subscribe.lua start all manual`，节点有变化会自动重启 PassWall2）。

## 编译

GitHub Actions 手动触发（Actions → Build ImmortalWrt-25.12 for armsr_armv8 → Run workflow），或每月 1 日、16 日北京时间 08:00 自动跑。

- 源码：ImmortalWrt `openwrt-25.12`，target `armsr/armv8`
- 打包：`ophub/amlogic-s9xxx-openwrt@main`，`s905d`，flippy 内核 `6.12.y`（来自 `ophub/kernel`）
- 产物：`openwrt_amlogic_s905d_k6.12.x_日期.img.gz`，发布到本仓库 Releases，保留最近 2 个
- 预检：`diy/precheck.sh` 在 download 之前分两步拦错——`feeds`（各 Go 核心的 `go.mod` 要求 vs feed 里的工具链版本）和 `config`（`make defconfig` 之后回读 `.config`，看我们写下的开关有没有被强制改写）。大约第 10 分钟就能报出问题，不用等编译两小时。它只查静态可验证的错，包内源码编译失败仍然要到 compile 阶段才知道。

> **fork 后必须先去 Actions 页手动启用 workflows**，否则 Run workflow 按钮不出现。
>
> `diy.sh` 里有一处 xray-core 的 Go 版本补丁：Xray-core 26.11.9 起 `go.mod` 要求 go ≥ 1.27，而 feed 的 `GO_DEFAULT_VERSION` 写死 1.26。若日后 feed 默认版本追到 1.27 以上，那段可整块删除。

## 刷机

1. 先做一个可启动 U 盘，把 `.img.gz` 解压写入
2. N1 原厂安卓下开启开发者模式 + ADB，`adb connect <盒子IP>` 后执行 `adb shell reboot update`，从 U 盘启动
3. 浏览器进 `http://192.168.6.69`，**系统 → 晶晨宝盒 → 安装 OpenWrt** 写入 eMMC

> 写 eMMC 前请先备份原厂安卓。救砖需要 Amlogic USB Burning Tool + USB 双公头线 + 短接。
> 在线升级已指向本仓库，后缀 `.img.gz`；**不要改动挂载点**，否则无法启动。

**命令行等价写法**：`/usr/sbin/openwrt-install-amlogic yes 101 auto ext4`（依次是 写不写 uboot、机型 ID、dtb、共享分区格式），ttyd 里直接跑也行；四个参数给全就不再交互提问。`101` 是 `/etc/model_database.txt` 里的 Phicomm-N1。

> 晶晨宝盒页面上的 **"自动写入 bootloader" 必须保持开启**（配置项 `amlogic_write_bootloader` 不能是 `0`），关掉就只写根分区，盒子无法自行启动。
>
> eMMC 安装是把 `/etc`、`/usr`、`/www` 等整体复制过去，所以密码、LAN 配置、PassWall2 节点都会保留，不用重配。

## 主路由侧还需设置

固件本身管不到主路由。要让客户端走盒子，二选一：

- 客户端手动把网关/DNS 指向 `192.168.6.69`；或
- 主路由 DHCP 下发的网关/DNS 改成 `192.168.6.69`（全网设备都走盒子）

若客户端只是把盒子当显式代理（`192.168.6.69:端口`）用，则主路由无需任何改动。

## 致谢

- [nantayo/N1-OpenWrt](https://github.com/nantayo/N1-OpenWrt) —— 原始精简结构
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) —— 源码
- [ophub](https://github.com/ophub/amlogic-s9xxx-openwrt) —— 打包脚本与[内核](https://github.com/ophub/kernel/releases/tag/kernel_flippy)
- [Openwrt-Passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) —— PassWall2