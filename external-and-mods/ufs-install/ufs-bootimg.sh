#!/usr/bin/env bash
# SteamOS SM8550 helpers for UFS ROCKNIX install (this project only).
# SD keeps dual-boot KERNEL (root=UUID=... + masi.ufsroot=PARTLABEL=STORAGE).
# ROCKNIX always gets root=PARTLABEL=STORAGE so UFS boot does not depend on the SD.
set -euo pipefail

UFS_INTERNAL_CMDLINE='clk_ignore_unused pd_ignore_unused quiet rw rootwait root=PARTLABEL=STORAGE rootfstype=ext4 errors=remount-ro mem_sleep_default=deep ufshcd_core.uic_cmd_timeout=3000'

have_android_mkbootimg() {
    command -v unpack_bootimg >/dev/null 2>&1 && command -v mkbootimg >/dev/null 2>&1
}

have_abootimg() {
    command -v abootimg >/dev/null 2>&1
}

have_bootimg_tools() {
    have_android_mkbootimg || have_abootimg
}

read_bootimg_cmdline() {
    local kernel="$1" line
    [[ -f "$kernel" ]] || return 1
    if have_android_mkbootimg; then
        line="$(unpack_bootimg --boot_img "$kernel" --format=info 2>/dev/null \
            | sed -n 's/^command line args: //p' | head -1)"
        if [[ -n "$line" ]]; then
            printf '%s' "$line"
            return 0
        fi
    fi
    if have_abootimg; then
        abootimg -i "$kernel" 2>/dev/null | sed -n 's/^\* cmdline = //p' | head -1
        return 0
    fi
    strings "$kernel" 2>/dev/null | grep -m1 '^clk_ignore_unused' || return 1
}

# Build ROCKNIX cmdline from an existing KERNEL (keeps suspend/debug extras, forces PARTLABEL root).
build_ufs_rocknix_cmdline() {
    local src="${1:-}"
    local cmdline token
    local -a out=()

    if [[ -n "$src" && -f "$src" ]]; then
        cmdline="$(read_bootimg_cmdline "$src" || true)"
    fi

    if [[ -z "${cmdline:-}" ]]; then
        printf '%s' "$UFS_INTERNAL_CMDLINE"
        return 0
    fi

    for token in $cmdline; do
        case "$token" in
            root=*|rootfstype=*|errors=*|masi.ufsroot=*|masi.sdroot=*|masi.root=*)
                continue
                ;;
            *)
                out+=("$token")
                ;;
        esac
    done

    out+=("root=PARTLABEL=STORAGE" "rootfstype=ext4" "errors=remount-ro")
    printf '%s' "${out[*]}"
}

_install_kernel_mkbootimg() {
    local src="$1" dst="$2" cmdline="$3"
    local work args_file
    local -a mk_args=()
    local skip=0 arg

    work="$(mktemp -d)"
    args_file="${work}/mkbootimg_args"
    if ! unpack_bootimg --boot_img "$src" --out "$work" --format=mkbootimg -0 \
            >"$args_file" 2>/dev/null; then
        rm -rf "$work"
        return 1
    fi

    while IFS= read -r -d '' arg; do
        if (( skip )); then
            skip=0
            continue
        fi
        if [[ "$arg" == "--cmdline" ]]; then
            mk_args+=(--cmdline "$cmdline")
            skip=1
            continue
        fi
        mk_args+=("$arg")
    done <"$args_file"

    mkdir -p "$(dirname "$dst")"
    if ! mkbootimg "${mk_args[@]}" -o "$dst" >/dev/null 2>&1; then
        rm -rf "$work"
        return 1
    fi
    rm -rf "$work"
    [[ -s "$dst" ]]
}

