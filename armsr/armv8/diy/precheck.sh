#!/usr/bin/env bash
# 预检：不编译任何东西，只花几十秒拦住「静态可验证」的构建失败，
# 免得跑满三小时才在 compile 阶段炸出一个版本要求。
#   工作目录：openwrt 源码根目录。参数：
#     feeds  —— diy.sh 之后、make defconfig 之前：Go 工具链版本审计 + diy.sh 补丁是否真落地
#     config —— make defconfig 之后：N1/.config 里明确写过的开关有没有被依赖解析改掉
#   原则：只有确定不符才 FAIL。取不到信息一律 WARN 后继续，误报多了预检就没人看了。
set -uo pipefail

MODE=${1:-feeds}
FAIL=0
ok()   { echo "  [ok]   $*"; }
warn() { echo "  [WARN] $*"; }
bad()  { echo "  [FAIL] $*"; FAIL=1; }

# 版本比较：sort -V 能正确处理 1.9 < 1.27
ver_lt() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && [ "$1" != "$2" ]; }

gh_fetch() { # $1=owner/repo $2=ref $3=文件路径；成功打印内容，失败打印空
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}" auth=()
  [ -n "$token" ] && auth=(-H "Authorization: Bearer $token")
  curl -fsSL --max-time 40 --retry 2 -H "Accept: application/vnd.github.raw" \
    "${auth[@]}" "https://api.github.com/repos/$1/contents/$3?ref=$2" 2>/dev/null
}

required_go() { # $1=owner/repo $2=ref；打印该源码要求的 Go 版本，判不出则打印空
  local c
  c=$(gh_fetch "$1" "$2" go.mod)
  # hysteria 这类已改成 go.work 工作区，根目录没有 go.mod
  [ -z "$c" ] && c=$(gh_fetch "$1" "$2" go.work)
  [ -z "$c" ] && return
  printf '%s\n' "$c" | grep -E '^(go|toolchain)[[:space:]]+' \
    | awk '{print $2}' | sed 's/^go//' | sort -V | tail -1
}

