#!/usr/bin/env bash
#
# lib/kbuild.sh — compile SM8550 gaming kernel (Image + modules + AYN DTBs)
#
# Usage:
#   ./lib/kbuild.sh
#   KERNEL_VER=7.0.14 ./lib/kbuild.sh
#   DEVICE_TARGET=odin2 ./lib/kbuild.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT

: "${OUTPUT_DIR:=${ROOT}/output}"
: "${CACHE_DIR:=${ROOT}/.cache}"
: "${PATCH_CACHE:=${CACHE_DIR}/armbian-patches}"
export OUTPUT_DIR CACHE_DIR PATCH_CACHE

# shellcheck source=config/defaults.conf
source "${ROOT}/config/defaults.conf"
[[ -f "${ROOT}/config/local.conf" ]] && source "${ROOT}/config/local.conf"

# shellcheck source=lib/kernel-org.sh
source "${ROOT}/lib/kernel-org.sh"
# shellcheck source=lib/armbian-support.sh
source "${ROOT}/lib/armbian-support.sh"
# shellcheck source=lib/armbian-patch-sync.sh
source "${ROOT}/lib/armbian-patch-sync.sh"
# shellcheck source=lib/kbuild/source.sh
source "${ROOT}/lib/kbuild/source.sh"
# shellcheck source=lib/kbuild/patches.sh
source "${ROOT}/lib/kbuild/patches.sh"
# shellcheck source=lib/output.sh
source "${ROOT}/lib/output.sh"
# shellcheck source=lib/kbuild/compile.sh
source "${ROOT}/lib/kbuild/compile.sh"
# shellcheck source=lib/dtb-chain.sh
source "${ROOT}/lib/dtb-chain.sh"
# shellcheck source=lib/cmdline.sh
source "${ROOT}/lib/cmdline.sh"
# shellcheck source=lib/initramfs.sh
source "${ROOT}/lib/initramfs.sh"
# shellcheck source=lib/bootimg.sh
source "${ROOT}/lib/bootimg.sh"
# shellcheck source=lib/firmware.sh
source "${ROOT}/lib/firmware.sh"
# shellcheck source=lib/ui.sh
source "${ROOT}/lib/ui.sh"
# shellcheck source=lib/preflight.sh
source "${ROOT}/lib/preflight.sh"

