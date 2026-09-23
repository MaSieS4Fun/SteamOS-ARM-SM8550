#!/usr/bin/env bash
# Install userspace hooks so modular QDSP6/ADSP audio works after kernel update.
set -euo pipefail

_audio_modprobe_name() {
    local release="$1" mod="$2" ko
    local modules_root="${INSTALL_MODULES_DST}/${release}"

    shopt -s nullglob
    for ko in "${modules_root}"/kernel/**/"${mod}".ko \
              "${modules_root}"/kernel/**/"${mod//_/-}".ko; do
        [[ -f "${ko}" ]] || continue
        basename "${ko}" .ko
        shopt -u nullglob
        return 0
    done
    shopt -u nullglob
    echo "${mod}"
}

verify_audio_firmware_tree() {
    local fw_root="$1" dev adsp adsp_dtb size min=1000000 failed=0

    [[ -d "${fw_root}" ]] || {
        echo "verify-audio: missing firmware tree ${fw_root}" >&2
        return 1
    }

    for dev in odin2 odin2mini odin2portal thor; do
        adsp="${fw_root}/qcom/sm8550/ayn/${dev}/adsp.mbn"
        adsp_dtb="${fw_root}/qcom/sm8550/ayn/${dev}/adsp_dtb.mbn"
        # Thor gyro: stock Android split ADSP (adsp.mdt + .bXX) with SH5001.
        if [[ "${dev}" == "thor" && ! -f "${adsp}" ]]; then
            adsp="${fw_root}/qcom/sm8550/ayn/${dev}/adsp.mdt"
            adsp_dtb="${fw_root}/qcom/sm8550/ayn/${dev}/adsp_dtb.mdt"
        fi
        if [[ ! -f "${adsp}" ]]; then
            echo "verify-audio: missing ${adsp}" >&2
            failed=1
            continue
        fi
        size="$(stat -c %s "${adsp}" 2>/dev/null || echo 0)"
        if [[ "${adsp}" == *.mbn && "${size}" -lt "${min}" ]]; then
            echo "verify-audio: ${adsp} too small (${size} bytes)" >&2
            failed=1
        fi
        if [[ "${adsp}" == *.mdt && ! -f "${fw_root}/qcom/sm8550/ayn/${dev}/adsp.b00" ]]; then
            echo "verify-audio: Thor adsp.mdt without adsp.b00 segments" >&2
            failed=1
        fi
        [[ -f "${adsp_dtb}" ]] || {
            echo "verify-audio: missing ${adsp_dtb}" >&2
            failed=1
        }
    done

    # AYANEO Pocket boards (symlink/copy of ayn ADSP under qcom/sm8550/ayaneo/)
    adsp="${fw_root}/qcom/sm8550/ayaneo/adsp.mbn"
    adsp_dtb="${fw_root}/qcom/sm8550/ayaneo/adsp_dtb.mbn"
    if [[ ! -f "${adsp}" ]]; then
        echo "verify-audio: missing ${adsp}" >&2
        failed=1
    else
        size="$(stat -c %s "${adsp}" 2>/dev/null || echo 0)"
        if [[ "${size}" -lt "${min}" ]]; then
            echo "verify-audio: ${adsp} too small (${size} bytes)" >&2
            failed=1
        fi
        [[ -f "${adsp_dtb}" ]] || {
            echo "verify-audio: missing ${adsp_dtb}" >&2
            failed=1
        }
    fi
    [[ "${failed}" -eq 0 ]]
}

verify_audio_modules() {
    local modules_root="$1" release="${2:-}" missing=0 ko

    [[ -d "${modules_root}" ]] || {
        echo "verify-audio: missing modules tree ${modules_root}" >&2
        return 1
    }

    # Machine + bus (always separate .ko files)
    for ko in qcom_q6v5_adsp snd_soc_sc8280xp soundwire_qcom; do
        if ! find "${modules_root}" -type f \( -name "${ko}.ko" -o -name "${ko//_/-}.ko" \) \
            -print -quit 2>/dev/null | grep -q .; then
            echo "verify-audio: missing module ${ko}.ko in ${modules_root}" >&2
            missing=$((missing + 1))
        fi
    done

    # CONFIG_SND_SOC_QDSP6 has no snd_soc_qdsp6.ko on linux 7.x — it splits into q6core, q6routing, …
    local qdsp_found=0 qdsp_ko
    for qdsp_ko in q6core q6routing q6afe q6asm snd-q6apm snd-q6dsp-common; do
        if find "${modules_root}" -type f \( -name "${qdsp_ko}.ko" -o -name "${qdsp_ko//_/-}.ko" \) \
            -print -quit 2>/dev/null | grep -q .; then
            qdsp_found=1
            break
        fi
    done
    if [[ "${qdsp_found}" -eq 0 ]]; then
        echo "verify-audio: missing QDSP6 stack modules (expected q6core.ko or similar) in ${modules_root}" >&2
        missing=$((missing + 1))
    fi

    if [[ "${missing}" -gt 0 ]]; then
        echo "verify-audio: audio stack modules incomplete (release ${release})" >&2
        return 1
    fi
    return 0
}

install_audio_stack() {
    local release="$1"
    local modules_root="${INSTALL_MODULES_DST}/${release}"
    local adsp_mod machine_mod

    echo "==> MaSi audio stack (${release})" >&2

    if [[ ! -d "${modules_root}" ]]; then
        echo "  WARNING: no modules/${release} — skip audio stack" >&2
        return 0
    fi

    if command -v depmod >/dev/null 2>&1; then
        echo "  depmod -a ${release}" >&2
        depmod -a "${release}"
    else
        echo "  WARNING: depmod not found — module deps may be stale" >&2
    fi

    mkdir -p /usr/lib/masi /etc/modules-load.d /etc/modprobe.d

    install -m755 "${ROOT}/scripts/masi-qcom-audio-init.sh" \
        /usr/lib/masi/masi-qcom-audio-init.sh
    install -m644 "${ROOT}/config/audio/modules-load.d/masi-qcom-audio.conf" \
        /etc/modules-load.d/masi-qcom-audio.conf
    install -m644 "${ROOT}/config/audio/modprobe.d/masi-qcom-audio.conf" \
        /etc/modprobe.d/masi-qcom-audio.conf

    adsp_mod="$(_audio_modprobe_name "${release}" "qcom_q6v5_adsp")"
    machine_mod="$(_audio_modprobe_name "${release}" "snd_soc_sc8280xp")"
    if [[ "${adsp_mod}" != "qcom_q6v5_adsp" || "${machine_mod}" != "snd_soc_sc8280xp" ]]; then
        cat > /etc/modprobe.d/masi-qcom-audio-release.conf <<EOF
# Generated by MaSi update.sh for ${release}
softdep ${machine_mod} pre: ${adsp_mod} qcom_q6v5 qcom_rproc_common qcom_pil_info qcom_sysmon
EOF
    fi

    if [[ -d /etc/systemd/system ]]; then
        install -m644 "${ROOT}/config/masi-qcom-audio.service" \
            /etc/systemd/system/masi-qcom-audio.service
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable masi-qcom-audio.service 2>/dev/null || true
        echo "  enabled masi-qcom-audio.service" >&2
    else
        echo "  no systemd — modules-load.d + modprobe.d only" >&2
    fi

    echo "  audio: ADSP firmware path qcom/sm8550/ayn/<board>/" >&2
    echo "  audio: DP sink = DP0 Playback (USB-C DisplayPort)" >&2
}
