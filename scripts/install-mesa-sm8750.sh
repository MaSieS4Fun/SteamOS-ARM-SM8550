#!/usr/bin/env bash
# Install SM8750 Mesa (Adreno 830 Turnip + OpenGL) onto a SteamOS Frame rootfs.
# Does not use mesa-sm8550 Turnip.
#
# Usage: sudo ./scripts/install-mesa-sm8750.sh [rootfs]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
MOD="${MESA_MOD:-${ROOT}/external-and-mods/mesa-sm8750}"
STOCK="${R}/opt/stock-steamos"
TURNIP="${MOD}/turnip-working/libvulkan_freedreno.so"
OGL="${MOD}/opengl-working"
WAYLAND="${MOD}/wayland/libwayland-client.so.0.26.0"
[[ -f "$WAYLAND" ]] || WAYLAND="${ROOT}/external-and-mods/mesa-sm8550/wayland/libwayland-client.so.0.26.0"

log() { printf '==> [mesa-sm8750] %s\n' "$*"; }
die() { printf 'ERROR: [mesa-sm8750] %s\n' "$*" >&2; exit 1; }

[[ -d "$R/usr/lib" ]] || die "missing rootfs: $R"
[[ -f "$TURNIP" ]] || die "missing $TURNIP (build with scripts/build-mesa-sm8750.sh)"
[[ -f "$OGL/libEGL_mesa.so.0.0.0" ]] || die "missing $OGL"
[[ -f "$WAYLAND" ]] || die "missing wayland client 0.26"

backup() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  [[ -e "$dest" ]] || cp -a "$src" "$dest"
}

python3 - "$TURNIP" <<'PY' || die "Turnip missing A830 chip ids — not the SM8750 pack"
import struct, sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
need = (0xffff44050000, 0xffff44050001, 0x44050000, 0x44050001)
missing = [hex(v) for v in need if data.count(struct.pack("<Q", v)) < 1]
if missing:
    raise SystemExit("missing " + ", ".join(missing))
print("A830 chip ids OK")
PY

log "Turnip A830 → $R/usr/lib/libvulkan_freedreno.so"
backup "$R/usr/lib/libvulkan_freedreno.so" "$STOCK/usr/lib/libvulkan_freedreno.so"
install -D -m 0755 "$TURNIP" "$R/usr/lib/libvulkan_freedreno.so"
rm -f "$R/usr/lib/libgallium-26.2.3.so" 2>/dev/null || true

log "OpenGL (EGL/GLX/GBM/DRI) from mesa-sm8750"
for item in \
  libEGL_mesa.so.0.0.0 \
  libGLX_mesa.so.0.0.0 \
  libgbm.so.1.0.0
do
  backup "$R/usr/lib/$item" "$STOCK/usr/lib/$item"
  install -D -m 0755 "$OGL/$item" "$R/usr/lib/$item"
done
backup "$R/usr/lib/gbm/dri_gbm.so" "$STOCK/usr/lib/gbm/dri_gbm.so"
backup "$R/usr/lib/dri/libdril_dri.so" "$STOCK/usr/lib/dri/libdril_dri.so"
install -D -m 0755 "$OGL/gbm/dri_gbm.so" "$R/usr/lib/gbm/dri_gbm.so"
install -D -m 0755 "$OGL/dri/libdril_dri.so" "$R/usr/lib/dri/libdril_dri.so"
ln -sfn libEGL_mesa.so.0.0.0 "$R/usr/lib/libEGL_mesa.so.0"
ln -sfn libEGL_mesa.so.0 "$R/usr/lib/libEGL_mesa.so"
ln -sfn libGLX_mesa.so.0.0.0 "$R/usr/lib/libGLX_mesa.so.0"
ln -sfn libGLX_mesa.so.0 "$R/usr/lib/libGLX_mesa.so"
ln -sfn libgbm.so.1.0.0 "$R/usr/lib/libgbm.so.1"
ln -sfn libgbm.so.1 "$R/usr/lib/libgbm.so"

log "Wayland client 0.26.0"
backup "$R/usr/lib/libwayland-client.so.0.26.0" "$STOCK/usr/lib/libwayland-client.so.0.26.0"
install -D -m 0755 "$WAYLAND" "$R/usr/lib/libwayland-client.so.0.26.0"
ln -sfn libwayland-client.so.0.26.0 "$R/usr/lib/libwayland-client.so.0"
ln -sfn libwayland-client.so.0 "$R/usr/lib/libwayland-client.so"

mkdir -p "$R/usr/share/steamos-odin"
{
  date -Iseconds
  echo "source=external-and-mods/mesa-sm8750"
  echo "patch=mesa/patches/SM8750/0001-add-a830-chip-id.patch"
  echo "not=mesa-sm8550"
  md5sum "$R/usr/lib/libvulkan_freedreno.so"
} > "$R/usr/share/steamos-odin/mesa-sm8750.txt"

log "Done."
