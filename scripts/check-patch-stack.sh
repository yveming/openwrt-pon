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

# 构建系统用的是 PATH 里的 patch —— OpenWrt 会把 staging_dir/host/bin 放在最前，
# 那是它自己编译的 GNU patch。系统自带的 patch 在 fuzz/offset 处理上可能不同，
# 会导致"假失败"。这里显式对齐。
patch_bin="staging_dir/host/bin/patch"
[ -x "$patch_bin" ] || patch_bin="$(command -v patch)"

echo "内核版本: ${ver}${suffix}"
echo "tarball : $tarball"
echo "target  : $target"
echo "patch   : $patch_bin ($("$patch_bin" --version 2>/dev/null | head -n1))"
echo "解包到  : $tmp/src"
mkdir -p "$tmp/src"
tar -xf "$tarball" -C "$tmp/src" --strip-components=1

# 构建系统在套补丁之前会先把 files/ 与 files-<ver>/ 覆盖进内核树（Kernel/Patch/Default）
for fdir in "target/linux/generic/files" "target/linux/generic/files-${ver}" \
            "target/linux/${target}/files" "target/linux/${target}/files-${ver}"; do
	[ -d "$fdir" ] || continue
	echo "覆盖 overlay: $fdir"
	cp -a "$fdir"/. "$tmp/src"/
done

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
	# 必须用字节序（LC_ALL=C）枚举补丁：构建系统的 patch-kernel.sh 跑在 /bin/sh
	# （dash，字节序）下，而 bash 的 glob 会按 locale 排序 —— 两者在
	# `914-…` 与 `914b-…` 这类名字上顺序相反，会得出完全不同的结果。
	while IFS= read -r p; do
		n=$((n + 1))
		applied=$((applied + 1))
		if ! LC_ALL=C "$patch_bin" -f -p1 -d "$tmp/src" -i "$p" >"$tmp/out" 2>&1; then
			f=$((f + 1))
			failed=$((failed + 1))
			echo "  ✗ $(basename "$p")"
			grep -E 'FAILED|saving rejects' "$tmp/out" | head -3 | sed 's/^/      /'
		fi
	done < <(find "$PWD/$d" -maxdepth 1 -name '*.patch' -print | LC_ALL=C sort)
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
