#!/usr/bin/env bash
# Stage AYN Thor userspace fix bundle into build output (fix-thor-screen/).
set -euo pipefail

stage_fix_thor_screen() {
	local out_dir="$1"
	local src="${ROOT}/payload/fix-thor-screen"
	local dest="${out_dir}/fix-thor-screen"

	[[ -d "${src}" ]] || {
		echo "  WARN fix-thor-screen: missing ${src}" >&2
		return 0
	}

	rm -rf "${dest}"
	cp -a "${src}" "${dest}"
	chmod 0755 "${dest}/fix-thor.sh"

	echo "  fix-thor-screen/  (AYN Thor: ./fix-thor.sh — system-wide, asks root)" >&2
}

verify_fix_thor_screen_bundle() {
	local out_dir="$1"
	local dest="${out_dir}/fix-thor-screen"

	[[ -x "${dest}/fix-thor.sh" ]] || {
		echo "  ERROR: missing ${dest}/fix-thor.sh" >&2
		return 1
	}

	"${dest}/fix-thor.sh" --check-only >/dev/null || {
		echo "  ERROR: fix-thor-screen bundle incomplete" >&2
		return 1
	}

	echo "  OK  fix-thor-screen/" >&2
	return 0
}

_thor_device_hint() {
	[[ -f /proc/device-tree/compatible ]] || return 1
	tr -d '\0' < /proc/device-tree/compatible | grep -q 'ayn,thor'
}

	print_fix_thor_hint() {
	local build_dir="${1:-}"

	[[ -n "${build_dir}" ]] || return 0
	[[ -d "${build_dir}/fix-thor-screen" ]] || return 0

	echo ""
	echo "AYN Thor — after reboot, apply userspace touch fix (system-wide, asks root):"
	echo "  cd ${build_dir}/fix-thor-screen && ./fix-thor.sh"
	echo ""
}
