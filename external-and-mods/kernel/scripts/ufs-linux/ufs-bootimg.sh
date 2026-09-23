#!/usr/bin/env bash
# MaSi ABL boot/KERNEL helpers (diagnostics + legacy repair).
# Normal flow: one KERNEL for microSD + UFS —
#   root=UUID=<sd> + masi.ufsroot=PARTLABEL=STORAGE  (after update.sh)
#   or legacy root=PARTLABEL=STORAGE only
# Copy the same file to ROCKNIX — no cmdline patch.
set -euo pipefail

UFS_INTERNAL_CMDLINE='clk_ignore_unused pd_ignore_unused quiet rw rootwait root=PARTLABEL=STORAGE rootfstype=ext4 errors=remount-ro mem_sleep_default=deep ufshcd_core.uic_cmd_timeout=3000'

read_bootimg_cmdline() {
    local kernel="$1"
    [[ -f "$kernel" ]] || return 1
    if command -v abootimg >/dev/null 2>&1; then
        abootimg -i "$kernel" 2>/dev/null | sed -n 's/^\* cmdline = //p' | head -1
        return 0
    fi
    strings "$kernel" 2>/dev/null | grep -m1 '^clk_ignore_unused' || return 1
}

patch_kernel_for_internal_boot() {
    local src="$1" dst="$2"
    local cmdline="${3:-$UFS_INTERNAL_CMDLINE}"
    local work zimage initrd cfg

    command -v abootimg >/dev/null 2>&1 || return 1
    [[ -f "$src" ]] || return 1

    work="$(mktemp -d)"
    if ! (
        cd "${work}"
        cp "${src}" bootimg.in
        abootimg -x bootimg.in >/dev/null 2>&1
    ); then
        rm -rf "${work}"
        return 1
    fi

    zimage="${work}/zImage"
    initrd="${work}/initrd.img"
    cfg="${work}/bootimg.cfg"
    if [[ ! -f "${zimage}" || ! -f "${initrd}" || ! -f "${cfg}" ]]; then
        rm -rf "${work}"
        return 1
    fi

    {
        grep -E '^(bootsize|pagesize|kerneladdr|ramdiskaddr|secondaddr|tagsaddr|name) ' "${cfg}"
        printf 'cmdline = %s\n' "${cmdline}"
    } > "${cfg}.new"
    mv -f "${cfg}.new" "${cfg}"

    mkdir -p "$(dirname "${dst}")"
    if ! abootimg --create "${dst}" -f "${cfg}" -k "${zimage}" -r "${initrd}" >/dev/null 2>&1; then
        rm -rf "${work}"
        return 1
    fi
    rm -rf "${work}"
    [[ -s "${dst}" ]]
}

# Accept current dual-boot cmdline OR legacy UFS-only PARTLABEL root.
# IMPORTANT: test masi.ufsroot before root=PARTLABEL — the token
# "root=PARTLABEL=STORAGE" is a substring of "masi.ufsroot=PARTLABEL=STORAGE".
verify_internal_kernel_cmdline() {
    local kernel="$1" cmdline

    cmdline="$(read_bootimg_cmdline "${kernel}" || true)"
    [[ -n "${cmdline}" ]] || return 1
    if [[ "${cmdline}" == *'masi.ufsroot=PARTLABEL=STORAGE'* ]]; then
        [[ "${cmdline}" == *'root=UUID='* ]] || return 1
        return 0
    fi
    # Legacy UFS-only: standalone root=PARTLABEL= (not inside masi.ufsroot=)
    [[ "${cmdline}" == 'root=PARTLABEL=STORAGE'* \
        || "${cmdline}" == *' root=PARTLABEL=STORAGE'* ]] || return 1
}

describe_kernel_root() {
    local kernel="$1" cmdline

    cmdline="$(read_bootimg_cmdline "${kernel}" || true)"
    if [[ -z "${cmdline}" ]]; then
        echo "unknown (could not read bootimg cmdline)"
    elif [[ "${cmdline}" == *'masi.ufsroot=PARTLABEL=STORAGE'* && "${cmdline}" == *'root=UUID='* ]]; then
        echo "dual-boot (SD root=UUID + UFS masi.ufsroot=PARTLABEL=STORAGE)"
    elif [[ "${cmdline}" == 'root=PARTLABEL=STORAGE'* \
            || "${cmdline}" == *' root=PARTLABEL=STORAGE'* ]]; then
        echo "UFS-only cmdline (run update.sh for dual-boot SD+UFS)"
    elif [[ "${cmdline}" == *'root=UUID='* ]]; then
        echo "microSD only (legacy — run update.sh for UFS dual-boot)"
    else
        echo "other: ${cmdline}"
    fi
}
