#!/bin/sh
# 30-custom-network：定制配置开关、网口选择、默认模式、IPv6
. "$(dirname "$0")/helpers.sh"

S="$REPO/build/files/etc/uci-defaults/30-custom-network"

run() {
	sh "$S" || fail "30-custom-network 退出码非 0"
}

absent() { # absent <key> <说明>
	uci -q get "$1" >/dev/null && fail "$2: $1 应不存在，实际为 [$(uci_val "$1")]"
	return 0
}

# 开启定制配置时的 IPv6：只有 WAN 侧取地址，局域网不使用 IPv6
check_ipv6_common() {
	absent network.lan.ip6assign "局域网不分配 v6 前缀"
	absent network.globals.ula_prefix "不使用 ULA"
	assert_eq "try" "$(uci_val network.wan6.reqaddress)" "wan6 获取地址"
	assert_eq "no" "$(uci_val network.wan6.reqprefix)" "wan6 不请求前缀"
	assert_eq "0" "$(uci_val network.wan6.peerdns)" "wan6 不用运营商 DNS"
}

# 关闭定制配置时的 IPv6：保持 ImmortalWrt 默认
check_ipv6_official() {
	assert_eq "60" "$(uci_val network.lan.ip6assign)" "$1: 局域网保持分配 v6 前缀"
	assert_eq "fd12:3456:789a::/48" "$(uci_val network.globals.ula_prefix)" "$1: 保留 ULA"
	absent network.wan6.reqaddress "$1: wan6 保持默认"
	absent network.wan6.reqprefix "$1: wan6 保持默认"
	absent network.wan6.peerdns "$1: wan6 保持默认"
}

# 定制模式：check_custom <wan> <lan> <说明>
check_custom() {
	assert_eq "$1" "$(uci_val network.wan.device)" "$3: WAN 网口"
	assert_eq "pppoe" "$(uci_val network.wan.proto)" "$3: WAN 使用 PPPoE"
	absent network.wan.username "$3: PPPoE 用户名留空"
	absent network.wan.password "$3: PPPoE 密码留空"
	assert_eq "1" "$(uci_val network.wan.ipv6)" "$3: PPPoE 启用 IPv6"
	assert_eq "0" "$(uci_val network.wan.peerdns)" "$3: 不用运营商 DNS"
	assert_eq "@wan" "$(uci_val network.wan6.device)" "$3: wan6 跟随 PPPoE"
	assert_eq "dhcpv6" "$(uci_val network.wan6.proto)" "$3: wan6 DHCPv6"
	assert_eq "$2" "$(uci_val network.lan.device)" "$3: LAN 直接使用网口"
	assert_eq "static" "$(uci_val network.lan.proto)" "$3: LAN 静态地址"
	assert_eq "10.214.37.1" "$(uci_val network.lan.ipaddr)" "$3: LAN 地址"
	assert_eq "255.255.255.0" "$(uci_val network.lan.netmask)" "$3: LAN 掩码"
	absent "network.@device[0].name" "$3: 删除 br-lan 网桥"
	absent "network.ll_$1" "$3: WAN 口不另建接口"
	absent "network.ll_$2" "$3: LAN 口不另建接口"
	check_ipv6_common
	assert_file_contains "$LOG_FILE" "mode=custom wan=$1 lan=$2" "$3: 日志记录模式"
}

# 默认模式：官方布局，只改 LAN 地址
check_default() {
	assert_eq "br-lan" "$(uci_val network.lan.device)" "$1: LAN 仍为 br-lan"
	assert_eq "eth0" "$(uci_val network.@device[0].ports)" "$1: 网桥保留"
	assert_eq "eth1" "$(uci_val network.wan.device)" "$1: WAN 保持 eth1"
	assert_eq "dhcp" "$(uci_val network.wan.proto)" "$1: WAN 保持 DHCP"
	assert_eq "0" "$(uci_val network.wan.peerdns)" "$1: 不用运营商 DNS"
	assert_eq "10.214.37.1" "$(uci_val network.lan.ipaddr)" "$1: LAN 地址"
	assert_eq "255.255.255.0" "$(uci_val network.lan.netmask)" "$1: LAN 掩码"
	assert_eq "eth1" "$(uci_val network.wan6.device)" "$1: wan6 保持 eth1"
	assert_eq "" "$(uci show network | grep '^network\.ll_')" "$1: 默认模式不建 ll_ 接口"
	assert_file_contains "$LOG_FILE" "mode=default" "$1: 日志记录模式"
}

