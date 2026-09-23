#!/usr/bin/env bash
# Backup running kernel and clean install from output/.
set -euo pipefail

INSTALL_BOOT_DST="${INSTALL_BOOT_DST:-/boot}"
INSTALL_FIRMWARE_DST="${INSTALL_FIRMWARE_DST:-/usr/lib/firmware}"
INSTALL_MODULES_DST="${INSTALL_MODULES_DST:-/usr/lib/modules}"

SELECTED_INSTALL_BUILD=""

_resolve_path() {
    readlink -f "$1" 2>/dev/null || echo "$1"
}

_install_fstype() {
    findmnt -no FSTYPE "$1" 2>/dev/null || true
}

_install_wipe_dir() {
    local dir="$1"
    shopt -s dotglob nullglob
    rm -rf "${dir:?}"/*
    shopt -u dotglob nullglob
}

_install_cp_tree() {
    local src="$1" dest="$2"
    local fstype
    fstype="$(_install_fstype "${dest}")"

    case "${fstype,,}" in
        vfat|fat|msdos|exfat)
            cp -rf --no-preserve=ownership,mode "${src}/." "${dest}/"
            ;;
        *)
            cp -a "${src}/." "${dest}/"
            ;;
    esac
}

install_boot_is_vfat() {
    local fstype
    fstype="$(_install_fstype "${INSTALL_BOOT_DST}")"
    case "${fstype,,}" in
        vfat|fat|msdos|exfat) return 0 ;;
        *) return 1 ;;
    esac
}

install_system_paths() {
    INSTALL_BOOT_DST="$(_resolve_path "${INSTALL_BOOT_DST}")"
    INSTALL_FIRMWARE_DST="$(_resolve_path "${INSTALL_FIRMWARE_DST}")"
    INSTALL_MODULES_DST="$(_resolve_path "${INSTALL_MODULES_DST}")"
}

install_list_builds() {
    local d base rel
    install_list_builds_result=()
    shopt -s nullglob
    for d in "${OUTPUT_DIR}"/*-"${OUTPUT_SUFFIX:-kbase}"/; do
        base="$(basename "${d}")"
        [[ "${base}" == "old_kernel" || "${base}" == "meta" || "${base}" == ".build" ]] && continue
        [[ -f "${d}/boot/KERNEL" ]] || continue
        install_list_builds_result+=("${d%/}")
    done
    shopt -u nullglob
}

install_backup_owner_ids() {
    if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
        echo "${SUDO_UID}:${SUDO_GID}"
        return 0
    fi
    return 1
}

install_fixup_backup_ownership() {
    local backup_root="$1" own

    own="$(install_backup_owner_ids)" || return 0
    chown -R "${own}" "${backup_root}" 2>/dev/null || return 0
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "  backup owned by ${SUDO_USER} — rm -rf output/old_kernel/ without sudo" >&2
    else
        echo "  backup ownership fixed for invoking user" >&2
    fi
}

# Temporary UUID-repack tree under output/. Always remove after install (success or fail)
# so a normal user is not left with a root-owned leftover.
install_cleanup_staging() {
    local staging="${OUTPUT_DIR}/.install-staging"
    [[ -e "${staging}" ]] || return 0
    rm -rf "${staging}"
    echo "  cleaned output/.install-staging" >&2
}

install_pick_build() {
    local build="${UPDATE_BUILD:-}" builds=() i newest=0 pick_ts=0 ts

    # Explicit build (apt bundle, UPDATE_BUILD=…) wins over scanning OUTPUT_DIR.
    if [[ -n "${build}" ]]; then
        [[ -d "${build}" ]] || build="${OUTPUT_DIR}/${build}"
        [[ -f "${build}/boot/KERNEL" ]] || {
            echo "Incomplete or missing build: ${build}" >&2
            return 1
        }
        SELECTED_INSTALL_BUILD="${build}"
        return 0
    fi

    install_list_builds
    builds=("${install_list_builds_result[@]}")

    if [[ ${#builds[@]} -eq 0 ]]; then
        echo "No builds in ${OUTPUT_DIR}/ (missing boot/KERNEL). Run ./make.sh first." >&2
        return 1
    fi

    if [[ ${#builds[@]} -eq 1 ]]; then
        SELECTED_INSTALL_BUILD="${builds[0]}"
        return 0
    fi

    for i in "${!builds[@]}"; do
        ts="$(stat -c %Y "${builds[$i]}" 2>/dev/null || echo 0)"
        if [[ "${ts}" -ge "${pick_ts}" ]]; then
            pick_ts="${ts}"
            newest="${i}"
        fi
    done

    if [[ -t 0 ]]; then
        echo "Available builds:"
        PS3="Choose build to install: "
        select choice in "${builds[@]}"; do
            [[ -n "${choice}" ]] || { echo "Invalid selection." >&2; return 1; }
            SELECTED_INSTALL_BUILD="${choice}"
            break
        done
    else
        SELECTED_INSTALL_BUILD="${builds[$newest]}"
        echo "Using newest build: ${SELECTED_INSTALL_BUILD}" >&2
    fi
}

install_resolve_release() {
    local build="$1"
    local rel dir
    shopt -s nullglob
    for dir in "${build}/modules"/*; do
        [[ -d "${dir}" ]] || continue
        rel="$(basename "${dir}")"
        shopt -u nullglob
        echo "${rel}"
        return 0
    done
    shopt -u nullglob
    return 1
}

install_backup_running() {
    local backup_root="${OUTPUT_DIR}/old_kernel"

    echo "==> Backing up current system → ${backup_root}/" >&2

    rm -rf "${backup_root}"
    mkdir -p "${backup_root}/boot" "${backup_root}/firmware" "${backup_root}/modules"

    for dir in "${INSTALL_BOOT_DST}" "${INSTALL_FIRMWARE_DST}" "${INSTALL_MODULES_DST}"; do
        [[ -d "${dir}" ]] || {
            echo "Missing ${dir}" >&2
            return 1
        }
    done

    echo "  boot/     ← ${INSTALL_BOOT_DST}/" >&2
    cp -a "${INSTALL_BOOT_DST}/." "${backup_root}/boot/"

    echo "  firmware/ ← ${INSTALL_FIRMWARE_DST}/" >&2
    cp -a "${INSTALL_FIRMWARE_DST}/." "${backup_root}/firmware/"

    echo "  modules/  ← ${INSTALL_MODULES_DST}/" >&2
    cp -a "${INSTALL_MODULES_DST}/." "${backup_root}/modules/"

    cat > "${backup_root}/BACKUP.txt" <<EOF
date=$(date -Iseconds)
running_kernel=$(uname -r)
boot=${INSTALL_BOOT_DST}
firmware=${INSTALL_FIRMWARE_DST}
modules=${INSTALL_MODULES_DST}
EOF

    echo "  backup size: $(du -sh "${backup_root}" | cut -f1)" >&2
    install_fixup_backup_ownership "${backup_root}"
}

install_bootlog_service() {
    local build="$1"

    [[ -f "${build}/boot/DEBUG-BOOTLOG.txt" ]] || return 0
    [[ -d /etc/systemd/system ]] || {
        echo "  bootlog: no systemd — skip userspace capture service" >&2
        return 0
    }

    mkdir -p /usr/lib/masi
    install -m755 "${ROOT}/scripts/masi-bootlog-continue.sh" \
        /usr/lib/masi/masi-bootlog-continue.sh
    install -m644 "${ROOT}/config/masi-bootlog.service" \
        /etc/systemd/system/masi-bootlog.service
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable masi-bootlog.service 2>/dev/null || true
    echo "  bootlog: enabled masi-bootlog.service (appends to /boot/masi-boot.log)" >&2
}

install_from_build() {
    local build="$1" release modules_src firmware_src
    local kernel_src kernel_stage boot_stage

    release="$(install_resolve_release "${build}")" || {
        echo "No modules/* found in ${build}" >&2
        return 1
    }
    modules_src="${build}/modules/${release}"
    firmware_src="${build}/firmware"

    [[ -f "${build}/boot/KERNEL" ]] || {
        echo "Missing ${build}/boot/KERNEL" >&2
        return 1
    }

    kernel_src="${build}/boot/KERNEL"
    boot_stage="${OUTPUT_DIR}/.install-staging/boot"
    kernel_stage="${boot_stage}/KERNEL"
    # Clean on function return (success, failure, or early exit) so root leftovers
    # never stick around for the invoking user. Clear the RETURN trap afterwards.
    trap 'install_cleanup_staging; trap - RETURN' RETURN
    rm -rf "${OUTPUT_DIR}/.install-staging"
    mkdir -p "${boot_stage}"

    # SD boot partition holds one KERNEL (~37 MiB). Same file is copied to UFS ROCKNIX on install/update.
    local boot_extra f
    for boot_extra in KERNEL KERNEL.md5 LinuxLoader.cfg DEBUG-BOOTLOG.txt masi-bootlog-continue.sh; do
        [[ -f "${build}/boot/${boot_extra}" ]] && cp -a "${build}/boot/${boot_extra}" "${boot_stage}/"
    done

    if [[ "${INSTALL_REPACK_KERNEL:-1}" == "1" ]]; then
        export CMDLINE_QUIET="${CMDLINE_QUIET:-1}"
        # shellcheck source=lib/cmdline.sh
        source "${ROOT}/lib/cmdline.sh"
        # shellcheck source=lib/bootimg.sh
        source "${ROOT}/lib/bootimg.sh"
        if ! repack_bootimg_local_uuid "${kernel_src}" "${kernel_stage}" "${release}"; then
            if [[ "${INSTALL_STRICT:-0}" == "1" ]]; then
                echo "ERROR: UUID repack failed — refusing to install builder KERNEL." >&2
                echo "  Run on THIS device with valid root=UUID= in /boot/LinuxLoader.cfg or /boot/KERNEL." >&2
                return 1
            fi
            echo "  WARNING: repack failed — installing template KERNEL (may black-screen on this SD)" >&2
            cp -f "${kernel_src}" "${kernel_stage}"
        fi
    else
        # Still stage KERNEL when skipping UUID rewrite (cmdline already matches).
        cp -f "${kernel_src}" "${kernel_stage}"
    fi

    if install_boot_is_vfat \
        && [[ "${INSTALL_WRITE_LINUXLOADER_CFG:-1}" == "1" ]] \
        && [[ ! -f "${INSTALL_BOOT_DST}/LinuxLoader.cfg" ]]; then
        # shellcheck source=lib/cmdline.sh
        source "${ROOT}/lib/cmdline.sh" 2>/dev/null || true
        "${ROOT}/scripts/setup-linuxloader-cfg.sh" "${boot_stage}/LinuxLoader.cfg" 2>/dev/null || true
    fi

    echo "==> Clean install from ${build}/ (release ${release})" >&2

    echo "  wiping ${INSTALL_BOOT_DST}/" >&2
    install_boot_is_vfat && echo "  (boot on FAT)" >&2
    _install_wipe_dir "${INSTALL_BOOT_DST}"
    echo "  ${INSTALL_BOOT_DST}/ ← boot/KERNEL (SD + UFS ROCKNIX)" >&2
    _install_cp_tree "${boot_stage}" "${INSTALL_BOOT_DST}"
    sync "${INSTALL_BOOT_DST}" 2>/dev/null || sync

    if [[ -d "${firmware_src}" ]]; then
        echo "  wiping ${INSTALL_FIRMWARE_DST}/" >&2
        _install_wipe_dir "${INSTALL_FIRMWARE_DST}"
        echo "  ${INSTALL_FIRMWARE_DST}/ ← firmware/" >&2
        _install_cp_tree "${firmware_src}" "${INSTALL_FIRMWARE_DST}"
    else
        echo "  WARNING: no firmware/ in build — skipping firmware" >&2
    fi

    if [[ -d "${modules_src}" ]]; then
        echo "  wiping ${INSTALL_MODULES_DST}/" >&2
        _install_wipe_dir "${INSTALL_MODULES_DST}"
        mkdir -p "${INSTALL_MODULES_DST}"
        echo "  ${INSTALL_MODULES_DST}/${release}/ ← modules/${release}/" >&2
        cp -a "${modules_src}" "${INSTALL_MODULES_DST}/"
    else
        echo "  WARNING: no modules/${release}/ — skipping modules" >&2
    fi

    if [[ "${INSTALL_MINIMAL:-0}" == "1" ]]; then
        echo "==> Install complete (${release})" >&2
        return 0
    fi

    {
        echo "installed_build=${build}"
        echo "installed_release=${release}"
        echo "installed_date=$(date -Iseconds)"
    } >> "${OUTPUT_DIR}/old_kernel/BACKUP.txt"

    install_fixup_backup_ownership "${OUTPUT_DIR}/old_kernel"

    install_bootlog_service "${build}"

    # shellcheck source=lib/audio-stack.sh
    source "${ROOT}/lib/audio-stack.sh"
    install_audio_stack "${release}"

    # shellcheck source=lib/suspend.sh
    source "${ROOT}/lib/suspend.sh"
    install_deep_suspend_config

    # shellcheck source=lib/ufs-install.sh
    source "${ROOT}/lib/ufs-install.sh"
    install_ufs_linux_scripts
    update_internal_ufs_kernel "${kernel_stage}"

    # Explicitly purge any leftover fake-suspend / gaming keepalive
    disable_fake_suspend_and_keepalive

    # shellcheck source=lib/fix-thor-screen.sh
    source "${ROOT}/lib/fix-thor-screen.sh"
    print_fix_thor_hint "${build}"

    echo ""
    echo "Deep suspend: power button → S2RAM (mem). No fake-suspend / keepalive."
    echo "AYN Thor / Odin 2 — gyro userspace (external):"
    echo "  cd ~/Projects/giroscopio && ./install.sh"
    echo "  (kernel already ships FastRPC/SensorsPD + Thor ADSP firmware + CONFIG_UHID)"
    echo ""

    echo "==> Install complete (${release})" >&2
}

install_prompt_reboot() {
    echo ""
    echo "============================================================"
    echo "  IMPORTANT: reboot to use the new kernel."
    echo "  Changes take effect only after reboot."
    echo "============================================================"
    echo ""

    if [[ "${SKIP_REBOOT:-0}" == "1" ]]; then
        echo "SKIP_REBOOT=1 — reboot skipped."
        echo "Reboot manually when ready: sudo reboot"
        return 0
    fi

    if [[ ! -t 0 ]]; then
        echo "Reboot manually: sudo reboot"
        return 0
    fi

    read -r -p "Reboot now? [y/N] " ans
    if [[ "${ans,,}" == "y" ]]; then
        echo "Rebooting..."
        systemctl reboot
    else
        echo ""
        echo "Reboot postponed."
        echo "The new kernel is installed but not yet active."
        echo "When ready: sudo reboot"
    fi
}
