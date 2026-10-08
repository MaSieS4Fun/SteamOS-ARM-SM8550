#!/usr/bin/env bash
# Preflight checks before apply-odin-mods / make-steamos-sm8550.sh.
# Ensures project gamescope, Mesa SM8550, kernel, and MangoHud source exist.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MOD="${ROOT}/external-and-mods"
GS="${MOD}/gamescope/build/src/gamescope"
# shellcheck source=lib/sm8550-kernel-out.sh
source "${SCRIPT_DIR}/lib/sm8550-kernel-out.sh"
KOUT="$(sm8550_resolve_kout "${MOD}" || true)"
KREL="$(sm8550_kernel_release "${KOUT}" 2>/dev/null || true)"
MESA="${MOD}/mesa-sm8550"
MANGOHUD="${MOD}/MangoHud"

ok=0
fail=0

check() {
  local label="$1"
  shift
  if "$@"; then
    printf '  OK  %s\n' "$label"
    ok=$((ok + 1))
  else
    printf '  FAIL %s\n' "$label" >&2
    fail=$((fail + 1))
  fi
}

not_grep() {
  local pattern="$1" file="$2"
  ! grep -Fq "$pattern" "$file"
}

log() { printf '==> [verify-sm8550] %s\n' "$*"; }
die() { printf 'ERROR: [verify-sm8550] %s\n' "$*" >&2; exit 1; }

log "Checking SM8550 build inputs in ${ROOT}"

check "kernel KERNEL" test -f "${KOUT}/boot/KERNEL"
check "kernel modules" test -n "${KREL}" -a -d "${KOUT}/modules/${KREL}"
check "gamescope (project build)" test -x "${GS}"
check "MangoHud source" test -f "${MANGOHUD}/meson.build"
check "Mesa turnip-working" test -f "${MESA}/turnip-working/libvulkan_freedreno.so"
check "Mesa opengl-working" test -f "${MESA}/opengl-working/libEGL_mesa.so.0.0.0"
check "Mesa wayland 0.26.0" test -f "${MESA}/wayland/libwayland-client.so.0.26.0"
check "QAM INTERNAL_X11 contract" grep -qx \
  'export GAMESCOPE_SM8550_STEAM_INTERNAL_X11=1' \
  "${ROOT}/odin-overlay/usr/lib/steamos/gamescope-session"
check "game-only mangoapp supervisor" grep -Fq \
  '/usr/lib/steamos/sm8550-mangoapp --supervisor' \
  "${ROOT}/odin-overlay/usr/lib/steamos/gamescope-onready"
check "OOBE relaunch preserves display config" not_grep \
  'sm8550-fix-steam-display' \
  "${ROOT}/odin-overlay/usr/lib/steamos/sm8550-relaunch-steam"
check "Steam-controlled MangoHud" grep -qx 'control=mangohud' \
  "${ROOT}/odin-overlay/usr/share/steamos-odin/MangoHud/steam/MangoHud.conf"

if [[ -f "${MESA}/MANIFEST.sha256" ]]; then
  if ( cd "${MESA}" && sha256sum -c MANIFEST.sha256 >/dev/null 2>&1 ); then
    printf '  OK  Mesa MANIFEST.sha256\n'
    ok=$((ok + 1))
  else
    printf '  FAIL Mesa MANIFEST.sha256 (checksum mismatch)\n' >&2
    fail=$((fail + 1))
  fi
else
  printf '  WARN Mesa MANIFEST.sha256 missing (optional)\n' >&2
fi

if [[ -x "${GS}" ]]; then
  printf '      gamescope: %s\n' "$(file -b "${GS}")"
  printf '      md5:       %s\n' "$(md5sum "${GS}" | awk '{print $1}')"
fi

if [[ -f "${MESA}/turnip-working/libvulkan_freedreno.so" ]]; then
  printf '      turnip:    %s\n' "$(md5sum "${MESA}/turnip-working/libvulkan_freedreno.so" | awk '{print $1}')"
fi

if (( fail > 0 )); then
  echo >&2
  die "${fail} check(s) failed. Run: sudo ./make-steamos-sm8550.sh (compiles gamescope + MangoHud) or ./scripts/build-gamescope-sm8550.sh"
fi

log "All ${ok} checks passed"
