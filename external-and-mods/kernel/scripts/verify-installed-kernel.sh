#!/usr/bin/env bash
# After update.sh: confirm KERNEL cmdline matches THIS device's root UUID.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${1:-/boot/KERNEL}"

[[ -f "${KERNEL}" ]] || {
    echo "ERROR: missing ${KERNEL}" >&2
    exit 1
}

# shellcheck source=lib/cmdline.sh
source "${ROOT}/lib/cmdline.sh"

local_uuid=""
if resolve_root_uuid >/dev/null 2>&1; then
    local_uuid="${RESOLVED_ROOT_UUID}"
fi

cmdline="$(read_cmdline_from_bootimg "${KERNEL}")" || {
    echo "ERROR: cannot read cmdline from ${KERNEL}" >&2
    exit 1
}

echo "==> Installed KERNEL check"
echo "  cmdline: ${cmdline}"
echo ""

if [[ "${cmdline}" == *"devicetree="* || "${cmdline}" == *"dtb="* ]]; then
    echo "  ERROR: cmdline pins DTB — ABL must pick DTB automatically." >&2
    exit 1
fi

if [[ -z "${local_uuid}" ]]; then
    echo "  WARN: could not read local root UUID (no LinuxLoader.cfg / KERNEL on running system?)" >&2
    if [[ "${cmdline}" == *"root=PARTLABEL=STORAGE"* && "${cmdline}" != *"root=UUID="* ]]; then
        echo "  OK   cmdline uses PARTLABEL-only (UFS-first image)" >&2
        exit 0
    fi
    exit 1
fi

if [[ "${cmdline}" == *"root=UUID=${local_uuid}"* ]]; then
    echo "  OK   root=UUID matches this device (${local_uuid})" >&2
else
    echo "  ERROR: KERNEL root UUID does NOT match this microSD." >&2
    echo "         Local UUID: ${local_uuid}" >&2
    echo "         Run: sudo ./update.sh on THIS device before reboot." >&2
    exit 1
fi

if [[ "${cmdline}" == *"masi.ufsroot=PARTLABEL=STORAGE"* ]]; then
    echo "  OK   dual-root UFS hook present (masi.ufsroot=PARTLABEL=STORAGE)" >&2
else
    echo "  WARN: missing masi.ufsroot — internal UFS boot may fail." >&2
fi
