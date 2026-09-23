#!/usr/bin/env bash
# Extract DTB chain from local /boot/KERNEL zImage → slot-NN.dtb (build cache only).
set -euo pipefail

extract_dtb_chain_from_zimage() {
    local zimage="$1" dest_dir="$2"

    [[ -f "${zimage}" ]] || {
        echo "Missing zImage: ${zimage}" >&2
        return 1
    }
    mkdir -p "${dest_dir}"

    python3 - "${zimage}" "${dest_dir}" <<'PY'
import hashlib, struct, sys
from pathlib import Path

zpath, outdir = Path(sys.argv[1]), Path(sys.argv[2])
data = zpath.read_bytes()
magic = b"\xd0\x0d\xfe\xed"
idx = n = 0
manifest = []

while True:
    i = data.find(magic, idx)
    if i < 0:
        break
    if i + 8 <= len(data):
        size = struct.unpack(">I", data[i + 4 : i + 8])[0]
        if 0x1000 < size < 0x400000 and i + size <= len(data):
            blob = data[i : i + size]
            slot = outdir / f"slot-{n:02d}.dtb"
            slot.write_bytes(blob)
            hint = ""
            for needle in (
                b"ayn,odin2mini", b"ayn,odin2portal", b"ayn,odin2", b"ayn,thor",
                b"retroidpocket,rp6", b"qcom,qcs8550",
            ):
                if needle in blob:
                    hint = needle.decode()
                    break
            manifest.append((n, size, hint, hashlib.sha256(blob).hexdigest()[:16]))
            n += 1
            idx = i + size
            continue
    idx = i + 4

if n == 0:
    sys.stderr.write("No DTBs found in zImage\n")
    sys.exit(1)

lines = [
    "# DTB chain extract",
    f"# source: {zpath}",
    f"# count: {n}",
    "",
    "slot\tsize\thint\tsha256_16",
]
for row in manifest:
    lines.append(f"{row[0]}\t{row[1]}\t{row[2]}\t{row[3]}")
(outdir / "MANIFEST.txt").write_text("\n".join(lines) + "\n")
print(n)
PY
}

extract_dtb_chain_from_boot_kernel() {
    local kernel_blob="$1" dest_dir="$2" work count min_slots

    # shellcheck source=lib/dtb-chain/map.sh
    source "${ROOT}/lib/dtb-chain/map.sh"
    min_slots="$(dtb_chain_min_slots)"

    kernel_blob="$(readlink -f "${kernel_blob}")"
    [[ -f "${kernel_blob}" ]] || {
        echo "Missing boot KERNEL: ${kernel_blob}" >&2
        return 1
    }
    command -v abootimg >/dev/null 2>&1 || {
        echo "Install: sudo apt install abootimg" >&2
        return 1
    }

    work="$(mktemp -d)"
    (
        cd "${work}"
        abootimg -x "${kernel_blob}" >/dev/null 2>&1
    )
    [[ -f "${work}/zImage" ]] || {
        rm -rf "${work}"
        echo "abootimg failed on ${kernel_blob}" >&2
        return 1
    }

    echo "==> Caching DTB chain from ${kernel_blob}..." >&2
    count="$(extract_dtb_chain_from_zimage "${work}/zImage" "${dest_dir}")"
    rm -rf "${work}"
    echo "  ${count} slot(s) → ${dest_dir}/" >&2
    export DTB_CHAIN_REFERENCE_COUNT="${count}"
    [[ "${count}" -ge "${min_slots}" ]] || {
        echo "Expected ≥${min_slots} DTBs; found ${count}" >&2
        return 1
    }
    echo "${count}"
}

# Back-compat alias
extract_dtb_chain_from_rocknix_kernel() {
    extract_dtb_chain_from_boot_kernel "$@"
}

resolve_local_boot_kernel() {
    local candidate
    if [[ -n "${BOOT_KERNEL_PATH:-}" && -f "${BOOT_KERNEL_PATH}" ]]; then
        readlink -f "${BOOT_KERNEL_PATH}"
        return 0
    fi
    for candidate in /boot/KERNEL; do
        [[ -f "${candidate}" ]] && readlink -f "${candidate}" && return 0
    done
    return 1
}

resolve_rocknix_kernel_path() {
    resolve_local_boot_kernel
}

_ref_chain_slot_count() {
    local dir="$1" n=0 f
    shopt -s nullglob
    for f in "${dir}"/slot-*.dtb; do
        [[ -f "${f}" ]] && n=$((n + 1))
    done
    shopt -u nullglob
    echo "${n}"
}

ensure_reference_dtb_chain() {
    local ref_dir="${DTB_REFERENCE_DIR:-${CACHE_DIR}/dtb-chain/reference}"
    local kernel n min_slots

    # shellcheck source=lib/dtb-chain/map.sh
    source "${ROOT}/lib/dtb-chain/map.sh"
    min_slots="$(dtb_chain_min_slots)"

    mkdir -p "${ref_dir}"
    n="$(_ref_chain_slot_count "${ref_dir}")"

    if [[ "${n}" -ge "${min_slots}" ]]; then
        echo "==> DTB chain cache: ${n} slots" >&2
        DTB_REFERENCE_DIR="${ref_dir}"
        export DTB_REFERENCE_DIR
        return 0
    fi

    kernel="$(resolve_local_boot_kernel)" || {
        echo "Need ${BOOT_KERNEL_PATH:-/boot/KERNEL} on this system for DTB chain base slots." >&2
        echo "  Build on the handheld, or copy a working KERNEL to /boot/ first." >&2
        return 1
    }

    extract_dtb_chain_from_boot_kernel "${kernel}" "${ref_dir}" >/dev/null
    DTB_REFERENCE_DIR="${ref_dir}"
    export DTB_REFERENCE_DIR
}
