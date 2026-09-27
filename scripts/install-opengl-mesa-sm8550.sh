#!/usr/bin/env bash
# Replace Frame OpenGL Mesa (EGL/GLX/GBM/DRI) with known-good SM8550 set.
# Keeps stock libgallium-26.3.0-devel.so and libvulkan_freedreno.so (Turnip) untouched.
#
# Source: external-and-mods/mesa-sm8550/opengl-working/ (extracted from working SD)
# Usage:  sudo ./scripts/install-opengl-mesa-sm8550.sh [/path/to/rootfs]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
OGL="${ROOT}/external-and-mods/mesa-sm8550/opengl-working"
STOCK="${R}/opt/stock-steamos"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "$R/usr/lib" ]] || die "missing rootfs: $R"
[[ -f "$OGL/libEGL_mesa.so.0.0.0" ]] || die "missing $OGL"

backup() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  [[ -e "$dest" ]] || cp -a "$src" "$dest"
}

log "OpenGL Mesa (working set) → $R"
for item in \
  usr/lib/libEGL_mesa.so.0.0.0 \
  usr/lib/libGLX_mesa.so.0.0.0 \
  usr/lib/libgbm.so.1.0.0 \
  usr/lib/gbm/dri_gbm.so \
  usr/lib/dri/libdril_dri.so
do
  backup "$R/$item" "$STOCK/$item"
done

install -D -m 0755 "$OGL/libEGL_mesa.so.0.0.0" "$R/usr/lib/libEGL_mesa.so.0.0.0"
install -D -m 0755 "$OGL/libGLX_mesa.so.0.0.0" "$R/usr/lib/libGLX_mesa.so.0.0.0"
install -D -m 0755 "$OGL/libgbm.so.1.0.0" "$R/usr/lib/libgbm.so.1.0.0"
install -D -m 0755 "$OGL/gbm/dri_gbm.so" "$R/usr/lib/gbm/dri_gbm.so"
install -D -m 0755 "$OGL/dri/libdril_dri.so" "$R/usr/lib/dri/libdril_dri.so"

for link in libEGL_mesa.so libEGL_mesa.so.0 libGLX_mesa.so libGLX_mesa.so.0 libgbm.so libgbm.so.1; do
  [[ -L "$OGL/$link" ]] || continue
  ln -sfn "$(readlink "$OGL/$link")" "$R/usr/lib/$link"
done
ln -sfn libGLX_mesa.so.0.0.0 "$R/usr/lib/libGLX_indirect.so.0" 2>/dev/null || true

for d in kgsl msm zink swrast kms_swrast; do
  ln -sfn libdril_dri.so "$R/usr/lib/dri/${d}_dri.so"
done

mkdir -p "$R/usr/share/steamos-odin"
{
  date -Iseconds
  echo "opengl=working-sd-extract"
  echo "gallium=stock-26.3.0-devel"
  echo "vulkan=turnip-working (install-mesa-sm8550.sh)"
  md5sum "$R/usr/lib/libEGL_mesa.so.0.0.0" "$R/usr/lib/libgbm.so.1.0.0" "$R/usr/lib/dri/libdril_dri.so"
} > "$R/usr/share/steamos-odin/mesa-opengl-sm8550.txt"

log "Done."
