#!/bin/sh
# 在 immortalwrt/imagebuilder 容器内执行：应用镜像配置、集成软件包、生成固件并校验。
# 由 .github/workflows/build.yml 调用，挂载：
#   /home/build/immortalwrt/{build.sh,config.override,packages.txt}
#   /staging/files   build/stage.sh 生成的根目录覆盖层
#   /extra/apk       官方源以外的 apk（timecontrol）
#   /home/build/immortalwrt/bin   输出目录

IB_DIR=/home/build/immortalwrt

# 固件中不应出现的包：dropbear（改用 OpenSSH）、精简版 dnsmasq（改用 dnsmasq-full）、
# legacy iptables（只用 nftables 兼容层）、官方 Docker 包（改用静态二进制）
FORBIDDEN_PACKAGES="dropbear dnsmasq iptables-zz-legacy ip6tables-zz-legacy xtables-legacy dockerd docker containerd runc"

# apply_config_override <覆盖片段> <.config>：只替换片段里出现的配置项，其余保持官方默认
apply_config_override() {
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			CONFIG_*=*) key=${line%%=*} ;;
			"# CONFIG_"*" is not set")
				key=${line#"# "}
				key=${key%" is not set"}
				;;
			*) continue ;;
		esac
		awk -v k="$key" '!(index($0, k "=") == 1 || $0 == "# " k " is not set")' "$2" > "$2.tmp"
		mv "$2.tmp" "$2"
		echo "$line" >> "$2"
	done < "$1"
}

# packages_from_list <清单>：去掉注释和空行，输出空格分隔的包名
packages_from_list() {
	awk '{ sub(/#.*/, ""); for (i = 1; i <= NF; i++) printf "%s%s", (n++ ? " " : ""), $i } END { print "" }' "$1"
}

# check_manifest <manifest> <清单>：不能有 FORBIDDEN_PACKAGES，清单里要求的包都要在
check_manifest() {
	_names=$(awk '{ print $1 }' "$1")
	_bad=0
	for p in $FORBIDDEN_PACKAGES; do
		if printf '%s\n' "$_names" | grep -qx -- "$p"; then
			echo "固件中不应包含：$p"
			_bad=1
		fi
	done
	for p in $(packages_from_list "$2"); do
		case "$p" in -*) continue ;; esac
		if ! printf '%s\n' "$_names" | grep -qx -- "$p"; then
			echo "固件中缺少：$p"
			_bad=1
		fi
	done
	return $_bad
}

# check_images <目录>：恰好一个 squashfs-combined-efi.img.gz，没有 BIOS 镜像、ISO、ext4 镜像
check_images() {
	_n=$(find "$1" -maxdepth 1 -name '*-squashfs-combined-efi.img.gz' | wc -l)
	if [ "$_n" -ne 1 ]; then
		echo "应恰好生成一个 squashfs-combined-efi.img.gz，实际 $_n 个"
		return 1
	fi
	_extra=$(find "$1" -maxdepth 1 \( -name '*-combined.img.gz' -o -name '*.iso' -o -name '*ext4*' \))
	if [ -n "$_extra" ]; then
		echo "不应生成：$_extra"
		return 1
	fi
	return 0
}

main() {
	set -eu
	cd "$IB_DIR"

	echo "==> 应用镜像配置"
	apply_config_override config.override .config
	grep -E '^(# )?CONFIG_(TARGET_ROOTFS_(SQUASHFS|EXT4FS|TARGZ|PARTSIZE)|GRUB_|ISO_IMAGES|TARGET_IMAGES_GZIP)' .config

	echo "==> 本地软件包（官方源以外）"
	mkdir -p packages
	cp /extra/apk/*.apk packages/
	ls -l packages/

	pkgs=$(packages_from_list packages.txt)
	echo "==> 生成固件：$pkgs"
	make image PROFILE=generic PACKAGES="$pkgs" FILES=/staging/files

	out=bin/targets/x86/64
	echo "==> 校验产物"
	check_images "$out"
	set -- "$out"/*.manifest
	[ $# -eq 1 ] && [ -f "$1" ] || { echo "应恰好有一个 manifest 文件：$*"; exit 1; }
	check_manifest "$1" packages.txt
	ls -lh "$out"
	echo "==> 构建完成"
}

[ -n "${BUILD_LIB_ONLY:-}" ] || main "$@"
