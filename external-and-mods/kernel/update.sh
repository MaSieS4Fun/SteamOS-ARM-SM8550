#!/usr/bin/env bash
# Install kernel on THIS device — mandatory UUID repack, preflight checks.
#
# Usage:
#   sudo ./update.sh
#   UPDATE_BUILD=output/7.0.14-edge-sm8550-kbase sudo ./update.sh
#
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    exec sudo -- "$0" "$@"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT
export OUTPUT_DIR="${OUTPUT_DIR:-${ROOT}/output}"
mkdir -p "${OUTPUT_DIR}"

# shellcheck source=config/defaults.conf
source "${ROOT}/config/defaults.conf"
[[ -f "${ROOT}/config/local.conf" ]] && source "${ROOT}/config/local.conf"

# shellcheck source=lib/install.sh
source "${ROOT}/lib/install.sh"

install_system_paths

echo "============================================================"
echo "  kernel-new-base — Safe install"
echo "  Backup → output/old_kernel/  |  UUID repack REQUIRED"
echo "============================================================"
echo ""
echo "Running kernel: $(uname -r)"
echo ""

"${ROOT}/scripts/preflight-device.sh" || {
    echo ""
    echo "Preflight failed — fix ABL device / use correct kernel base." >&2
    exit 1
}

install_pick_build || exit 1
build="${SELECTED_INSTALL_BUILD}"
release="$(install_resolve_release "${build}")" || exit 1

echo ""
echo "Build to install: ${build}"
echo "  boot/KERNEL  → ${INSTALL_BOOT_DST}/  (repacked with THIS SD UUID)"
echo "  firmware/    → ${INSTALL_FIRMWARE_DST}/"
echo "  modules/     → ${INSTALL_MODULES_DST}/${release}/"
echo ""
echo "  Do NOT copy boot/KERNEL to another SD card."
echo "  Each device must run sudo ./update.sh locally."
echo ""
echo "Current system backup: ${OUTPUT_DIR}/old_kernel/"
echo ""

if [[ "${UPDATE_YES:-0}" == "1" ]]; then
    echo "UPDATE_YES=1 — continuing without prompt."
elif [[ -t 0 ]]; then
    read -r -p "Continue with backup and install? [y/N] " ans
    [[ "${ans,,}" == "y" ]] || { echo "Cancelled."; exit 0; }
fi

install_backup_running
install_from_build "${build}"

"${ROOT}/scripts/verify-installed-kernel.sh" "${INSTALL_BOOT_DST}/KERNEL" || {
    echo "ERROR: post-install KERNEL verification failed." >&2
    exit 1
}

echo ""
echo "============================================================"
echo "  BEFORE REBOOT — ABL menu (Vol Down at power-on):"
echo "    Set the Device → your exact handheld model"
echo "    Boot Mode → Linux → START"
echo "============================================================"
echo ""

install_prompt_reboot
