#!/usr/bin/env bash
#
# lib/initramfs.sh — initrd for ABL bootimg (efi-clean or optional gold ref)
#
set -euo pipefail

_has_busybox_for_initramfs() {
    command -v busybox >/dev/null 2>&1 && return 0
    command -v busybox-static >/dev/null 2>&1 && return 0
    dpkg -s busybox-static >/dev/null 2>&1 && return 0
    dpkg -s busybox >/dev/null 2>&1 && return 0
    return 1
}

_initrd_try_ref() {
    local candidate="$1"
    [[ -n "${candidate}" && -f "${candidate}" ]] || return 1
    echo "${candidate}"
    return 0
}

_initrd_cache_reference() {
    local src="$1"
    local dest_dir="${ROOT}/reference"
    local base dest

    [[ -f "${src}" ]] || return 1
    [[ "${src}" == "${ROOT}/reference/"* ]] && {
        echo "${src}"
        return 0
    }

    mkdir -p "${dest_dir}"
    base="$(basename "${src}")"
    dest="${dest_dir}/${base}"
    cp -f "${src}" "${dest}" 2>/dev/null || return 1
    echo "${dest}"
}

_initrd_use_or_cache() {
    local src="$1" cached

    [[ -f "${src}" ]] || return 1
    [[ "${src}" == "${ROOT}/reference/"* ]] && {
        echo "${src}"
        return 0
    }

    if cached="$(_initrd_cache_reference "${src}")"; then
        echo "  gold: cached $(basename "${src}") → reference/" >&2
        echo "${cached}"
        return 0
    fi

    echo "  gold: using ${src} (reference/ cache unavailable)" >&2
    echo "${src}"
}

_extract_initrd_from_bootimg() {
    local kernel="$1" work="${CACHE_DIR:-/tmp}/initrd-from-bootimg-$$"

    [[ -f "${kernel}" ]] || return 1
    command -v abootimg >/dev/null 2>&1 || return 1

    rm -rf "${work}"
    mkdir -p "${work}"
    if ! ( cd "${work}" && abootimg -x "${kernel}" >/dev/null 2>&1 ); then
        rm -rf "${work}"
        return 1
    fi
    [[ -f "${work}/initrd.img" ]] || {
        rm -rf "${work}"
        return 1
    }

    local extracted="${CACHE_DIR:-/tmp}/initrd-from-bootimg-$$.img"
    cp -f "${work}/initrd.img" "${extracted}"
    rm -rf "${work}"
    _initrd_use_or_cache "${extracted}"
}

resolve_gold_initrd_ref() {
    local ver="${1:-}" candidate cfg_initrd bootimg

    for candidate in \
        "${GOLD_INITRD_REF:-}" \
        "${ROOT}/reference/initrd.img-${ver}" \
        "/boot/initrd.img-${ver}"; do
        _initrd_try_ref "${candidate}" && return 0
    done

    if cfg_initrd="$(read_initrd_path_from_linuxloader_cfg 2>/dev/null || true)"; then
        if [[ -n "${cfg_initrd}" && -f "${cfg_initrd}" ]]; then
            echo "  gold: initrd from ${BOOT_LINUXLOADER_CFG_PATH:-/boot/LinuxLoader.cfg}" >&2
            _initrd_use_or_cache "${cfg_initrd}"
            return 0
        fi
    fi

    shopt -s nullglob
    for candidate in \
        "${ROOT}/reference"/initrd.img-* \
        /boot/initrd.img-*edge-sm8550* \
        /boot/initrd.img-*; do
        _initrd_try_ref "${candidate}" && {
            echo "  gold: using ${candidate}" >&2
            shopt -u nullglob
            return 0
        }
    done
    shopt -u nullglob

    for bootimg in "${BOOT_KERNEL_PATH:-/boot/KERNEL}" /boot/KERNEL; do
        [[ -f "${bootimg}" ]] || continue
        if candidate="$(_extract_initrd_from_bootimg "${bootimg}")"; then
            echo "  gold: initrd extracted from ${bootimg}" >&2
            echo "${candidate}"
            return 0
        fi
    done

    return 1
}

