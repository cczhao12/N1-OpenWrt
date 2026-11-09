#!/bin/bash
# 在 feeds update / install 全部完成之后运行，工作目录为 openwrt 源码根目录。
# PassWall 集成采用官方 README「方法2」：把包放进 package/ 而不是 feeds/，
# 这样不会被后续 feeds 操作覆盖，且版本始终跟随 PassWall 上游。
set -e

CORE_PKGS="xray-core v2ray-geodata sing-box chinadns-ng dns2socks hysteria ipt2socks microsocks naiveproxy shadowsocks-rust shadowsocksr-libev simple-obfs tcping v2ray-plugin xray-plugin geoview shadow-tls smartdns"

# 移除 ImmortalWrt 自带的核心包（版本滞后，且部分包缺失），换成 PassWall 上游版本
for p in $CORE_PKGS; do
  rm -rf "feeds/packages/net/$p" "package/feeds/packages/$p"
done
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages

# 移除过时的 LuCI 版本，换成最新 PassWall
rm -rf feeds/luci/applications/luci-app-passwall package/feeds/luci/luci-app-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci

# luci-app-amlogic：eMMC 写入 / 在线升级 / CPU 调频
rm -rf package/feeds/packages/luci-app-amlogic package/feeds/luci/luci-app-amlogic
git clone --depth=1 https://github.com/ophub/luci-app-amlogic.git clone/amlogic
cp -rf clone/amlogic/luci-app-amlogic package/luci-app-amlogic
rm -rf clone

# 去掉attendedsysupgrade菜单项（本固件用 luci-app-amlogic 升级）
if [ -f feeds/luci/collections/luci/Makefile ]; then
  sed -i '/luci-app-attendedsysupgrade/d' feeds/luci/collections/luci/Makefile
fi

# luci-light 无条件依赖 luci-proto-ipv6（+IPV6:...，而 IPV6 是 def_bool y），
# 不摘掉这行的话 .config 里的 =n 会被依赖解析改回 y
if [ -f feeds/luci/collections/luci-light/Makefile ]; then
  sed -i '/IPV6:luci-proto-ipv6/d' feeds/luci/collections/luci-light/Makefile
fi