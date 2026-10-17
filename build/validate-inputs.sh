#!/bin/sh
# 校验工作流输入。用法：build/validate-inputs.sh <版本号> <LAN 地址>
# 版本号：25.12.2 或 25.12.0-rc2 这样的格式
# LAN 地址：必须是 x.x.x.1（掩码固定 /24），每段 0-255，不带前导 0

valid_version() {
	awk -v s="$1" 'BEGIN { exit !(s ~ /^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$/) }'
}

valid_lan_ip() {
	awk -v s="$1" 'BEGIN {
		if (s !~ /^[0-9.]+$/ || split(s, o, ".") != 4) exit 1
		for (i = 1; i <= 4; i++)
			if (o[i] !~ /^(0|[1-9][0-9]?[0-9]?)$/ || o[i] + 0 > 255) exit 1
		exit !(o[4] == "1")
	}'
}

main() {
	if ! valid_version "${1:-}"; then
		echo "::error::版本号格式不正确：'${1:-}'（例如 25.12.2）"
		exit 1
	fi
	if ! valid_lan_ip "${2:-}"; then
		echo "::error::LAN 地址必须是 x.x.x.1 的形式（例如 10.214.37.1），实际为：'${2:-}'"
		exit 1
	fi
	echo "输入有效：版本 $1，LAN 地址 $2"
}

[ -n "${BUILD_LIB_ONLY:-}" ] || main "$@"
