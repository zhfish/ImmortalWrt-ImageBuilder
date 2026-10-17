#!/bin/sh
# 20-custom-system / 90-custom-done / sysctl / keep.d
. "$(dirname "$0")/helpers.sh"
setup_env

D="$REPO/build/files"
export SSHD_CONFIG="$T/sshd_config"
cp "$REPO/tests/fixtures/sshd_config" "$SSHD_CONFIG"

sh "$D/etc/uci-defaults/20-custom-system" || fail "20-custom-system 退出码非 0"

assert_eq "/luci-static/argon" "$(uci_val luci.main.mediaurlbase)" "默认主题 argon"
assert_eq "https://mirrors.cernet.edu.cn/immortalwrt" "$(uci_val system.@imm_init[0].apk_mirror)" "apk 镜像"
assert_eq "0" "$(uci_val upnpd.config.enabled)" "UPnP 默认关闭"
assert_eq "0" "$(uci_val firewall.@defaults[0].flow_offloading)" "软件流量卸载关闭"
assert_eq "0" "$(uci_val firewall.@defaults[0].flow_offloading_hw)" "硬件流量卸载关闭"
assert_eq "1" "$(grep -c '^PermitRootLogin yes$' "$SSHD_CONFIG")" "PermitRootLogin yes 恰好一行"
assert_eq "1" "$(grep -c 'PermitRootLogin' "$SSHD_CONFIG")" "没有残留的 PermitRootLogin 行"

# sshd_config 中没有 PermitRootLogin 行时追加
printf 'Port 22\n' > "$SSHD_CONFIG"
rm -f "$CUSTOM_MARKER"
sh "$D/etc/uci-defaults/20-custom-system"
assert_file_contains "$SSHD_CONFIG" "PermitRootLogin yes" "缺失时追加"

# 已初始化（保留配置升级）：不写任何配置
setup_env
export SSHD_CONFIG="$T/sshd_config"
cp "$REPO/tests/fixtures/sshd_config" "$SSHD_CONFIG"
touch "$CUSTOM_MARKER"
sh "$D/etc/uci-defaults/20-custom-system"
assert_eq "" "$(cat "$UCI_LOG")" "已初始化时不写 uci"
cmp -s "$SSHD_CONFIG" "$REPO/tests/fixtures/sshd_config" || fail "已初始化时不改 sshd_config"

# 90-custom-done 写标记
rm -f "$CUSTOM_MARKER"
sh "$D/etc/uci-defaults/90-custom-done"
[ -e "$CUSTOM_MARKER" ] || fail "90-custom-done 应创建标记"

# sysctl
S="$D/etc/sysctl.d/90-router.conf"
assert_file_contains "$S" "net.ipv4.tcp_congestion_control=bbr" "BBR"
assert_file_contains "$S" "net.core.default_qdisc=fq_codel" "队列规则 fq_codel"
assert_file_contains "$S" "net.netfilter.nf_conntrack_max=262144" "conntrack 上限"
assert_file_contains "$S" "net.ipv4.tcp_mtu_probing=1" "MTU 探测"
assert_file_contains "$S" "net.ipv4.conf.macvlan-shim.arp_filter=1" "shim arp_filter"
grep -v '^#' "$S" | grep -Eq '\.(arp_ignore|rp_filter)=' && fail "不应修改 arp_ignore / rp_filter"

# keep.d：升级时保留标记
assert_file_contains "$D/lib/upgrade/keep.d/custom" "/etc/custom-provisioned" "keep.d 保留初始化标记"
assert_file_contains "$D/lib/upgrade/keep.d/custom" "/etc/docker/daemon.json" "keep.d 保留 Docker 配置"

pass
