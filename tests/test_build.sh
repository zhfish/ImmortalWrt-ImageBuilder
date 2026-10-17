#!/bin/sh
# 构建脚本中的函数：输入校验、Docker 版本选择、软件包清单、manifest 校验、覆盖层渲染
. "$(dirname "$0")/helpers.sh"
setup_env
F="$REPO/tests/fixtures"
B="$REPO/build"

# 不 export：只让 source 进来的脚本跳过 main，子进程里的命令行调用照常执行
# shellcheck disable=SC2034  # 由 source 进来的脚本读取
BUILD_LIB_ONLY=1
. "$B/validate-inputs.sh"
. "$B/fetch-extras.sh"
. "$B/stage.sh"
. "$B/build.sh"

# 输入校验：版本号
for v in 25.12.2 25.12.0-rc2 24.10.10; do
	valid_version "$v" || fail "版本号应合法: [$v]"
done
for v in 25.12 v25.12.2 "25.12.2 " "" "25.12.2
x"; do
	valid_version "$v" && fail "版本号应非法: [$v]"
done

# 输入校验：LAN 地址必须是 x.x.x.1
for ip in 10.214.37.1 192.168.1.1 172.16.0.1; do
	valid_lan_ip "$ip" || fail "LAN 地址应合法: [$ip]"
done
for ip in 10.214.37.2 192.168.1.254 10.214.37.01 010.214.37.1 256.1.1.1 "10.214.37.1 " 10.214.37 10.214.37.1.1 "" a.b.c.1; do
	valid_lan_ip "$ip" && fail "LAN 地址应非法: [$ip]"
done

# 命令行：非法输入时输出 ::error:: 并返回 1
out=$(sh "$B/validate-inputs.sh" 25.12.2 10.214.37.2 2>&1) && fail "非法 LAN 地址应返回 1"
assert_contains "$out" "::error::" "非法输入输出 ::error::"
sh "$B/validate-inputs.sh" 25.12.2 10.214.37.1 >/dev/null 2>&1 || fail "合法输入应返回 0"

# Docker 版本按数字比较：29.10.0 > 29.9.1；忽略 rc 和 rootless-extras
assert_eq "29.10.0" "$(latest_docker_version < "$F/docker-index.html")" "取最新 Docker 版本"
assert_eq "" "$(echo '<html></html>' | latest_docker_version)" "没有版本时不输出"

# 软件包清单
assert_eq "-dropbear -dnsmasq curl openssh-server ethtool luci-i18n-nut-zh-cn" \
	"$(packages_from_list "$F/packages-small.txt")" "packages_from_list"

# manifest 校验
check_manifest "$F/manifest-good.txt" "$F/packages-small.txt" >/dev/null || fail "正常 manifest 应通过"
out=$(check_manifest "$F/manifest-bad.txt" "$F/packages-small.txt") && fail "含 dropbear、缺 ethtool 的 manifest 应失败"
assert_contains "$out" "dropbear" "报告多出的 dropbear"
assert_contains "$out" "ethtool" "报告缺少的 ethtool"

# 产物校验
mkdir -p "$T/img"
touch "$T/img/immortalwrt-25.12.2-x86-64-generic-squashfs-combined-efi.img.gz" \
	"$T/img/immortalwrt-25.12.2-x86-64-generic-kernel.bin"
