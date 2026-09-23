#!/usr/bin/env bash
# Verify this handheld is supported by the SM8550 kernel and show ABL hints.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

read_dt_string() {
    local path="$1"
    [[ -f "${path}" ]] || return 1
    tr -d '\0' < "${path}"
}

model=""
compatible=""
if [[ -d /proc/device-tree ]]; then
    model="$(read_dt_string /proc/device-tree/model 2>/dev/null || true)"
    compatible="$(read_dt_string /proc/device-tree/compatible 2>/dev/null || true)"
fi

echo "==> Device preflight (SM8550 kernel base)"
echo "  model:      ${model:-unknown}"
echo "  compatible: ${compatible:-unknown}"
echo ""

fail=0
warn=0

case "${compatible}" in
    *qcom,sm8750*|*qcom,qcs8750*)
        echo "  ERROR: Odin 3 / SM8750 — this kernel is SM8550 only." >&2
        fail=1
        ;;
    *qcom,sm8650*|*qcom,qcs8650*)
        echo "  ERROR: SM8650 device (Pocket FIT, Pocket S2, …) — NOT supported by this kernel." >&2
        echo "         Fan 100% + black screen is expected with the wrong SoC image." >&2
        fail=1
        ;;
    *qcom,sm8550*|*qcom,qcs8550*)
        echo "  OK   SoC: SM8550 / QCS8550"
        ;;
    *)
        echo "  WARN: SoC not recognized — proceed only if this is an SM8550 handheld." >&2
        warn=1
        ;;
esac

echo ""
echo "  ABL must match your exact model (Set the Device):"
echo ""

_hint() {
    local needle="$1" abl_name="$2" slot="$3"
    if [[ "${compatible}" == *"${needle}"* ]]; then
        echo "  → Your DT says: ${needle}"
        echo "    ABL menu:     ${abl_name}"
        echo "    DTB chain:    slot ${slot}"
        echo ""
    fi
}

_hint "ayn,odin2portal" "AYN Odin 2 Portal" "1"
_hint "ayn,odin2mini"   "AYN Odin 2 Mini"   "3"
_hint "ayn,odin2"       "AYN Odin 2"        "2"
_hint "ayn,thor"        "AYN Thor"          "4"
_hint "retroidpocket,rp6" "Retroid Pocket 6" "5"
_hint "ayaneo,pocketace"  "AYANEO Pocket ACE" "9"
_hint "ayaneo,pocketdmg"  "AYANEO Pocket DMG" "10"
_hint "ayaneo,pocketds"   "AYANEO Pocket DS"  "11"
_hint "ayaneo,pocketevo"  "AYANEO Pocket EVO" "12"
_hint "ayaneo,pocket-s1"  "AYANEO Pocket S 2K" "13"

if [[ "${compatible}" == *"ayn,odin2"* && "${compatible}" != *"portal"* && "${compatible}" != *"mini"* ]]; then
    echo "  CRITICAL: Odin 2 and Odin 2 Mini share hardware IDs."
    echo "            Wrong ABL entry = black screen BEFORE Linux (no boot log)."
    echo ""
fi

echo "  Before reboot after install:"
echo "    1. Hold Vol Down → ABL → Set the Device → exact model above"
echo "    2. Boot Mode = Linux → START"
echo "    3. Never copy boot/KERNEL to another SD without running update.sh there"
echo ""

if [[ "${fail}" -ne 0 ]]; then
    exit 1
fi
exit "${warn}"
