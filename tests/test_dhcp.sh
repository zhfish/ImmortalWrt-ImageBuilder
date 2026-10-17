#!/bin/sh
# 40-custom-dhcp：DNS 转发与缓存、DHCP 地址池、kexue 标签、局域网不发 IPv6
. "$(dirname "$0")/helpers.sh"
setup_env
custom_config 1

S="$REPO/build/files/etc/uci-defaults/40-custom-dhcp"
sh "$S" || fail "40-custom-dhcp 退出码非 0"

assert_eq "1" "$(uci_val dhcp.@dnsmasq[0].noresolv)" "不读取运营商 DNS"
assert_eq "123.123.123.123 114.114.114.114" "$(uci_val dhcp.@dnsmasq[0].server)" "上游 DNS 按顺序"
assert_eq "8000" "$(uci_val dhcp.@dnsmasq[0].cachesize)" "DNS 缓存"
assert_eq "0" "$(uci_val dhcp.@dnsmasq[0].rebind_protection)" "关闭重绑定保护"
assert_eq "1" "$(uci_val dhcp.@dnsmasq[0].dns_redirect)" "DNS 重定向保持默认"
assert_eq "/tmp/resolv.conf.d/resolv.conf.auto" "$(uci_val dhcp.@dnsmasq[0].resolvfile)" "resolvfile 不动"

assert_eq "50" "$(uci_val dhcp.lan.start)" "地址池起点 .50"
assert_eq "151" "$(uci_val dhcp.lan.limit)" "地址池到 .200"
assert_eq "3,10.214.37.1 6,10.214.37.1" "$(uci_val dhcp.lan.dhcp_option)" "下发网关和 DNS"
assert_eq "disabled" "$(uci_val dhcp.lan.ra)" "不发 RA"
assert_eq "disabled" "$(uci_val dhcp.lan.dhcpv6)" "不开 DHCPv6"
assert_eq "disabled" "$(uci_val dhcp.lan.ndp)" "不做 NDP 代理"

assert_eq "tag" "$(uci_val dhcp.kexue)" "kexue 标签"
assert_eq "3,10.214.37.2" "$(uci_val dhcp.kexue.dhcp_option)" "kexue 网关 .2"

# 重复执行（例如脚本中途失败后重试）不会产生重复的列表项
rm -f "$CUSTOM_MARKER"
sh "$S"
assert_eq "123.123.123.123 114.114.114.114" "$(uci_val dhcp.@dnsmasq[0].server)" "重复执行不重复 server"
assert_eq "3,10.214.37.2" "$(uci_val dhcp.kexue.dhcp_option)" "重复执行不重复 kexue 选项"

# 关闭定制配置：DNS 与地址池照常设置，局域网 IPv6 与 kexue 标签保持默认
setup_env
custom_config 0
sh "$S" || fail "关闭时 40-custom-dhcp 退出码非 0"
assert_eq "123.123.123.123 114.114.114.114" "$(uci_val dhcp.@dnsmasq[0].server)" "关闭时: 上游 DNS"
assert_eq "0" "$(uci_val dhcp.@dnsmasq[0].rebind_protection)" "关闭时: 关闭重绑定保护"
assert_eq "50" "$(uci_val dhcp.lan.start)" "关闭时: 地址池起点"
assert_eq "151" "$(uci_val dhcp.lan.limit)" "关闭时: 地址池大小"
assert_eq "3,10.214.37.1 6,10.214.37.1" "$(uci_val dhcp.lan.dhcp_option)" "关闭时: 网关和 DNS"
assert_eq "server" "$(uci_val dhcp.lan.ra)" "关闭时: RA 保持默认"
assert_eq "server" "$(uci_val dhcp.lan.dhcpv6)" "关闭时: DHCPv6 保持默认"
uci -q get dhcp.lan.ndp >/dev/null && fail "关闭时: 不设置 NDP"
uci -q get dhcp.kexue >/dev/null && fail "关闭时: 不建 kexue 标签"

# 已初始化：不写任何配置
setup_env
touch "$CUSTOM_MARKER"
sh "$S"
assert_eq "" "$(cat "$UCI_LOG")" "已初始化时不写 uci"

pass
