#!/usr/bin/env bash
# Assemble slot-NN.dtb chain from compiled kernel DTBs only.
set -euo pipefail

assemble_dtb_chain() {
    local out_dir="$1" kbuild_dtb_dir="${2:-}" _ref_unused="${3:-}"
    local map="${ROOT}/config/dtb-chain.map"
    local ref_dir="${ROOT}/reference/dtb-chain"
    local slot source kbuild_dtb device src_path expected count

    if [[ ! -f "${ref_dir}/slot-00.dtb" ]]; then
        if [[ -f "${ROOT}/reference-boot-partition/KERNEL" ]]; then
            echo "  extracting DTB reference chain..." >&2
            "${ROOT}/scripts/extract-reference-dtb-chain.sh" || return 1
        else
            echo "  MISSING ${ref_dir}/ — run ./scripts/extract-reference-dtb-chain.sh" >&2
            return 1
        fi
    fi

    # shellcheck source=lib/dtb-chain/map.sh
    source "${ROOT}/lib/dtb-chain/map.sh"
    expected="$(dtb_chain_slot_count)"

    [[ -f "${map}" ]] || {
        echo "Missing ${map}" >&2
        return 1
    }
    [[ -d "${kbuild_dtb_dir}" ]] || {
        echo "Missing compiled DTBs: ${kbuild_dtb_dir}" >&2
        return 1
    }

    rm -rf "${out_dir}"
    mkdir -p "${out_dir}"

    echo "==> Assembling ABL DTB chain (${expected} slots)..." >&2

    while IFS='|' read -r slot source kbuild_dtb device; do
        [[ -z "${slot}" || "${slot}" =~ ^# ]] && continue
        slot="$(printf '%02d' "${slot}")"
        src_path=""

        case "${source}" in
            kbuild)
                src_path="${kbuild_dtb_dir}/${kbuild_dtb}"
                echo "  slot-${slot}: ${kbuild_dtb} (${device})" >&2
                ;;
            reference)
                src_path="${ref_dir}/${kbuild_dtb}"
                echo "  slot-${slot}: ${kbuild_dtb} (${device})" >&2
                ;;
            *)
                echo "  unknown source in slot ${slot}: ${source}" >&2
                return 1
                ;;
        esac

        [[ -f "${src_path}" ]] || {
            echo "  MISSING ${src_path}" >&2
            echo "  Run: ./scripts/extract-reference-dtb-chain.sh" >&2
            return 1
        }
        cp -f "${src_path}" "${out_dir}/slot-${slot}.dtb"
    done < "${map}"

    count="$(find "${out_dir}" -name 'slot-*.dtb' | wc -l | tr -d ' ')"
    [[ "${count}" -eq "${expected}" ]] || {
        echo "Incomplete chain: ${count}/${expected} slots" >&2
        return 1
    }

    {
        echo "# DTB chain assembled (reference slot order)"
        echo "# date: $(date -Iseconds)"
        echo "# kbuild: ${kbuild_dtb_dir}"
        echo "# reference: ${ref_dir}"
        echo ""
        ls -1 "${out_dir}"/slot-*.dtb | while read -r f; do
            printf '%s\t%s\n' "$(basename "$f")" "$(sha256sum "$f" | awk '{print $1}')"
        done
    } > "${out_dir}/MANIFEST.txt"

    export DTB_CHAIN_ASSEMBLED_DIR="${out_dir}"
    echo "  ${count} slots → ${out_dir}/" >&2
}
