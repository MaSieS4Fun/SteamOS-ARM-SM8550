#!/usr/bin/env bash
# Download SM8550 firmware subset from public Armbian firmware git (no host image copy).
set -euo pipefail

FIRMWARE_GIT_URL="${FIRMWARE_GIT_URL:-https://github.com/armbian/firmware.git}"
FIRMWARE_GIT_REF="${FIRMWARE_GIT_REF:-master}"

_firmware_cache_dir() {
    echo "${CACHE_DIR}/firmware-armbian"
}

_firmware_sparse_paths() {
    cat <<'EOF'
qcom/sm8550
qcom/a740_sqe.fw
qcom/gmu_gen70200.bin
qcom/vpu
ath12k/WCN7850
qca
regulatory.db
regulatory.db.p7s
renesas_usb_fw.mem
rtl_nic
EOF
}

download_firmware_sm8550() {
    local dest="$1" cache work ref
    cache="$(_firmware_cache_dir)"
    work="${CACHE_DIR}/.firmware-download-$$"

    if [[ -d "${cache}/qcom/sm8550" ]]; then
        echo "==> firmware cache: ${cache}" >&2
        _firmware_stage_copy "${cache}" "${dest}"
        return 0
    fi

    command -v git >/dev/null 2>&1 || {
        echo "Install git to download firmware from ${FIRMWARE_GIT_URL}" >&2
        return 1
    }

    echo "==> Downloading firmware from ${FIRMWARE_GIT_URL} (${FIRMWARE_GIT_REF})..." >&2
    rm -rf "${work}"
    ref="${FIRMWARE_GIT_REF}"
    if ! git clone --depth 1 --branch "${ref}" \
        --filter=blob:none --sparse "${FIRMWARE_GIT_URL}" "${work}" >&2; then
        if [[ "${ref}" != "master" ]]; then
            echo "  retry: branch master" >&2
            rm -rf "${work}"
            ref="master"
            git clone --depth 1 --branch "${ref}" \
                --filter=blob:none --sparse "${FIRMWARE_GIT_URL}" "${work}" >&2 || return 1
        else
            return 1
        fi
    fi

    [[ -d "${work}/.git" ]] || {
        echo "Firmware download failed — clone directory missing" >&2
        rm -rf "${work}"
        return 1
    }

    (
        cd "${work}"
        _firmware_sparse_paths | git sparse-checkout set --stdin
        git checkout "${ref}" >/dev/null 2>&1 || true
    ) || {
        rm -rf "${work}"
        return 1
    }

    [[ -d "${work}/qcom/sm8550" ]] || {
        echo "Firmware download incomplete — no qcom/sm8550 in checkout" >&2
        rm -rf "${work}"
        return 1
    }

    rm -rf "${cache}"
    mv "${work}" "${cache}"
    _firmware_stage_copy "${cache}" "${dest}"
}

