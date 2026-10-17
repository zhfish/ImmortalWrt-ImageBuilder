#!/bin/sh
# 数据分区相关函数，固件内路径 /usr/lib/custom/datadisk.sh。
# 依赖 lib.sh 中的 sfdisk_largest_free；需要 sfdisk（util-linux）。
# 构建时 build/smoke-datadisk.sh 也会用它在真实固件镜像上演练一遍。

# GPT 的 "Linux filesystem" 分区类型
DATADISK_TYPE=0FC63DAF-8483-4772-8E79-3D69D8477DE4

# datadisk_new_partition <磁盘路径> <最小字节数>
# 先把 GPT 备份头移到磁盘末尾（镜像写入更大的磁盘后，备份头还停在镜像末尾，
# 末尾的空间对分区工具不可见），再在最大的空闲区新建一个分区占满它。
# 成功时输出新分区号；空闲区不足 <最小字节数> 时不输出并返回 1。
datadisk_new_partition() {
	_disk=$1
	_min=$2

	# 磁盘正在使用，不能让内核整表重读；失败不致命，后面按实际空闲空间判断
	sfdisk --no-reread --no-tell-kernel --relocate gpt-bak-std "$_disk" >/dev/null 2>&1 || true

	# shellcheck disable=SC2046  # 有意按空格拆成两个参数
	set -- $(sfdisk -F "$_disk" 2>/dev/null | sfdisk_largest_free)
	[ $# -eq 2 ] || return 1

	# 起始扇区按 1MiB（2048 扇区）对齐
	_start=$((($1 + 2047) / 2048 * 2048))
	_end=$2
	[ "$_start" -le "$_end" ] || return 1
	[ $(((_end - _start + 1) * 512)) -ge "$_min" ] || return 1

	# 不写 size：sfdisk 会占满从起始扇区到该空闲区末尾的全部空间
	echo "start=$_start, type=$DATADISK_TYPE, name=data" |
		sfdisk --append --no-reread --no-tell-kernel -q "$_disk" >/dev/null 2>&1 || return 1

	# 从 `sfdisk -d` 中找起始扇区为 _start 的分区，取设备名末尾的数字作为分区号
	sfdisk -d "$_disk" 2>/dev/null |
		sed -n "s/^.*[^0-9]\([0-9][0-9]*\) *: *start= *$_start,.*/\1/p"
}

# datadisk_find_label <磁盘名>：输出该磁盘上卷标为 data 的分区名（如 sda3），没有则不输出
datadisk_find_label() {
	block info 2>/dev/null |
		sed -n "s#^/dev/\($1p\{0,1\}[0-9][0-9]*\): .*LABEL=\"data\".*#\1#p" |
		head -n 1
}
