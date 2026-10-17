#!/bin/sh
# 数据分区：在磁盘镜像文件上真实运行 sfdisk（需要 util-linux，macOS 上跳过）
. "$(dirname "$0")/helpers.sh"
setup_env
. "$CUSTOM_LIBDIR/lib.sh"
. "$CUSTOM_LIBDIR/datadisk.sh"

# datadisk_find_label：只认启动盘上卷标为 data 的分区（不需要 sfdisk）
cat > "$T/block-info" <<'EOF'
/dev/sda1: UUID="1234-ABCD" LABEL="kernel" VERSION="FAT16" TYPE="vfat"
/dev/sda2: UUID="aaaa" VERSION="4.0" MOUNT="/rom" TYPE="squashfs"
/dev/sdb1: UUID="bbbb" LABEL="data" VERSION="1.0" TYPE="ext4"
/dev/nvme0n1p3: UUID="cccc" LABEL="data" VERSION="1.0" TYPE="ext4"
EOF
export BLOCK_INFO="$T/block-info"
assert_eq "" "$(datadisk_find_label sda)" "其他磁盘上的 data 分区不算"
assert_eq "nvme0n1p3" "$(datadisk_find_label nvme0n1)" "找到启动盘上的 data 分区"

# 首次启动脚本按文件名排序执行：必须排在 fstools 的 10-fstab 之后（它负责创建 /etc/config/fstab）
UD="$REPO/build/files/etc/uci-defaults"
script=$(cd "$UD" && ls ./*-custom-data-disk 2>/dev/null)
[ -n "$script" ] || fail "找不到数据分区首次启动脚本"
assert_eq "$script" "$(printf './10-fstab\n%s\n' "$script" | sort | tail -n 1)" "数据分区脚本应在 10-fstab 之后执行"
assert_eq "$script" "$(printf './20-custom-system\n%s\n' "$script" | sort | head -n 1)" "数据分区脚本应在其他初始化脚本之前执行"

if ! command -v sfdisk >/dev/null 2>&1; then
	echo "SKIP sfdisk not available"
	exit 0
fi

GPT_LINUX=0FC63DAF-8483-4772-8E79-3D69D8477DE4

# 仿照 OpenWrt combined-efi 的布局：p128 BIOS boot、p1 引导分区、p2 rootfs。
# first-lba 必须写明 34（与 OpenWrt 的 ptgen 一致）：不写时 sfdisk 新建 GPT 默认按对齐取 2048，
# 34 和 512 扇区上的分区会被拒绝，整个分区表建不出来
make_image() {
	truncate -s 300M "$1"
	sfdisk -q "$1" >/dev/null <<EOF || fail "构造测试磁盘镜像失败（sfdisk 拒绝了分区表）"
label: gpt
first-lba: 34
${1}1 : start=512, size=131072, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
${1}2 : start=131584, size=262144, type=$GPT_LINUX
${1}128 : start=34, size=478, type=21686148-6449-6E6F-744E-656564454649
EOF
}

part_field() { # part_field <镜像> <分区号> <start|size>
	sfdisk -d "$1" | grep "^${1}$2 :" | sed -n "s/.*$3= *\([0-9]*\).*/\1/p"
}

MIN=536870912 # 测试用 512 MiB

# 镜像写入更大的磁盘：在末尾新建分区 3
img="$T/disk.img"
make_image "$img"
truncate -s 2G "$img"
nr=$(datadisk_new_partition "$img" "$MIN") || fail "有足够空间时应成功"
assert_eq "3" "$nr" "新分区号"
sfdisk --verify "$img" >/dev/null 2>&1 || fail "分区表校验失败"
start=$(part_field "$img" 3 start)
size=$(part_field "$img" 3 size)
[ $((start % 2048)) -eq 0 ] || fail "起始扇区未按 1MiB 对齐: $start"
[ "$start" -ge 393728 ] || fail "新分区与 rootfs 重叠: $start"
total=$((2 * 1024 * 1024 * 1024 / 512))
[ $((start + size)) -ge $((total - 34 - 2048)) ] || fail "新分区没有用到磁盘末尾: $start+$size / $total"

# 再次执行：已没有足够空间，不新建
out=$(datadisk_new_partition "$img" "$MIN") && fail "第二次执行不应再新建分区"
assert_eq "" "$out" "第二次执行不输出"
assert_eq "" "$(part_field "$img" 4 start)" "没有出现分区 4"

# 磁盘与镜像一样大（例如虚拟机）：不新建
img2="$T/small.img"
make_image "$img2"
out=$(datadisk_new_partition "$img2" "$MIN") && fail "没有剩余空间时应返回 1"
assert_eq "" "$out" "没有剩余空间时不输出"

pass
