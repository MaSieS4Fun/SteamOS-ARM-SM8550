#!/usr/bin/env bash
#
# lib/bootimg.sh — pack zImage (ABL+DTBs) + initrd → boot/KERNEL
# No devicetree= in cmdline — ABL picks the embedded DTB.
#
set -euo pipefail

copy_bootimg_hw_template() {
    local template="${1}" dest_cfg="$2"
    local work="${CACHE_DIR}/bootimg-template"

    [[ -f "${template}" ]] || {
        echo "Missing bootimg template: ${template}" >&2
        return 1
    }

    if [[ "${template}" == *.cfg || "${template}" == *.hw.cfg ]]; then
        grep -E '^(bootsize|pagesize|kerneladdr|ramdiskaddr|secondaddr|tagsaddr|name) ' \
            "${template}" > "${dest_cfg}" 2>/dev/null || cp -f "${template}" "${dest_cfg}"
        echo 'cmdline = PLACEHOLDER' >> "${dest_cfg}"
        echo "  bootimg template: $(basename "${template}")" >&2
        return 0
    fi

    command -v abootimg >/dev/null 2>&1 || {
        echo "Install: sudo apt install abootimg" >&2
        return 1
    }

    rm -rf "${work}"
    mkdir -p "${work}"
    ( cd "${work}" && abootimg -x "${template}" >/dev/null 2>&1 )

    [[ -f "${work}/bootimg.cfg" ]] || {
        echo "Could not read bootimg.cfg from ${template}" >&2
        return 1
    }

    grep -E '^(bootsize|pagesize|kerneladdr|ramdiskaddr|secondaddr|tagsaddr|name) ' \
        "${work}/bootimg.cfg" > "${dest_cfg}"
    echo 'cmdline = PLACEHOLDER' >> "${dest_cfg}"
    echo "  bootimg template: $(basename "${template}")" >&2
    rm -rf "${work}"
}

resolve_bootimg_template() {
    local candidate
    if [[ -n "${BOOTIMG_TEMPLATE:-}" && -f "${BOOTIMG_TEMPLATE}" ]]; then
        echo "${BOOTIMG_TEMPLATE}"
        return 0
    fi
    if [[ -f "${ROOT}/config/bootimg.abl.cfg" ]]; then
        echo "${ROOT}/config/bootimg.abl.cfg"
        return 0
    fi
    return 1
}

_write_abl_bootimg_cfg() {
    local hw_cfg="$1" cmdline="$2" out_cfg="$3"
    {
        grep -E '^(bootsize|pagesize|kerneladdr|ramdiskaddr|secondaddr|tagsaddr|name) ' \
            "${hw_cfg}"
        printf 'cmdline = %s\n' "${cmdline}"
    } > "${out_cfg}"
}

_create_abl_bootimg() {
    local zimage="$1" initrd="$2" cfg="$3" kernel_out="$4"
    local kernel_tmp err
    kernel_tmp="$(dirname "${cfg}")/KERNEL.packing"
    err="$(dirname "${cfg}")/KERNEL.packing.err"

    rm -f "${kernel_tmp}" "${kernel_out}" "${err}"
    mkdir -p "$(dirname "${kernel_out}")" "$(dirname "${kernel_tmp}")"

    # Pre-create so abootimg never fails with ENOENT on the output path
    # (some abootimg builds open O_RDWR without O_CREAT).
    : > "${kernel_tmp}" || {
        echo "ERROR: cannot create ${kernel_tmp}" >&2
        return 1
    }

    if ! abootimg --create "${kernel_tmp}" -f "${cfg}" -k "${zimage}" -r "${initrd}" 2>"${err}"; then
        echo "ERROR: abootimg --create failed for ${kernel_out}" >&2
        echo "  zImage: ${zimage}" >&2
        echo "  initrd: ${initrd}" >&2
        echo "  cfg:    ${cfg}" >&2
        [[ -s "${err}" ]] && sed 's/^/  abootimg: /' "${err}" >&2
        rm -f "${kernel_tmp}" "${err}"
        return 1
    fi
    rm -f "${err}"

    mv -f "${kernel_tmp}" "${kernel_out}"

    [[ -s "${kernel_out}" ]] || {
        echo "ERROR: ${kernel_out} empty after abootimg" >&2
        return 1
    }
    return 0
}

