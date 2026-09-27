#!/usr/bin/env bash
# Bake Steam Game Mode home paths into a mounted image (offline, before publish).
# Without ~/.steam symlinks, steamwebhelper and steamrt paths fail → black screen + X cursor.
#
# Usage: ensure-steam-home-for-image.sh ROOTFS [HOME_DST]
set -euo pipefail

R="${1:?rootfs mount}"
R="${R%/}"
HOME_DST="${2:-$(dirname "$R")/home/steamos}"
STEAM_HOME="${HOME_DST}/.local/share/Steam"

log() { printf '==> [steam-home] %s\n' "$*"; }

[[ -d "$STEAM_HOME" ]] || { log "WARN: no Steam client at $STEAM_HOME"; exit 0; }

# Symlink *targets* must be runtime paths (/home/steamos/...). Existence checks use
# STEAM_HOME on the mounted image — /home/steamos does not exist on the build host.
_steam_link() {
  local runtime_target="$1"
  local dest="$2"
  local mount_check="${3:-}"
  if [[ -n "$mount_check" && ! -e "$mount_check" ]]; then
    return 0
  fi
  ln -sfn "$runtime_target" "$dest"
}

log "Steam ~/.steam symlinks"
mkdir -p "${HOME_DST}/.steam"
_steam_link /home/steamos/.local/share/Steam "${HOME_DST}/.steam/steam" "$STEAM_HOME"
_steam_link /home/steamos/.local/share/Steam "${HOME_DST}/.steam/root" "$STEAM_HOME"
_steam_link /home/steamos/.local/share/Steam/linux32 "${HOME_DST}/.steam/sdk32" \
  "${STEAM_HOME}/linux32"
_steam_link /home/steamos/.local/share/Steam/linux64 "${HOME_DST}/.steam/sdk64" \
  "${STEAM_HOME}/linux64"
_steam_link /home/steamos/.local/share/Steam/linuxarm64 "${HOME_DST}/.steam/sdkarm64" \
  "${STEAM_HOME}/linuxarm64"
_steam_link /home/steamos/.local/share/Steam/steamrtarm64 "${HOME_DST}/.steam/binarm64" \
  "${STEAM_HOME}/steamrtarm64"
_steam_link /home/steamos/.local/share/Steam/ubuntu12_32 "${HOME_DST}/.steam/bin32" \
  "${STEAM_HOME}/ubuntu12_32"
_steam_link /home/steamos/.local/share/Steam/ubuntu12_64 "${HOME_DST}/.steam/bin64" \
  "${STEAM_HOME}/ubuntu12_64"

if [[ -d "${STEAM_HOME}/linuxarm64" && -d "${STEAM_HOME}/steamrtarm64" ]]; then
  for _lib in steamclient.so crashhandler.so steam-launch-wrapper; do
    if [[ -s "${STEAM_HOME}/steamrtarm64/${_lib}" && ! -s "${STEAM_HOME}/linuxarm64/${_lib}" ]]; then
      cp -f "${STEAM_HOME}/steamrtarm64/${_lib}" "${STEAM_HOME}/linuxarm64/${_lib}"
      log "copied ${_lib} steamrtarm64 → linuxarm64"
    fi
  done
fi

# RUNSTEAM in home must match deckard (steam.service copies with cp -u).
if [[ -f "${R}/usr/share/deckard/RUNSTEAM.sh" ]]; then
  install -D -m0755 "${R}/usr/share/deckard/RUNSTEAM.sh" "${STEAM_HOME}/RUNSTEAM.sh"
fi

if [[ ! -s "${STEAM_HOME}/steam.inf" ]]; then
  ver=1788652215
  if [[ -r "${STEAM_HOME}/.odin-handheld-client" ]]; then
    ver="$(awk 'NR==2 && /^[0-9]+$/{print; exit}' "${STEAM_HOME}/.odin-handheld-client")"
  fi
  printf 'ClientVersion=%s\n' "${ver:-1788652215}" >"${STEAM_HOME}/steam.inf"
  cp -f "${STEAM_HOME}/steam.inf" "${STEAM_HOME}/steamrtarm64/steam.inf" 2>/dev/null || true
  log "seeded steam.inf (ClientVersion=${ver:-1788652215})"
fi

# Seed the display identity proven to keep Home/QAM above games. The session's
# INTERNAL_X11 contract exposes this nested output as DSI-1.
CONFIG_VDF="${STEAM_HOME}/config/config.vdf"
mkdir -p "$(dirname "$CONFIG_VDF")"
if [[ ! -s "$CONFIG_VDF" ]]; then
  cat >"$CONFIG_VDF" <<'EOF'
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"Display"
				{
					"IsExternalDisplay"		"1"
					"name"		"External: DSI-1 8\"|||Windowed"
				}
			}
		}
	}
}
EOF
  log "seeded config.vdf (External: DSI-1 Windowed)"
else
  python3 - "$CONFIG_VDF" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8", errors="replace")
text, count = re.subn(
    r'(?m)^([ \t]*"IsExternalDisplay"[ \t]+)"[^"]*"',
    r'\g<1>"1"',
    text,
    count=1,
)
if count:
    start = text.find('"IsExternalDisplay"')
    end = min(len(text), start + 1024)
    chunk = text[start:end]
    chunk, names = re.subn(
        r'(?m)^([ \t]*"name"[ \t]+)"(?:[^"\\]|\\.)*"',
        r'\g<1>"External: DSI-1 8\\"|||Windowed"',
        chunk,
        count=1,
    )
    if names:
        text = text[:start] + chunk + text[end:]
        p.write_text(text, encoding="utf-8")
PY
  log "normalized config.vdf display identity"
fi

# Steam reads this fallback directly. Keep it on the working image's
# control=mangohud model; no session-level mangoapp supervisor is needed.
MANGO_SYSTEM="${R}/usr/share/steamos-odin/MangoHud/steam/MangoHud.conf"
if [[ -f "$MANGO_SYSTEM" ]]; then
  install -m0644 "$MANGO_SYSTEM" "${STEAM_HOME}/config/mangohud.conf"
  log "seeded Steam MangoHud fallback"
fi

# gamescope-session expects holo-cursor.png (Frame ships only holo-cursor-256.png).
if [[ -f "${R}/usr/share/holo/holo-cursor-256.png" ]]; then
  ln -sfn holo-cursor-256.png "${R}/usr/share/holo/holo-cursor.png"
  log "holo-cursor.png → holo-cursor-256.png"
else
  log "WARN: missing ${R}/usr/share/holo/holo-cursor-256.png"
fi

count="$(find "${HOME_DST}/.steam" -maxdepth 1 -type l 2>/dev/null | wc -l)"
log "done: ${count} symlinks under ~/.steam (expect 8)"
