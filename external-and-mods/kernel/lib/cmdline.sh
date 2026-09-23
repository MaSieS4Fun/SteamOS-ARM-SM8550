#!/usr/bin/env bash
set -euo pipefail

# Root UUID: /boot/LinuxLoader.cfg first, then /boot/KERNEL bootimg cmdline.
BOOT_LINUXLOADER_CFG_PATH="${BOOT_LINUXLOADER_CFG_PATH:-/boot/LinuxLoader.cfg}"
BOOT_KERNEL_PATH="${BOOT_KERNEL_PATH:-/boot/KERNEL}"
# Set by resolve_root_uuid on success (source path or "ROOT_UUID override")
ROOT_UUID_SOURCE="${ROOT_UUID_SOURCE:-}"
RESOLVED_ROOT_UUID="${RESOLVED_ROOT_UUID:-}"

_abootimg_cmdline() {
    local kernel="$1"
    abootimg -i "${kernel}" 2>/dev/null | sed -n 's/^\* cmdline = //p' | head -1
}

_read_bootimg_cmdline_python() {
    local kernel="$1"
    python3 - "${kernel}" <<'PY'
import struct, sys
from pathlib import Path

p = Path(sys.argv[1])
data = p.read_bytes()
if data[:8] != b"ANDROID!":
    sys.exit(1)
cmd = data[0x40 : 0x40 + 512].split(b"\x00")[0].decode("ascii", errors="replace")
print(cmd)
PY
}

read_cmdline_from_bootimg() {
    local kernel="${1:-${BOOT_KERNEL_PATH}}"
    local cmdline=""

    [[ -e "${kernel}" ]] || return 1

    if command -v abootimg >/dev/null 2>&1; then
        if [[ -r "${kernel}" ]]; then
            cmdline="$(_abootimg_cmdline "${kernel}")"
        elif [[ -f "${kernel}" ]] && command -v sudo >/dev/null 2>&1; then
            # /boot is often root-only (umask=0077) — read cmdline without write access.
            cmdline="$(sudo abootimg -i "${kernel}" 2>/dev/null | sed -n 's/^\* cmdline = //p' | head -1)"
        fi
        [[ -n "${cmdline}" ]] && { printf '%s' "${cmdline}"; return 0; }
    fi

    if [[ -r "${kernel}" ]]; then
        _read_bootimg_cmdline_python "${kernel}"
        return 0
    fi

    if [[ -f "${kernel}" ]] && command -v sudo >/dev/null 2>&1; then
        cmdline="$(sudo python3 - "${kernel}" <<'PY'
import struct, sys
from pathlib import Path

p = Path(sys.argv[1])
data = p.read_bytes()
if data[:8] != b"ANDROID!":
    sys.exit(1)
cmd = data[0x40 : 0x40 + 512].split(b"\x00")[0].decode("ascii", errors="replace")
print(cmd)
PY
)"
        [[ -n "${cmdline}" ]] && { printf '%s' "${cmdline}"; return 0; }
    fi

    return 1
}

resolve_root_uuid_from_running_system() {
    local uuid="" dev=""

    if command -v findmnt >/dev/null 2>&1; then
        uuid="$(findmnt -no UUID -r / 2>/dev/null || true)"
        if [[ -n "${uuid}" ]]; then
            ROOT_UUID_SOURCE="running root (findmnt /)"
            RESOLVED_ROOT_UUID="${uuid}"
            echo "${uuid}"
            return 0
        fi
        dev="$(findmnt -no SOURCE -r / 2>/dev/null || true)"
    fi

    if [[ -n "${dev}" ]] && command -v blkid >/dev/null 2>&1; then
        uuid="$(blkid -s UUID -o value "${dev}" 2>/dev/null || true)"
        if [[ -n "${uuid}" ]]; then
            ROOT_UUID_SOURCE="running root (${dev})"
            RESOLVED_ROOT_UUID="${uuid}"
            echo "${uuid}"
            return 0
        fi
    fi

    return 1
}

