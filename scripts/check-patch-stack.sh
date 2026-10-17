#!/usr/bin/env bash
#
# 校验内核补丁链能否干净套用（不需要 swig / python3-setuptools，也不用编译）。
#
#   scripts/check-patch-stack.sh [target]      # target 默认 airoha
#
# 做法：把 dl/ 里的 linux-<ver>.tar.xz 解到临时目录，按构建系统同样的顺序
# （generic/backport → generic/pending → generic/hack → <target>/patches）
# 用同样的参数（patch -f -p1）套一遍，报出任何失败。
#
# 为什么需要：两个供应商（pbs05/naoki66）对同一个内核各维护一套补丁，
# 合并后很容易出现"同号不同名""同功能两份实现""补丁已失效"等情况 ——
# 这些在 defconfig 阶段看不出来，只会在编译时炸，而且报错难读。

set -euo pipefail

cd "$(cd "$(dirname "$0")" && pwd)/.." || exit 1

target="${1:-airoha}"
ver="$(sed -n 's/^LINUX_VERSION-\([0-9.]*\) *=.*/\1/p' "target/linux/generic/kernel-${KERNEL_PATCHVER:-6.18}" 2>/dev/null | head -n1)"
[ -n "$ver" ] || { echo "读不到内核版本（target/linux/generic/kernel-*）" >&2; exit 1; }
suffix="$(sed -n "s/^LINUX_VERSION-${ver} *= *//p" "target/linux/generic/kernel-${ver}" 2>/dev/null | head -n1)"

tarball="$(ls -1 dl/linux-${ver}${suffix}*.tar.* 2>/dev/null | head -n1)"
[ -n "$tarball" ] || { echo "dl/ 里没有 linux-${ver}${suffix}*.tar.* ：请先 make download 或放入 tarball" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "内核版本: ${ver}${suffix}"
echo "tarball : $tarball"
echo "target  : $target"
echo "解包到  : $tmp/src"
mkdir -p "$tmp/src"
tar -xf "$tarball" -C "$tmp/src" --strip-components=1

dirs=(
	"target/linux/generic/backport-${ver}"
	"target/linux/generic/pending-${ver}"
	"target/linux/generic/hack-${ver}"
	"target/linux/${target}/patches-${ver}"
)

failed=0
applied=0

for d in "${dirs[@]}"; do
	[ -d "$d" ] || { echo "跳过不存在的 $d"; continue; }
	n=0
	f=0
	for p in "$PWD/$d"/*.patch; do
		[ -f "$p" ] || continue
		n=$((n + 1))
		applied=$((applied + 1))
		if ! patch -f -p1 -d "$tmp/src" -i "$p" >"$tmp/out" 2>&1; then
			f=$((f + 1))
			failed=$((failed + 1))
			echo "  ✗ $(basename "$p")"
			grep -E 'FAILED|saving rejects' "$tmp/out" | head -3 | sed 's/^/      /'
		fi
	done
	printf '%-42s 应用 %3d，失败 %d\n' "$d" "$n" "$f"
done

echo
if [ "$failed" -eq 0 ]; then
	echo "✓ 全部 $applied 个补丁干净套用"
else
	echo "✗ $applied 个补丁中 $failed 个失败"
	echo "  提示：失败多为两家补丁栈混用（同号不同名 / 同功能两份实现 / 补丁对当前内核已失效）"
	exit 1
fi
