#!/bin/sh
# Load Qualcomm ADSP + SC8280XP ASoC after firmware is on rootfs (MaSi kernel modules are =m).
set -eu

log() {
    echo "masi-qcom-audio: $*" >&2
}

modprobe_best() {
    local base="$1" alt
    alt="$(echo "${base}" | tr '_' '-')"
    modprobe "${base}" 2>/dev/null && return 0
    [ "${alt}" = "${base}" ] && return 1
    modprobe "${alt}" 2>/dev/null
}

adsp_ready() {
    [ -d /sys/class/remoteproc ] || return 1
    for _r in /sys/class/remoteproc/remoteproc*; do
        [ -d "${_r}" ] || continue
        if grep -q adsp "${_r}/name" 2>/dev/null; then
            state="$(cat "${_r}/state" 2>/dev/null || echo "")"
            [ "${state}" = "running" ] && return 0
        fi
    done
    return 1
}

load_adsp() {
    if adsp_ready; then
        return 0
    fi
    modprobe_best qcom_pil_info || true
    modprobe_best qcom_rproc_common || true
    modprobe_best qcom_q6v5 || true
    modprobe_best qcom_sysmon || true
    if modprobe_best qcom_q6v5_adsp; then
        return 0
    fi
    log "qcom_q6v5_adsp failed — check /usr/lib/firmware/qcom/sm8550/ayn/*/adsp.mbn"
    return 1
}

load_machine() {
    if modprobe_best snd_soc_sc8280xp; then
        return 0
    fi
    log "snd_soc_sc8280xp failed — kernel modules or depmod missing?"
    return 1
}

load_hdmi_bridge() {
    modprobe_best lontium_lt8912b 2>/dev/null || \
        modprobe_best drm_lontium_lt8912b 2>/dev/null || true
}

case "${1:-boot}" in
    load_machine)
        load_machine
        ;;
    load_hdmi)
        load_hdmi_bridge
        ;;
    boot|*)
        load_adsp || exit 0
        load_machine || exit 0
        load_hdmi_bridge
        ;;
esac

exit 0