check_images "$T/img" >/dev/null || fail "只有 combined-efi 时应通过"
touch "$T/img/immortalwrt-25.12.2-x86-64-generic-squashfs-combined.img.gz"
check_images "$T/img" >/dev/null && fail "出现 BIOS 镜像时应失败"
rm "$T/img/immortalwrt-25.12.2-x86-64-generic-squashfs-combined.img.gz"
touch "$T/img/immortalwrt-25.12.2-x86-64-generic-image-efi.iso"
check_images "$T/img" >/dev/null && fail "出现 ISO 时应失败"
rm -f "$T/img"/*
check_images "$T/img" >/dev/null && fail "没有 combined-efi 时应失败"

# .config 覆盖
printf '%s\n' 'CONFIG_GRUB_TIMEOUT="0"' '# CONFIG_TARGET_ROOTFS_PARTSIZE is not set' 'CONFIG_ISO_IMAGES=y' 'CONFIG_OTHER=y' > "$T/.config"
printf '%s\n' '## 说明' 'CONFIG_GRUB_TIMEOUT="3"' 'CONFIG_TARGET_ROOTFS_PARTSIZE=4096' '# CONFIG_ISO_IMAGES is not set' > "$T/override"
apply_config_override "$T/override" "$T/.config"
assert_eq "1" "$(grep -c 'CONFIG_GRUB_TIMEOUT' "$T/.config")" "GRUB_TIMEOUT 只有一行"
assert_file_contains "$T/.config" 'CONFIG_GRUB_TIMEOUT="3"' "GRUB 等待 3 秒"
assert_file_contains "$T/.config" 'CONFIG_TARGET_ROOTFS_PARTSIZE=4096' "rootfs 4096"
assert_file_contains "$T/.config" '# CONFIG_ISO_IMAGES is not set' "关闭 ISO"
grep -q '^CONFIG_ISO_IMAGES=y' "$T/.config" && fail "ISO 的旧值应被删除"
assert_file_contains "$T/.config" 'CONFIG_OTHER=y' "其他配置保留"
grep -q '说明' "$T/.config" && fail "## 说明行不应写入 .config"

# 本仓库的镜像配置
C="$B/config.override"
for line in 'CONFIG_GRUB_EFI_IMAGES=y' '# CONFIG_GRUB_IMAGES is not set' 'CONFIG_GRUB_TIMEOUT="3"' \
	'CONFIG_TARGET_ROOTFS_PARTSIZE=4096' 'CONFIG_TARGET_ROOTFS_SQUASHFS=y' '# CONFIG_ISO_IMAGES is not set'; do
	grep -qxF "$line" "$C" || fail "config.override 缺少: $line"
done

# 本仓库的软件包清单（抽查规格中的关键项）
PK=" $(packages_from_list "$B/packages.txt") "
for p in -dropbear -dnsmasq dnsmasq-full firewall4 nftables-json iptables-nft ip6tables-nft \
	kmod-tcp-bbr kmod-nft-offload kmod-nf-flow kmod-macvlan openssh-server luci-theme-argon \
	luci-i18n-nut-zh-cn nut-driver-usbhid-ups luci-app-timecontrol luci-i18n-timecontrol-zh-cn \
	luci-app-softether luci-i18n-softether-zh-cn openvpn-openssl luci-proto-wireguard \
	miniupnpd-nftables luci-i18n-wol-zh-cn default-settings-chn sfdisk partx-utils e2fsprogs ethtool; do
	assert_contains "$PK" " $p " "packages.txt 应包含 $p"
done
for p in luci-app-softethervpn dockerd docker luci-app-dockerman luci-app-openvpn-server; do
	assert_not_contains "$PK" " $p " "packages.txt 不应包含 $p"
done

# Action 勾选项 -> build.conf 中的 1/0
assert_eq "1" "$(bool_flag true)" "true -> 1"
assert_eq "0" "$(bool_flag false)" "false -> 0"
assert_eq "1" "$(bool_flag 1)" "1 -> 1"
assert_eq "0" "$(bool_flag 0)" "0 -> 0"
bool_flag yes >/dev/null && fail "无法识别的值应返回 1"
bool_flag "" >/dev/null && fail "空值应返回 1"

# 模板渲染
printf '{"dns": ["@LAN_IP@"], "x": "@LAN_IP@"}\n' > "$T/t.in"
render_template "$T/t.in" "$T/t.out" 10.1.2.1
assert_eq '{"dns": ["10.1.2.1"], "x": "10.1.2.1"}' "$(cat "$T/t.out")" "替换所有 @LAN_IP@"

# DPanel 配置：只把 prof 的监听地址改成 127.0.0.1
cp "$F/dpanel-config.yaml" "$T/config.yaml"
patch_dpanel_config "$T/config.yaml" || fail "应找到 prof.host"
assert_file_contains "$T/config.yaml" 'host: ${APP_SERVER_HOST-0.0.0.0}' "面板监听地址不变"
assert_eq "1" "$(grep -c 'host: 127.0.0.1' "$T/config.yaml")" "prof 改为 127.0.0.1"
grep -q 'host: 0.0.0.0$' "$T/config.yaml" && fail "不应再有 0.0.0.0 的 prof"
printf 'app:\n  name: x\n' > "$T/noprof.yaml"
patch_dpanel_config "$T/noprof.yaml" && fail "没有 prof 时应返回 1"

pass