pack_bootimg_abl() {
    local out_dir="$1" release="${2:-}"
    local sd_uuid="" cmdline
    local staging boot_dir zimage initrd cfg kernel_out template hw_cfg

    out_dir="$(cd "${out_dir}" && pwd)"
    staging="$(resolve_build_staging_dir "${out_dir}" "${release}")"
    staging="$(cd "${staging}" && pwd)"
    boot_dir="${out_dir}/boot"
    zimage="${staging}/zImage"
    initrd="${staging}/initrd.img-${release}"
    cfg="${staging}/bootimg.cfg"
    kernel_out="${boot_dir}/KERNEL"
    hw_cfg="${staging}/bootimg.hw.cfg"

    [[ -f "${zimage}" ]] || {
        echo "Missing ${zimage} — run dtb-chain first" >&2
        return 1
    }
    [[ -f "${initrd}" ]] || {
        echo "Missing ${initrd} — run initramfs first" >&2
        return 1
    }

    if resolve_root_uuid >/dev/null 2>&1; then
        sd_uuid="${RESOLVED_ROOT_UUID}"
        echo "  masi.ufsroot: PARTLABEL=${INTERNAL_ROOT_PARTLABEL:-STORAGE} (from ${ROOT_UUID_SOURCE})" >&2
    else
        echo "  masi.sdroot: (none — run update.sh on device to embed microSD root UUID)" >&2
    fi

    cmdline="$(build_unified_abl_cmdline "${sd_uuid}")" || return 1

    template="$(resolve_bootimg_template)" || {
        echo "No bootimg template (config/bootimg.abl.cfg)" >&2
        return 1
    }

    mkdir -p "${boot_dir}" "${staging}"
    [[ -d "${boot_dir}" ]] || {
        echo "ERROR: could not create ${boot_dir}" >&2
        return 1
    }

    copy_bootimg_hw_template "${template}" "${hw_cfg}"

    local ksize rsize max_boot need pagesize
    pagesize="$(grep -E '^pagesize ' "${hw_cfg}" | awk '{print $3}')"
    pagesize="${pagesize:-2048}"
    ksize="$(stat -c%s "${zimage}")"
    rsize="$(stat -c%s "${initrd}")"
    max_boot="$(grep -E '^bootsize ' "${hw_cfg}" | awk '{print $3}')"
    max_boot="${max_boot:-${BOOTIMG_MAX_BYTES:-82536448}}"
    need=$(( (ksize + pagesize - 1) / pagesize * pagesize + (rsize + pagesize - 1) / pagesize * pagesize + pagesize * 4 ))
    if [[ "${need}" -gt "${max_boot}" ]]; then
        echo "ERROR: bootimg too large (${need} vs bootsize ${max_boot} bytes)" >&2
        echo "  zImage: ${ksize} bytes | initrd: ${rsize} bytes" >&2
        echo "  initrd too large for bootsize ${max_boot} — shrink initrd or raise bootsize in config/bootimg.abl.cfg" >&2
        return 1
    fi

    echo "==> ABL bootimg: zImage + initrd → boot/KERNEL" >&2
    echo "  cmdline: ${cmdline}" >&2
    _write_abl_bootimg_cfg "${hw_cfg}" "${cmdline}" "${cfg}"
    _create_abl_bootimg "${zimage}" "${initrd}" "${cfg}" "${kernel_out}" || return 1
    abootimg -i "${kernel_out}" 2>&1 | grep -E 'kernel size|ramdisk size|cmdline' >&2 || true
    assert_no_efi_devicetree "${cmdline}" || return 1
    verify_unified_abl_cmdline "${cmdline}" || {
        echo "KERNEL cmdline verify failed" >&2
        return 1
    }

    rm -f "${hw_cfg}"

    write_output_install "${out_dir}" "${release}" "${sd_uuid:-}"

    echo "  → ${kernel_out} ($(du -h "${kernel_out}" | cut -f1))" >&2
    export MASI_BOOT_KERNEL="${kernel_out}"
}

