#!/usr/bin/env bash
# Sync boot/KERNEL to internal UFS ROCKNIX partition (same file as microSD — no cmdline patch).
set -euo pipefail

update_internal_ufs_kernel() {
    local kernel="${1:-/boot/KERNEL}"
    local rk_dev mount="/run/masi-ufs-rocknix" need_umount=0

    [[ -f "${kernel}" ]] || {
        echo "  UFS: skip ROCKNIX sync (no ${kernel})" >&2
        return 0
    }

    rk_dev="$(lsblk -rn -o NAME,PARTLABEL 2>/dev/null | awk '$2=="ROCKNIX"{print "/dev/"$1; exit}')"
    [[ -n "${rk_dev}" ]] || {
        echo "  UFS: no ROCKNIX partition — skip internal KERNEL sync" >&2
        return 0
    }

    echo "==> UFS ROCKNIX ← ${kernel}" >&2

    if findmnt -rn -S "$rk_dev" >/dev/null 2>&1; then
        mount="$(findmnt -rn -o TARGET -S "$rk_dev")"
    else
        mkdir -p "$mount"
        mount "$rk_dev" "$mount" || {
            echo "  WARNING: could not mount ${rk_dev} — skip ROCKNIX KERNEL sync" >&2
            return 0
        }
        need_umount=1
    fi

    cp -a "${kernel}" "${mount}/KERNEL"
    md5sum "${mount}/KERNEL" | awk '{print $1}' > "${mount}/KERNEL.md5"
    sync "$mount" 2>/dev/null || sync

    if (( need_umount )); then
        umount "$mount" 2>/dev/null || true
        rmdir "$mount" 2>/dev/null || true
    fi

    echo "  UFS ROCKNIX KERNEL updated (${rk_dev})" >&2
}

install_ufs_linux_scripts() {
    local src="${ROOT}/scripts/ufs-linux"
    local dest="/usr/lib/masi/ufs-linux"

    [[ -d "${src}" ]] || {
        echo "  WARNING: missing ${src} — skip UFS install scripts" >&2
        return 0
    }

    echo "==> UFS internal install scripts → ${dest}/" >&2
    mkdir -p "${dest}"
    install -m755 "${src}/install-masios-to-internal.sh" "${dest}/"
    install -m755 "${src}/ufs-bootimg.sh" "${dest}/"
    install -m755 "${src}/ufs-fix-internal-boot.sh" "${dest}/"
    install -m755 "${src}/ufs-diagnose.sh" "${dest}/"

    mkdir -p /usr/local/bin
    ln -sf "${dest}/install-masios-to-internal.sh" /usr/local/bin/masi-install-to-ufs 2>/dev/null || true
    ln -sf "${dest}/ufs-diagnose.sh" /usr/local/bin/masi-ufs-diagnose 2>/dev/null || true

    echo "  Internal UFS: sudo masi-install-to-ufs" >&2
    echo "  Diagnose:     sudo masi-ufs-diagnose" >&2
}
