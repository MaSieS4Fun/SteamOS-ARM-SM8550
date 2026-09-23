#!/bin/bash
# Replace the Frame steamclient (version 0, incomplete library IPC) with
# Valve's published steamdeck_stable ARM64 handheld client.
# Usage: install-steam-client-arm64.sh <STEAM_HOME>
set -euo pipefail

STEAM_HOME="${1:?STEAM_HOME}"
HERE="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="${STEAM_CLIENT_ARM64_DIR:-$HERE/../external-and-mods/steam-client-arm64}"
BINS="$PKG/bins_linuxarm64_linuxarm64.zip"
UI="$PKG/steamui_websrc_all.zip"

if [[ ! -f "$BINS" || ! -f "$UI" ]]; then
  echo "install-steam-client-arm64: missing $BINS or $UI" >&2
  exit 1
fi

mkdir -p "$STEAM_HOME"

python3 - "$BINS" "$STEAM_HOME" << 'PY'
import sys, zipfile
from pathlib import Path
src, dest = Path(sys.argv[1]), Path(sys.argv[2])
with zipfile.ZipFile(src) as z:
    for info in z.infolist():
        name = info.filename.replace("\\", "/")
        if name.endswith("/") or name.startswith("/") or ".." in name.split("/"):
            continue
        out = dest / name
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(z.read(info))
        if name.endswith(("/steam", "/steamwebhelper", "/steamwebhelper.sh",
                          "/gldriverquery", "/vulkandriverquery", "/steamsysinfo")):
            out.chmod(0o755)
print("extracted bins to", dest)
PY

python3 - "$UI" "$STEAM_HOME" << 'PY'
import sys, zipfile, shutil
from pathlib import Path
src, dest = Path(sys.argv[1]), Path(sys.argv[2])
steamui = dest / "steamui"
if steamui.exists():
    shutil.rmtree(steamui)
with zipfile.ZipFile(src) as z:
    for info in z.infolist():
        name = info.filename.replace("\\", "/")
        if not name.startswith("steamui/") or name.endswith("/"):
            continue
        if ".." in name.split("/"):
            continue
        out = dest / name
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(z.read(info))
print("extracted steamui to", steamui)
PY

mkdir -p "$STEAM_HOME/linuxarm64" "$STEAM_HOME/package"
for _lib in steamclient.so crashhandler.so steam-launch-wrapper; do
  if [[ -s "$STEAM_HOME/steamrtarm64/${_lib}" ]]; then
    cp -f "$STEAM_HOME/steamrtarm64/${_lib}" "$STEAM_HOME/linuxarm64/${_lib}"
  fi
done
echo steamdeck_stable > "$STEAM_HOME/package/beta"
printf '%s\n' 'steamdeck_stable' '1788652215' > "$STEAM_HOME/.odin-handheld-client"
touch "$STEAM_HOME/.install-complete"
echo "install-steam-client-arm64: installed handheld client in $STEAM_HOME"
