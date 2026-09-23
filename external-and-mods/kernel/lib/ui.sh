#!/usr/bin/env bash
# Interactive menus (whiptail → dialog → plain text) — kernel version selector.
set -euo pipefail

SELECTED_KERNEL_VER=""

ui_banner() {
    clear
    echo "============================================================"
    echo "  kernel-new-base — SM8550 gaming + ABL bootimg"
    echo "  golden.config (max performance) | ABL DTBs | initrd efi-clean"
    echo "============================================================"
    echo ""
}

_ui_cmd() {
    [[ "${UI:-}" == "plain" ]] && { echo plain; return; }
    [[ ! -t 0 || ! -t 1 ]] && { echo plain; return; }
    if command -v whiptail >/dev/null 2>&1; then echo whiptail
    elif command -v dialog >/dev/null 2>&1; then echo dialog
    else echo plain
    fi
}

ui_menu() {
    local title="$1" text="$2"
    shift 2
    local -a items=("$@")
    local ui n i choice

    UI_MENU_RESULT=""
    ui="$(_ui_cmd)"

    if [[ "${ui}" != "plain" ]]; then
        local -a args=()
        for i in "${!items[@]}"; do
            args+=("$((i+1))" "${items[$i]}")
        done
        if [[ "${ui}" == "whiptail" ]]; then
            choice="$(whiptail --title "${title}" --menu "${text}" 22 78 14 "${args[@]}" 3>&1 1>&2 2>&3)" || return 1
        else
            choice="$(dialog --stdout --title "${title}" --menu "${text}" 22 78 14 "${args[@]}")" || return 1
        fi
        UI_MENU_RESULT="${items[$((choice-1))]}"
        return 0
    fi

    {
        echo ""
        echo "-- ${title} --"
        echo "${text}"
        echo ""
        for i in "${!items[@]}"; do
            echo "  $((i+1))) ${items[$i]}"
        done
        echo "  0) Cancel"
        echo ""
    } >&2

    if [[ -r /dev/tty ]]; then
        read -r -p "Choice: " n < /dev/tty
    else
        read -r -p "Choice: " n
    fi
    [[ "${n}" == "0" ]] && return 1
    if ! [[ "${n}" =~ ^[0-9]+$ && "${n}" -ge 1 && "${n}" -le ${#items[@]} ]]; then
        echo "Invalid choice: ${n}" >&2
        return 1
    fi
    UI_MENU_RESULT="${items[$((n-1))]}"
    return 0
}

ui_select_kernel() {
    local -a versions=() labels=()
    local ver patch

    SELECTED_KERNEL_VER=""
    local host_ver
    host_ver="$(uname -r 2>/dev/null | cut -d- -f1 || true)"

    refresh_armbian_support
    echo "Armbian SM8550 series: $(armbian_support_summary)" >&2
    echo "Querying kernel.org (releases + CDN; may take a few seconds)..." >&2

    while IFS= read -r ver; do
        [[ -n "${ver}" ]] || continue
        versions+=("${ver}")
        patch="$(patch_set_for_version "${ver}" 2>/dev/null || echo "?")"
        if kernel_source_cached "${ver}"; then
            labels+=("linux-${ver} [${patch}] (local cache)")
        elif [[ -n "${host_ver}" && "${ver}" == "${host_ver}" ]]; then
            labels+=("linux-${ver} [${patch}] (running kernel)")
        else
            labels+=("linux-${ver} [${patch}]")
        fi
    done < <(enumerate_kernel_menu_versions)

    [[ ${#versions[@]} -gt 0 ]] || {
        echo "No compatible versions — only kernels with a published Armbian sm8550-<series> patch set are listed." >&2
        echo "Try: KERNEL_VER=7.0.14 ./make.sh" >&2
        return 1
    }

    ui_menu "Step 1/2 — Kernel version" \
        "Choose version to build (Armbian patch set in brackets):" \
        "${labels[@]}" || return 1

    local i pick="${UI_MENU_RESULT}"
    for i in "${!labels[@]}"; do
        [[ "${labels[$i]}" == "${pick}" ]] && {
            SELECTED_KERNEL_VER="${versions[$i]}"
            break
        }
    done

    [[ -n "${SELECTED_KERNEL_VER}" ]] || {
        echo "Could not resolve selected version." >&2
        return 1
    }

    echo "Selected: linux-${SELECTED_KERNEL_VER}" >&2
    return 0
}

ui_confirm_build() {
    local ver="$1" patch_set="$2"
    local msg
    msg="Kernel: linux-${ver}
Patches: ${patch_set}
Config: golden.config (max performance / CPUFREQ=performance)
Initrd: ${INITRAMFS_PROFILE:-efi-clean}
DTBs: ABL chain, 11 devices
Output: ${OUTPUT_DIR}/${ver}${KERNEL_LOCALVERSION}-${OUTPUT_SUFFIX:-kbase}/
Jobs: ${JOBS}

Generates output/ only — install with sudo ./update.sh or INSTALL.txt."

    local ui="$(_ui_cmd)"
    if [[ "${ui}" == "whiptail" ]]; then
        whiptail --title "Confirm build" --yesno "${msg}" 18 72
        return $?
    elif [[ "${ui}" == "dialog" ]]; then
        dialog --title "Confirm build" --yesno "${msg}" 18 72
        return $?
    fi

    echo "" >&2
    echo "${msg}" >&2
    echo "" >&2
    read -r -p "Build? [y/N] " ans < /dev/tty
    [[ "${ans,,}" == "y" ]]
}

ui_build_complete() {
    local out="$1"
    echo ""
    echo "============================================================"
    echo "  BUILD COMPLETE"
    echo "============================================================"
    echo "  ${out}/"
    echo "  boot/KERNEL"
    echo "  firmware/"
    echo "  modules/"
    echo ""
    echo "  Install: sudo ./update.sh"
    echo ""
}
