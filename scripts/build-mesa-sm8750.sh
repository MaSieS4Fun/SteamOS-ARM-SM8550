#!/usr/bin/env bash
# Build Mesa Turnip for SM8750 / Adreno 830.
# Applies ONLY patches/SM8750 (A830 chip ids). Does not apply SM8550 patches.
#
#   ./scripts/build-mesa-sm8750.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MESA_VER="${MESA_VER:-26.2.3}"
SRC="${MESA_SRC:-${ROOT}/output/src/mesa-${MESA_VER}}"
BUILD="${MESA_BUILD:-${ROOT}/output/work/mesa-${MESA_VER}-sm8750}"
PATCH_SM8750="${ROOT}/external-and-mods/mesa/patches/SM8750"
OUT="${ROOT}/external-and-mods/mesa-sm8750"
WAYLAND="${ROOT}/external-and-mods/mesa-sm8550/wayland"
JOBS="${JOBS:-$(nproc)}"
MARKER="${SRC}/.steamos-sm8750-a830-only"

log() { printf '==> [mesa-sm8750] %s\n' "$*"; }
die() { printf 'ERROR: [mesa-sm8750] %s\n' "$*" >&2; exit 1; }

[[ -d "${SRC}/src/freedreno" ]] || die "missing Mesa source ${SRC}"
[[ -f "${PATCH_SM8750}/0001-add-a830-chip-id.patch" ]] \
  || die "missing ${PATCH_SM8750}/0001-add-a830-chip-id.patch"
command -v ninja >/dev/null || die "ninja missing"
command -v meson >/dev/null || die "meson missing"

apply_patch() {
  local p="$1"
  [[ -f "$p" ]] || return 0
  if patch -d "$SRC" -p1 --forward --dry-run < "$p" >/dev/null 2>&1; then
    log "apply $(basename "$p")"
    patch -d "$SRC" -p1 --forward < "$p"
  elif patch -d "$SRC" -p1 -R --dry-run < "$p" >/dev/null 2>&1; then
    log "already applied: $(basename "$p")"
  else
    die "failed $(basename "$p")"
  fi
}

if [[ ! -f "$MARKER" ]]; then
  log "Applying SM8750 A830 patch only (no SM8550 patches)"
  apply_patch "${PATCH_SM8750}/0001-add-a830-chip-id.patch"
  grep -q '0xffff44050001' "${SRC}/src/freedreno/common/freedreno_devices.py" \
    || die "A830 extra chip ids not present after patch"
  touch "$MARKER"
else
  log "patches already marked (${MARKER})"
fi

if [[ ! -f "${BUILD}/build.ninja" ]]; then
  log "meson setup ${BUILD}"
  meson setup "$BUILD" "$SRC" \
    --prefix=/usr \
    --libdir=lib \
    --buildtype=release \
    -Dplatforms=wayland \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=msm \
    -Dglvnd=disabled \
    -Degl=disabled \
    -Dgles1=disabled \
    -Dgles2=disabled \
    -Dgbm=disabled \
    -Dglx=disabled \
    -Dopengl=false \
    -Dllvm=disabled \
    -Dvalgrind=disabled \
    -Dbuild-tests=false \
    -Dmicrosoft-clc=disabled \
    -Dlibunwind=disabled \
    -Dlmsensors=disabled \
    -Dvulkan-layers= \
    -Dvideo-codecs=all_free
fi

log "ninja -C ${BUILD} -j ${JOBS}"
ninja -C "$BUILD" -j "$JOBS"
STAGING="${BUILD}/install-staging"
rm -rf "$STAGING"
meson install -C "$BUILD" --no-rebuild --destdir "$STAGING"
LIB="${STAGING}/usr/lib"
[[ -f "${LIB}/libvulkan_freedreno.so" ]] || die "install missing libvulkan_freedreno.so"

python3 - "${LIB}/libvulkan_freedreno.so" <<'PY'
import struct, sys
from pathlib import Path
data = Path(sys.argv[1]).read_bytes()
need = (0xffff44050000, 0xffff44050001, 0x44050000, 0x44050001)
missing = [hex(v) for v in need if data.count(struct.pack("<Q", v)) < 1]
if missing:
    raise SystemExit("Turnip missing A830 chip ids: " + ", ".join(missing))
print("A830 chip ids present in Turnip")
PY

log "Stage ${OUT}"
rm -rf "${OUT}/turnip-working"
mkdir -p "${OUT}/turnip-working"
install -m0755 "${LIB}/libvulkan_freedreno.so" "${OUT}/turnip-working/libvulkan_freedreno.so"
if [[ ! -f "${OUT}/opengl-working/libEGL_mesa.so.0.0.0" ]]; then
  mkdir -p "${OUT}/opengl-working"
  cp -a "${ROOT}/external-and-mods/mesa-sm8550/opengl-working/." "${OUT}/opengl-working/"
fi
if [[ -d "$WAYLAND" && ! -f "${OUT}/wayland/libwayland-client.so.0.26.0" ]]; then
  rm -rf "${OUT}/wayland"
  cp -a "$WAYLAND" "${OUT}/wayland"
fi

{
  date -Iseconds
  echo "mesa=${MESA_VER}"
  echo "patches=SM8750-a830-only"
  echo "source=${SRC}"
} > "${OUT}/BUILD.txt"

log "OK: ${OUT}/turnip-working/libvulkan_freedreno.so"
md5sum "${OUT}/turnip-working/libvulkan_freedreno.so"
