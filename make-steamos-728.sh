#!/usr/bin/env bash
# SM8550 image with kernel 7.2.8-edge-sm8550-kbase (test: visible boot log).
# Same overlay/apply as make-steamos-sm8550.sh (Plasma + Wayland 0.26).
#
# Usage:
#   sudo ./make-steamos-728.sh
#   sudo ./make-steamos-728.sh --skip-download --skip-build
#   SM8550_DEBUG_BOOT=0 sudo ./make-steamos-728.sh   # quiet production
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/sm8550-kernel-out.sh
source "${ROOT}/scripts/lib/sm8550-kernel-out.sh"

DEFAULT_KERNEL="${ROOT}/external-and-mods/kernel/output/7.2.9-edge-sm8550-kbase"
export KERNEL_OUT="${KERNEL_OUT:-${DEFAULT_KERNEL}}"
export STEAMOS_SM8550_IMG="${STEAMOS_728_IMG:-${STEAMOS_SM8550_IMG:-${ROOT}/steamos-sm8550.img}}"
# Test image: visible boot log. Dump units are timeout-capped; efi partsets masked.
export SM8550_DEBUG_BOOT="${SM8550_DEBUG_BOOT:-1}"
export SUSPEND_DEEP="${SUSPEND_DEEP:-1}"
if [[ "${SM8550_DEBUG_BOOT}" == "1" ]]; then
  export CMDLINE_QUIET="${CMDLINE_QUIET:-0}"
  export DEBUG_BOOTLOG="${DEBUG_BOOTLOG:-1}"
else
  export CMDLINE_QUIET="${CMDLINE_QUIET:-1}"
  export DEBUG_BOOTLOG="${DEBUG_BOOTLOG:-0}"
fi

log() { printf '==> [steamos-728] %s\n' "$*"; }
die() { printf 'ERROR: [steamos-728] %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  exec "${ROOT}/make-steamos-sm8550.sh" "$@"
fi

[[ -f "${KERNEL_OUT}/boot/KERNEL" ]] \
  || die "missing ${KERNEL_OUT}/boot/KERNEL"
KREL="$(sm8550_kernel_release "${KERNEL_OUT}" 2>/dev/null || true)"
[[ -n "${KREL}" && -d "${KERNEL_OUT}/modules/${KREL}" ]] \
  || die "missing modules under ${KERNEL_OUT}/modules/"

log "Kernel pack:  ${KERNEL_OUT}"
log "Kernel rel:   ${KREL}"
log "Output image: ${STEAMOS_SM8550_IMG}"
log "Debug boot:   ${SM8550_DEBUG_BOOT}"
log "Delegating to make-steamos-sm8550.sh ($*)"

exec env \
  KERNEL_OUT="${KERNEL_OUT}" \
  STEAMOS_SM8550_IMG="${STEAMOS_SM8550_IMG}" \
  SM8550_DEBUG_BOOT="${SM8550_DEBUG_BOOT}" \
  SUSPEND_DEEP="${SUSPEND_DEEP}" \
  CMDLINE_QUIET="${CMDLINE_QUIET}" \
  DEBUG_BOOTLOG="${DEBUG_BOOTLOG}" \
  "${ROOT}/make-steamos-sm8550.sh" "$@"
