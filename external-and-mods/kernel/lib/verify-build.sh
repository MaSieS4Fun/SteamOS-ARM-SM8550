#!/usr/bin/env bash
# Post-build gate — fail ./make.sh if the bundle is not safe to ship.
set -euo pipefail

_initrd_has_poison_root() {
    local initrd="$1"
    local tmp
    tmp="$(mktemp -d)"
    if gzip -dc "${initrd}" 2>/dev/null | (cd "${tmp}" && cpio -idm conf/conf.d/root 2>/dev/null); then
        if [[ -f "${tmp}/conf/conf.d/root" ]]; then
            rm -rf "${tmp}"
            return 0
        fi
    fi
    rm -rf "${tmp}"
    return 1
}

verify_build_output() {
    local out_dir="$1" release="${2:-}"
    local kernel work cmdline

    [[ -f "${out_dir}/boot/KERNEL" ]] || {
        echo "verify-build: missing ${out_dir}/boot/KERNEL" >&2
        return 1
    }

    kernel="${out_dir}/boot/KERNEL"

    echo "==> verify-build (ship gate)" >&2

    command -v abootimg >/dev/null 2>&1 || {
        echo "  ERROR: abootimg required for verify-build" >&2
        return 1
    }

    work="$(mktemp -d)"
    (
        cd "${work}"
        abootimg -x "${kernel}" >/dev/null
    ) || {
        rm -rf "${work}"
        echo "  ERROR: cannot unpack boot/KERNEL" >&2
        return 1
    }

    [[ -f "${work}/zImage" ]] || {
        rm -rf "${work}"
        echo "  ERROR: no zImage in KERNEL" >&2
        return 1
    }

    # shellcheck source=lib/dtb-chain/verify.sh
    source "${ROOT}/lib/dtb-chain/verify.sh"
    verify_abl_dtb_chain "${work}/zImage" || {
        rm -rf "${work}"
        return 1
    }

    if [[ -f "${work}/initrd.img" ]]; then
        if _initrd_has_poison_root "${work}/initrd.img"; then
            echo "  ERROR: initrd contains conf/conf.d/root (host path — breaks other devices)" >&2
            rm -rf "${work}"
            return 1
        fi
        echo "  OK  initrd: no poisoned conf/conf.d/root" >&2
    fi

    cmdline="$(abootimg -i "${kernel}" 2>/dev/null | sed -n 's/^\* cmdline = //p' | head -1)"
    if [[ "${cmdline}" == *"devicetree="* || "${cmdline}" == *"dtb="* ]]; then
        echo "  ERROR: cmdline pins DTB via devicetree=" >&2
        rm -rf "${work}"
        return 1
    fi
    echo "  OK  cmdline: no devicetree= pin" >&2

    # shellcheck source=lib/cmdline.sh
    source "${ROOT}/lib/cmdline.sh"
    if verify_unified_abl_cmdline "${cmdline}"; then
        echo "  OK  cmdline: dual-boot (root=UUID + masi.ufsroot or PARTLABEL)" >&2
    else
        echo "  ERROR: KERNEL cmdline is not dual-boot capable" >&2
        echo "        need: root=UUID=… + masi.ufsroot=PARTLABEL=STORAGE" >&2
        echo "           or: root=PARTLABEL=STORAGE" >&2
        echo "        got:  ${cmdline}" >&2
        rm -rf "${work}"
        return 1
    fi

    if grep -Fq 'scripts/init-premount/masi-dual-root' \
        < <(gzip -dc "${work}/initrd.img" 2>/dev/null | cpio -t 2>/dev/null); then
        echo "  OK  initrd: masi-dual-root init-premount (SD vs UFS root)" >&2
    else
        echo "  ERROR: initrd missing scripts/init-premount/masi-dual-root" >&2
        rm -rf "${work}"
        return 1
    fi

    [[ -d "${out_dir}/modules/${release}" ]] || {
        echo "  ERROR: missing modules/${release}" >&2
        rm -rf "${work}"
        return 1
    }
    echo "  OK  modules/${release}" >&2

    # shellcheck source=lib/audio-stack.sh
    source "${ROOT}/lib/audio-stack.sh"

    if [[ -d "${out_dir}/firmware" ]]; then
        echo "  OK  firmware/" >&2
        verify_audio_firmware_tree "${out_dir}/firmware" || {
            rm -rf "${work}"
            return 1
        }
        echo "  OK  firmware: ADSP blobs for AYN boards" >&2
    fi

    verify_audio_modules "${out_dir}/modules/${release}" "${release}" || {
        rm -rf "${work}"
        return 1
    }
    echo "  OK  audio modules (ADSP + SC8280XP + QDSP6)" >&2

    # shellcheck source=lib/fix-thor-screen.sh
    source "${ROOT}/lib/fix-thor-screen.sh"
    verify_fix_thor_screen_bundle "${out_dir}" || {
        rm -rf "${work}"
        return 1
    }

    rm -rf "${work}"
    echo "==> verify-build PASSED" >&2
    return 0
}
