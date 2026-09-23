#!/usr/bin/env bash
# Legacy rescue: patch an old boot/KERNEL (root=UUID= only) for UFS testing.
# Normal flow: ./make.sh + update.sh → one KERNEL with root=PARTLABEL=STORAGE — copy, do not patch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UFS_LIB="${UFS_LINUX_DIR:-${ROOT}/lib}/ufs-bootimg.sh"

usage() {
  cat <<EOF
Usage: $0 [KERNEL-in] [KERNEL-out]

Legacy: patch cmdline to root=PARTLABEL=STORAGE (old builds only).

Current builds: use /boot/KERNEL as-is on ROCKNIX — no second file, no patch.

Requires: abootimg
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

src="${1:-/boot/KERNEL}"
dst="${2:-${src}.ufs-patch}"

[[ -f "$UFS_LIB" ]] || {
  echo "Missing ${UFS_LIB}" >&2
  exit 1
}
# shellcheck source=/dev/null
source "$UFS_LIB"

command -v abootimg >/dev/null || { echo "Install: sudo apt install abootimg" >&2; exit 1; }
[[ -f "$src" ]] || { echo "Missing ${src}" >&2; exit 1; }

if read_bootimg_cmdline "$src" | grep -q 'root=PARTLABEL=STORAGE'; then
  echo "KERNEL already uses root=PARTLABEL=STORAGE — copy to ROCKNIX, do not patch."
  exit 0
fi

echo "==> Legacy patch ${src} -> ${dst}"
patch_kernel_for_internal_boot "$src" "$dst"
verify_internal_kernel_cmdline "$dst" || exit 1
echo "OK: $(describe_kernel_root "$dst")"
