#!/usr/bin/env sh
#
# 打印各来源相对 vendor.lock 基线的增量，供人工挑选后合入 pon。
#
#   scripts/sync-vendors.sh              # 全部来源
#   scripts/sync-vendors.sh pbs05        # 只看一个
#
# 只读：本脚本不修改任何分支，也不 push。
#
# 设计要点：
#   * upstream —— 官方基座，直接 merge 到 pon 即可（冲突只会出现在我们自己的改动上）
#   * pbs05    —— 产品层，通常整段 merge 到 pon；新增包应移到 pon_feed，不进主树
#   * naoki66  —— 只挑单个补丁（他们的 delta 里有本产品不需要的包与 feed）
#   * 若某个来源被 force-push 过（锁定提交不再是其祖先），退化为"相对官方基座的树差"

set -eu

cd "$(cd "$(dirname "$0")" && pwd)/.." || exit 1

LOCK=vendor.lock
[ -f "$LOCK" ] || { echo "缺少 $LOCK" >&2; exit 1; }

lock_value() {
	sed -n "s/^$1=//p" "$LOCK" | head -n1
}

remote_url() {
	case "$1" in
	upstream) echo https://github.com/immortalwrt/immortalwrt.git ;;
	pbs05) echo https://github.com/pbs05/ponwrt.git ;;
	naoki66) echo https://github.com/naoki66/ImmortalWrt-for-Gemtek-brightspeed.git ;;
	esac
}

wanted="${1:-upstream pbs05 naoki66}"

for name in $wanted; do
	base="$(lock_value "$name")"
	url="$(remote_url "$name")"
	[ -n "$base" ] || { echo "== $name: vendor.lock 里没有记录，跳过"; continue; }

	echo
	echo "================ $name ================"
	echo "基线: $base"

	# 用一次性 ref 取 tip，避免在本地仓库里堆积 vendor 分支
	ref="refs/vendor-lock/$name"
	git fetch --no-tags "$url" "+refs/heads/master:$ref" >/dev/null 2>&1 || {
		echo "  取不到 $url，跳过"; continue;
	}
	tip="$(git rev-parse "$ref")"

	if [ "$tip" = "$base" ]; then
		echo "  已是最新（$tip）"
		continue
	fi

	if git merge-base --is-ancestor "$base" "$tip" 2>/dev/null; then
		n_all=$(git rev-list --count "$base..$tip")
		n_own=$(git rev-list --count --no-merges "$base..$tip")
		echo "  新增 $n_all 个提交（其中非 merge $n_own 个）"
		echo "  --- 他们的提交 ---"
		git log --oneline --no-merges "$base..$tip" | sed 's/^/    /' | head -40
		echo "  --- 受影响的路径（只看产品相关目录） ---"
		git diff --name-status "$base" "$tip" -- \
			target/linux package configs include feeds.conf.default 2>/dev/null |
			sed 's/^/    /' | head -60
	else
		echo "  基线不再是祖先（对方可能 force-push / rebase）→ 退化为相对官方基座的树差"
		echo "  --- 他们相对官方新增/修改的文件 ---"
		git diff --name-status upstream/master "$tip" -- \
			target/linux package configs include feeds.conf.default 2>/dev/null |
			sed 's/^/    /' | head -60
	fi

	echo "  提示: 吸收完成后把 vendor.lock 里 $name 改为 $tip"
done
