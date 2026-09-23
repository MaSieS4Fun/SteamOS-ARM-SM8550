#!/usr/bin/env bash
# DTB chain map helpers — slot count from config/dtb-chain.map
set -euo pipefail

dtb_chain_slot_count() {
    local map="${ROOT}/config/dtb-chain.map" n=0 slot
    [[ -f "${map}" ]] || {
        echo "11"
        return 0
    }
    while IFS='|' read -r slot _rest; do
        [[ -z "${slot}" || "${slot}" =~ ^# ]] && continue
        n=$((n + 1))
    done < "${map}"
    echo "${n}"
}

dtb_chain_min_slots() {
    echo "${DTB_CHAIN_MIN_SLOTS:-$(dtb_chain_slot_count)}"
}
