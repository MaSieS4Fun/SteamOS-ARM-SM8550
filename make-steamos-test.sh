#!/usr/bin/env bash
# Provisional SM8550 image build — same pipeline as make-steamos-sm8550.sh but pins an
# external kernel tree (default: 7.0.14 from Desktop) instead of external-and-mods/kernel/output.
#
# Gamescope / Mesa / Decky / apply-odin-mods are unchanged (SM8550 gamescope + Thor backlight).
# Plasma desktop (Switch to Desktop, Steam OSK, Return to Gaming) uses the same
# overlay contract as make-steamos-sm8550.sh (verify-qam-image-contract.sh).
#
# Usage: identical flags to make-steamos-sm8550.sh
#   ./make-steamos-test.sh
#   ./make-steamos-test.sh --skip-download --skip-build
#
# Env:
#   KERNEL_OUT          Override kernel pack (must contain boot/KERNEL + modules/*-edge-sm8550/)
#   STEAMOS_SM8550_IMG  Default: ./steamos-test.img (via STEAMOS_TEST_IMG)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/sm8550-kernel-out.sh
source "${ROOT}/scripts/lib/sm8550-kernel-out.sh"

# Fixed path (do not use $HOME — build hosts may have HOME=/home/steamos on a mounted SD).
DEFAULT_KERNEL="/home/masies/Desktop/7.0.14-edge-sm8550-initial kernel"
export KERNEL_OUT="${KERNEL_OUT:-${DEFAULT_KERNEL}}"
export STEAMOS_SM8550_IMG="${STEAMOS_TEST_IMG:-${STEAMOS_SM8550_IMG:-${ROOT}/steamos-test.img}}"

log() { printf '==> [steamos-test] %s\n' "$*"; }
die() { printf 'ERROR: [steamos-test] %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  exec "${ROOT}/make-steamos-sm8550.sh" "$@"
fi

[[ -f "${KERNEL_OUT}/boot/KERNEL" ]] || die "missing ${KERNEL_OUT}/boot/KERNEL (set KERNEL_OUT to your 7.0.14 pack)"

KREL="$(sm8550_kernel_release "${KERNEL_OUT}" 2>/dev/null || true)"
[[ -n "${KREL}" && -d "${KERNEL_OUT}/modules/${KREL}" ]] \
  || die "missing modules under ${KERNEL_OUT}/modules/ (expected *-edge-sm8550)"

log "Test kernel pack: ${KERNEL_OUT}"
log "Kernel release:   ${KREL}"
log "Output image:     ${STEAMOS_SM8550_IMG}"
log "Gamescope:        external-and-mods/gamescope (SM8550 build, Thor backlight — unchanged)"
log "Delegating to make-steamos-sm8550.sh ($*)"

exec env KERNEL_OUT="${KERNEL_OUT}" STEAMOS_SM8550_IMG="${STEAMOS_SM8550_IMG}" \
  "${ROOT}/make-steamos-sm8550.sh" "$@"
