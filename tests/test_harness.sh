#!/bin/sh
# 测试辅助工具本身：伪 uci 的行为必须与脚本依赖的语义一致
. "$(dirname "$0")/helpers.sh"
setup_env

uci -q set network.lan.ipaddr=10.0.0.1
assert_eq "10.0.0.1" "$(uci_val network.lan.ipaddr)" "set 覆盖旧值"

uci -q set network.lan.ipaddr=
uci -q get network.lan.ipaddr >/dev/null && fail "set 空值应删除选项（与真实 uci 一致）"
uci -q set network.lan.ipaddr=10.0.0.1

uci -q delete dhcp.lan.dhcp_option
uci -q add_list dhcp.lan.dhcp_option=3,a
uci -q add_list dhcp.lan.dhcp_option=6,b
assert_eq "3,a 6,b" "$(uci -q get dhcp.lan.dhcp_option)" "list 按顺序空格连接"

uci -q del_list dhcp.lan.dhcp_option=3,a
assert_eq "6,b" "$(uci -q get dhcp.lan.dhcp_option)" "del_list 只删一项"

uci -q delete network.lan
uci -q get network.lan.ipaddr >/dev/null && fail "delete 应删除整个 section"
uci -q get network.lan >/dev/null && fail "delete 应删除 section 本身"

uci -q get network.nope >/dev/null && fail "不存在的键 get 应返回非 0"

uci -q get system.@imm_init[0] >/dev/null && fail "初始状态不应有 imm_init"
uci -q add system imm_init >/dev/null
uci -q get system.@imm_init[0] >/dev/null || fail "add 之后应能 get 到 @imm_init[0]"

assert_file_contains "$UCI_LOG" "set network.lan.ipaddr=10.0.0.1" "写操作记入日志"
grep -q "^get " "$UCI_LOG" && fail "get 不应记入日志"

assert_eq "1" "$(uci -q get firewall.@zone[1].name | grep -c wan)" "默认状态包含 wan 区域"

pass
