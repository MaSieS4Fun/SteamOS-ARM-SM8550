#!/usr/bin/env bash
# Pre-build checks — autonomous build from public sources.
set -euo pipefail

preflight_sm8550_build() {
    local boot="${BOOT_KERNEL_PATH:-/boot/KERNEL}"
    local cfg="${BOOT_LINUXLOADER_CFG_PATH:-/boot/LinuxLoader.cfg}"
    local ok=1

    echo "==> Preflight" >&2

    if [[ -n "${ROOT_UUID:-}" ]]; then
        echo "  OK  root UUID: ROOT_UUID override (${ROOT_UUID})" >&2
    elif resolve_root_uuid >/dev/null 2>&1 && [[ -n "${RESOLVED_ROOT_UUID:-}" ]]; then
        export ROOT_UUID="${RESOLVED_ROOT_UUID}"
        echo "  OK  root UUID: ${ROOT_UUID_SOURCE} (${RESOLVED_ROOT_UUID})" >&2
    elif [[ "${PREFLIGHT_SKIP_ROOT_UUID:-0}" == "1" ]]; then
        echo "  OK  root UUID: skipped (embed at make-disk-image or sudo ./update.sh on device)" >&2
    else
        echo "  !!  root UUID: need ${cfg} or ${boot} (or ROOT_UUID= / PREFLIGHT_SKIP_ROOT_UUID=1)" >&2
        ok=0
    fi

    if [[ -f "${ROOT}/config/bootimg.abl.cfg" ]]; then
        echo "  OK  bootimg layout: config/bootimg.abl.cfg" >&2
    else
        echo "  !!  bootimg: missing config/bootimg.abl.cfg" >&2
        ok=0
    fi

    echo "  OK  DTB chain: reference slot order (config/dtb-chain.map)" >&2
    if [[ ! -f "${ROOT}/reference/dtb-chain/slot-00.dtb" ]]; then
        if [[ -f "${ROOT}/reference-boot-partition/KERNEL" ]]; then
            echo "  ..  extracting reference/dtb-chain from reference-boot-partition/KERNEL" >&2
            "${ROOT}/scripts/extract-reference-dtb-chain.sh" || ok=0
        else
            echo "  !!  missing reference/dtb-chain (run ./scripts/extract-reference-dtb-chain.sh)" >&2
            ok=0
        fi
    else
        echo "  OK  reference/dtb-chain/" >&2
    fi
    echo "  OK  firmware: ${FIRMWARE_SOURCE:-download} (${FIRMWARE_GIT_URL:-armbian/firmware})" >&2
    echo "  OK  initrd: ${INITRAMFS_PROFILE:-efi-clean} (scrubbed; gold off unless INITRAMFS_USE_GOLD=1)" >&2

    [[ "${ok}" -eq 1 ]] || {
        echo "  Fix the items above, then re-run ./make.sh" >&2
        return 1
    }
    echo >&2
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export ROOT
    # shellcheck source=config/defaults.conf
    source "${ROOT}/config/defaults.conf"
    [[ -f "${ROOT}/config/local.conf" ]] && source "${ROOT}/config/local.conf"
    # shellcheck source=lib/cmdline.sh
    source "${ROOT}/lib/cmdline.sh"
    preflight_sm8550_build
fi
