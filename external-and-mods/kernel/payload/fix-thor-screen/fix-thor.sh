#!/usr/bin/env bash
# AYN Thor — userspace fix for dual touchscreens (KDE Plasma / Wayland).
#
# Kernel/DTB fixes ship in boot/KERNEL (rebuild). This script installs what
# must live in the running system: udev, systemd, KWin session mapper.
#
# Usage (on AYN Thor, after ./update.sh and reboot):
#   cd output/7.0.14-edge-sm8550-kbase/fix-thor-screen
#   ./fix-thor.sh
#
# Prompts for root password if not already root. Installs only under /usr and /etc.
# Options:
#   --force       skip device-tree check
#   --check-only  verify payload, do not install
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE=0
CHECK_ONLY=0

usage() {
	cat <<EOF
AYN Thor touch + display userspace fix (system-wide install only)

  ./fix-thor.sh                 prompts for root; installs under /usr and /etc
  ./fix-thor.sh --check-only    verify bundle (no root)
  ./fix-thor.sh --force         install even if DT is not ayn,thor

Nothing is written under /home — KDE autostart comes from /etc/xdg/autostart/.

See README.txt in this folder.
EOF
}

for arg; do
	case "${arg}" in
		--force) FORCE=1 ;;
		--check-only) CHECK_ONLY=1 ;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: ${arg}" >&2
			usage >&2
			exit 2
			;;
	esac
done

need=(
	"${SCRIPT_DIR}/usr/bin/thorch-kwin-touch-map"
	"${SCRIPT_DIR}/usr/bin/thorch-touchscreen-setup"
	"${SCRIPT_DIR}/usr/bin/thorch-display-setup"
	"${SCRIPT_DIR}/usr/lib/systemd/system/thorch-touchscreen-setup.service"
	"${SCRIPT_DIR}/etc/xdg/autostart/thorch-kwin-touch-map.desktop"
	"${SCRIPT_DIR}/etc/xdg/autostart/thorch-display-setup.desktop"
)

for f in "${need[@]}"; do
	[[ -f "${f}" ]] || {
		echo "ERROR: incomplete bundle — missing ${f}" >&2
		exit 1
	}
done

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
	echo "OK   fix-thor-screen bundle complete"
	exit 0
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	echo "Root required — installing system-wide under /usr and /etc." >&2
	exec sudo -- "$0" "$@"
fi

_thor_is_thor() {
	[[ -f /proc/device-tree/compatible ]] || return 1
	tr -d '\0' < /proc/device-tree/compatible | grep -q 'ayn,thor'
}

if [[ "${FORCE}" -eq 0 ]] && ! _thor_is_thor; then
	echo "ERROR: this script is for AYN Thor only (compatible=ayn,thor)." >&2
	echo "       Use --force to override." >&2
	exit 1
fi

echo "==> Installing AYN Thor userspace fix (system-wide only)"

cp -a "${SCRIPT_DIR}/usr/." /usr/
cp -a "${SCRIPT_DIR}/etc/." /etc/

chmod 0755 \
	/usr/bin/thorch-kwin-touch-map \
	/usr/bin/thorch-touchscreen-setup \
	/usr/bin/thorch-display-setup

chmod 0644 \
	/etc/xdg/autostart/thorch-kwin-touch-map.desktop \
	/etc/xdg/autostart/thorch-display-setup.desktop

systemctl daemon-reload
systemctl enable thorch-touchscreen-setup.service
systemctl restart thorch-touchscreen-setup.service || systemctl start thorch-touchscreen-setup.service || true

echo ""
echo "==> Done — installed:"
echo "  /etc/udev/rules.d/99-thorch-touchscreen-calibration.rules"
echo "  /usr/lib/systemd/system/thorch-touchscreen-setup.service"
echo "  /etc/xdg/autostart/thorch-{kwin-touch-map,display-setup}.desktop"
echo "  /usr/bin/thorch-{kwin-touch-map,display-setup,touchscreen-setup}"
echo ""
echo "Reboot or log out/in to KDE Plasma (Wayland) so autostart applies."
echo ""