_firmware_stage_copy() {
    local src="$1" dest="$2" path

    rm -rf "${dest}"
    mkdir -p "${dest}"

    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        [[ -e "${src}/${path}" ]] || continue
        mkdir -p "${dest}/$(dirname "${path}")"
        cp -a "${src}/${path}" "${dest}/${path}"
        echo "  + ${path}" >&2
    done < <(_firmware_sparse_paths)

    local ayn="${dest}/qcom/sm8550/ayn"
    if [[ -d "${ayn}/odin2" ]]; then
        # mini/portal share Odin 2 ADSP. Thor gets its own SH5001 overlay later
        # (must not be a symlink to odin2).
        for dev in odin2mini odin2portal; do
            [[ -e "${ayn}/${dev}" ]] || ln -sfn odin2 "${ayn}/${dev}"
        done
        if [[ -L "${ayn}/thor" ]]; then
            rm -f "${ayn}/thor"
        fi
    elif [[ ! -f "${ayn}/odin2/adsp.mbn" ]]; then
        echo "  WARNING: no qcom/sm8550/ayn/odin2 in firmware checkout" >&2
    fi

    # AYANEO Pocket SM8550 boards share AYN Odin2 ADSP firmware blobs under ayaneo/.
    local ayaneo="${dest}/qcom/sm8550/ayaneo"
    if [[ ! -e "${ayaneo}" && -d "${ayn}/odin2" ]]; then
        ln -sfn ayn/odin2 "${ayaneo}"
        echo "  + qcom/sm8550/ayaneo -> ayn/odin2" >&2
    elif [[ -d "${ayaneo}" && ! -f "${ayaneo}/adsp.mbn" && -f "${ayn}/odin2/adsp.mbn" ]]; then
        ln -sfn "../ayn/odin2/adsp.mbn" "${ayaneo}/adsp.mbn"
        ln -sfn "../ayn/odin2/adsp_dtb.mbn" "${ayaneo}/adsp_dtb.mbn"
        echo "  + qcom/sm8550/ayaneo/{adsp,adsp_dtb}.mbn -> ayn/odin2" >&2
    fi

    # Odin 2 Mini reference DTB (slot-03 reference) asks for qcom/sm8550/a740_zap.mbn;
    # Armbian/MaSi only ship ayn/ (and sheng/). Without this alias Turnip fails
    # with "could not get GPU ID" and gamescope falls back to llvmpipe.
    firmware_ensure_a740_zap_alias "${dest}"

    local n
    n="$(find "${dest}" -type f 2>/dev/null | wc -l | tr -d ' ')"
    echo "  ${n} files ($(du -sh "${dest}" | cut -f1))" >&2
    [[ "${n}" -gt 0 ]]
}

# Create ZAP firmware aliases for every path used by AYN / Mini / stock DTBs.
# Known-good Armbian 6.18.8 Odin 2 DTB asks for:
#   qcom/sm8550/ayn/odin2portal/a740_zap.mbn
# Odin 2 Mini reference / some MaSi slots ask for:
#   qcom/sm8550/a740_zap.mbn
# Armbian only ships ayn/a740_zap.mbn (and sheng/). Missing ZAP → Turnip
# "could not get GPU ID" / SECVID fallback / geometry corruption.
firmware_ensure_a740_zap_alias() {
    local dest="$1"
    local sm="${dest}/qcom/sm8550"
    local board

    [[ -d "${sm}" ]] || return 0

    if [[ -f "${sm}/ayn/a740_zap.mbn" && ! -L "${sm}/ayn/a740_zap.mbn" ]]; then
        :
    elif [[ -f "${sm}/sheng/a740_zap.mbn" ]]; then
        mkdir -p "${sm}/ayn"
        if [[ ! -e "${sm}/ayn/a740_zap.mbn" ]]; then
            ln -sfn "../sheng/a740_zap.mbn" "${sm}/ayn/a740_zap.mbn"
            echo "  + qcom/sm8550/ayn/a740_zap.mbn -> ../sheng/a740_zap.mbn" >&2
        fi
    else
        echo "  WARNING: no a740_zap.mbn under ayn/ or sheng/ — GPU may glitch" >&2
        return 0
    fi

    # Short path (Odin 2 Mini reference / some chain slots)
    if [[ ! -e "${sm}/a740_zap.mbn" ]]; then
        ln -sfn "ayn/a740_zap.mbn" "${sm}/a740_zap.mbn"
        echo "  + qcom/sm8550/a740_zap.mbn -> ayn/a740_zap.mbn" >&2
    fi

    # Board subdirs used by older Armbian AYN DTBs (odin2 / portal / mini)
    for board in odin2 odin2portal odin2mini thor; do
        mkdir -p "${sm}/ayn/${board}"
        if [[ ! -e "${sm}/ayn/${board}/a740_zap.mbn" ]]; then
            ln -sfn "../a740_zap.mbn" "${sm}/ayn/${board}/a740_zap.mbn"
            echo "  + qcom/sm8550/ayn/${board}/a740_zap.mbn -> ../a740_zap.mbn" >&2
        fi
    done
}
