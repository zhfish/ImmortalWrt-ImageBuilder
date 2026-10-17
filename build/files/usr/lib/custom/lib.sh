#!/bin/sh
# 首次启动脚本共用的函数，固件内路径 /usr/lib/custom/lib.sh。
# 下列路径可用同名环境变量覆盖，供 tests/ 在本机测试。

CUSTOM_CONF=${CUSTOM_CONF:-/etc/custom/build.conf}
CUSTOM_MARKER=${CUSTOM_MARKER:-/etc/custom-provisioned}
CUSTOM_SYSFS=${CUSTOM_SYSFS:-/sys}

# 写系统日志，用 `logread -e custom-init` 查看
custom_log() {
	logger -t custom-init "$*"
}

# 读取构建时写入的配置，得到 LAN_IP、LAN_PREFIX（前三段）和 CUSTOM_CONFIG
custom_load_conf() {
	CUSTOM_CONFIG=
	# shellcheck disable=SC1090
	. "$CUSTOM_CONF"
	# shellcheck disable=SC2034  # 供调用者使用
	LAN_PREFIX=$(lan_prefix "$LAN_IP")
}

# 构建时是否勾选了“使用定制配置”（网口、macvlan、IPv6、kexue 标签），需先 custom_load_conf
custom_enabled() {
	[ "${CUSTOM_CONFIG:-0}" = 1 ]
}

# 是否已经初始化过（保留配置升级后标记文件仍在）
custom_is_provisioned() {
	[ -e "$CUSTOM_MARKER" ]
}

# 10.214.37.1 -> 10.214.37
lan_prefix() {
	echo "${1%.*}"
}

# 从 ethtool 输出（标准输入）中取 "Supported link modes" 段的最高速率（Mb/s），没有则输出 0
ethtool_max_speed() {
	awk '
		{
			line = $0
			if (line ~ /Supported link modes:/) {
				inblock = 1
				sub(/.*Supported link modes:/, "", line)
			} else if (line ~ /:/) {
				inblock = 0
			}
			if (!inblock) next
			n = split(line, w, /[ \t]+/)
			for (i = 1; i <= n; i++)
				if (w[i] ~ /^[0-9]+base/ && w[i] + 0 > max) max = w[i] + 0
		}
		END { print max + 0 }'
}

port_max_speed() {
	ethtool "$1" 2>/dev/null | ethtool_max_speed
}

# 列出物理以太网口（有 device、type=1、不是无线网卡），按名称里的编号排序
phys_ports() {
	for _p in "$CUSTOM_SYSFS"/class/net/*; do
		[ -d "$_p/device" ] || continue
		[ "$(cat "$_p/type" 2>/dev/null)" = 1 ] || continue
		if [ -e "$_p/wireless" ] || [ -e "$_p/phy80211" ]; then
			continue
		fi
		echo "${_p##*/}"
	done | awk '{ n = $0; sub(/^[^0-9]*/, "", n); print n + 0, $0 }' | sort -n -k1,1 | cut -d' ' -f2
}

# 标准输入每行 "<网口> <最高速率>"（已按网口顺序）。
# 恰好两个网口最高速率为 2500 时输出 "<第一个> <第二个>"，否则不输出并返回 1
pick_2g5_ports() {
	awk '$2 == 2500 { p[++n] = $1 } END { if (n != 2) exit 1; print p[1], p[2] }'
}

# 定制网口模式选 WAN/LAN。标准输入同 pick_2g5_ports。
# 恰好两个 2.5G 口时用它们，否则按顺序用前两个网口，输出 "<wan> <lan>"；不足两个网口返回 1
pick_custom_ports() {
	awk '{ name[++n] = $1 } $2 == 2500 { p[++m] = $1 }
		END {
			if (m == 2) { print p[1], p[2]; exit 0 }
			if (n < 2) exit 1
			print name[1], name[2]
		}'
}

# 分区设备名：sda 3 -> sda3；nvme0n1 3 -> nvme0n1p3
part_name() {
	case "$1" in
		*[0-9]) echo "${1}p$2" ;;
		*) echo "$1$2" ;;
	esac
}

# 从 `sfdisk -F` 输出（标准输入）中取扇区数最多的空闲区，输出 "<起始扇区> <结束扇区>"
sfdisk_largest_free() {
	awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
			if ($3 + 0 > max) { max = $3 + 0; s = $1; e = $2 }
		}
		END { if (max) print s, e }'
}

# 按名称查找防火墙区域的序号（firewall.@zone[N]），找不到返回 1
uci_zone_index() {
	_i=0
	while _n=$(uci -q get "firewall.@zone[$_i].name"); do
		if [ "$_n" = "$1" ]; then
			echo "$_i"
			return 0
		fi
		_i=$((_i + 1))
	done
	return 1
}
