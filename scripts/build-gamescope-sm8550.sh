#!/usr/bin/env bash
# Build SM8550-patched gamescope from external-and-mods/gamescope/.
#
# Patches (already in tree): MSM backlight, rotation shader, QAM layout, etc.
# Output: external-and-mods/gamescope/build/src/gamescope
#
# Usage:
#   ./scripts/build-gamescope-sm8550.sh
# Env:  GAMESCOPE_SRC  GAMESCOPE_BUILD  JOBS  FORCE_REBUILD=1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${GAMESCOPE_SRC:-${ROOT}/external-and-mods/gamescope}"
BUILD="${GAMESCOPE_BUILD:-${SRC}/build}"
JOBS="${JOBS:-$(nproc)}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

log() { printf '==> [gamescope-sm8550] %s\n' "$*"; }
die() { printf 'ERROR: [gamescope-sm8550] %s\n' "$*" >&2; exit 1; }

[[ -f "${SRC}/meson.build" ]] || die "missing ${SRC}/meson.build"
command -v meson >/dev/null || die "meson not found"
command -v ninja >/dev/null || die "ninja not found"

cd "${SRC}"

if [[ "${FORCE_REBUILD}" == "1" && -d "${BUILD}" ]]; then
  log "FORCE_REBUILD=1 — wiping ${BUILD}"
  rm -rf "${BUILD}"
fi

# Meson embeds absolute paths. A build copied from another user/machine
# (e.g. /home/steam/... vs /home/masies/...) breaks with mkdtemp FileNotFoundError.
if [[ -f "${BUILD}/build.ninja" ]] && ! grep -Fq "${ROOT}" "${BUILD}/build.ninja"; then
  log "stale gamescope build (wrong prefix) — wiping ${BUILD}"
  rm -rf "${BUILD}"
fi

# Optional features off on dev hosts (avoids libsdl2→libgbm-dev apt fights).
MESON_OPTS=(
  --buildtype=release
  -Dstrip=true
  -Dsdl2_backend=disabled
  -Davif_screenshots=disabled
  -Dbenchmark=disabled
  -Dinput_emulation=disabled
  -Denable_openvr_support=false
)

if [[ ! -f "${BUILD}/build.ninja" ]]; then
  log "meson setup ${BUILD} (release, optional backends off)"
  meson setup "${BUILD}" "${MESON_OPTS[@]}"
else
  log "meson reconfigure ${BUILD}"
  meson setup "${BUILD}" --reconfigure "${MESON_OPTS[@]}"
fi

log "ninja -C ${BUILD} -j ${JOBS} (gamescope + ctl + reaper only)"
ninja -C "${BUILD}" -j "${JOBS}" src/gamescope src/gamescopectl src/gamescopereaper
if [[ -f "${BUILD}/layer/libVkLayer_FROG_gamescope_wsi_aarch64.so" ]]; then
  ninja -C "${BUILD}" -j "${JOBS}" layer/libVkLayer_FROG_gamescope_wsi_aarch64.so 2>/dev/null || true
fi

BIN="${BUILD}/src/gamescope"
[[ -x "${BIN}" ]] || die "missing ${BIN}"

{
  date -Iseconds
  echo "source=${SRC}"
  file -b "${BIN}"
  md5sum "${BIN}"
} | tee "${BUILD}/install_manifest.txt"

log "OK: ${BIN}"
log "md5: $(md5sum "${BIN}" | awk '{print $1}')"
