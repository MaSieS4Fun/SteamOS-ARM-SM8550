#!/usr/bin/env bash
# DTB compile/assemble targets from config/dtb-chain.map + config/devices.conf
set -euo pipefail

dtb_chain_kbuild_targets() {
    local map="${ROOT}/config/dtb-chain.map" dtb
    declare -A seen=()
    [[ -f "${map}" ]] || return 1
    while IFS='|' read -r _slot source kbuild_dtb _device; do
        [[ -z "${source:-}" || "${source}" =~ ^# ]] && continue
        [[ "${source}" == "kbuild" && -n "${kbuild_dtb:-}" ]] || continue
        [[ -n "${seen[$kbuild_dtb]:-}" ]] && continue
        seen["$kbuild_dtb"]=1
        echo "${kbuild_dtb}"
    done < "${map}"
}

dtb_chain_device_targets() {
    local map="${ROOT}/config/devices.conf" id dtb
    while IFS='|' read -r id dtb _label; do
        [[ -z "${id:-}" || "${id}" =~ ^# ]] && continue
        [[ -z "${dtb:-}" ]] && continue
        echo "${dtb}"
    done < "${map}"
}

dtb_chain_all_compile_targets() {
    declare -A seen=()
    local dtb
    while IFS= read -r dtb; do
        [[ -n "${dtb}" ]] || continue
        [[ -n "${seen[$dtb]:-}" ]] && continue
        seen["$dtb"]=1
        echo "${dtb}"
    done < <(
        dtb_chain_device_targets
        dtb_chain_kbuild_targets
    )
}

verify_kbuild_dtbs_ready() {
    local kbuild_dir="$1" missing=0 dtb

    # shellcheck source=lib/dtb-chain/map.sh
    source "${ROOT}/lib/dtb-chain/map.sh"

    while IFS='|' read -r _slot source kbuild_dtb _device; do
        [[ -z "${source:-}" || "${source}" =~ ^# ]] && continue
        [[ "${source}" == "kbuild" ]] || continue
        [[ -f "${kbuild_dir}/${kbuild_dtb}" ]] && continue
        echo "  MISSING kbuild DTB: ${kbuild_dtb} (${_device})" >&2
        missing=1
    done < "${ROOT}/config/dtb-chain.map"

    [[ "${missing}" -eq 0 ]] || {
        echo "DTB chain: compile kernel with all targets in config/dtb-chain.map" >&2
        return 1
    }
    echo "==> DTB chain: kbuild ready ($(dtb_chain_slot_count) slots)" >&2
}
