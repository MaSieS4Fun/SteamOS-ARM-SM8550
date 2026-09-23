#!/usr/bin/env bash
# Install the one-shot Thor touch autoinstaller into a multi-device image.
#
# Run once while preparing the image:
#   sudo ./install-auto.sh
#   sudo ./install-auto.sh --root /mnt/armbi_root
#
# After this you can delete this Thor/ folder from the image sources.
# The system only needs what was copied under /usr and /etc.
#
# On user boot:
#   • AYN Thor  → applies patch with no password, then disables itself
#   • other HW  → ignores forever
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=""
CHECK_ONLY=0

usage() {
	cat <<EOF
Bake AYN Thor touch auto-apply into this system or a rootfs.

  sudo $0
  sudo $0 --root /path/to/armbian/rootfs
  $0 --check-only

Package: ${SCRIPT_DIR}
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--root)
			[[ $# -ge 2 ]] || { echo "ERROR: --root requires a path" >&2; exit 2; }
			ROOT="$2"
			shift 2
			;;
		--root=*)
			ROOT="${1#--root=}"
			shift
			;;
		--check-only)
			CHECK_ONLY=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

need=(
	"${SCRIPT_DIR}/payload/usr/bin/thorch-kwin-touch-map"
	"${SCRIPT_DIR}/payload/usr/bin/thorch-touchscreen-setup"
	"${SCRIPT_DIR}/payload/usr/bin/thorch-display-setup"
	"${SCRIPT_DIR}/payload/usr/lib/systemd/system/thorch-touchscreen-setup.service"
	"${SCRIPT_DIR}/payload/etc/xdg/autostart/thorch-kwin-touch-map.desktop"
	"${SCRIPT_DIR}/payload/etc/xdg/autostart/thorch-display-setup.desktop"
	"${SCRIPT_DIR}/auto/thor-autoinstall.sh"
	"${SCRIPT_DIR}/auto/thor-autoinstall.service"
)

for f in "${need[@]}"; do
	[[ -f "${f}" ]] || {
		echo "ERROR: incomplete Thor package — missing ${f}" >&2
		exit 1
	}
done

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
	echo "OK   Thor package complete"
	exit 0
fi

if [[ -n "${ROOT}" && ! -d "${ROOT}" ]]; then
	echo "ERROR: --root is not a directory: ${ROOT}" >&2
	exit 1
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	if [[ -z "${ROOT}" ]] || ! mkdir -p "${ROOT}/usr/lib/odin3" 2>/dev/null; then
		echo "Root required." >&2
		if [[ -n "${ROOT}" ]]; then
			exec sudo -- "$0" --root "${ROOT}"
		fi
		exec sudo -- "$0"
	fi
fi

prefix() {
	if [[ -n "${ROOT}" ]]; then
		printf '%s%s' "${ROOT}" "$1"
	else
		printf '%s' "$1"
	fi
}

PAYLOAD_DST="$(prefix /usr/share/odin3/fix-thor-screen)"
AUTO_BIN="$(prefix /usr/lib/odin3/thor-autoinstall.sh)"
AUTO_UNIT="$(prefix /usr/lib/systemd/system/odin3-thor-autoinstall.service)"
WANTS_DIR="$(prefix /etc/systemd/system/multi-user.target.wants)"

echo "==> Staging Thor payload → ${PAYLOAD_DST}"
rm -rf "${PAYLOAD_DST}"
install -d -m 0755 "${PAYLOAD_DST}"
cp -a "${SCRIPT_DIR}/payload/usr" "${PAYLOAD_DST}/"
cp -a "${SCRIPT_DIR}/payload/etc" "${PAYLOAD_DST}/"
[[ -f "${SCRIPT_DIR}/README.txt" ]] && cp -a "${SCRIPT_DIR}/README.txt" "${PAYLOAD_DST}/"

echo "==> Installing autoinstall helper → ${AUTO_BIN}"
install -d -m 0755 "$(dirname "${AUTO_BIN}")"
install -m 0755 "${SCRIPT_DIR}/auto/thor-autoinstall.sh" "${AUTO_BIN}"

echo "==> Installing systemd unit → ${AUTO_UNIT}"
install -d -m 0755 "$(dirname "${AUTO_UNIT}")"
install -m 0644 "${SCRIPT_DIR}/auto/thor-autoinstall.service" "${AUTO_UNIT}"

chmod 0755 "${PAYLOAD_DST}/usr/bin"/thorch-* || true
rm -f "$(prefix /var/lib/odin3/thor-autoinstall.done)"

install -d -m 0755 "${WANTS_DIR}"
ln -sfn /usr/lib/systemd/system/odin3-thor-autoinstall.service \
	"${WANTS_DIR}/odin3-thor-autoinstall.service"

if [[ -z "${ROOT}" ]]; then
	systemctl daemon-reload
	systemctl enable odin3-thor-autoinstall.service
fi

echo ""
echo "==> Listo para empaquetar la imagen."
echo "  En el sistema quedan solo rutas de sistema (no hace falta esta carpeta Thor/):"
echo "    /usr/share/odin3/fix-thor-screen/"
echo "    /usr/lib/odin3/thor-autoinstall.sh"
echo "    odin3-thor-autoinstall.service (enabled)"
echo ""
echo "  Usuario en Thor  → patch automático, luego el servicio se retira"
echo "  Otro dispositivo → ignorado para siempre"