build_initramfs_gold() {
    local out_dir="$1" release="$2"
    local staging ref size

    staging="$(resolve_build_staging_dir "${out_dir}" "${release}")"
    local initrd="${staging}/initrd.img-${release}"

    ref="$(resolve_gold_initrd_ref "${release}")" || {
        echo "initramfs gold: no reference initrd found." >&2
        echo "  Or: GOLD_INITRD_REF=/path/to/initrd.img ./make.sh" >&2
        return 1
    }

    mkdir -p "${staging}"
    cp -f "${ref}" "${initrd}"
    _initrd_scrub_host_paths "${initrd}" || {
        echo "initramfs gold: could not scrub host ROOT= from ${ref}" >&2
        rm -f "${initrd}"
        return 1
    }
    size="$(du -h "${initrd}" | cut -f1)"
    echo "  initrd gold: $(basename "${ref}") → initrd.img-${release} (${size})" >&2
    export MASI_INITRD="${initrd}"
}

_initrd_max_bytes() {
    local max_mb="${INITRD_MAX_MB:-150}"
    echo $((max_mb * 1024 * 1024))
}

_initrd_scrub_host_paths() {
    local initrd="$1"
    local work="${CACHE_DIR:-/tmp}/initrd-scrub-$$"
    local cleaned="${initrd}.scrubbed"

    command -v cpio >/dev/null 2>&1 || return 1
    [[ -f "${initrd}" ]] || return 1

    rm -rf "${work}"
    mkdir -p "${work}/root"
    (
        cd "${work}/root"
        if gzip -t "${initrd}" 2>/dev/null; then
            gzip -dc "${initrd}"
        else
            cat "${initrd}"
        fi | cpio -idm 2>/dev/null
    ) || {
        rm -rf "${work}"
        return 1
    }

    # mkinitramfs -r <fake-root> and gold copies bake the build host path here.
    # That breaks root=UUID= on every other device (Portal: "cannot find UUID").
    rm -f "${work}/root/conf/conf.d/root"

    (
        cd "${work}/root"
        find . -print0 | sort -z | cpio --null -o -H newc --owner 0:0 2>/dev/null
    ) | gzip -9 > "${cleaned}" || {
        rm -rf "${work}" "${cleaned}"
        return 1
    }

    mv -f "${cleaned}" "${initrd}"
    rm -rf "${work}"
    echo "  initrd: removed conf/conf.d/root (use kernel cmdline root=UUID= only)" >&2
}

_initrd_repack_strip_bloat() {
    local initrd="$1"
    local work="${CACHE_DIR:-/tmp}/initrd-strip-$$"
    local stripped="${initrd}.stripped"

    command -v cpio >/dev/null 2>&1 || return 1

    rm -rf "${work}"
    mkdir -p "${work}/root"
    (
        cd "${work}/root"
        if gzip -t "${initrd}" 2>/dev/null; then
            gzip -dc "${initrd}"
        else
            cat "${initrd}"
        fi | cpio -idm 2>/dev/null
    ) || {
        rm -rf "${work}"
        return 1
    }

    rm -rf \
        "${work}/root/lib/firmware" \
        "${work}/root/usr/lib/firmware" \
        "${work}/root/lib/modules"
    find "${work}/root" -type f -name '*.ko*' -delete 2>/dev/null || true

    (
        cd "${work}/root"
        find . -print0 | sort -z | cpio --null -o -H newc --owner 0:0 2>/dev/null
    ) | gzip -9 > "${stripped}" || {
        rm -rf "${work}" "${stripped}"
        return 1
    }

    mv -f "${stripped}" "${initrd}"
    rm -rf "${work}"
}

_try_initrd_gold() {
    local out_dir="$1" release="$2"
    local staging initrd max_bytes

    staging="$(resolve_build_staging_dir "${out_dir}" "${release}")"
    initrd="${staging}/initrd.img-${release}"
    max_bytes="$(_initrd_max_bytes)"

    build_initramfs_gold "${out_dir}" "${release}" 2>/dev/null || return 1
    [[ -f "${initrd}" ]] || return 1
    [[ "$(stat -c%s "${initrd}")" -le "${max_bytes}" ]] || {
        echo "  gold initrd too large for ABL limit" >&2
        rm -f "${initrd}"
        return 1
    }
    return 0
}

