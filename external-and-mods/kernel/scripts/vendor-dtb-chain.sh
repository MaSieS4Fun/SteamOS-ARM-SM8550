#!/usr/bin/env bash
# LEGACY: optional cache of DTB chain from /boot/KERNEL (not used by default build).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT

: "${CACHE_DIR:=${ROOT}/.cache}"
KERNEL="${1:-${BOOT_KERNEL_PATH:-/boot/KERNEL}}"

[[ -f "${KERNEL}" ]] || {
    echo "Usage: $0 [/boot/KERNEL]" >&2
    exit 1
}

# shellcheck source=lib/dtb-chain/extract.sh
source "${ROOT}/lib/dtb-chain/extract.sh"

dest="${CACHE_DIR}/dtb-chain/reference"
rm -rf "${dest}"
mkdir -p "${dest}"

extract_dtb_chain_from_boot_kernel "${KERNEL}" "${dest}" >/dev/null
echo "Cached: ${dest}/ ($(ls "${dest}"/slot-*.dtb | wc -l | tr -d ' ') slots)"
