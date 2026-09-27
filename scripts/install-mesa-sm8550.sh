#!/usr/bin/env bash
# Install SM8550 Mesa overrides onto a SteamOS Frame rootfs.
#
# Replaces only the libraries verified on a working AYN Odin 2 SD:
#   - Turnip (Vulkan): libvulkan_freedreno.so
#   - OpenGL: EGL, GLX, GBM, dri_gbm, libdril_dri (+ DRI symlinks)
#   - Wayland: libwayland-client.so.0 -> 0.26.0 (wl_fixes_interface)
#
# Keeps stock: libgallium-26.3.0-devel.so, libdisplay-info, everything else.
#
# Source: external-and-mods/mesa-sm8550/{turnip-working,opengl-working,wayland}/
# Usage:  sudo ./scripts/install-mesa-sm8550.sh [/path/to/rootfs]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
MOD="${ROOT}/external-and-mods/mesa-sm8550"
STOCK="${R}/opt/stock-steamos"
TURNIP="${MOD}/turnip-working/libvulkan_freedreno.so"
OGL="${MOD}/opengl-working"
WAYLAND="${MOD}/wayland/libwayland-client.so.0.26.0"

log() { printf '==> [mesa-sm8550] %s\n' "$*"; }
die() { printf 'ERROR: [mesa-sm8550] %s\n' "$*" >&2; exit 1; }

[[ -d "$R/usr/lib" ]] || die "missing rootfs: $R"
[[ -f "$TURNIP" ]] || die "missing $TURNIP"
[[ -f "$OGL/libEGL_mesa.so.0.0.0" ]] || die "missing $OGL"
[[ -f "$WAYLAND" ]] || die "missing $WAYLAND"

backup() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  [[ -e "$dest" ]] || cp -a "$src" "$dest"
}

log "Turnip → $R/usr/lib/libvulkan_freedreno.so"
backup "$R/usr/lib/libvulkan_freedreno.so" "$STOCK/usr/lib/libvulkan_freedreno.so"
install -D -m 0755 "$TURNIP" "$R/usr/lib/libvulkan_freedreno.so"
rm -f "$R/usr/lib/libgallium-26.2.3.so" 2>/dev/null || true

log "OpenGL (EGL/GLX/GBM/DRI)"
"${SCRIPT_DIR}/install-opengl-mesa-sm8550.sh" "$R"

log "Wayland client 0.26.0 (wl_fixes_interface)"
backup "$R/usr/lib/libwayland-client.so.0.26.0" "$STOCK/usr/lib/libwayland-client.so.0.26.0"
install -D -m 0755 "$WAYLAND" "$R/usr/lib/libwayland-client.so.0.26.0"
ln -sfn libwayland-client.so.0.26.0 "$R/usr/lib/libwayland-client.so.0"
ln -sfn libwayland-client.so.0 "$R/usr/lib/libwayland-client.so"

mkdir -p "$R/usr/share/steamos-odin"
{
  date -Iseconds
  echo "source=external-and-mods/mesa-sm8550"
  echo "gallium=stock-26.3.0-devel"
  md5sum \
    "$R/usr/lib/libvulkan_freedreno.so" \
    "$R/usr/lib/libEGL_mesa.so.0.0.0" \
    "$R/usr/lib/libGLX_mesa.so.0.0.0" \
    "$R/usr/lib/libgbm.so.1.0.0" \
    "$R/usr/lib/gbm/dri_gbm.so" \
    "$R/usr/lib/dri/libdril_dri.so" \
    "$R/usr/lib/libwayland-client.so.0.26.0"
} > "$R/usr/share/steamos-odin/mesa-sm8550.txt"

log "Done."