_install_initramfs_hooks() {
    local mod_root="$1" profile="$2" fw_mode="$3" out_dir="$4"

    mkdir -p "${mod_root}/etc/initramfs-tools/hooks" \
        "${mod_root}/etc/initramfs-tools/conf.d"

    install -m755 "${ROOT}/hooks/masi-no-early-drm" \
        "${mod_root}/etc/initramfs-tools/hooks/masi-no-early-drm"
    mkdir -p "${mod_root}/etc/initramfs-tools/scripts/init-premount"
    install -m755 "${ROOT}/hooks/masi-dual-root-premount" \
        "${mod_root}/etc/initramfs-tools/scripts/init-premount/masi-dual-root"
    install -m755 "${ROOT}/hooks/masi-dual-root" \
        "${mod_root}/etc/initramfs-tools/hooks/masi-dual-root"

    if [[ "${DEBUG_BOOTLOG:-0}" == "1" ]]; then
        install -m755 "${ROOT}/hooks/masi-bootlog" \
            "${mod_root}/etc/initramfs-tools/hooks/masi-bootlog"
        echo "  initramfs: DEBUG_BOOTLOG=1 → /boot/masi-boot.log capture enabled" >&2
    fi

    case "${profile}" in
        efi-clean|minimal)
            cat > "${mod_root}/etc/initramfs-tools/initramfs.conf" <<'EOF'
MODULES=list
BUSYBOX=y
KEYFILE=n
COMPRESS=gzip
UMASK=0077
EOF
            : > "${mod_root}/etc/initramfs-tools/modules"
            install -m644 "${ROOT}/hooks/masi-efi-clean.conf" \
                "${mod_root}/etc/initramfs-tools/conf.d/masi-efi-clean.conf"
            install -m755 "${ROOT}/hooks/zz-masi-strip-initrd-bloat" \
                "${mod_root}/etc/initramfs-tools/hooks/zz-masi-strip-initrd-bloat"
            echo "  initramfs: ${profile} (MODULES=list, no firmware/modules in cpio)" >&2
            ;;
        full)
            echo 'MODULES=most' > "${mod_root}/etc/initramfs-tools/conf.d/masi-full.conf"
            echo "  initramfs: full (MODULES=most)" >&2
            ;;
        *)
            echo "Unknown initramfs profile: ${profile}" >&2
            return 1
            ;;
    esac

    if [[ "${fw_mode}" != "none" ]]; then
        install -m755 "${ROOT}/hooks/masi-firmware" \
            "${mod_root}/etc/initramfs-tools/hooks/masi-firmware"
        case "${fw_mode}" in
            staging)
                if [[ -d "${out_dir}/firmware" ]]; then
                    echo "${out_dir}/firmware" > "${mod_root}/etc/masi-firmware-staging"
                    echo "  firmware initrd: staging" >&2
                fi
                ;;
            host|minimal)
                echo "  firmware initrd: minimal paths from host /lib/firmware" >&2
                ;;
        esac
    else
        echo "  firmware initrd: none (use rootfs /usr/lib/firmware)" >&2
    fi
}

_seed_modules_for_mkinitramfs() {
    local mod_root="$1" modules_src="$2" release="$3"

    [[ -d "${modules_src}" ]] || return 0

    mkdir -p "${mod_root}/lib/modules"
    rm -rf "${mod_root}/lib/modules/${release}"
    cp -a "${modules_src}" "${mod_root}/lib/modules/${release}"
    depmod -b "${mod_root}" "${release}" 2>/dev/null || true
}

