#!/bin/sh
# 等 Docker 就绪后创建 macvlan 网络 lan_macvlan（由 /etc/init.d/lan-macvlan 在开机时调用）。
#   子网 = LAN 网段 x.x.x.0/24，网关 = LAN 地址 x.x.x.1，父接口 = LAN 的三层设备
#   自动分配段 x.x.x.8/29（x.x.x.8-15）；需要固定地址的容器用 --ip 指定 x.x.x.2-7
# 网络已存在时不重建（可能有容器在用）；与当前 LAN 不一致时只记日志。
. "${CUSTOM_LIBDIR:-/usr/lib/custom}/lib.sh"
custom_load_conf

NET=lan_macvlan
WAIT=${DOCKER_WAIT:-120}

parent=$(uci -q get network.lan.device)
[ -n "$parent" ] || parent=br-lan

waited=0
until docker info >/dev/null 2>&1; do
	if [ "$waited" -ge "$WAIT" ]; then
		custom_log "macvlan: docker not ready after ${WAIT}s (timeout), skipped"
		exit 0
	fi
	sleep 2
	waited=$((waited + 2))
done

if docker network inspect "$NET" >/dev/null 2>&1; then
	actual=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}} {{index .Options "parent"}}' "$NET")
	expected="$LAN_PREFIX.0/24 $parent"
	if [ "$actual" != "$expected" ]; then
		custom_log "macvlan: $NET is '$actual' but LAN is '$expected'; not recreating it, remove it with 'docker network rm $NET' and restart lan-macvlan"
	fi
	exit 0
fi

if docker network create -d macvlan \
	--subnet "$LAN_PREFIX.0/24" --gateway "$LAN_IP" --ip-range "$LAN_PREFIX.8/29" \
	-o parent="$parent" "$NET" >/dev/null; then
	custom_log "macvlan: created $NET on $parent"
else
	custom_log "macvlan: failed to create $NET on $parent"
fi
exit 0
