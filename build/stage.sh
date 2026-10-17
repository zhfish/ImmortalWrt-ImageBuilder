#!/bin/sh
# 组装固件根目录覆盖层：build/files + 下载的二进制 + 按 LAN 地址渲染的配置。
# 用法：build/stage.sh <fetch-extras 输出目录> <LAN 地址> <输出目录> [使用定制网口配置 true|false]

# bool_flag <值>：把 Action 的勾选结果（true/false）转成 build.conf 用的 1/0，无法识别时返回 1
bool_flag() {
	case "$1" in
		true | 1) echo 1 ;;
		false | 0) echo 0 ;;
		*) return 1 ;;
	esac
}

# render_template <模板> <输出> <LAN 地址>：替换所有 @LAN_IP@
render_template() {
	sed "s/@LAN_IP@/$3/g" "$1" > "$2"
}

# DPanel 的性能分析端口（prof，8087）默认监听 0.0.0.0，改为只监听本机。
# 找不到 prof.host 时返回 1（上游配置格式变了，需要人工确认）
patch_dpanel_config() {
	awk '
		/^  prof:/ { inprof = 1; print; next }
		/^[^ ]/ || /^  [^ ]/ { inprof = 0 }
		inprof && /^    host:/ { sub(/host:.*/, "host: 127.0.0.1"); done = 1 }
		{ print }
		END { exit !done }' "$1" > "$1.tmp"
	_rc=$?
	mv "$1.tmp" "$1"
	return $_rc
}

main() {
	set -eu
	extras=${1:?用法：build/stage.sh <下载目录> <LAN 地址> <输出目录>}
	lan_ip=${2:?缺少 LAN 地址}
	out=${3:?缺少输出目录}
	if ! custom_ports=$(bool_flag "${4:-false}"); then
		echo "::error::使用定制网口配置 的值无法识别：'$4'（应为 true 或 false）"
		exit 1
	fi
	here=$(cd "$(dirname "$0")" && pwd)

	rm -rf "$out"
	mkdir -p "$out"
	cp -a "$here/files/." "$out/"

	# Docker 静态二进制
	mkdir -p "$out/usr/bin"
	for b in dockerd docker containerd containerd-shim-runc-v2 ctr runc docker-init docker-proxy; do
		install -m 0755 "$extras/docker/$b" "$out/usr/bin/$b"
	done
	# Docker Compose 插件（docker compose），并提供 docker-compose 命令
	mkdir -p "$out/usr/libexec/docker/cli-plugins"
	install -m 0755 "$extras/docker-compose" "$out/usr/libexec/docker/cli-plugins/docker-compose"
	ln -sf ../libexec/docker/cli-plugins/docker-compose "$out/usr/bin/docker-compose"
	# Docker 配置
	mkdir -p "$out/etc/docker"
	render_template "$here/templates/daemon.json.in" "$out/etc/docker/daemon.json" "$lan_ip"

	# DPanel
	install -m 0755 "$extras/dpanel" "$out/usr/bin/dpanel"
	mkdir -p "$out/etc/dpanel"
	cp "$extras/dpanel-config.yaml" "$out/etc/dpanel/config.yaml"
	patch_dpanel_config "$out/etc/dpanel/config.yaml" ||
		echo "::warning::DPanel config.yaml 中没有找到 prof.host，性能分析端口 8087 仍监听 0.0.0.0"

	# 构建信息：首次启动脚本读取 LAN_IP、CUSTOM_PORTS，dpanel 服务读取 DPANEL_VERSION
	mkdir -p "$out/etc/custom"
	{
		echo "LAN_IP='$lan_ip'"
		echo "CUSTOM_PORTS='$custom_ports'"
		cat "$extras/versions.env"
		echo "BUILD_DATE='$(date -u '+%Y-%m-%dT%H:%M:%SZ')'"
	} > "$out/etc/custom/build.conf"

	echo "覆盖层已生成：$out"
	cat "$out/etc/custom/build.conf"
}

[ -n "${BUILD_LIB_ONLY:-}" ] || main "$@"