build_initramfs_masi() {
    local out_dir="$1" release="${2:-}"
    local staging mod_root initrd profile fw_mode
    local mkinitramfs_cmd="/usr/sbin/mkinitramfs"
    local modules_src="${out_dir}/modules/${release}"
    local gold_fallback=0 max_bytes

    staging="$(resolve_build_staging_dir "${out_dir}" "${release}")"
    mod_root="${staging}/.initramfs-root"
    profile="${INITRAMFS_PROFILE:-efi-clean}"
    fw_mode="${FIRMWARE_IN_INITRD:-none}"
    max_bytes="$(_initrd_max_bytes)"

    [[ -n "${release}" ]] || {
        echo "initramfs: missing release" >&2
        return 1
    }

    case "${profile}" in
        gold|gold-ref)
            _try_initrd_gold "${out_dir}" "${release}" && return 0
            echo "  gold unavailable — falling back to efi-clean" >&2
            profile="efi-clean"
            fw_mode="none"
            gold_fallback=1
            ;;
        efi-clean|minimal)
            if [[ "${INITRAMFS_USE_GOLD:-0}" == "1" ]] && _try_initrd_gold "${out_dir}" "${release}"; then
                return 0
            fi
            echo "  building minimal efi-clean initrd (INITRAMFS_USE_GOLD=0)" >&2
            ;;
    esac

    command -v mkinitramfs >/dev/null 2>&1 || [[ -x "${mkinitramfs_cmd}" ]] || {
        echo "Install: sudo apt install initramfs-tools" >&2
        return 1
    }
    _has_busybox_for_initramfs || {
        echo "E: busybox or busybox-static is required for mkinitramfs" >&2
        echo "Install: sudo apt install busybox-static" >&2
        return 1
    }

    initrd="${staging}/initrd.img-${release}"
    mkdir -p "${staging}"
    rm -rf "${mod_root}"
    mkdir -p "${mod_root}"

    _install_initramfs_hooks "${mod_root}" "${profile}" "${fw_mode}" "${out_dir}" || return 1

    if [[ "${profile}" == "full" ]]; then
        [[ -d "${modules_src}" ]] || {
            echo "initramfs full: missing ${modules_src}" >&2
            return 1
        }
        _seed_modules_for_mkinitramfs "${mod_root}" "${modules_src}" "${release}"
    else
        mkdir -p "${mod_root}/lib/modules/${release}"
    fi

    local mk_d="${mod_root}/etc/initramfs-tools"

    echo "==> mkinitramfs ${release}..." >&2
    [[ "${gold_fallback}" -eq 1 ]] && \
        echo "  (warnings about UUID fsck or /etc/shadow are usually harmless)" >&2

    if command -v mkinitramfs >/dev/null 2>&1; then
        mkinitramfs -k "${release}" -r "${mod_root}" -d "${mk_d}" -o "${initrd}" 2>&1 | tail -12 >&2
    else
        "${mkinitramfs_cmd}" -k "${release}" -r "${mod_root}" -d "${mk_d}" -o "${initrd}" 2>&1 | tail -12 >&2
    fi

    [[ -f "${initrd}" ]] || {
        echo "initramfs failed: ${initrd} was not created" >&2
        if ! _has_busybox_for_initramfs; then
            echo "  missing busybox-static — sudo apt install busybox-static" >&2
        fi
        return 1
    }

    rm -rf "${mod_root}"

    _initrd_scrub_host_paths "${initrd}" || {
        echo "initramfs: scrub failed — refusing poisoned initrd" >&2
        rm -f "${initrd}"
        return 1
    }

    if [[ "${profile}" == "efi-clean" || "${profile}" == "minimal" ]]; then
        _initrd_repack_strip_bloat "${initrd}" || true
    fi

    local size ko
    size="$(du -h "${initrd}" | cut -f1)"
    ko="$(grep -c '\.ko$' < <(lsinitramfs "${initrd}" 2>/dev/null) || true)"
    echo "  initrd.img-${release} (${size}, ${ko} .ko in cpio)" >&2

    if ! grep -Fq 'scripts/init-premount/masi-dual-root' < <(lsinitramfs "${initrd}" 2>/dev/null); then
        echo "ERROR: initrd missing scripts/init-premount/masi-dual-root (hook failed)" >&2
        rm -f "${initrd}"
        return 1
    fi
    echo "  initrd: masi-dual-root init-premount OK" >&2

    if [[ "$(stat -c%s "${initrd}")" -gt "${max_bytes}" ]]; then
        echo "ERROR: initrd > $((max_bytes / 1024 / 1024)) MB — does not fit ABL bootimg." >&2
        echo "  Raise INITRD_MAX_MB or use INITRAMFS_PROFILE=efi-clean" >&2
        rm -f "${initrd}"
        return 1
    fi

    export MASI_INITRD="${initrd}"
}
