#!/usr/bin/env bash
set -euo pipefail

list_dtb_chain_slots() {
    local zimage="$1"
    python3 - "${zimage}" <<'PY'
import struct, sys

def read_cstr(data, off):
    end = data.find(b"\x00", off)
    return data[off:end].decode("utf-8", "replace") if end >= 0 else ""

with open(sys.argv[1], "rb") as f:
    data = f.read()
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
    model = compatible = ""
    off = 0
    while off + 8 <= len(blob):
        length = struct.unpack(">I", blob[off + 4 : off + 8])[0]
        if length < 8 or off + length > len(blob):
            break
        name_off = off + 8
        name_end = blob.find(b"\x00", name_off, off + length)
        name = blob[name_off:name_end].decode("utf-8", "replace") if name_end >= 0 else ""
        val_off = ((name_end + 4) // 4) * 4 if name_end >= 0 else off + 8
        if name == "model" and val_off < off + length:
            model = read_cstr(blob, val_off).strip()
        elif name == "compatible" and val_off < off + length:
            compat = []
            p = val_off
            while p < off + length:
                s = read_cstr(blob, p)
                if not s:
                    break
                compat.append(s)
                p += len(s.encode("utf-8")) + 1
                p = ((p + 3) // 4) * 4
            compatible = ",".join(compat[:4])
        off += length
    hint = compatible or "?"
    for needle in ("ayn,odin2mini", "ayn,odin2portal", "ayn,odin2", "ayn,thor", "retroidpocket,rp6",
                   "ayaneo,pocketace", "ayaneo,pocketdmg", "ayaneo,pocketds", "ayaneo,pocketevo", "ayaneo,pocket-s1"):
        if needle in blob.decode("latin-1", errors="replace"):
            hint = needle
            break
    print(f"{n}\t{size}\t{model or '-'}\t{hint}")
    n += 1
    idx = i + size
PY
}

verify_abl_dtb_chain() {
    local zimage="$1"
    local count missing=0 min_slots

    [[ -f "${zimage}" ]] || return 1

    # shellcheck source=lib/dtb-chain/map.sh
    source "${ROOT}/lib/dtb-chain/map.sh"
    min_slots="$(dtb_chain_min_slots)"

    count="$(python3 - "${zimage}" <<'PY'
import struct, sys
with open(sys.argv[1], "rb") as f:
    data = f.read()
magic = b"\xd0\x0d\xfe\xed"
idx = n = 0
while True:
    i = data.find(magic, idx)
    if i < 0: break
    if i + 8 <= len(data):
        size = struct.unpack(">I", data[i + 4 : i + 8])[0]
        if 0x1000 < size < 0x400000 and i + size <= len(data):
            n += 1
            idx = i + size
            continue
    idx = i + 4
print(n)
PY
)"

    echo "==> ABL chain verification (${count} DTBs)" >&2
    [[ "${count}" -ge "${min_slots}" ]] || {
        echo "  ERROR: expected ≥${min_slots} DTBs, found ${count}" >&2
        return 1
    }

    echo "  Slots in zImage:" >&2
    while IFS=$'\t' read -r n _ model hint; do
        [[ -n "${n}" ]] || continue
        echo "    [${n}] ${hint} ${model:+(model=${model})}" >&2
    done < <(list_dtb_chain_slots "${zimage}")

    for needle in "qcom,qcs8550-aim300" "qcom,qcs8550-aim300-aiot"; do
        if list_dtb_chain_slots "${zimage}" | grep -qF "${needle}"; then
            echo "  ERROR: chain includes ${needle} — breaks Mini/Portal/Thor selection" >&2
            missing=1
        fi
    done

    for needle in "ayn,odin2mini" "ayn,odin2portal" "ayn,odin2" "ayn,thor" "retroidpocket,rp6"         "ayaneo,pocketace" "ayaneo,pocketdmg" "ayaneo,pocketds" "ayaneo,pocketevo" "ayaneo,pocket-s1"; do
        if ! list_dtb_chain_slots "${zimage}" | grep -qF "${needle}"; then
            echo "  MISSING compatible: ${needle}" >&2
            missing=1
        fi
    done

    [[ "${missing}" -eq 0 ]] || return 1
    verify_reference_chain_order "${zimage}" || return 1
    echo "  OK — ABL picks DTB by device index (reference slot order)" >&2
    echo "  Set ROCKNIX-ABL → Set the Device → your exact model" >&2
}

verify_reference_chain_order() {
    local zimage="$1"
    local -a expect=(
        "1:ayn,odin2portal"
        "2:ayn,odin2"
        "3:ayn,odin2mini"
        "4:ayn,thor"
        "5:retroidpocket,rp6"
        "9:ayaneo,pocketace"
        "10:ayaneo,pocketdmg"
        "11:ayaneo,pocketds"
        "12:ayaneo,pocketevo"
        "13:ayaneo,pocket-s1"
    )
    local line n hint pair

    while IFS=$'\t' read -r n _ _ hint; do
        [[ -n "${n}" ]] || continue
        for pair in "${expect[@]}"; do
            [[ "${pair%%:*}" == "${n}" ]] || continue
            if [[ "${hint}" != *"${pair#*:}"* ]]; then
                echo "  ERROR: DTB slot ${n} is '${hint}' — expected ${pair#*:} (reference index)" >&2
                return 1
            fi
        done
    done < <(list_dtb_chain_slots "${zimage}")
    return 0
}

assert_no_efi_devicetree() {
    local cmdline="${1:-}"
    if [[ "${cmdline}" == *"devicetree="* ]] || [[ "${cmdline}" == *"dtb="* ]]; then
        echo "ERROR: cmdline includes devicetree/dtb — ABL boot must not pin DTB via EFI." >&2
        return 1
    fi
    return 0
}
