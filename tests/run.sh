#!/bin/sh
# 运行 tests/test_*.sh：每个文件在独立的 sh 中执行，任何一个失败则整体失败。
# 用法：sh tests/run.sh [测试文件...]
# 用哪个 sh 跑就用哪个 sh 执行测试（dash / busybox sh 均可），以覆盖固件上的 ash 行为。
cd "$(dirname "$0")/.." || exit 1

SHELL_BIN=${TEST_SHELL:-sh}
failed=0
total=0

if [ $# -gt 0 ]; then
	files="$*"
else
	files=$(ls tests/test_*.sh)
fi

for t in $files; do
	total=$((total + 1))
	if out=$("$SHELL_BIN" "$t" 2>&1); then
		case "$out" in
			*SKIP*) echo "SKIP $t: $(printf '%s\n' "$out" | grep SKIP | head -n 1)" ;;
			*) echo "PASS $t" ;;
		esac
	else
		failed=$((failed + 1))
		echo "FAIL $t"
		printf '%s\n' "$out" | sed 's/^/    /'
	fi
done

echo "$((total - failed))/$total passed"
[ "$failed" -eq 0 ]
