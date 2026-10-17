#!/bin/sh
# 在 GitHub Actions Runner 上下载官方软件源以外的组件（需要 curl、tar、gh，gh 使用 GH_TOKEN）。
# 用法：build/fetch-extras.sh <输出目录>
# 输出：
#   docker/            Docker 静态二进制（清华 TUNA 镜像的最新版，失败时改用 download.docker.com）
#   docker-compose     Docker Compose 插件（GitHub 最新版）
#   dpanel             DPanel 社区版 musl 二进制（GitHub 最新版）
#   dpanel-config.yaml DPanel 同版本的配置文件
#   apk/*.apk          luci-app-timecontrol 及其中文包（sirpdboy，nftables 版）
#   versions.env       各组件版本，供固件 /etc/custom/build.conf 与 Release 说明使用

DOCKER_MIRRORS="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/static/stable/x86_64 https://download.docker.com/linux/static/stable/x86_64"
DOCKER_BINARIES="dockerd docker containerd containerd-shim-runc-v2 ctr runc docker-init docker-proxy"

die() {
	echo "::error::$*" >&2
	exit 1
}

# 下载；速度低于 100 KB/s 持续 60 秒视为失败
download() {
	curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 \
		--speed-limit 102400 --speed-time 60 -o "$2" "$1"
}

# 从目录索引页（标准输入）中取最新的 docker-X.Y.Z.tgz 版本号，按数字比较
latest_docker_version() {
	awk '{
			while (match($0, /docker-[0-9]+\.[0-9]+\.[0-9]+\.tgz/)) {
				print substr($0, RSTART + 7, RLENGTH - 11)
				$0 = substr($0, RSTART + RLENGTH)
			}
		}' | sort -u -t. -k1,1n -k2,2n -k3,3n | tail -n 1
}

gh_latest_tag() {
	gh api "repos/$1/releases/latest" --jq .tag_name
}

fetch_docker() {
	for base in $DOCKER_MIRRORS; do
		v=$(curl -fsSL --retry 3 --connect-timeout 20 "$base/" | latest_docker_version)
		if [ -n "$v" ] && download "$base/docker-$v.tgz" "$OUT/docker.tgz"; then
			DOCKER_VERSION=$v
			DOCKER_SOURCE=$base
			break
		fi
		echo "::warning::从 $base 获取 Docker 失败，尝试下一个下载源"
	done
	[ -n "${DOCKER_VERSION:-}" ] || die "无法下载 Docker 静态二进制"
	tar -xzf "$OUT/docker.tgz" -C "$OUT"
	rm -f "$OUT/docker.tgz"
	for b in $DOCKER_BINARIES; do
		[ -x "$OUT/docker/$b" ] || die "Docker $DOCKER_VERSION 中缺少 $b"
	done
	echo "Docker $DOCKER_VERSION（$DOCKER_SOURCE）"
}

fetch_compose() {
	COMPOSE_VERSION=$(gh_latest_tag docker/compose) || die "无法获取 Docker Compose 最新版本"
	download "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-linux-x86_64" \
		"$OUT/docker-compose" || die "下载 Docker Compose $COMPOSE_VERSION 失败"
	echo "Docker Compose $COMPOSE_VERSION"
}

fetch_dpanel() {
	DPANEL_VERSION=$(gh_latest_tag donknap/dpanel) || die "无法获取 DPanel 最新版本"
	base="https://github.com/donknap/dpanel/releases/download/$DPANEL_VERSION"
	download "$base/dpanel-ce-musl-amd64" "$OUT/dpanel" || die "下载 dpanel-ce-musl-amd64 失败"
	download "$base/config.yaml" "$OUT/dpanel-config.yaml" || die "下载 DPanel config.yaml 失败"
	echo "DPanel $DPANEL_VERSION"
}

fetch_timecontrol() {
	TIMECONTROL_VERSION=$(gh_latest_tag sirpdboy/luci-app-timecontrol) || die "无法获取 timecontrol 最新版本"
	download "https://github.com/sirpdboy/luci-app-timecontrol/releases/download/$TIMECONTROL_VERSION/SNAPSHOT-x86_64.tar.gz" \
		"$OUT/timecontrol.tar.gz" || die "下载 timecontrol $TIMECONTROL_VERSION 失败"
	mkdir -p "$OUT/timecontrol"
	tar -xzf "$OUT/timecontrol.tar.gz" -C "$OUT/timecontrol"
	find "$OUT/timecontrol" -name '*.apk' -exec cp {} "$OUT/apk/" \;
	rm -rf "$OUT/timecontrol" "$OUT/timecontrol.tar.gz"
	for p in luci-app-timecontrol luci-i18n-timecontrol-zh-cn; do
		ls "$OUT/apk/$p"-[0-9]*.apk >/dev/null 2>&1 || die "timecontrol $TIMECONTROL_VERSION 中缺少 $p"
	done
	echo "timecontrol $TIMECONTROL_VERSION"
}

main() {
	set -eu
	OUT=${1:?用法：build/fetch-extras.sh <输出目录>}
	mkdir -p "$OUT/apk"
	fetch_docker
	fetch_compose
	fetch_dpanel
	fetch_timecontrol
	cat > "$OUT/versions.env" <<-VERSIONS
		DOCKER_VERSION='$DOCKER_VERSION'
		DOCKER_SOURCE='$DOCKER_SOURCE'
		COMPOSE_VERSION='$COMPOSE_VERSION'
		DPANEL_VERSION='$DPANEL_VERSION'
		TIMECONTROL_VERSION='$TIMECONTROL_VERSION'
	VERSIONS
	cat "$OUT/versions.env"
}

[ -n "${BUILD_LIB_ONLY:-}" ] || main "$@"
