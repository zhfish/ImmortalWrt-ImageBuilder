#!/bin/bash
# x86-64 ImmortalWrt 25.12.x 固件构建脚本
# 运行在 immortalwrt/imagebuilder 容器内，由 .github/workflows/build-x86-64-25.12.x.yml 调用。
#
# 输入（环境变量）：
#   CUSTOM_ROUTER_IP   LAN 管理地址
#
# 固定配置：
#   根分区 4G       见 x86-64/config.override 中的 CONFIG_TARGET_ROOTFS_PARTSIZE
#   集成 Docker     见下方默认软件包列表
#
# 输出（写入挂载的 bin/ 目录）：
#   bin/targets/x86/64/   固件镜像
#   bin/packages.txt      本次请求集成的软件包（用于 Release 说明）
set -euo pipefail

IB_DIR=/home/build/immortalwrt
cd "$IB_DIR"

: "${CUSTOM_ROUTER_IP:=10.214.37.1}"

# 集成 luci-app-ssr-plus 时下载的 mihomo 内核版本
MIHOMO_VERSION="v1.19.24"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"; }

# 判断 PACKAGES 中是否包含某个包（不用 echo | grep -q，避免 pipefail 下的误判）
has_package() { [[ " $PACKAGES " == *" $1 "* ]]; }


# ============ 1. 应用 .config 覆盖片段 ============
# 只覆盖 config.override 中出现的配置项，其余保持 ImageBuilder 自带的官方默认值
apply_config_override() {
    local line key
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            CONFIG_*=*) key=${line%%=*} ;;
            "# CONFIG_"*" is not set") key=${line#"# "}; key=${key%" is not set"} ;;
            *) continue ;;
        esac
        sed -i -e "/^${key}=/d" -e "/^# ${key} is not set\$/d" .config
        echo "$line" >> .config
    done < "$1"
}
apply_config_override config.override
log "生效的镜像配置："
grep -E '^(# )?CONFIG_(TARGET_ROOTFS_(SQUASHFS|EXT4FS|TARGZ|PARTSIZE)|GRUB_|ISO_IMAGES|QCOW2_IMAGES|VDI_IMAGES|VMDK_IMAGES|VHDX_IMAGES|TARGET_IMAGES_GZIP|TARGET_KERNEL_PARTSIZE)' .config


# ============ 2. 生成设置 LAN 地址的首次启动脚本 ============
# 固件首次启动时执行一次；其余网络设置保持 ImmortalWrt 官方默认
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/90-lan-ip <<EOF
#!/bin/sh
# 由 x86-64/build25.sh 在构建时生成：设置 LAN 管理地址
uci set network.lan.ipaddr='${CUSTOM_ROUTER_IP}'
uci commit network
exit 0
EOF
log "管理地址: $CUSTOM_ROUTER_IP"


# ============ 3. 组装软件包列表 ============
source shell/apk-custom-packages.sh

if [ -n "${CUSTOM_PACKAGES// /}" ]; then
    log "同步第三方软件仓库 wukongdaily/apk ..."
    rm -rf /tmp/store-apk-repo
    git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo
    mkdir -p extra-packages
    cp -r /tmp/store-apk-repo/run/x86/* extra-packages/
    # 解包 .run 文件，把其中的 apk 放进 ImageBuilder 的本地软件源 packages/
    sh shell/apk-prepare-packages.sh
    ls -lah packages/
else
    log "未选择任何自定义软件包"
fi

# 默认集成的软件包，可按需增删
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES openssh-sftp-server"                 # SFTP，可用 WinSCP 等工具传文件
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"            # 防火墙中文界面
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"     # 软件包管理
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"             # 磁盘管理
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"         # 文件管理
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"                # 网页终端
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"  # Argon 主题
PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"           # Docker 及其管理界面
# nftables 防火墙栈（均为官方默认，这里显式写出，防止被换成旧版）：
#   firewall4 + nftables-json   防火墙（不用 fw3）
#   dnsmasq-full                DNS/DHCP，官方编译开启 nftset、未开启 ipset
#   kmod-nft-offload            软件流量卸载，依赖 kmod-nf-flow
PACKAGES="$PACKAGES firewall4 nftables-json dnsmasq-full kmod-nft-offload kmod-nf-flow"
# Docker 硬性依赖 iptables/ip6tables：明确指定 nft 转换层版本，不装 legacy 版本。
# Docker 本身已改用 nftables 后端（见 files/etc/docker/daemon.json），不会调用它们
PACKAGES="$PACKAGES iptables-nft ip6tables-nft"
# shell/apk-custom-packages.sh 中启用的包
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# OpenClash：下载 Meta 内核、GeoIP/GeoSite 数据和最新版 apk
if has_package luci-app-openclash; then
    log "已选择 luci-app-openclash，下载内核和规则数据"
    mkdir -p files/etc/openclash/core
    wget -qO- https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64-v1.tar.gz \
        | tar xOz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
    RELEASE_JSON=$(curl -fsSL https://api.github.com/repos/vernesong/OpenClash/releases/latest)
    OPENCLASH_URL=$(grep -m1 -oE '"browser_download_url": *"[^"]+\.apk"' <<< "$RELEASE_JSON" | cut -d '"' -f 4 || true)
    if [ -z "$OPENCLASH_URL" ]; then
        echo "错误：无法获取 OpenClash 最新版 apk 的下载地址" >&2
        exit 1
    fi
    log "OpenClash apk: $OPENCLASH_URL"
    mkdir -p packages
    wget -q "$OPENCLASH_URL" -P packages/
fi

# ShadowSocksR Plus+：下载 mihomo 内核
if has_package luci-app-ssr-plus; then
    log "已选择 luci-app-ssr-plus，下载 mihomo $MIHOMO_VERSION"
    mkdir -p files/usr/bin
    wget -qO- "https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/mihomo-linux-amd64-compatible-${MIHOMO_VERSION}.gz" \
        | gzip -dc > files/usr/bin/mihomo
    chmod +x files/usr/bin/mihomo
fi

mkdir -p bin
# shellcheck disable=SC2086  # 按空格拆成每行一个包
printf '%s\n' $PACKAGES > bin/packages.txt
log "请求集成的软件包："
cat bin/packages.txt


# ============ 4. 构建镜像 ============
# 根分区大小取自 config.override 中的 CONFIG_TARGET_ROOTFS_PARTSIZE
log "开始构建固件"
make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="$IB_DIR/files"
log "构建完成"
ls -lh bin/targets/x86/64/
