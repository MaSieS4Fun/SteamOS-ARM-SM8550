#!/usr/bin/env bash
# One-shot boot helper: if AYN Thor, apply userspace touch fix; otherwise retire forever.
# Installed as /usr/lib/odin3/thor-autoinstall.sh — runs as root, no password.
set -euo pipefail

MARKER_DIR=/var/lib/odin3
MARKER="${MARKER_DIR}/thor-autoinstall.done"
PAYLOAD="${ODIN3_THOR_PAYLOAD:-/usr/share/odin3/fix-thor-screen}"

log() { printf '%s\n' "$*" | tee -a /var/log/odin3-thor-autoinstall.log >&2; }

is_thor() {
	[[ -f /proc/device-tree/compatible ]] || return 1
	tr -d '\0' < /proc/device-tree/compatible | grep -q 'ayn,thor'
}

retire() {
	mkdir -p "${MARKER_DIR}"
	date -u +'%Y-%m-%dT%H:%M:%SZ' > "${MARKER}"
	systemctl disable odin3-thor-autoinstall.service >/dev/null 2>&1 || true
}

apply_fix() {
	local need=(
		"${PAYLOAD}/usr/bin/thorch-kwin-touch-map"
		"${PAYLOAD}/usr/bin/thorch-touchscreen-setup"
		"${PAYLOAD}/usr/bin/thorch-display-setup"
		"${PAYLOAD}/usr/lib/systemd/system/thorch-touchscreen-setup.service"
		"${PAYLOAD}/etc/xdg/autostart/thorch-kwin-touch-map.desktop"
		"${PAYLOAD}/etc/xdg/autostart/thorch-display-setup.desktop"
	)
	local f
	for f in "${need[@]}"; do
		[[ -f "${f}" ]] || {
			log "ERROR: incomplete payload — missing ${f}"
			return 1
		}
	done

	log "Installing AYN Thor userspace fix from ${PAYLOAD}"
	# SteamOS /usr is often read-only; the image already bakes these files.
	if [[ -w /usr/bin ]]; then
		cp -a "${PAYLOAD}/usr/." /usr/ || log "WARN: /usr not writable, using baked binaries"
	else
		log "/usr is read-only — using baked Thor binaries"
	fi
	cp -a "${PAYLOAD}/etc/." /etc/

	chmod 0755 \
		/usr/bin/thorch-kwin-touch-map \
		/usr/bin/thorch-touchscreen-setup \
		/usr/bin/thorch-display-setup
	chmod 0644 \
		/etc/xdg/autostart/thorch-kwin-touch-map.desktop \
		/etc/xdg/autostart/thorch-display-setup.desktop
	chmod 0644 /usr/lib/systemd/system/thorch-touchscreen-setup.service

	systemctl daemon-reload
	systemctl enable thorch-touchscreen-setup.service
	systemctl start thorch-touchscreen-setup.service || true

	log "Thor touch fix installed and enabled"
}

if [[ -f "${MARKER}" ]]; then
	log "Marker present — retiring"
	retire
	exit 0
fi

if ! is_thor; then
	log "Not AYN Thor (compatible != ayn,thor) — ignoring permanently"
	retire
	exit 0
fi

if [[ -f /var/run/resize2fs-reboot ]]; then
	log "armbian-resize pending reboot — deferring Thor install to next boot"
	exit 0
fi
if systemctl is-enabled armbian-resize-filesystem.service >/dev/null 2>&1; then
	log "armbian-resize-filesystem still enabled — deferring Thor install to next boot"
	exit 0
fi

if apply_fix; then
	retire
	exit 0
fi

log "Install failed — will retry next boot"
exit 1
