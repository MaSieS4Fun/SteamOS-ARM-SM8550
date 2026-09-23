#!/usr/bin/env bash
# Copy or download SM8550 firmware → output/firmware/
set -euo pipefail

_system_firmware_root() {
    local p
    for p in /usr/lib/firmware /lib/firmware; do
        [[ -d "${p}/qcom/sm8550" || -d "${p}/qcom" ]] && echo "${p}" && return 0
    done
    return 1
}

prepare_firmware_masi() {
    local out_dir="$1"
    local fw_out="${out_dir}/firmware"
    local mode="${FIRMWARE_SOURCE:-download}"

    rm -rf "${fw_out}"
    mkdir -p "${fw_out}"

    case "${mode}" in
        host)
            local system_src path
            system_src="$(_system_firmware_root)" || {
                echo "FIRMWARE_SOURCE=host but no qcom firmware on system" >&2
                return 1
            }
            echo "==> firmware → ${fw_out}/ (from ${system_src})" >&2
            for path in \
                qcom/sm8550 qcom/a740_sqe.fw qcom/gmu_gen70200.bin qcom/vpu \
                ath12k/WCN7850 qca regulatory.db regulatory.db.p7s \
                renesas_usb_fw.mem rtl_nic; do
                [[ -e "${system_src}/${path}" ]] || continue
                mkdir -p "${fw_out}/$(dirname "${path}")"
                cp -a "${system_src}/${path}" "${fw_out}/${path}"
                echo "  + ${path}" >&2
            done
            # shellcheck source=lib/firmware-download.sh
            source "${ROOT}/lib/firmware-download.sh"
            firmware_ensure_a740_zap_alias "${fw_out}"
            ;;
        download|*)
            # shellcheck source=lib/firmware-download.sh
            source "${ROOT}/lib/firmware-download.sh"
            download_firmware_sm8550 "${fw_out}" || return 1
            ;;
    esac

    local n ayn="${fw_out}/qcom/sm8550/ayn"
    n="$(find "${fw_out}" -type f 2>/dev/null | wc -l | tr -d ' ')"
    echo "  ${n} files ($(du -sh "${fw_out}" | cut -f1))" >&2

    # shellcheck source=lib/audio-stack.sh
    source "${ROOT}/lib/audio-stack.sh"
    # shellcheck source=lib/gyro-firmware.sh
    source "${ROOT}/lib/gyro-firmware.sh"
    stage_qcom_gyro_firmware "${fw_out}"

    if ! verify_audio_firmware_tree "${fw_out}"; then
        if [[ "${mode}" == "host" ]] && [[ -d "${fw_out}/qcom/sm8550" ]]; then
            echo "  WARNING: host firmware missing AYN ADSP — HDMI/DP audio may not work" >&2
        else
            echo "ERROR: AYN ADSP firmware incomplete (need qcom/sm8550/ayn/*/adsp.mbn or thor adsp.mdt)" >&2
            return 1
        fi
    else
        echo "  OK   ADSP firmware for odin2/mini/portal/thor" >&2
    fi

    # Overlay Rocknix/linux-firmware a740_sqe.fw (Armbian SQE causes RPCS3 glitches)
    firmware_overlay_rocknix_sqe "${fw_out}" || return 1

    [[ "${n}" -gt 0 ]] || {
        echo "ERROR: empty firmware output" >&2
        return 1
    }
}

# Replace Armbian a740_sqe.fw with Rocknix/linux-firmware (md5 0211fdf6…).
firmware_overlay_rocknix_sqe() {
    local fw_out="$1"
    local ov_sqe="${ROOT}/firmware-overrides/qcom/a740_sqe.fw"
    local want="0211fdf6aa6f523e9d392f31ffbf10a1"
    local have=""

    [[ -f "${ov_sqe}" ]] || {
        echo "ERROR: missing ${ov_sqe} (Rocknix SQE override)" >&2
        return 1
    }
    have="$(md5sum "${ov_sqe}" | awk '{print $1}')"
    [[ "${have}" == "${want}" ]] || {
        echo "ERROR: firmware-overrides/qcom/a740_sqe.fw md5 ${have} != ${want}" >&2
        return 1
    }
    mkdir -p "${fw_out}/qcom"
    cp -a "${ov_sqe}" "${fw_out}/qcom/a740_sqe.fw"
    echo "  + qcom/a740_sqe.fw ← Rocknix/linux-firmware (RPCS3 fix)" >&2
}
