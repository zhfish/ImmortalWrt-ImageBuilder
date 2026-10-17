#!/bin/sh
# 30-custom-network：网口识别、接口定制模式 / 默认模式、IPv6
. "$(dirname "$0")/helpers.sh"

S="$REPO/build/files/etc/uci-defaults/30-custom-network"

run() {
	sh "$S" || fail "30-custom-network 退出码非 0"
}

absent() { # absent <key> <说明>
	uci -q get "$1" >/dev/null && fail "$2: $1 应不存在，实际为 [$(uci_val "$1")]"
	return 0
}

# 两种模式都要满足的 IPv6 设置
check_ipv6_common() {
	absent network.lan.ip6assign "局域网不分配 v6 前缀"
	absent network.globals.ula_prefix "不使用 ULA"
	assert_eq "try" "$(uci_val network.wan6.reqaddress)" "wan6 获取地址"
	assert_eq "no" "$(uci_val network.wan6.reqprefix)" "wan6 不请求前缀"
	assert_eq "0" "$(uci_val network.wan6.peerdns)" "wan6 不用运营商 DNS"
}

# A：2 个 2.5G + 2 个 1G -> 定制模式
setup_env
make_port eth0 1g
make_port eth1 2g5
make_port eth2 2g5
make_port eth3 1g
run
assert_eq "eth1" "$(uci_val network.wan.device)" "A: 第一个 2.5G 口是 WAN"
assert_eq "pppoe" "$(uci_val network.wan.proto)" "A: WAN 使用 PPPoE"
absent network.wan.username "A: PPPoE 用户名留空"
absent network.wan.password "A: PPPoE 密码留空"
assert_eq "1" "$(uci_val network.wan.ipv6)" "A: PPPoE 启用 IPv6"
assert_eq "0" "$(uci_val network.wan.peerdns)" "A: 不用运营商 DNS"
assert_eq "@wan" "$(uci_val network.wan6.device)" "A: wan6 跟随 PPPoE"
assert_eq "dhcpv6" "$(uci_val network.wan6.proto)" "A: wan6 DHCPv6"
assert_eq "eth2" "$(uci_val network.lan.device)" "A: 第二个 2.5G 口直接作为 LAN"
assert_eq "static" "$(uci_val network.lan.proto)" "A: LAN 静态地址"
assert_eq "10.214.37.1" "$(uci_val network.lan.ipaddr)" "A: LAN 地址"
assert_eq "255.255.255.0" "$(uci_val network.lan.netmask)" "A: LAN 掩码"
absent "network.@device[0].name" "A: 删除 br-lan 网桥"
assert_eq "eth0" "$(uci_val network.ll_eth0.device)" "A: eth0 单独启用"
assert_eq "none" "$(uci_val network.ll_eth0.proto)" "A: eth0 无地址"
assert_eq "eth3" "$(uci_val network.ll_eth3.device)" "A: eth3 单独启用"
assert_eq "none" "$(uci_val network.ll_eth3.proto)" "A: eth3 无地址"
absent network.ll_eth1 "A: WAN 口不另建接口"
absent network.ll_eth2 "A: LAN 口不另建接口"
check_ipv6_common
assert_file_contains "$LOG_FILE" "mode=custom wan=eth1 lan=eth2" "A: 日志记录模式"
assert_file_contains "$LOG_FILE" "eth1 2500" "A: 日志记录网口速率"

# B：只有 1 个 2.5G -> 默认模式
setup_env
make_port eth0 1g
make_port eth1 2g5
run
assert_eq "br-lan" "$(uci_val network.lan.device)" "B: LAN 仍为 br-lan"
assert_eq "eth0" "$(uci_val network.@device[0].ports)" "B: 网桥保留"
assert_eq "eth1" "$(uci_val network.wan.device)" "B: WAN 保持 eth1"
assert_eq "dhcp" "$(uci_val network.wan.proto)" "B: WAN 保持 DHCP"
assert_eq "0" "$(uci_val network.wan.peerdns)" "B: 不用运营商 DNS"
assert_eq "10.214.37.1" "$(uci_val network.lan.ipaddr)" "B: LAN 地址"
assert_eq "255.255.255.0" "$(uci_val network.lan.netmask)" "B: LAN 掩码"
assert_eq "eth1" "$(uci_val network.wan6.device)" "B: wan6 保持 eth1"
assert_eq "" "$(uci show network | grep '^network\.ll_')" "B: 默认模式不建 ll_ 接口"
check_ipv6_common
assert_file_contains "$LOG_FILE" "mode=default" "B: 日志记录模式"

# C：3 个 2.5G -> 默认模式
setup_env
make_port eth0 2g5
make_port eth1 2g5
make_port eth2 2g5
run
assert_eq "br-lan" "$(uci_val network.lan.device)" "C: 3 个 2.5G 不进入定制模式"
assert_eq "dhcp" "$(uci_val network.wan.proto)" "C: WAN 保持 DHCP"

# D：2.5G + 10G + 2.5G -> 定制模式，10G 口不算
setup_env
make_port eth0 2g5
make_port eth1 10g
make_port eth2 2g5
run
assert_eq "eth0" "$(uci_val network.wan.device)" "D: WAN"
assert_eq "eth2" "$(uci_val network.lan.device)" "D: LAN"
assert_eq "none" "$(uci_val network.ll_eth1.proto)" "D: 10G 口单独启用"

# E：虚拟机 virtio 网口 -> 默认模式
setup_env
make_port eth0 virtio
make_port eth1 virtio
run
assert_eq "br-lan" "$(uci_val network.lan.device)" "E: virtio 不进入定制模式"
check_ipv6_common

# F：已初始化（保留配置升级）-> 不改任何配置
setup_env
make_port eth0 1g
make_port eth1 2g5
make_port eth2 2g5
touch "$CUSTOM_MARKER"
run
assert_eq "" "$(cat "$UCI_LOG")" "F: 已初始化时不写 uci"

pass
