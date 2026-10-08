#!/usr/bin/env bash
# Bake-time debug logging for a 7.2.8 (or any) SM8550 rootfs.
# Persistent journal + BOOT-DEBUG dumps + gamescope QAM file log.
# Does not steal the DRM seat (no extra getty/debug-shell).
#
# Usage: enable-sm8550-debug-boot.sh <rootfs> [home/steamos]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVL="${ROOT}/odin-overlay"
R="${1:?rootfs}"
R="$(cd "$R" && pwd)"
H="${2:-}"

log() { printf '==> [debug-boot] %s\n' "$*"; }
die() { printf 'ERROR: [debug-boot] %s\n' "$*" >&2; exit 1; }

[[ -d "$R/usr" ]] || die "missing rootfs $R"

install_file() {
  local src="$1" dest="$2" mode="${3:-}"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  [[ -n "$mode" ]] && chmod "$mode" "$dest"
}

log "persist journal + BOOT-DEBUG + gamescope QAM log in $R"
install_file "$OVL/usr/lib/steamos/sm8550-boot-debug" \
  "$R/usr/lib/steamos/sm8550-boot-debug" 0755
install_file "$OVL/usr/lib/systemd/system/sm8550-boot-debug.service" \
  "$R/usr/lib/systemd/system/sm8550-boot-debug.service" 0644
install_file "$OVL/usr/lib/systemd/system/sm8550-boot-debug-late.service" \
  "$R/usr/lib/systemd/system/sm8550-boot-debug-late.service" 0644
install_file "$OVL/etc/systemd/journald.conf.d/99-sm8550-persist.conf" \
  "$R/etc/systemd/journald.conf.d/99-sm8550-persist.conf" 0644

mkdir -p "$R/etc/systemd/system/multi-user.target.wants" \
  "$R/etc/systemd/system/graphical.target.wants" \
  "$R/var/log/journal"
chmod 2755 "$R/var/log/journal" || true
mid="$(tr -d '[:space:]' < "$R/etc/machine-id" 2>/dev/null || true)"
if [[ -n "$mid" ]]; then
  mkdir -p "$R/var/log/journal/${mid}"
  chmod 2755 "$R/var/log/journal/${mid}" || true
fi

ln -sfn /usr/lib/systemd/system/sm8550-boot-debug.service \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-boot-debug.service"
ln -sfn /usr/lib/systemd/system/sm8550-boot-debug-late.service \
  "$R/etc/systemd/system/graphical.target.wants/sm8550-boot-debug-late.service"

# gamescope-session writes ~/.local/share/qam-debug/gamescope-qam.log
: >"$R/etc/sm8550-qam-debug"
chmod 0644 "$R/etc/sm8550-qam-debug"

if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
  install_file "$OVL/etc/systemd/journald.conf.d/99-sm8550-persist.conf" \
    "$R/var/lib/overlays/etc/upper/systemd/journald.conf.d/99-sm8550-persist.conf" 0644
  mkdir -p "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants" \
    "$R/var/lib/overlays/etc/upper/systemd/system/graphical.target.wants"
  ln -sfn /usr/lib/systemd/system/sm8550-boot-debug.service \
    "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/sm8550-boot-debug.service"
  ln -sfn /usr/lib/systemd/system/sm8550-boot-debug-late.service \
    "$R/var/lib/overlays/etc/upper/systemd/system/graphical.target.wants/sm8550-boot-debug-late.service"
  : >"$R/var/lib/overlays/etc/upper/sm8550-qam-debug"
  chmod 0644 "$R/var/lib/overlays/etc/upper/sm8550-qam-debug"
fi

if [[ -n "$H" && -d "$H" ]]; then
  mkdir -p "$H/.local/share/qam-debug"
  cat >"$H/LEEME-DEBUG.txt" <<'EOF'
Arranque de diagnóstico (kernel 7.2.8 / SM8550_DEBUG_BOOT)
----------------------------------------------------------
Tras el primer boot (aunque apagues a la fuerza) mira en la partición home:

  /home/steamos/BOOT-DEBUG-early.txt
  /home/steamos/BOOT-DEBUG-late.txt
  /home/steamos/.local/share/qam-debug/gamescope-qam.log

Journal persistente:
  journalctl -b
  /var/log/journal/

Pantalla negra + cursor: el late dump espera 25s tras graphical.target.
EOF
  chown 1000:1000 "$H/LEEME-DEBUG.txt" "$H/.local/share/qam-debug" 2>/dev/null || true
fi

log "OK — BOOT-DEBUG + journal + gamescope-qam.log"
