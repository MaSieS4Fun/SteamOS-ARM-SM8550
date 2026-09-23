#!/usr/bin/env bash
# Extract DTB chain blobs from a reference boot/KERNEL → reference/dtb-chain/
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${1:-${ROOT}/reference-boot-partition/KERNEL}"
OUT="${2:-${ROOT}/reference/dtb-chain}"

[[ -f "${KERNEL}" ]] || {
    echo "Missing reference KERNEL: ${KERNEL}" >&2
    exit 1
}
command -v abootimg >/dev/null 2>&1 || {
    echo "Install: sudo apt install abootimg" >&2
    exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

(
    cd "${work}"
    abootimg -x "${KERNEL}" >/dev/null
)

mkdir -p "${OUT}"
python3 - "${work}/zImage" "${OUT}" <<'PY'
import struct, sys
from pathlib import Path

zpath, outdir = Path(sys.argv[1]), Path(sys.argv[2])
data = zpath.read_bytes()
magic = b"\xd0\x0d\xfe\xed"
idx = n = 0
while True:
    i = data.find(magic, idx)
    if i < 0:
        break
    if i + 8 > len(data):
        break
    size = struct.unpack(">I", data[i + 4 : i + 8])[0]
    if not (0x1000 < size < 0x400000 and i + size <= len(data)):
        idx = i + 4
        continue
    blob = data[i : i + size]
    (outdir / f"slot-{n:02d}.dtb").write_bytes(blob)
    n += 1
    idx = i + size
if n == 0:
    sys.exit("No DTBs in zImage")
print(n)
PY

echo "Extracted ${OUT}/slot-*.dtb ($(find "${OUT}" -name 'slot-*.dtb' | wc -l) slots)"
echo "Source: ${KERNEL}"