log()  { printf '[kbuild] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

check_build_deps() {
    local miss=() pkg
    for pkg in curl patch bc bison flex make gcc dtc git; do
        command -v "${pkg}" >/dev/null 2>&1 || miss+=("${pkg}")
    done
    dpkg -s libssl-dev libncurses-dev libelf-dev >/dev/null 2>&1 || {
        miss+=(libssl-dev/libncurses-dev/libelf-dev)
    }
    if [[ "${BUILD_INITRD:-1}" == "1" ]]; then
        command -v mkinitramfs >/dev/null 2>&1 || \
            [[ -x /usr/sbin/mkinitramfs ]] || miss+=(initramfs-tools)
        command -v busybox >/dev/null 2>&1 || \
            command -v busybox-static >/dev/null 2>&1 || \
            dpkg -s busybox-static >/dev/null 2>&1 || \
            dpkg -s busybox >/dev/null 2>&1 || miss+=(busybox-static)
    fi
    if [[ "${BUILD_BOOTIMG:-1}" == "1" ]]; then
        command -v abootimg >/dev/null 2>&1 || miss+=(abootimg)
    fi
    [[ ${#miss[@]} -eq 0 ]] || die "Missing dependencies: ${miss[*]}. See README.md (apt install …)"
}

resolve_kernel_for_build() {
    local kernel_ver patch_set

    if [[ -n "${KERNEL_VER:-}" ]]; then
        kernel_ver="$(resolve_kernel_version)" || exit 1
        return 0
    fi

    if [[ "${UI:-}" != "plain" && -t 0 && -t 1 ]]; then
        ui_banner
        ui_select_kernel || exit 1
        kernel_ver="${SELECTED_KERNEL_VER}"
        patch_set="$(patch_set_for_version "${kernel_ver}")" || exit 1
        ui_confirm_build "${kernel_ver}" "${patch_set}" || exit 0
        KERNEL_VER="${kernel_ver}"
        export KERNEL_VER
        return 0
    fi

    kernel_ver="$(resolve_kernel_version)" || exit 1
    KERNEL_VER="${kernel_ver}"
    export KERNEL_VER
}

kbuild_main() {
    local kernel_ver patch_set src_dir release out_suffix

    mkdir -p "${OUTPUT_DIR}" "${CACHE_DIR}" "${PATCH_CACHE}"

    check_build_deps
    refresh_armbian_support
    preflight_sm8550_build || exit 1

    resolve_kernel_for_build
    kernel_ver="${KERNEL_VER}"
    patch_set="$(patch_set_for_version "${kernel_ver}")" || exit 1
    _patch_set_matches_kernel_series "${kernel_ver}" "${patch_set}" || \
        die "Refusing linux-${kernel_ver} with ${patch_set} (requires sm8550-$(kernel_major_minor "${kernel_ver}"))."
    release="${kernel_ver}${KERNEL_LOCALVERSION}"
    out_suffix="${OUTPUT_SUFFIX:-kbase}"
    BUILD_OUT_DIR="${OUTPUT_DIR}/${release}-${out_suffix}"
    BUILD_RELEASE="${release}"
    BUILD_KERNEL_VER="${kernel_ver}"
    export BUILD_OUT_DIR BUILD_RELEASE BUILD_KERNEL_VER

    log "Kernel: linux-${kernel_ver} (${patch_set}) — source tarball from kernel.org; SM8550 patches from Armbian ${patch_set}"
    log "Output: ${BUILD_OUT_DIR}/"
    [[ "${DEBUG_BOOTLOG:-0}" == "1" ]] && \
        log "DEBUG_BOOTLOG=1 — boot log → /boot/masi-boot.log on device"

    if [[ "${BUILD_COMPILE:-1}" == "1" ]]; then
        src_dir="$(download_kernel_source "${kernel_ver}")"
        apply_armbian_patches "${src_dir}" "${patch_set}" "${kernel_ver}"
        verify_eas_in_dtsi "${src_dir}/arch/arm64/boot/dts/qcom/sm8550.dtsi"
        prepare_kernel_config "${src_dir}" "${kernel_ver}"
        compile_kernel_tree "${src_dir}" "${kernel_ver}" "${DEVICE_TARGET:-all}"
    else
        local staging
        staging="$(resolve_build_staging_dir "${BUILD_OUT_DIR}" "${BUILD_RELEASE}")"
        [[ -f "${staging}/Image" ]] || \
            die "BUILD_COMPILE=0 but ${staging}/Image is missing — run a full build first."
        log "BUILD_COMPILE=0 — reusing cached kernel/modules/DTBs in output"
    fi

    prepare_firmware_masi "${BUILD_OUT_DIR}"

    if [[ "${BUILD_ZIMAGE:-1}" == "1" ]]; then
        BUILD_OUT_DIR="${BUILD_OUT_DIR}"
        export BUILD_OUT_DIR
        dtb_chain_main
    fi

    if [[ "${BUILD_INITRD:-1}" == "1" ]]; then
        build_initramfs_masi "${BUILD_OUT_DIR}" "${BUILD_RELEASE}" || exit 1
    fi

    finalize_output_layout "${BUILD_OUT_DIR}" "${BUILD_RELEASE}"

    # shellcheck source=lib/fix-thor-screen.sh
    source "${ROOT}/lib/fix-thor-screen.sh"
    stage_fix_thor_screen "${BUILD_OUT_DIR}"

    if [[ "${BUILD_BOOTIMG:-1}" == "1" ]]; then
        pack_bootimg_abl "${BUILD_OUT_DIR}" "${BUILD_RELEASE}" || exit 1
    fi

    finalize_output_layout "${BUILD_OUT_DIR}" "${BUILD_RELEASE}"

    # shellcheck source=lib/verify-build.sh
    source "${ROOT}/lib/verify-build.sh"
    verify_build_output "${BUILD_OUT_DIR}" "${BUILD_RELEASE}" || exit 1

    log "DONE: ${BUILD_OUT_DIR}"
    log "  boot:     ${BUILD_OUT_DIR}/boot/KERNEL"
    log "  firmware: ${BUILD_OUT_DIR}/firmware/"
    log "  modules:  ${BUILD_OUT_DIR}/modules/${BUILD_RELEASE}/"
    log "  Thor fix: ${BUILD_OUT_DIR}/fix-thor-screen/fix-thor.sh  (manual, asks root)"
    log "  Gyro userspace: external project giroscopio (./install.sh) — not shipped here"
    log "  Install: sudo ./update.sh  or see INSTALL.txt"

    if [[ -t 0 && -t 1 && "${UI:-}" != "plain" ]]; then
        ui_build_complete "${BUILD_OUT_DIR}"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    kbuild_main "$@"
fi
