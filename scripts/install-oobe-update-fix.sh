#!/usr/bin/env bash
# OOBE Wi-Fi fake OS update loop fix (ArmadaOS / Steam-ubuntu model).
#
# After Wi-Fi: OOBE Update page → steamos-update apply → sm8550-relaunch-steam
# → login (factory images no longer block /login after SetOOBEComplete).
#
# Installs: steamos-update, sm8550-relaunch-steam, sm8550-launch-steam, steamui patches.
# Does NOT install: sm8550-oobe-watch, sm8550-display-guard (extra Steam kills).
#
# Usage: sudo STEAMOS_HOME=... ./scripts/install-oobe-update-fix.sh [/run/media/steam/root]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-/run/media/steam/root}"
R="$(cd "$R" && pwd)"
OVL="${ROOT}/odin-overlay"
HOME_DST="${STEAMOS_HOME:-$(dirname "$R")/home/steamos}"
STEAM_UI="${HOME_DST}/.local/share/Steam/steamui"

log() { printf '==> [oobe-fix] %s\n' "$*"; }
die() { printf 'ERROR: [oobe-fix] %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "run as root: sudo $0 $R"

install -D -m0755 "$OVL/usr/bin/steamos-update" "$R/usr/bin/steamos-update"
install -D -m0755 "$OVL/usr/bin/steamos-polkit-helpers/steamos-update" \
  "$R/usr/bin/steamos-polkit-helpers/steamos-update"
for f in sm8550-relaunch-steam sm8550-launch-steam sm8550-oobe-restart-steam \
    sm8550-ensure-steam-home sm8550-patch-steamui; do
  install -D -m0755 "$OVL/usr/lib/steamos/$f" "$R/usr/lib/steamos/$f"
done

mkdir -p "$R/var/lib/steamos-sm8550"
mkdir -p "$R/etc/systemd/system"
if [[ ! -L "$R/etc/systemd/system/atomupd.service" ]]; then
  ln -sfn /dev/null "$R/etc/systemd/system/atomupd.service"
  log "disabled atomupd.service (no RAUC on SM8550 image)"
fi

if [[ -d "$STEAM_UI" && -x "$R/usr/lib/steamos/sm8550-patch-steamui" ]]; then
  log "patch steamui in home (OOBE update / Blocked 40 / mandatory update)"
  HOME="$HOME_DST" STEAM_HOME="$HOME_DST" \
    "$R/usr/lib/steamos/sm8550-patch-steamui" "$STEAM_UI" || log "WARN: steamui patch incomplete"
else
  log "WARN: no $STEAM_UI — patch after Steam client is baked into home"
fi

log "OK: steamos-update + relaunch installed"