# Repack boot/KERNEL with this device's masi.sdroot UUID (fixes multi-device SD cards).
repack_bootimg_local_uuid() {
    local kernel_in="$1" kernel_out="${2:-$1}" release="${3:-}"
    local work uuid cmdline cfg zimage initrd

    [[ -f "${kernel_in}" ]] || return 1
    command -v abootimg >/dev/null 2>&1 || {
        echo "  repack: abootimg missing — installing KERNEL as-is" >&2
        [[ "${kernel_in}" != "${kernel_out}" ]] && cp -f "${kernel_in}" "${kernel_out}"
        return 0
    }

    resolve_root_uuid || return 1
    uuid="${RESOLVED_ROOT_UUID}"

    cmdline="$(build_unified_abl_cmdline "${uuid}")" || return 1

    work="$(mktemp -d)"
    (
        cd "${work}"
        abootimg -x "${kernel_in}" >/dev/null 2>&1
    ) || {
        rm -rf "${work}"
        echo "  repack: could not unpack ${kernel_in}" >&2
        return 1
    }

    zimage="${work}/zImage"
    initrd="${work}/initrd.img"
    cfg="${work}/bootimg.cfg"
    [[ -f "${zimage}" && -f "${initrd}" && -f "${cfg}" ]] || {
        rm -rf "${work}"
        echo "  repack: missing zImage/initrd in bootimg" >&2
        return 1
    }

    {
        grep -E '^(bootsize|pagesize|kerneladdr|ramdiskaddr|secondaddr|tagsaddr|name) ' "${cfg}"
        printf 'cmdline = %s\n' "${cmdline}"
    } > "${cfg}.new"
    mv -f "${cfg}.new" "${cfg}"

    mkdir -p "$(dirname "${kernel_out}")"
    # Some abootimg builds open the output O_RDWR without O_CREAT.
    : > "${kernel_out}" || {
        rm -rf "${work}"
        echo "  repack: cannot create ${kernel_out}" >&2
        return 1
    }
    abootimg --create "${kernel_out}" -f "${cfg}" -k "${zimage}" -r "${initrd}" || {
        rm -rf "${work}"
        rm -f "${kernel_out}"
        return 1
    }
    rm -rf "${work}"

    echo "  repack KERNEL: masi.sdroot UUID ${uuid} (this device)" >&2
    echo "  cmdline: ${cmdline}" >&2
    export MASI_BOOT_KERNEL="${kernel_out}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export ROOT
    : "${CACHE_DIR:=${ROOT}/.cache}"
    # shellcheck source=config/defaults.conf
    source "${ROOT}/config/defaults.conf"
    # shellcheck source=lib/cmdline.sh
    source "${ROOT}/lib/cmdline.sh"
    # shellcheck source=lib/dtb-chain/verify.sh
    source "${ROOT}/lib/dtb-chain/verify.sh"
    # shellcheck source=lib/output.sh
    source "${ROOT}/lib/output.sh"

    # shellcheck source=lib/output.sh
    source "${ROOT}/lib/output.sh"

    out="$(find "${OUTPUT_DIR:-${ROOT}/output}" -maxdepth 1 -type d -name "*-${OUTPUT_SUFFIX:-kbase}" 2>/dev/null | sort -V | tail -1)"
    [[ -n "${out}" ]] || { echo "No build output found"; exit 1; }
    rel="$(basename "$(find "${out}/modules" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)")"
    pack_bootimg_abl "${out}" "${rel}"
fi
