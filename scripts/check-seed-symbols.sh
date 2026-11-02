#!/usr/bin/env sh
#
# 校验种子配置：make defconfig 之后，种子里选中的符号是否仍然生效。
#
#   scripts/check-seed-symbols.sh                        # 检查 configs/*.config
#   scripts/check-seed-symbols.sh configs/1710.config    # 只检查一个
#
# 为什么需要：包被移出主树、或者 pon_feed 没挂上时，Kconfig 会**静默丢弃**
# 对应的 CONFIG_PACKAGE_xxx —— 构建照常成功，但镜像里少了一整块功能。
# lucky、luci-app-airoha-factory/fancontrol/recovery 都踩过这个坑。
#
# 前置：./scripts/feeds update -a && ./scripts/feeds install -a
# 副作用：会临时改写根目录 .config，结束时恢复原样。

set -eu

cd "$(cd "$(dirname "$0")" && pwd)/.." || exit 1

[ "$#" -gt 0 ] || set -- configs/*.config

allowlist=scripts/seed-symbols-allowlist.txt
tmpdir="$(mktemp -d)"
backup="$tmpdir/config.bak"

[ -f .config ] && cp .config "$backup" || : > "$backup"

restore() {
	cp "$backup" .config
	rm -rf "$tmpdir"
}
trap restore EXIT INT TERM

status=0

# 强制重建包元数据。tmp/.packageinfo 是增量扫描的缓存（include/toplevel.mk 的
# scan_unchanged 按 mtime 判断），上游删包/改名后若缓存没刷新，defconfig 会用旧
# 符号表，校验就会"假绿"——kmod-iptables 被上游删除时就漏过一次。
rm -f tmp/.packageinfo tmp/.config-package.in tmp/.config-feeds.in

for seed in "$@"; do
	[ -f "$seed" ] || { echo "跳过不存在的 $seed"; continue; }
	echo "== $seed"

	cp "$seed" .config
	if ! make defconfig >"$tmpdir/defconfig.log" 2>&1; then
		echo "   defconfig 执行失败，详见 $tmpdir/defconfig.log"
		status=1
		continue
	fi

	# 注意字符类里要包含 `-`：OpenWrt 的 package 符号大量带连字符
	# （CONFIG_PACKAGE_kmod-iptables、CONFIG_PACKAGE_luci-app-*），只写
	# [A-Za-z0-9_] 会静默跳过它们 —— 1710 种子 1282 个符号里有 292 个被漏掉。
	grep -E '^CONFIG_[A-Za-z0-9_-]+=[ym]$' "$seed" > "$tmpdir/syms" || : > "$tmpdir/syms"
	: > "$tmpdir/missing"

	while IFS= read -r line; do
		sym="${line%%=*}"
		want="${line##*=}"
		# 用固定字符串匹配，避免符号里的 `+`/`.` 被当成正则
		got="$(grep -F -- "$sym=" .config | head -n1 || true)"
		[ "$got" = "$sym=$want" ] && continue
		if [ -f "$allowlist" ] && grep -qxF "$sym" "$allowlist"; then
			continue
		fi
		printf '%s（期望 %s，实际 %s）\n' "$sym" "$want" "${got:-无}" >> "$tmpdir/missing"
	done < "$tmpdir/syms"

	if [ -s "$tmpdir/missing" ]; then
		echo "   ✗ $(wc -l < "$tmpdir/missing" | tr -d ' ') 个符号被丢弃："
		sed 's/^/     /' "$tmpdir/missing"
		echo "     （确认包是否被移出主树、pon_feed 是否已安装；确属预期就加入 $allowlist）"
		status=1
	else
		echo "   ✓ 种子里 $(wc -l < "$tmpdir/syms" | tr -d ' ') 个符号全部生效"
	fi
done

exit $status
