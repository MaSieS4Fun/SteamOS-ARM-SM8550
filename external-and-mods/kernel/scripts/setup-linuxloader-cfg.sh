#!/usr/bin/env bash
# Write /boot/LinuxLoader.cfg with DisableDisplayHW + local root UUID.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT

# shellcheck source=config/defaults.conf
source "${ROOT}/config/defaults.conf"
# shellcheck source=lib/cmdline.sh
source "${ROOT}/lib/cmdline.sh"

dest="${1:-${BOOT_LINUXLOADER_CFG_PATH:-/boot/LinuxLoader.cfg}}"

resolve_root_uuid >/dev/null || {
    echo "Could not resolve root UUID for ${dest}" >&2
    exit 1
}
uuid="${RESOLVED_ROOT_UUID}"

mkdir -p "$(dirname "${dest}")"

cat > "${dest}" <<EOF
#
# MaSi-OS — LinuxLoader.cfg (display-safe mainline boot)
# See docs/DISPLAY-BOOT.md
#

[LinuxLoader]
Target = "Linux"
DefaultVolUp = "Linux"
DisableDisplayHW = true
HypUartEnable = false
Debug = false

[Linux]
Image = "Image"
initrd = "initrd.img-${KERNEL_VER:-7.0.14}${KERNEL_LOCALVERSION}"
devicetree = "qcs8550-ayn-odin2.dtb"
cmdline = "clk_ignore_unused pd_ignore_unused quiet rw rootwait root=UUID=${uuid}"
EOF

echo "Wrote ${dest}"
echo "  UUID: ${uuid} (from ${ROOT_UUID_SOURCE})"
echo "  DisableDisplayHW = true"
echo ""
echo "Place Image, initrd, and device DTB on the same FAT partition."
