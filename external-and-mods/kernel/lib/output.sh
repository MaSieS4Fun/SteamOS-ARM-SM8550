#!/usr/bin/env bash
set -euo pipefail

build_artifact_dir() {
    local release="$1"
    echo "${OUTPUT_DIR}/${release}-${OUTPUT_SUFFIX:-kbase}"
}

build_staging_dir() {
    local release="$1"
    echo "${OUTPUT_DIR}/.build/${release}-${OUTPUT_SUFFIX:-kbase}"
}

build_staging_dir_for() {
    local artifact_dir="$1"
    echo "${OUTPUT_DIR}/.build/$(basename "${artifact_dir}")"
}

resolve_build_staging_dir() {
    local artifact_dir="$1" release="${2:-}" staging

    if [[ -n "${release}" ]]; then
        staging="$(build_staging_dir "${release}")"
    else
        staging="$(build_staging_dir_for "${artifact_dir}")"
    fi

    if [[ -f "${staging}/Image" ]]; then
        echo "${staging}"
        return 0
    fi

    if [[ -f "${artifact_dir}/.staging/Image" ]]; then
        echo "${artifact_dir}/.staging"
        return 0
    fi

    echo "${staging}"
}

build_meta_dir() {
    echo "${OUTPUT_DIR}/meta"
}

write_output_install() {
    local out_dir="$1" release="${2:-}" uuid="${3:-}"
    local staging meta_cfg

    staging="$(resolve_build_staging_dir "${out_dir}" "${release}")"
    meta_cfg="$(build_meta_dir)/config-${release}"

    cat > "${out_dir}/INSTALL.txt" <<EOF
MaSi-OS Kernel Updater — install bundle
release: ${release}
root UUID: ${uuid:-unknown}

Install on device:
  sudo ./update.sh

Or manually:
  cp -a boot/KERNEL /boot/
  cp -a firmware/* /usr/lib/firmware/
  cp -a modules/${release} /usr/lib/modules/

AYN Thor (after reboot, KDE Plasma):
  cd fix-thor-screen && ./fix-thor.sh

AYN Thor / Odin 2 gyro userspace (external project; not in this bundle):
  cd ~/Projects/giroscopio && ./install.sh
  (kernel already includes FastRPC/SensorsPD DT + Thor ADSP firmware + CONFIG_UHID)

Internal UFS install: same boot/KERNEL → ROCKNIX partition (no second image; see docs/INTERNAL-UFS-BOOT.md)

Reboot after install.
EOF

    cat > "${out_dir}/MANIFEST.txt" <<EOF
MaSi-OS build manifest
release: ${release}
date: $(date -Iseconds)
root UUID: ${uuid:-unknown}
boot/KERNEL: $(stat -c%s "${out_dir}/boot/KERNEL" 2>/dev/null || echo 0) bytes
EOF

    if [[ -f "${out_dir}/boot/KERNEL" ]]; then
        md5sum "${out_dir}/boot/KERNEL" > "${out_dir}/boot/KERNEL.md5"
        echo "  boot/KERNEL.md5 ($(cut -c1-8 < "${out_dir}/boot/KERNEL.md5"))" >&2
    fi

    if [[ "${DEBUG_BOOTLOG:-0}" == "1" ]]; then
        cat > "${out_dir}/boot/DEBUG-BOOTLOG.txt" <<'EOF'
MaSi DEBUG kernel — boot log capture enabled

On boot (even if the screen stays black), the initramfs writes:
  /boot/masi-boot.log

After a failed boot:
  1. Power off
  2. Boot ROCKNIX or another Linux image (same SD card)
  3. Copy /boot/masi-boot.log and send it for analysis

The file is plain text (dmesg + cmdline + device-tree model).
EOF
        cp -f "${ROOT}/scripts/masi-bootlog-continue.sh" \
            "${out_dir}/boot/masi-bootlog-continue.sh" 2>/dev/null || true
        echo "  boot/DEBUG-BOOTLOG.txt (diagnostic build)" >&2
    fi

    find "${out_dir}/modules" -mindepth 2 -maxdepth 2 \( -name source -o -name build \) -type l -delete 2>/dev/null || true

    if [[ -f "${staging}/config-${release}" ]]; then
        mkdir -p "$(build_meta_dir)"
        cp -f "${staging}/config-${release}" "${meta_cfg}" 2>/dev/null || true
        echo "  meta/config-${release}" >&2
    fi

    rm -rf "${out_dir}/.staging" "${out_dir}/meta" "${out_dir}/.modules-staging" 2>/dev/null || true

    echo "==> Output ready:" >&2
    echo "  ${out_dir}/boot/KERNEL (SD + UFS ROCKNIX)" >&2
    echo "  ${out_dir}/firmware/" >&2
    echo "  ${out_dir}/modules/${release}/" >&2
    echo "  ${out_dir}/fix-thor-screen/  (AYN Thor: ./fix-thor.sh — asks root)" >&2
    echo "  (gyro userspace: ~/Projects/giroscopio — not staged here)" >&2
    echo "  (build tree: ${staging}/)" >&2
}

finalize_output_layout() {
    local out_dir="$1" release="${2:-}"

    mkdir -p "${out_dir}/boot" "${out_dir}/firmware" "${out_dir}/modules"
    [[ -n "${release}" && -d "${out_dir}/modules/${release}" ]] || true
}
