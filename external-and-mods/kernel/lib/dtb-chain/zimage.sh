#!/usr/bin/env bash
# gzip(Image) + DTB chain — ABL layout (no EFI devicetree)
set -euo pipefail

count_dtbs_in_zimage() {
    local zimage="$1"
    python3 - "${zimage}" <<'PY'
import struct, sys
with open(sys.argv[1], "rb") as f:
    data = f.read()
magic = b"\xd0\x0d\xfe\xed"
count = idx = 0
while True:
    i = data.find(magic, idx)
    if i < 0:
        break
    if i + 8 <= len(data):
        size = struct.unpack(">I", data[i + 4 : i + 8])[0]
        if 0x1000 < size < 0x400000 and i + size <= len(data):
            count += 1
            idx = i + size
            continue
    idx = i + 4
print(count)
PY
}

build_zimage_abl() {
    local image="$1" chain_dir="$2" dest_zimage="$3"
    local tmp="${dest_zimage}.part"
    local -a dtbs=() dtb count

    [[ -f "${image}" ]] || {
        echo "Missing Image: ${image}" >&2
        return 1
    }
    [[ -d "${chain_dir}" ]] || {
        echo "Missing DTB chain: ${chain_dir}" >&2
        return 1
    }

    shopt -s nullglob
    dtbs=("${chain_dir}"/slot-*.dtb)
    shopt -u nullglob

    [[ ${#dtbs[@]} -gt 0 ]] || {
        echo "No slot-*.dtb in ${chain_dir}" >&2
        return 1
    }

    echo "==> ABL zImage: gzip(Image) + ${#dtbs[@]} DTBs..." >&2
    rm -f "${tmp}" "${dest_zimage}"
    gzip -c -n "${image}" > "${tmp}"
    for dtb in "${dtbs[@]}"; do
        echo "  + $(basename "${dtb}")" >&2
        cat "${dtb}" >> "${tmp}"
    done
    mv -f "${tmp}" "${dest_zimage}"

    count="$(count_dtbs_in_zimage "${dest_zimage}")"
    [[ "${count}" -eq ${#dtbs[@]} ]] || {
        echo "DTB verification failed (expected ${#dtbs[@]}, found ${count})" >&2
        return 1
    }
    export ABL_EMBEDDED_DTB_COUNT="${count}"
    echo "  zImage $(du -h "${dest_zimage}" | cut -f1), ${count} embedded DTBs" >&2
}