# A：开启，2 个 2.5G + 2 个 1G -> 用两个 2.5G 口
setup_env
custom_config 1
make_port eth0 1g
make_port eth1 2g5
make_port eth2 2g5
make_port eth3 1g
run
check_custom eth1 eth2 "A"
assert_eq "eth0" "$(uci_val network.ll_eth0.device)" "A: eth0 单独启用"
assert_eq "none" "$(uci_val network.ll_eth0.proto)" "A: eth0 无地址"
assert_eq "eth3" "$(uci_val network.ll_eth3.device)" "A: eth3 单独启用"
assert_eq "none" "$(uci_val network.ll_eth3.proto)" "A: eth3 无地址"
assert_file_contains "$LOG_FILE" "eth1 2500" "A: 日志记录网口速率"
assert_file_contains "$LOG_FILE" "2.5G" "A: 日志说明按 2.5G 选择"

# B：开启，只有 1 个 2.5G -> 按顺序 eth0=WAN、eth1=LAN
setup_env
custom_config 1
make_port eth0 1g
make_port eth1 2g5
run
check_custom eth0 eth1 "B"
assert_file_contains "$LOG_FILE" "first two ports" "B: 日志说明按顺序选择"

# C：开启，3 个 2.5G -> 按顺序，其余网口单独启用
setup_env
custom_config 1
make_port eth0 2g5
make_port eth1 2g5
make_port eth2 2g5
run
check_custom eth0 eth1 "C"
assert_eq "none" "$(uci_val network.ll_eth2.proto)" "C: eth2 单独启用"

# D：开启，2.5G + 10G + 2.5G -> 用两个 2.5G 口，10G 口单独启用
setup_env
custom_config 1
make_port eth0 2g5
make_port eth1 10g
make_port eth2 2g5
run
check_custom eth0 eth2 "D"
assert_eq "none" "$(uci_val network.ll_eth1.proto)" "D: 10G 口单独启用"

# E：开启，虚拟机 virtio 网口 -> 按顺序
setup_env
custom_config 1
make_port eth0 virtio
make_port eth1 virtio
run
check_custom eth0 eth1 "E"

# F：开启，但只有 1 个网口 -> 默认模式
setup_env
custom_config 1
make_port eth0 1g
run
assert_eq "br-lan" "$(uci_val network.lan.device)" "F: 单网口保持 br-lan"
assert_eq "10.214.37.1" "$(uci_val network.lan.ipaddr)" "F: LAN 地址"
assert_file_contains "$LOG_FILE" "mode=default" "F: 日志记录模式"
assert_file_contains "$LOG_FILE" "fewer than 2" "F: 日志说明网口不足"
check_ipv6_common

# G：关闭，即使有 2 个 2.5G 口也用默认模式，且不做网口识别
setup_env
custom_config 0
make_port eth0 2g5
make_port eth1 2g5
run
check_default "G"
check_ipv6_official "G"
assert_file_contains "$LOG_FILE" "disabled" "G: 日志说明定制配置已关闭"
grep -q "port eth0" "$LOG_FILE" && fail "G: 关闭时不应识别网口"

# H：配置里没有 CUSTOM_CONFIG -> 视为关闭
setup_env
make_port eth0 2g5
make_port eth1 2g5
run
check_default "H"
check_ipv6_official "H"

# I：已初始化（保留配置升级）-> 不改任何配置
setup_env
custom_config 1
make_port eth0 1g
make_port eth1 2g5
make_port eth2 2g5
touch "$CUSTOM_MARKER"
run
assert_eq "" "$(cat "$UCI_LOG")" "I: 已初始化时不写 uci"

pass
