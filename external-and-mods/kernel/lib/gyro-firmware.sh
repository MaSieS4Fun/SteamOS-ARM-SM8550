#!/usr/bin/env bash
# Overlay Qualcomm Sensor Core firmware for AYN Thor ADSP (SH5001).
# Userspace (JSON registry, hexagonrpcd, motion) is NOT staged here — see ~/Projects/giroscopio.
set -euo pipefail

stage_qcom_gyro_firmware() {
	local fw_out="$1"
	local vendor="${ROOT}/vendor/qcom-gyro"
	local thor_src="${vendor}/firmware-thor-adsp"
	local ayn="${fw_out}/qcom/sm8550/ayn"
	local thor_dst="${ayn}/thor"
	local odin2="${ayn}/odin2"

	[[ -d "${thor_src}" ]] || {
		echo "  SKIP gyro firmware overlay (missing ${thor_src})" >&2
		return 0
	}

	echo "==> Overlay Thor ADSP (SH5001 split .mdt) for gyro" >&2

	# Armbian stages thor → odin2 as a symlink. Replace with a real directory so
	# we never delete or overwrite Odin 2's adsp.mbn.
	if [[ -L "${thor_dst}" ]]; then
		rm -f "${thor_dst}"
	elif [[ -d "${thor_dst}" ]]; then
		# Real dir from a previous overlay — refresh in place.
		rm -rf "${thor_dst}"
	fi

	mkdir -p "${thor_dst}"
	cp -a "${thor_src}/." "${thor_dst}/"

	# Keep shared JSON/amp blobs from Odin 2 family when Thor package omits them.
	if [[ -d "${odin2}" ]]; then
		local f
		for f in adspr.jsn adsps.jsn adspua.jsn battmgr.jsn aw883xx_acf.bin \
			cdsp.mbn cdsp_dtb.mbn; do
			if [[ -f "${odin2}/${f}" && ! -e "${thor_dst}/${f}" ]]; then
				cp -a "${odin2}/${f}" "${thor_dst}/${f}"
			fi
		done
	fi

	[[ -f "${thor_dst}/adsp.mdt" && -f "${thor_dst}/adsp.b00" ]] || {
		echo "ERROR: Thor ADSP overlay incomplete (${thor_dst})" >&2
		return 1
	}
	[[ -f "${odin2}/adsp.mbn" ]] || {
		echo "ERROR: Odin 2 adsp.mbn missing after Thor overlay — refuse to ship" >&2
		return 1
	}

	echo "  OK   ${thor_dst}/adsp.mdt (odin2 adsp.mbn untouched)" >&2
}