extract_root_uuid_from_cmdline() {
    local cmdline="$1"
    python3 - "${cmdline}" <<'PY'
import re, sys
m = re.search(r"root=UUID=([0-9a-fA-F-]{36})", sys.argv[1])
if m:
    print(m.group(1))
PY
}

read_cmdline_from_linuxloader_cfg() {
    read_linuxloader_linux_field cmdline "${1:-${BOOT_LINUXLOADER_CFG_PATH}}"
}

# initrd = "initrd.img-6.18.8-edge-sm8550" in [Linux] → absolute path under /boot/
read_initrd_path_from_linuxloader_cfg() {
    local cfg="${1:-${BOOT_LINUXLOADER_CFG_PATH}}" rel boot="/boot"

    rel="$(read_linuxloader_linux_field initrd "${cfg}")" || return 1
    [[ -n "${rel}" ]] || return 1

    rel="${rel#\"}"; rel="${rel%\"}"
    if [[ "${rel}" == /* ]]; then
        echo "${rel}"
    else
        echo "${boot}/${rel}"
    fi
}

read_linuxloader_linux_field() {
    local field="$1" cfg="${2:-${BOOT_LINUXLOADER_CFG_PATH}}"
    [[ -f "${cfg}" ]] || return 1

    python3 - "${field}" "${cfg}" <<'PY'
import re, sys
from pathlib import Path

field, path = sys.argv[1], sys.argv[2]
text = Path(path).read_text(errors="replace")
section = text
m = re.search(r"\[Linux\](.*?)(?=\[|\Z)", text, re.DOTALL | re.IGNORECASE)
if m:
    section = m.group(1)
pat = rf'^\s*{re.escape(field)}\s*=\s*"(.*?)"\s*$|^\s*{re.escape(field)}\s*=\s*(\S.*?)\s*$'
m = re.search(pat, section, re.MULTILINE | re.IGNORECASE)
if m:
    print((m.group(1) or m.group(2) or "").strip())
PY
}

resolve_root_uuid() {
    local cmdline uuid
    local cfg="${BOOT_LINUXLOADER_CFG_PATH}"
    local kernel="${BOOT_KERNEL_PATH}"

    ROOT_UUID_SOURCE=""
    RESOLVED_ROOT_UUID=""

    # Explicit override (debug)
    if [[ -n "${ROOT_UUID:-}" ]]; then
        ROOT_UUID_SOURCE="ROOT_UUID override"
        RESOLVED_ROOT_UUID="${ROOT_UUID}"
        echo "${ROOT_UUID}"
        return 0
    fi

    if [[ -f "${cfg}" ]]; then
        cmdline="$(read_cmdline_from_linuxloader_cfg "${cfg}")" || true
        if [[ -n "${cmdline:-}" ]]; then
            uuid="$(extract_root_uuid_from_cmdline "${cmdline}")"
            if [[ -n "${uuid}" ]]; then
                ROOT_UUID_SOURCE="${cfg}"
                RESOLVED_ROOT_UUID="${uuid}"
                echo "${uuid}"
                return 0
            fi
            echo "Cmdline missing root=UUID= in ${cfg}:" >&2
            echo "  ${cmdline}" >&2
            return 1
        fi
    fi

    if [[ -e "${kernel}" ]]; then
        cmdline="$(read_cmdline_from_bootimg "${kernel}")" || true
        if [[ -n "${cmdline:-}" ]]; then
            uuid="$(extract_root_uuid_from_cmdline "${cmdline}")"
            if [[ -n "${uuid}" ]]; then
                ROOT_UUID_SOURCE="${kernel}"
                RESOLVED_ROOT_UUID="${uuid}"
                echo "${uuid}"
                return 0
            fi
            echo "Cmdline missing root=UUID= in ${kernel}:" >&2
            echo "  ${cmdline}" >&2
            return 1
        fi
        echo "Could not read cmdline from ${kernel} (try: sudo abootimg -i ${kernel})" >&2
    else
        echo "Neither ${cfg} nor ${kernel} found — cannot read root=UUID=" >&2
    fi

    if resolve_root_uuid_from_running_system >/dev/null 2>&1; then
        echo "${RESOLVED_ROOT_UUID}"
        return 0
    fi

    return 1
}

build_abl_cmdline() {
    local uuid="${1:-}"
    build_unified_abl_cmdline "${uuid}"
}

# Unified ABL cmdline for every SM8550 device in the DTB chain.
# ABL selector picks the DTB — never put devicetree=/dtb= here.
# Per-SD root UUID is embedded at image build or vendor/kernel/update.sh only.
build_unified_abl_cmdline() {
    local sd_uuid="${1:-}"
    local partlabel="${INTERNAL_ROOT_PARTLABEL:-STORAGE}"
    local -a parts=(
        "clk_ignore_unused"
        "pd_ignore_unused"
    )
    # Panel stays black until gamescope DRM; no console=tty0 (kernel spam on panel).
    if [[ "${CMDLINE_QUIET:-1}" == "1" ]]; then
        parts+=(
            "quiet"
            "loglevel=0"
            "systemd.show_status=0"
            "systemd.log_level=err"
        )
    else
        parts+=("console=tty0")
    fi
    parts+=(
        "rw"
        "rootwait"
    )

    if [[ -n "${sd_uuid}" ]]; then
        parts+=(
            "root=UUID=${sd_uuid}"
            "masi.ufsroot=PARTLABEL=${partlabel}"
        )
    else
        parts+=("root=PARTLABEL=${partlabel}")
    fi

    parts+=(
        "rootfstype=ext4"
        "errors=remount-ro"
    )

    _append_abl_cmdline_extras parts

    local cmdline="${parts[*]}"
    if [[ "${cmdline}" == *"devicetree="* || "${cmdline}" == *"dtb="* ]]; then
        echo "cmdline must not include devicetree=/dtb= (ABL picks DTB)" >&2
        return 1
    fi
    printf '%s' "${cmdline}"
}

verify_unified_abl_cmdline() {
    local cmdline="$1"
    local partlabel="${INTERNAL_ROOT_PARTLABEL:-STORAGE}"

    [[ -n "${cmdline}" ]] || return 1
    [[ "${cmdline}" != *"devicetree="* && "${cmdline}" != *"dtb="* ]] || return 1

    if [[ "${cmdline}" == *"root=UUID="* ]]; then
        [[ "${cmdline}" == *"masi.ufsroot=PARTLABEL=${partlabel}"* ]] || return 1
        return 0
    fi

    # Legacy UFS-only — avoid matching inside masi.ufsroot=PARTLABEL=
    [[ "${cmdline}" == "root=PARTLABEL=${partlabel}"* \
        || "${cmdline}" == *" root=PARTLABEL=${partlabel}"* ]] || return 1
    return 0
}

# Alias for UFS docs / legacy callers.
build_internal_abl_cmdline() {
    build_unified_abl_cmdline ""
}

verify_internal_abl_cmdline() {
    verify_unified_abl_cmdline "$1"
}

# Shared optional cmdline tokens (debug, suspend, extras) for SD and UFS images.
_append_abl_cmdline_extras() {
    local -n _parts="$1"

    if [[ "${ABL_CMDLINE_EXTRAS:-0}" == "1" ]]; then
        _parts+=("psi=0" "arm64.nopauth" "efi=noruntime" "video=efifb:off")
    fi

    if [[ "${DEBUG_BOOTLOG:-0}" == "1" ]]; then
        _parts+=(
            "masi.bootlog=1"
            "ignore_loglevel"
            "loglevel=8"
            "log_buf_len=2M"
            "drm.debug=0x04"
            "fw_devlink=0"
        )
    fi

    if [[ "${SUSPEND_DEEP:-0}" == "1" ]]; then
        _parts+=(
            "mem_sleep_default=deep"
            "ufshcd_core.uic_cmd_timeout=3000"
        )
    fi

    if [[ -n "${KERNEL_CMDLINE_EXTRA:-}" ]]; then
        local extra
        read -ra extra <<<"${KERNEL_CMDLINE_EXTRA}"
        _parts+=("${extra[@]}")
    fi
}
