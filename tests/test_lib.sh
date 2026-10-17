#!/bin/sh
# lib.sh 中的纯函数
. "$(dirname "$0")/helpers.sh"
setup_env
. "$CUSTOM_LIBDIR/lib.sh"

F="$REPO/tests/fixtures"

# lan_prefix
assert_eq "10.214.37" "$(lan_prefix 10.214.37.1)" "lan_prefix"

# custom_load_conf
custom_load_conf
assert_eq "10.214.37.1" "$LAN_IP" "custom_load_conf LAN_IP"
assert_eq "10.214.37" "$LAN_PREFIX" "custom_load_conf LAN_PREFIX"

# ethtool_max_speed：只看 Supported link modes 段，取最高速率
assert_eq "2500" "$(ethtool_max_speed < "$F/ethtool/2g5.txt")" "2.5G 网口"
assert_eq "1000" "$(ethtool_max_speed < "$F/ethtool/1g.txt")" "1G 网口"
assert_eq "10000" "$(ethtool_max_speed < "$F/ethtool/10g.txt")" "10G 网口（2500 不是最高速率）"
assert_eq "0" "$(ethtool_max_speed < "$F/ethtool/virtio.txt")" "virtio 无速率"
assert_eq "0" "$(ethtool_max_speed < /dev/null)" "空输入"

# port_max_speed：经由 ethtool
make_port eth1 2g5
assert_eq "2500" "$(port_max_speed eth1)" "port_max_speed"
assert_eq "0" "$(port_max_speed eth9)" "ethtool 失败时为 0"

# pick_2g5_ports
out=$(printf 'eth0 1000\neth1 2500\neth2 2500\neth3 1000\n' | pick_2g5_ports) || fail "恰好两个 2.5G 应返回 0"
assert_eq "eth1 eth2" "$out" "两个 2.5G 口按顺序输出"

out=$(printf 'eth0 2500\neth1 2500\neth2 2500\n' | pick_2g5_ports) && fail "三个 2.5G 应返回 1"
assert_eq "" "$out" "三个 2.5G 不输出"

out=$(printf 'eth1 2500\neth2 10000\n' | pick_2g5_ports) && fail "一个 2.5G + 一个 10G 应返回 1"
assert_eq "" "$out" "10G 不算 2.5G"

out=$(printf 'eth0 2500\neth1 10000\neth2 2500\n' | pick_2g5_ports) || fail "2.5G+10G+2.5G 应返回 0"
assert_eq "eth0 eth2" "$out" "跳过 10G 口"

# pick_custom_ports：恰好两个 2.5G 口时用它们，否则按顺序用前两个网口
assert_eq "eth1 eth2" "$(printf 'eth0 1000\neth1 2500\neth2 2500\neth3 1000\n' | pick_custom_ports)" "两个 2.5G 口优先"
assert_eq "eth0 eth2" "$(printf 'eth0 2500\neth1 10000\neth2 2500\n' | pick_custom_ports)" "10G 口不算 2.5G"
assert_eq "eth0 eth1" "$(printf 'eth0 1000\neth1 2500\n' | pick_custom_ports)" "只有一个 2.5G 时按顺序"
assert_eq "eth0 eth1" "$(printf 'eth0 2500\neth1 2500\neth2 2500\n' | pick_custom_ports)" "三个 2.5G 时按顺序"
assert_eq "eth0 eth1" "$(printf 'eth0 0\neth1 0\n' | pick_custom_ports)" "虚拟网卡按顺序"
out=$(printf 'eth0 2500\n' | pick_custom_ports) && fail "只有一个网口应返回 1"
assert_eq "" "$out" "只有一个网口不输出"
out=$(printf '' | pick_custom_ports) && fail "没有网口应返回 1"

# part_name
assert_eq "sda3" "$(part_name sda 3)" "sda"
assert_eq "nvme0n1p3" "$(part_name nvme0n1 3)" "nvme"
assert_eq "mmcblk0p3" "$(part_name mmcblk0 3)" "mmc"
assert_eq "vda128" "$(part_name vda 128)" "vda 三位分区号"

# sfdisk_largest_free
assert_eq "8521728 16777182" "$(sfdisk_largest_free < "$F/sfdisk-F.txt")" "取最大空闲区"
assert_eq "" "$(printf 'Unpartitioned space /dev/sda: 0 B, 0 bytes, 0 sectors\n' | sfdisk_largest_free)" "无空闲区"

# phys_ports：只要物理以太网口，按编号排序
make_port eth10 1g
make_port eth2 1g
make_virtual lo 772
make_virtual br-lan 1
make_virtual docker0 1
make_port wlan0 none wireless
assert_eq "eth1 eth2 eth10" "$(phys_ports | tr '\n' ' ' | sed 's/ $//')" "phys_ports"

# custom_is_provisioned
custom_is_provisioned && fail "无标记时应为未初始化"
touch "$CUSTOM_MARKER"
custom_is_provisioned || fail "有标记时应为已初始化"

# uci_zone_index
assert_eq "1" "$(uci_zone_index wan)" "wan 区域序号"
assert_eq "0" "$(uci_zone_index lan)" "lan 区域序号"
uci_zone_index nope >/dev/null && fail "不存在的区域应返回 1"

# custom_log
custom_log "hello world"
assert_file_contains "$LOG_FILE" "-t custom-init hello world" "custom_log 使用 custom-init 标签"

pass
