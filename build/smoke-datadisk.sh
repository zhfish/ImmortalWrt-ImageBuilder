#!/bin/sh
# 在构建出的固件镜像上演练数据分区：
# 把镜像放进一个 8 GiB 的稀疏文件（相当于写入更大的硬盘），
# 运行固件里同一份 datadisk_new_partition，检查分区 3 占满剩余空间、分区表有效，
# 且第二次运行不会再建分区。需要 Linux 上的 sfdisk（util-linux）。
# 用法：build/smoke-datadisk.sh <固件 .img.gz>
set -eu

img_gz=$1
lib="$(cd "$(dirname "$0")" && pwd)/files/usr/lib/custom"
. "$lib/lib.sh"
. "$lib/datadisk.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
disk="$work/disk.img"

# 固件末尾附带签名数据，gzip 会报 "trailing garbage ignored" 并返回 2
gzip -dc "$img_gz" > "$disk" || [ $? -eq 2 ]
truncate -s 8G "$disk"

if ! nr=$(datadisk_new_partition "$disk" 1073741824); then
	echo "::error::数据分区演练失败：没有在镜像后的空闲空间建出分区"
	sfdisk -l "$disk" || true
	exit 1
fi
if [ "$nr" != 3 ]; then
	echo "::error::数据分区演练失败：新分区号是 '$nr'，应为 3"
	exit 1
fi
sfdisk --verify "$disk"

start=$(sfdisk -d "$disk" | grep "^${disk}3 :" | sed -n 's/.*start= *\([0-9]*\).*/\1/p')
size=$(sfdisk -d "$disk" | grep "^${disk}3 :" | sed -n 's/.*size= *\([0-9]*\).*/\1/p')
total=$((8 * 1024 * 1024 * 1024 / 512))
if [ $((start + size)) -lt $((total - 34 - 2048)) ]; then
	echo "::error::数据分区演练失败：分区 3 没有用到磁盘末尾（$start + $size / $total）"
	exit 1
fi

if datadisk_new_partition "$disk" 1073741824 >/dev/null; then
	echo "::error::数据分区演练失败：第二次运行又建了一个分区"
	exit 1
fi

sfdisk -l "$disk"
echo "数据分区演练通过：分区 3 起始扇区 $start，共 $size 扇区"
