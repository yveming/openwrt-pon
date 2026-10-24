#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
	cat >&2 <<'EOF'
usage: check-firmware-artifacts.sh --config <file> --directory <target-dir>
EOF
	exit 2
}

config_file=""
target_dir=""

while (( $# > 0 )); do
	case "$1" in
		--config)
			(( $# >= 2 )) || usage
			config_file="$2"
			shift 2
			;;
		--directory)
			(( $# >= 2 )) || usage
			target_dir="$2"
			shift 2
			;;
		*)
			usage
			;;
	esac
done

[[ -f "$config_file" && -d "$target_dir" ]] || usage

# bin/targets/<board>/<subtarget>
subtarget="$(basename "$target_dir")"
board="$(basename "$(dirname "$target_dir")")"

# 同时兼容两种写法：
#   CONFIG_TARGET_DEVICE_<board>_<subtarget>_DEVICE_<device>=y
#   CONFIG_TARGET_<board>_<subtarget>_DEVICE_<device>=y
mapfile -t devices < <(
	grep -E "^CONFIG_(TARGET_${board}_${subtarget}_DEVICE|TARGET_DEVICE_${board}_${subtarget}_DEVICE)_.+=y$" \
		"$config_file" 2>/dev/null |
		sed -E 's/^CONFIG_[^=]*_DEVICE_(.+)=y$/\1/' |
		sort -u || true
)

(( ${#devices[@]} > 0 )) || {
	echo "no device profile is selected in $config_file" >&2
	exit 1
}

failed=0
for device in "${devices[@]}"; do
	# 优先校验 sysupgrade ITB；只有 initramfs 的设备（例如 RAM boot
	# profile）退而校验 initramfs ITB。
	image="$(find "$target_dir" -maxdepth 1 -type f \
		-name "*-${device}-squashfs-*.itb" -size +0c -print -quit)"
	if [[ -z "$image" ]]; then
		image="$(find "$target_dir" -maxdepth 1 -type f \
			-name "*-${device}-initramfs-*.itb" -size +0c -print -quit)"
	fi
	if [[ -z "$image" ]]; then
		echo "missing firmware ITB for selected device $device in $target_dir" >&2
		failed=1
	else
		echo "Firmware artifact verified: $image"
	fi
done

(( failed == 0 )) || exit 1
