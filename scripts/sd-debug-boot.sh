#!/usr/bin/env bash
# Enable verbose boot + persistent logs on a mounted SteamOS SM8550 card.
# Default mounts (udisks):
#   BOOT=/run/media/steam/BOOT
#   ROOT=/run/media/steam/root
#   HOME=/run/media/steam/home
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
OVL="${PROJ}/odin-overlay"
BOOT="${BOOT:-/run/media/steam/BOOT}"
R="${ROOTFS_MNT:-/run/media/steam/root}"
H="${HOME_MNT:-/run/media/steam/home}"
MOD="${PROJ}/external-and-mods"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "${BOOT}/KERNEL" ]] || die "KERNEL not found at ${BOOT}/KERNEL"
[[ -d "${R}/usr" ]] || die "root mount not found at ${R}"

install_file() {
  local src="$1" dest="$2" mode="${3:-0644}"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  chmod "$mode" "$dest"
}

log "Installing debug units into ${R}"
install_file "${OVL}/usr/lib/steamos/sm8550-boot-debug" \
  "${R}/usr/lib/steamos/sm8550-boot-debug" 0755
install_file "${OVL}/usr/lib/systemd/system/sm8550-boot-debug.service" \
  "${R}/usr/lib/systemd/system/sm8550-boot-debug.service" 0644
install_file "${OVL}/usr/lib/systemd/system/sm8550-boot-debug-late.service" \
  "${R}/usr/lib/systemd/system/sm8550-boot-debug-late.service" 0644
install_file "${OVL}/etc/systemd/journald.conf.d/99-sm8550-persist.conf" \
  "${R}/etc/systemd/journald.conf.d/99-sm8550-persist.conf" 0644
install_file "${OVL}/etc/systemd/system/getty@tty2.service.d/autologin.conf" \
  "${R}/etc/systemd/system/getty@tty2.service.d/autologin.conf" 0644

mkdir -p "${R}/etc/systemd/system/multi-user.target.wants" \
  "${R}/etc/systemd/system/graphical.target.wants" \
  "${R}/etc/systemd/system/sysinit.target.wants" \
  "${R}/var/log/journal"
mid="$(tr -d '[:space:]' < "${R}/etc/machine-id" 2>/dev/null || true)"
if [[ -n "${mid}" ]]; then
  mkdir -p "${R}/var/log/journal/${mid}"
  chmod 2755 "${R}/var/log/journal" "${R}/var/log/journal/${mid}" || true
fi
chmod 2755 "${R}/var/log/journal" || true

ln -sfn /usr/lib/systemd/system/sm8550-boot-debug.service \
  "${R}/etc/systemd/system/multi-user.target.wants/sm8550-boot-debug.service"
ln -sfn /usr/lib/systemd/system/sm8550-boot-debug-late.service \
  "${R}/etc/systemd/system/graphical.target.wants/sm8550-boot-debug-late.service"
# Do not autologin getty@tty2 or debug-shell: a second seat0 session
# steals the DRM seat from gamescope. Use journal + BOOT-DEBUG files.

if [[ -d "${H}/steamos" ]]; then
  mkdir -p "${H}/steamos"
  cat >"${H}/steamos/LEEME-DEBUG.txt" <<'EOF'
Arranque de diagnóstico
-----------------------
Tras este boot (aunque apagues a la fuerza) mira:
  /home/steamos/BOOT-DEBUG-early.txt
  /home/steamos/BOOT-DEBUG-late.txt
  journalctl -b   (si el journal persistió)

Teclado USB:
  Ctrl+Alt+F2  → consola usuario steamos (sin contraseña)
  Ctrl+Alt+F9  → debug-shell root
EOF
  chown 1000:1000 "${H}/steamos/LEEME-DEBUG.txt" 2>/dev/null || true
fi

log "Patching KERNEL cmdline (verbose + console=tty0)"
# shellcheck source=external-and-mods/kernel/lib/cmdline.sh
source "${MOD}/kernel/lib/cmdline.sh"
uuid="$(python3 - "${BOOT}/KERNEL" <<'PY'
from pathlib import Path
import re, sys
d = Path(sys.argv[1]).read_bytes()
cmd = d[0x40:0x40+512].split(b"\x00",1)[0].decode("ascii","replace")
m = re.search(r"root=UUID=([0-9a-fA-F-]{36})", cmd)
print(m.group(1) if m else "")
PY
)"
[[ -n "${uuid}" ]] || die "could not read root UUID from KERNEL"
export CMDLINE_QUIET=0
export DEBUG_BOOTLOG=1
cmdline="$(build_unified_abl_cmdline "${uuid}")"
python3 - "${BOOT}/KERNEL" "${cmdline}" <<'PY'
import sys
from pathlib import Path
kern, cmdline = Path(sys.argv[1]), sys.argv[2]
data = bytearray(kern.read_bytes())
if data[:8] != b"ANDROID!":
    raise SystemExit("not ANDROID bootimg")
cmd = cmdline.encode("ascii")
if len(cmd) >= 512:
    raise SystemExit(f"cmdline too long ({len(cmd)})")
data[0x40:0x40 + 512] = cmd.ljust(512, b"\x00")
kern.write_bytes(data)
print(cmdline)
PY
( cd "${BOOT}" && md5sum KERNEL > KERNEL.md5 )

log "Done. Unmount the SD and boot again."
log "After the blink/force-off, remount and read:"
log "  ${H}/steamos/BOOT-DEBUG-early.txt"
log "  ${H}/steamos/BOOT-DEBUG-late.txt"
log "  ${R}/var/log/journal/"
