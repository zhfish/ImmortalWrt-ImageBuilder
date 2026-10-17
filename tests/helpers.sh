#!/bin/sh
# 测试公共函数。各测试文件以 `. "$(dirname "$0")/helpers.sh"` 引入。
# shellcheck disable=SC2034  # T 等变量由测试文件使用

REPO=$(cd "$(dirname "$0")/.." && pwd)

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

pass() {
	echo "ok"
	exit 0
}

assert_eq() {
	[ "$1" = "$2" ] || fail "$3: expected [$1] got [$2]"
}

assert_contains() {
	case "$1" in
		*"$2"*) ;;
		*) fail "$3: [$2] not found in [$1]" ;;
	esac
}

assert_not_contains() {
	case "$1" in
		*"$2"*) fail "$3: [$2] unexpectedly found in [$1]" ;;
	esac
}

assert_file_contains() {
	grep -qF -- "$2" "$1" || fail "$3: [$2] not found in $1"
}

# 准备隔离的测试环境：伪命令、伪 sysfs、伪 uci 状态，全部位于临时目录 $T
setup_env() {
	[ -n "${T:-}" ] && rm -rf "$T"
	T=$(mktemp -d "${TMPDIR:-/tmp}/custom-test.XXXXXX")
	trap 'rm -rf "$T"' EXIT
	PATH="$REPO/tests/stubs:$PATH"
	CUSTOM_LIBDIR="$REPO/build/files/usr/lib/custom"
	CUSTOM_CONF="$T/build.conf"
	CUSTOM_MARKER="$T/provisioned"
	CUSTOM_SYSFS="$T/sys"
	UCI_STATE="$T/uci.state"
	UCI_LOG="$T/uci.log"
	LOG_FILE="$T/log"
	ETHTOOL_DIR="$T/ethtool"
	DOCKER_LOG="$T/docker.log"
	export PATH CUSTOM_LIBDIR CUSTOM_CONF CUSTOM_MARKER CUSTOM_SYSFS \
		UCI_STATE UCI_LOG LOG_FILE ETHTOOL_DIR DOCKER_LOG

	printf "LAN_IP='10.214.37.1'\n" > "$CUSTOM_CONF"
	mkdir -p "$CUSTOM_SYSFS/class/net" "$ETHTOOL_DIR"
	cp "$REPO/tests/fixtures/uci/default.state" "$UCI_STATE"
	: > "$UCI_LOG"
	: > "$LOG_FILE"
	: > "$DOCKER_LOG"
}

# 读取伪 uci 状态中的值（列表以空格连接）
uci_val() {
	uci -q get "$1"
}

# make_port <名称> <ethtool 样本名|none> [wireless]：创建一个物理网口
make_port() {
	_d="$CUSTOM_SYSFS/class/net/$1"
	mkdir -p "$_d/device"
	echo 1 > "$_d/type"
	[ "${3:-}" = wireless ] && mkdir -p "$_d/wireless"
	[ "$2" = none ] || cp "$REPO/tests/fixtures/ethtool/$2.txt" "$ETHTOOL_DIR/$1"
}

# make_virtual <名称> <type>：创建一个没有 device 的虚拟接口
make_virtual() {
	_d="$CUSTOM_SYSFS/class/net/$1"
	mkdir -p "$_d"
	echo "$2" > "$_d/type"
}
