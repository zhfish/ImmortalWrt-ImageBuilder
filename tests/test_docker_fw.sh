#!/bin/sh
# 50-custom-docker：Docker 防火墙区域、macvlan shim
. "$(dirname "$0")/helpers.sh"

S="$REPO/build/files/etc/uci-defaults/50-custom-docker"

# 默认模式：LAN 是 br-lan
setup_env
custom_config 1
sh "$S" || fail "50-custom-docker 退出码非 0"

assert_eq "zone" "$(uci_val firewall.docker)" "docker 区域"
assert_eq "docker" "$(uci_val firewall.docker.name)" "区域名"
assert_eq "ACCEPT" "$(uci_val firewall.docker.input)" "input"
assert_eq "ACCEPT" "$(uci_val firewall.docker.output)" "output"
assert_eq "ACCEPT" "$(uci_val firewall.docker.forward)" "forward"
assert_eq "docker0 br-+" "$(uci_val firewall.docker.device)" "区域设备：docker0 与 Compose 网桥"

assert_eq "forwarding" "$(uci_val firewall.docker_wan)" "docker->wan"
assert_eq "docker" "$(uci_val firewall.docker_wan.src)" "docker->wan src"
assert_eq "wan" "$(uci_val firewall.docker_wan.dest)" "docker->wan dest"
assert_eq "docker" "$(uci_val firewall.docker_lan.src)" "docker->lan src"
assert_eq "lan" "$(uci_val firewall.docker_lan.dest)" "docker->lan dest"
assert_eq "lan" "$(uci_val firewall.lan_docker.src)" "lan->docker src"
assert_eq "docker" "$(uci_val firewall.lan_docker.dest)" "lan->docker dest"
assert_eq "" "$(uci show firewall | grep 'src=wan' | grep -v '@zone')" "不放行 wan->docker"

assert_eq "device" "$(uci_val network.macvlan_shim_dev)" "shim 设备"
assert_eq "macvlan" "$(uci_val network.macvlan_shim_dev.type)" "shim 类型"
assert_eq "macvlan-shim" "$(uci_val network.macvlan_shim_dev.name)" "shim 设备名"
assert_eq "br-lan" "$(uci_val network.macvlan_shim_dev.ifname)" "默认模式父接口 br-lan"
assert_eq "bridge" "$(uci_val network.macvlan_shim_dev.mode)" "macvlan bridge 模式"
assert_eq "interface" "$(uci_val network.macvlan_shim)" "shim 接口"
assert_eq "macvlan-shim" "$(uci_val network.macvlan_shim.device)" "shim 接口设备"
assert_eq "static" "$(uci_val network.macvlan_shim.proto)" "shim 静态地址"
assert_eq "10.214.37.1" "$(uci_val network.macvlan_shim.ipaddr)" "shim 地址与 LAN 相同"
assert_eq "255.255.255.255" "$(uci_val network.macvlan_shim.netmask)" "shim /32"
assert_eq "route" "$(uci_val network.macvlan_shim_route)" "shim 路由"
assert_eq "macvlan_shim" "$(uci_val network.macvlan_shim_route.interface)" "路由走 shim"
assert_eq "10.214.37.0/28" "$(uci_val network.macvlan_shim_route.target)" "容器地址段 /28"
assert_eq "lan macvlan_shim" "$(uci_val firewall.@zone[0].network)" "shim 加入 lan 区域"
assert_eq "dhcp" "$(uci_val dhcp.macvlan_shim)" "shim 的 dhcp 段"
assert_eq "macvlan_shim" "$(uci_val dhcp.macvlan_shim.interface)" "shim 的 dhcp 段对应接口"
assert_eq "1" "$(uci_val dhcp.macvlan_shim.ignore)" "dnsmasq 不在 shim 上提供 DHCP"

# 重复执行不重复加入 lan 区域
rm -f "$CUSTOM_MARKER"
sh "$S"
assert_eq "lan macvlan_shim" "$(uci_val firewall.@zone[0].network)" "重复执行不重复"
assert_eq "docker0 br-+" "$(uci_val firewall.docker.device)" "重复执行设备不重复"

# 定制模式：LAN 是网口 eth2
setup_env
custom_config 1
uci -q set network.lan.device=eth2
: > "$UCI_LOG"
sh "$S"
assert_eq "eth2" "$(uci_val network.macvlan_shim_dev.ifname)" "定制模式父接口为 LAN 网口"

# 关闭定制配置：Docker 防火墙区域照常建立，不建 macvlan shim
setup_env
custom_config 0
sh "$S" || fail "关闭时 50-custom-docker 退出码非 0"
assert_eq "docker0 br-+" "$(uci_val firewall.docker.device)" "关闭时: docker 区域照常建立"
assert_eq "wan" "$(uci_val firewall.docker_wan.dest)" "关闭时: docker->wan"
assert_eq "lan" "$(uci_val firewall.docker_lan.dest)" "关闭时: docker->lan"
assert_eq "docker" "$(uci_val firewall.lan_docker.dest)" "关闭时: lan->docker"
for k in network.macvlan_shim_dev network.macvlan_shim network.macvlan_shim_route dhcp.macvlan_shim; do
	uci -q get "$k" >/dev/null && fail "关闭时: 不应创建 $k"
done
assert_eq "lan" "$(uci_val firewall.@zone[0].network)" "关闭时: lan 区域不加 shim"

# 已初始化：不写任何配置
setup_env
touch "$CUSTOM_MARKER"
sh "$S"
assert_eq "" "$(cat "$UCI_LOG")" "已初始化时不写 uci"

pass
