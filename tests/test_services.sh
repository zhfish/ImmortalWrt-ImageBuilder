#!/bin/sh
# lan-macvlan.sh（创建 Docker macvlan 网络）、daemon.json 模板、LuCI 菜单
. "$(dirname "$0")/helpers.sh"

M="$REPO/build/files/usr/libexec/custom/lan-macvlan.sh"
CREATE="network create -d macvlan --subnet 10.214.37.0/24 --gateway 10.214.37.1 --ip-range 10.214.37.8/29 -o parent=eth2 lan_macvlan"

# a) 网络不存在：按 LAN 设置创建
setup_env
uci -q set network.lan.device=eth2
DOCKER_NET_EXISTS=0 sh "$M" || fail "a: 退出码非 0"
assert_file_contains "$DOCKER_LOG" "$CREATE" "a: 创建 lan_macvlan"

# b) 已存在且一致：不重建、不告警
setup_env
uci -q set network.lan.device=eth2
DOCKER_NET_EXISTS=1 DOCKER_NET_DESC='10.214.37.0/24 eth2' sh "$M"
grep -q "network create" "$DOCKER_LOG" && fail "b: 已存在时不应创建"
grep -q "lan_macvlan" "$LOG_FILE" && fail "b: 一致时不应告警"

# c) 已存在但与 LAN 不一致：只告警，不重建
setup_env
uci -q set network.lan.device=eth2
DOCKER_NET_EXISTS=1 DOCKER_NET_DESC='192.168.1.0/24 br-lan' sh "$M"
grep -q "network create" "$DOCKER_LOG" && fail "c: 不一致时也不应重建"
assert_file_contains "$LOG_FILE" "lan_macvlan" "c: 记录不一致告警"

# d) Docker 一直没就绪：超时退出，不创建
setup_env
uci -q set network.lan.device=eth2
DOCKER_INFO_RC=1 DOCKER_WAIT=2 sh "$M" || fail "d: 超时也应退出 0"
grep -q "network create" "$DOCKER_LOG" && fail "d: Docker 未就绪时不应创建"
assert_file_contains "$LOG_FILE" "timeout" "d: 记录超时"

# e/f 需要 jq（busybox 镜像里没有，Ubuntu 上的 dash 运行会覆盖）
if command -v jq >/dev/null 2>&1; then
	# e) daemon.json 模板
	J="$T/daemon.json"
	sed 's/@LAN_IP@/10.214.37.1/g' "$REPO/build/templates/daemon.json.in" > "$J"
	assert_eq "nftables" "$(jq -r '.["firewall-backend"]' "$J")" "e: nftables 后端"
	assert_eq "/data/docker" "$(jq -r '.["data-root"]' "$J")" "e: 数据目录"
	assert_eq "json-file" "$(jq -r '.["log-driver"]' "$J")" "e: json 日志"
	assert_eq "100m" "$(jq -r '.["log-opts"]["max-size"]' "$J")" "e: 单个日志 100m"
	assert_eq "5" "$(jq -r '.["log-opts"]["max-file"]' "$J")" "e: 最多 5 个日志文件"
	assert_eq "10.214.37.1" "$(jq -r '.dns[0]' "$J")" "e: 容器 DNS 指向路由器"

	# f) LuCI 菜单
	MENU="$REPO/build/files/usr/share/luci/menu.d/luci-app-dpanel.json"
	assert_eq "DPanel" "$(jq -r '.["admin/services/dpanel"].title' "$MENU")" "f: 菜单标题"
	assert_eq "view" "$(jq -r '.["admin/services/dpanel"].action.type' "$MENU")" "f: 菜单类型"
	assert_eq "dpanel" "$(jq -r '.["admin/services/dpanel"].action.path' "$MENU")" "f: 视图路径"
	V="$REPO/build/files/www/luci-static/resources/view/dpanel.js"
	assert_file_contains "$V" "window.location.replace" "f: 用 replace 跳转"
	assert_file_contains "$V" "':8086/'" "f: 跳转到 8086 端口"

else
	echo "note: jq not available, JSON checks skipped"
fi

pass