_install_kernel_abootimg() {
    local src="$1" dst="$2" cmdline="$3"
    local work zimage initrd cfg

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

# Pack KERNEL for ROCKNIX: same zImage/initrd as src, UFS-only cmdline.
# Prefer SteamOS unpack_bootimg/mkbootimg; fall back to abootimg.
install_kernel_for_ufs_rocknix() {
    local src="$1" dst="$2"
    local cmdline

    [[ -f "$src" ]] || return 1
    cmdline="$(build_ufs_rocknix_cmdline "$src")"

    if have_android_mkbootimg; then
        _install_kernel_mkbootimg "$src" "$dst" "$cmdline" && return 0
    fi
    if have_abootimg; then
        _install_kernel_abootimg "$src" "$dst" "$cmdline" && return 0
    fi
    return 1
}

# Legacy alias
patch_kernel_for_internal_boot() {
    local src="$1" dst="$2"
    install_kernel_for_ufs_rocknix "$src" "$dst"
}

# ROCKNIX KERNEL after install: must be PARTLABEL only (not SD UUID).
verify_ufs_rocknix_kernel_cmdline() {
    local kernel="$1" cmdline

    cmdline="$(read_bootimg_cmdline "${kernel}" || true)"
    [[ -n "${cmdline}" ]] || return 1
    [[ "${cmdline}" == *'root=PARTLABEL=STORAGE'* ]] || return 1
    [[ "${cmdline}" != *'root=UUID='* ]] || return 1
    [[ "${cmdline}" != *'masi.ufsroot='* ]] || return 1
}

# Accept dual-boot SD KERNEL or UFS ROCKNIX KERNEL.
verify_internal_kernel_cmdline() {
    local kernel="$1" cmdline

    cmdline="$(read_bootimg_cmdline "${kernel}" || true)"
    [[ -n "${cmdline}" ]] || return 1
    if [[ "${cmdline}" == *'masi.ufsroot=PARTLABEL=STORAGE'* ]]; then
        [[ "${cmdline}" == *'root=UUID='* ]] || return 1
        return 0
    fi
    [[ "${cmdline}" == *'root=PARTLABEL=STORAGE'* ]] || return 1
}

describe_kernel_root() {
    local kernel="$1" cmdline

    cmdline="$(read_bootimg_cmdline "${kernel}" || true)"
    if [[ -z "${cmdline}" ]]; then
        echo "unknown (could not read bootimg cmdline)"
    elif [[ "${cmdline}" == *'root=PARTLABEL=STORAGE'* && "${cmdline}" != *'root=UUID='* ]]; then
        echo "UFS ROCKNIX (root=PARTLABEL=STORAGE)"
    elif [[ "${cmdline}" == *'masi.ufsroot=PARTLABEL=STORAGE'* && "${cmdline}" == *'root=UUID='* ]]; then
        echo "microSD dual-boot (root=UUID + masi.ufsroot)"
    elif [[ "${cmdline}" == *'root=UUID='* ]]; then
        echo "microSD only (legacy — not safe for UFS ROCKNIX)"
    else
        echo "other: ${cmdline}"
    fi
}

ufs_fstab_text() {
    cat <<'EOF'
# SteamOS SM8550 — internal UFS (ROCKNIX ABL 3-partition)
PARTLABEL=STORAGE  /      ext4  defaults,noatime,commit=120,errors=remount-ro  0 1
PARTLABEL=ROCKNIX  /boot  vfat  defaults,umask=0077                           0 2
PARTLABEL=HOME     /home  ext4  defaults,noatime,x-systemd.growfs             0 2
tmpfs              /tmp   tmpfs defaults,nosuid                               0 0
EOF
}

# Write fstab on the copied root AND SteamOS /etc overlay upper (upper wins at boot).
write_ufs_fstab_tree() {
    local root="$1"
    mkdir -p "${root}/etc"
    ufs_fstab_text > "${root}/etc/fstab"
    if [[ -d "${root}/var/lib/overlays/etc/upper" ]]; then
        ufs_fstab_text > "${root}/var/lib/overlays/etc/upper/fstab"
    fi
}