precheck_feeds() {
  echo "== Go 核心：上游 go.mod 要求 vs feed 可用工具链"
  local godir=feeds/packages/lang/golang
  [ -d "$godir" ] || { bad "找不到 $godir，feeds 没装好"; return; }
  [ -d package/passwall-packages ] || { bad "package/passwall-packages 不存在，diy.sh 未执行"; return; }

  local default_go avail_go
  default_go=$(sed -n 's/^GO_DEFAULT_VERSION:=//p' "$godir/golang-values.mk" | head -1)
  avail_go=$(ls -d "$godir"/golang[0-9]* 2>/dev/null | sed 's|.*/golang||' | sort -V | paste -sd' ' -)
  echo "  feed 默认 golang/$default_go，已提供：${avail_go:-无}"
  [ -n "$default_go" ] || bad "读不到 GO_DEFAULT_VERSION"

  local mk name dep pin ver pkgname url ref repo need have
  for mk in package/passwall-packages/*/Makefile; do
    [ -f "$mk" ] || continue
    name=$(basename "$(dirname "$mk")")
    # 从 Makefile 里认包，不写死名单：上游哪天把某个包换成 Rust 或 C，这里自动就不审了
    dep=$(grep -m1 -oE 'golang[0-9.]*/host' "$mk") || continue
    pin=${dep#golang}; pin=${pin%/host}
    have=${pin:-$default_go}

    ver=$(sed -n 's/^PKG_VERSION:=//p' "$mk" | head -1)
    url=$(sed -n 's/^PKG_SOURCE_URL:=//p' "$mk" | head -1)
    repo=$(printf '%s' "$url" | sed -n 's|.*github\.com/\([^/]*\)/\([^/.]*\)\(\.git\)\?.*|\1/\2|p')
    if [ -z "$repo" ]; then warn "$name：源码不是 GitHub 或写法变了，跳过（$url）"; continue; fi

    ref=${url%%\?*}
    ref=${ref##*/tar.gz/}
    pkgname=$(sed -n 's/^PKG_NAME:=//p' "$mk" | head -1)
    ref=${ref//'$(PKG_VERSION)'/$ver}
    ref=${ref//'$(PKG_NAME)'/$pkgname}
    case "$ref" in *'$('*) warn "$name：源码 ref 展开后仍含变量，跳过（$ref）"; continue ;; esac

    if [ ! -d "$godir/golang$have" ]; then
      bad "$name：要用 golang$have，但 feed 里没有（可用：${avail_go:-无}）"
      continue
    fi
    need=$(required_go "$repo" "$ref")
    if [ -z "$need" ]; then warn "$name $ver：取不到 $repo@$ref 的 go.mod/go.work，跳过"; continue; fi
    # golang1.26 指的是 1.26 这条线，feed 的 Makefile 里才有准确 patch 号；
    # 不读它就会把「要求 1.26.0」误判成「1.26 满足不了」。
    local have_full="" cmp_have cmp_need
    if [ -f "$godir/golang$have/Makefile" ]; then
      have_full="$(sed -n 's/^GO_VERSION_MAJOR_MINOR:=//p' "$godir/golang$have/Makefile" | head -1)"
      have_full="$have_full.$(sed -n 's/^GO_VERSION_PATCH:=//p' "$godir/golang$have/Makefile" | head -1)"
      have_full=${have_full%.}
      cmp_have=$have_full; cmp_need=$need
    else
      cmp_have=$have; cmp_need=$(printf '%s' "$need" | cut -d. -f1,2)
    fi
    if ver_lt "$cmp_have" "$cmp_need"; then
      bad "$name $ver：go.mod 要求 $need，golang$have（$cmp_have）满足不了。改它 Makefile 的 PKG_BUILD_DEPENDS 指向更高版本（可用：$avail_go），或在 diy.sh 里打补丁"
    else
      ok "$name $ver：要求 $need，用 golang$have（$cmp_have）"
    fi
  done

  echo "== diy.sh 补丁"
  # Go 那条不重复查：上面的审计读的就是 diy.sh 改过之后的 PKG_BUILD_DEPENDS
  if grep -q 'IPV6:luci-proto-ipv6' feeds/luci/collections/luci-light/Makefile; then
    bad "luci-light 仍无条件依赖 luci-proto-ipv6，.config 里的 =n 会被改回 y"
  else
    ok "luci-light 的 luci-proto-ipv6 依赖已摘除"
  fi
}

precheck_config() {
  echo "== make defconfig 后的配置回读"
  local req=${1:-/tmp/n1-requested.config}
  [ -f .config ] || { bad "当前目录没有 .config"; return; }
  if [ ! -f "$req" ]; then warn "找不到请求配置快照 $req，跳过比对"; return; fi

  # include/target.mk 的 DEFAULT_PACKAGES 是另一条路子：它不走 =n，光改 .config 关不掉，
  # 所以这类符号被改回 y 只报 WARN，别把它当成 diy.sh 的补丁没生效。
  local dflt=""
  [ -f include/target.mk ] && dflt=$(awk '
    /^DEFAULT_PACKAGES(\.[a-z]+)?:=\\[[:space:]]*$/ {f=1; next}
    f && /^[[:space:]]+[A-Za-z0-9_.+-]+[[:space:]]*\\[[:space:]]*$/ {gsub(/[[:space:]\\\\]/,""); print; next}
    f {f=0}
  ' include/target.mk)

  local n=0 line sym want have short
  while IFS= read -r line; do
    case "$line" in
      CONFIG_*=y) sym=${line%=*}; want=y ;;
      CONFIG_*=m) sym=${line%=*}; want=m ;;
      CONFIG_*=n) sym=${line%=*}; want=n ;;
      '# CONFIG_'*' is not set') sym=${line#\# }; sym=${sym% is not set}; want=n ;;
      *) continue ;;
    esac
    n=$((n + 1))
    if   tr -d '\r' < .config | grep -q "^${sym}=y$"; then have=y
    elif tr -d '\r' < .config | grep -q "^${sym}=m$"; then have=m
    else have=n
    fi
    [ "$want" = "$have" ] && continue
    short=${sym#CONFIG_PACKAGE_}
    if [ "$want" = n ] && [ -n "$dflt" ] && printf '%s\n' "$dflt" | grep -qx -- "$short"; then
      warn "$sym：请求 n，defconfig 之后是 $have —— 它在 include/target.mk 的 DEFAULT_PACKAGES 里，要靠 .config 关不掉，只能改那份列表"
    else
      bad "$sym：请求 $want，defconfig 之后是 $have（多半是被某条 select 强制改写了）"
    fi
  done < <(tr -d '\r' < "$req")
  echo "  共比对 $n 项（DEFAULT_PACKAGES 命中 $(printf '%s\n' "$dflt" | grep -c .) 项在册）"
  [ "$FAIL" = 0 ] && ok "没有需要拦下的配置偏移"
}

case "$MODE" in
  feeds)  precheck_feeds ;;
  config) precheck_config "${2:-/tmp/n1-requested.config}" ;;
  *) echo "用法：$0 [feeds|config]"; exit 2 ;;
esac

[ "$FAIL" = 0 ] || { echo "预检未通过（上面 [FAIL] 行），已在此中止，不进入 download/compile。"; exit 1; }
echo "预检通过。"
