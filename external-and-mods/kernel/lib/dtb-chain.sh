#!/usr/bin/env bash
#
# lib/dtb-chain.sh — ABL multidevice chain (11 DTBs + zImage)
#
# ROCKNIX ABL picks the DTB by hardware; do NOT use devicetree= in EFI cmdline.
#
# Usage:
#   BUILD_OUT_DIR=output/... ./lib/dtb-chain.sh
#   ROCKNIX_KERNEL=/path/KERNEL ./lib/dtb-chain.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT

: "${OUTPUT_DIR:=${ROOT}/output}"
: "${CACHE_DIR:=${ROOT}/.cache}"
export OUTPUT_DIR CACHE_DIR

# shellcheck source=config/defaults.conf
source "${ROOT}/config/defaults.conf"
# shellcheck source=lib/output.sh
source "${ROOT}/lib/output.sh"

# shellcheck source=lib/dtb-chain/targets.sh
source "${ROOT}/lib/dtb-chain/targets.sh"
# shellcheck source=lib/dtb-chain/assemble.sh
source "${ROOT}/lib/dtb-chain/assemble.sh"
# shellcheck source=lib/dtb-chain/zimage.sh
source "${ROOT}/lib/dtb-chain/zimage.sh"
# shellcheck source=lib/dtb-chain/verify.sh
source "${ROOT}/lib/dtb-chain/verify.sh"

# shellcheck source=lib/dtb-chain/map.sh
source "${ROOT}/lib/dtb-chain/map.sh"
# shellcheck source=lib/dtb-chain/sanitize.sh
source "${ROOT}/lib/dtb-chain/sanitize.sh"

log()  { printf '[dtb-chain] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

resolve_build_out_dir() {
    if [[ -n "${BUILD_OUT_DIR:-}" && -d "${BUILD_OUT_DIR}" ]]; then
        local staging
        staging="$(resolve_build_staging_dir "${BUILD_OUT_DIR}" "${BUILD_RELEASE:-}")"
        [[ -f "${staging}/Image" ]] && echo "${BUILD_OUT_DIR}" && return 0
    fi
    local latest staging
    latest="$(find "${OUTPUT_DIR}" -maxdepth 1 -type d -name '*-edge-sm8550-*' 2>/dev/null | sort -V | tail -1)"
    [[ -n "${latest}" ]] || return 1
    staging="$(resolve_build_staging_dir "${latest}")"
    [[ -f "${staging}/Image" ]] || return 1
    echo "${latest}"
}

dtb_chain_main() {
    local out_dir staging chain_asm kbuild_dtbs zimage

    out_dir="$(resolve_build_out_dir)" || die "No prior build. Run ./make.sh (kbuild) first."
    staging="$(resolve_build_staging_dir "${out_dir}" "${BUILD_RELEASE:-}")"
    chain_asm="${staging}/dtb-chain"
    kbuild_dtbs="${staging}/dtbs"
    zimage="${staging}/zImage"

    [[ -f "${staging}/Image" ]] || die "Missing ${staging}/Image"

    verify_kbuild_dtbs_ready "${kbuild_dtbs}" || exit 1
    assemble_dtb_chain "${chain_asm}" "${kbuild_dtbs}" "" || exit 1
    sanitize_dtb_dir "${chain_asm}"
    sanitize_dtb_dir "${kbuild_dtbs}"
    build_zimage_abl "${staging}/Image" "${chain_asm}" "${zimage}" || exit 1
    verify_abl_dtb_chain "${zimage}" || exit 1

    BUILD_OUT_DIR="${out_dir}"
    export BUILD_OUT_DIR ABL_EMBEDDED_DTB_COUNT

    log "DONE: ${zimage}"
    log "  Chain: ${chain_asm}/ ($(dtb_chain_slot_count) slots)"
    log "  Boot: ABL selects DTB — do not use devicetree= in GRUB/EFI"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    dtb_chain_main "$@"
fi
