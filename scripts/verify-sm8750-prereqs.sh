#!/usr/bin/env bash
# Preflight for make-steamos-sm8750.sh (Odin 3 preview). Kernel pack only.
# New ABL has no EFI/GRUB path — pack is ANDROID bootimg at boot/KERNEL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MOD="${ROOT}/external-and-mods"
KOUT="${KOUT:-${MOD}/Kernel-ODIN3/output/7.1.4-edge-sm8750}"

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

is_android_bootimg() {
  local f="$1"
  [[ -f "${f}" ]] || return 1
  python3 - "${f}" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_bytes()
sys.exit(0 if data[:8] == b"ANDROID!" else 1)
PY
}

log() { printf '==> [verify-sm8750] %s\n' "$*"; }
die() { printf 'ERROR: [verify-sm8750] %s\n' "$*" >&2; exit 1; }

log "Checking ODIN 3 kernel pack ${KOUT}"

check "ABL KERNEL (ANDROID!)" is_android_bootimg "${KOUT}/boot/KERNEL"
check "modules 7.1.4-edge-sm8750" test -d "${KOUT}/modules/7.1.4-edge-sm8750"
check "UCM AYN/Odin3" test -f "${KOUT}/ucm/AYN/Odin3/AYN-Odin3.conf"
check "SM8750 A830 patch" test -f "${MOD}/mesa/patches/SM8750/0001-add-a830-chip-id.patch"
check "Mesa SM8750 Turnip" test -f "${MOD}/mesa-sm8750/turnip-working/libvulkan_freedreno.so"
check "Mesa SM8750 EGL" test -f "${MOD}/mesa-sm8750/opengl-working/libEGL_mesa.so.0.0.0"

if (( fail > 0 )); then
  echo >&2
  die "${fail} check(s) failed"
fi

log "All ${ok} checks passed (kernel 7.1.4-edge-sm8750; userspace = test preview)"
