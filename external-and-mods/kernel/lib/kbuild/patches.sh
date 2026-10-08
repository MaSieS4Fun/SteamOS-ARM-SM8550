#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/kbuild/patches-72.sh
source "${ROOT}/lib/kbuild/patches-72.sh"

_patch_is_skipped() {
    local base="$1" deny_list="${2:-${PATCH_SKIP:-}}" deny pat
    [[ -z "${deny_list}" ]] && return 1
    IFS=',' read -ra deny <<< "${deny_list}"
    for pat in "${deny[@]}"; do
        pat="${pat// /}"
        [[ -z "${pat}" ]] && continue
        [[ "${base}" == *"${pat}"* ]] && return 0
    done
    return 1
}

_ensure_dtb_in_makefile() {
    local mk="$1" dtb="$2"
    grep -q "${dtb}" "${mk}" && return 0
    if grep -q 'qcs8550-ayn-odin2portal\.dtb' "${mk}"; then
        sed -i "/qcs8550-ayn-odin2portal\.dtb/a dtb-\$(CONFIG_ARCH_QCOM)\t+= ${dtb}" "${mk}"
    elif grep -q 'qcs8550-ayn-odin2mini\.dtb' "${mk}"; then
        sed -i "/qcs8550-ayn-odin2mini\.dtb/a dtb-\$(CONFIG_ARCH_QCOM)\t+= ${dtb}" "${mk}"
    elif grep -q 'qcs8550-ayn-odin2\.dtb' "${mk}"; then
        sed -i "/qcs8550-ayn-odin2\.dtb/a dtb-\$(CONFIG_ARCH_QCOM)\t+= ${dtb}" "${mk}"
    else
        sed -i "/qcs8550-aim300-aiot\.dtb/a dtb-\$(CONFIG_ARCH_QCOM)\t+= ${dtb}" "${mk}"
    fi
}

_verify_masi_dtb_sources() {
    local src_dir="$1" devices="${ROOT}/config/devices.conf" mk
    local line dtb dts missing=0

    mk="${src_dir}/arch/arm64/boot/dts/qcom/Makefile"
    [[ -f "${mk}" ]] || {
        echo "ERROR: missing ${mk} after patches" >&2
        return 1
    }

    while IFS='|' read -r _id dtb _label; do
        [[ -z "${_id:-}" || "${_id}" =~ ^# ]] && continue
        [[ -z "${dtb:-}" || "${dtb}" == DTB_FILENAME ]] && continue
        [[ "${dtb}" == *.dtb ]] || continue
        dts="${dtb%.dtb}.dts"
        if [[ ! -f "${src_dir}/arch/arm64/boot/dts/qcom/${dts}" ]]; then
            echo "ERROR: missing device tree source ${dts} (required for ${dtb})" >&2
            missing=$((missing + 1))
            continue
        fi
        if ! grep -q "${dtb}" "${mk}"; then
            echo "  FIX  adding ${dtb} to dts/qcom/Makefile" >&2
            _ensure_dtb_in_makefile "${mk}" "${dtb}"
        fi
    done < "${devices}"

    if [[ -f "${ROOT}/config/dtb-chain.map" ]]; then
        while IFS='|' read -r _slot source kbuild_dtb _device; do
            [[ -z "${source:-}" || "${source}" =~ ^# ]] && continue
            [[ "${source}" == "kbuild" && "${kbuild_dtb}" == *.dtb ]] || continue
            dts="${kbuild_dtb%.dtb}.dts"
            if [[ ! -f "${src_dir}/arch/arm64/boot/dts/qcom/${dts}" ]]; then
                echo "ERROR: missing DTS ${dts} (dtb-chain.map kbuild ${kbuild_dtb})" >&2
                missing=$((missing + 1))
                continue
            fi
            if ! grep -q "${kbuild_dtb}" "${mk}"; then
                echo "  FIX  adding ${kbuild_dtb} to dts/qcom/Makefile" >&2
                _ensure_dtb_in_makefile "${mk}" "${kbuild_dtb}"
            fi
        done < "${ROOT}/config/dtb-chain.map"
    fi

    [[ "${missing}" -eq 0 ]] || return 1
}

_apply_pending_ayn_dtb_patches() {
    local src_dir="$1" patch_dir="$2" patch base applied=0
    shopt -s nullglob
    for patch in "${patch_dir}"/00*-arm64-dts-qcom-Add-AYN-*.patch; do
        base="$(basename "${patch}")"
        if patch -p1 --dry-run -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
            echo "  APPLY ${base}" >&2
            patch -p1 -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1 && applied=$((applied + 1))
        fi
    done
    shopt -u nullglob
    [[ "${applied}" -gt 0 ]]
}

# Armbian dts-directories: copy dt/*.dts{,i} as-is (7.2+ has no Add-AYN patches).
apply_armbian_board_dts() {
    local src_dir="$1" patch_dir="$2"
    local dt_dir="${patch_dir}/dt"
    local qcom="${src_dir}/arch/arm64/boot/dts/qcom"
    local mk="${qcom}/Makefile"
    local f base dtb copied=0

    [[ -d "${dt_dir}" && -f "${mk}" ]] || return 0
    shopt -s nullglob
    for f in "${dt_dir}"/*.dts "${dt_dir}"/*.dtsi; do
        [[ -f "${f}" ]] || continue
        base="$(basename "${f}")"
        cp -f "${f}" "${qcom}/${base}"
        copied=$((copied + 1))
        if [[ "${base}" == *.dts ]]; then
            dtb="${base%.dts}.dtb"
            _ensure_dtb_in_makefile "${mk}" "${dtb}"
        fi
    done
    shopt -u nullglob
    if [[ "${copied}" -gt 0 ]]; then
        echo "  OK   Armbian dt/: ${copied} board trees" >&2
    fi
}

apply_armbian_patches() {
    local src_dir="$1" patch_set="$2" kernel_ver="$3"
    local patch_dir failed=0 applied=0 skipped=0 denied=0 list_hash
    local stamp="${src_dir}/.masi-patched-${patch_set}-ok"
    patch_dir="$(fetch_armbian_patches "${patch_set}")"
    mkdir -p "${OUTPUT_DIR}"
    local log="${OUTPUT_DIR}/patch-log-${patch_set}.txt"
    : > "${log}"
    list_hash="$(_armbian_patch_list_stamp "${patch_dir}")"

    if [[ -f "${stamp}" && "$(tr -d '[:space:]' < "${stamp}")" == "${list_hash}" ]]; then
        apply_masi_extra_dts "${src_dir}"
        apply_masi_ayaneo_dts "${src_dir}" || true
        apply_masi_haptics_dtsi "${src_dir}" || true
        apply_masi_thor_touch_dts "${src_dir}" || true
        apply_masi_gyro_fastrpc_dts "${src_dir}" || true
        apply_masi_kernel_patches "${src_dir}" || true
        verify_masi_haptics_stack "${src_dir}" || return 1
        verify_masi_thor_touch_dts "${src_dir}" || return 1
        verify_masi_gyro_fastrpc_dts "${src_dir}" || return 1
        verify_masi_gmu_bw_vote_stack "${src_dir}" || return 1
        verify_masi_rsinput_suspend_stack "${src_dir}" || return 1
        verify_masi_armada_energy_stack "${src_dir}" || return 1
        if _kernel_is_72_series "${kernel_ver}"; then
            bridge_72_fixup_compile_apis "${src_dir}" || return 1
            verify_sm8550_72_compile "${src_dir}" || return 1
        fi
        echo "==> Patches ${patch_set} already applied (linux-${kernel_ver})" >&2
        return 0
    fi

    reset_kernel_source_from_tarball "${kernel_ver}" || return 1

    echo "==> Applying patches ${patch_set} (linux-${kernel_ver})" >&2
    local patch base fail_log
    while IFS= read -r patch; do
        [[ -n "${patch}" ]] || continue
        base="$(basename "${patch}")"
        if _patch_is_skipped "${base}" "${PATCH_SKIP:-}"; then
            echo "  DENY ${base}" >&2
            denied=$((denied + 1))
            continue
        fi
        if patch -p1 --dry-run -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
            patch -p1 -d "${src_dir}" -f < "${patch}" >> "${log}" 2>&1 && {
                echo "  OK   ${base}" >&2
                applied=$((applied + 1))
            } || { echo "  FAIL ${base}" >&2; failed=$((failed + 1)); }
        elif patch -p1 --dry-run -R -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
            echo "  SKIP ${base}" >&2
            skipped=$((skipped + 1))
        elif _kernel_is_72_series "${kernel_ver}" \
            && _armbian_patch_bridge_72 "${base}" "${src_dir}" "${patch_dir}"; then
            echo "  OK   ${base} (7.2 bridge)" >&2
            applied=$((applied + 1))
        else
            echo "  FAIL ${base}" >&2
            fail_log="${OUTPUT_DIR}/patch-fail-${base}.txt"
            patch -p1 --dry-run -d "${src_dir}" -f < "${patch}" > "${fail_log}" 2>&1 || true
            failed=$((failed + 1))
        fi
    done < <(_armbian_patch_paths_to_apply "${patch_dir}")

    echo "==> Patches: ${applied} ok, ${skipped} skip, ${denied} deny, ${failed} fail" >&2

    if _kernel_is_72_series "${kernel_ver}"; then
        apply_sm8550_72_patch_bridges "${src_dir}" "${patch_dir}" "${kernel_ver}" || true
    fi

    echo "==> Armbian board DTS (dt/)..." >&2
    apply_armbian_board_dts "${src_dir}" "${patch_dir}" || true
    echo "==> Ensuring AYN device tree patches..." >&2
    _apply_pending_ayn_dtb_patches "${src_dir}" "${patch_dir}" || true
    apply_masi_extra_dts "${src_dir}" || true
    apply_masi_ayaneo_dts "${src_dir}" || failed=1
    apply_masi_haptics_dtsi "${src_dir}" || failed=1
    apply_masi_thor_touch_dts "${src_dir}" || failed=1
    apply_masi_gyro_fastrpc_dts "${src_dir}" || failed=1
    apply_masi_kernel_patches "${src_dir}" || failed=1
        verify_masi_thor_panel_reset "${src_dir}" || failed=1
        verify_masi_thor_touch_dts "${src_dir}" || failed=1
        verify_masi_gyro_fastrpc_dts "${src_dir}" || failed=1
        verify_masi_haptics_stack "${src_dir}" || failed=1
        verify_masi_suspend_stack "${src_dir}" || failed=1
        verify_masi_armada_energy_stack "${src_dir}" || failed=1
        _verify_masi_dtb_sources "${src_dir}" || failed=1

    if _kernel_is_72_series "${kernel_ver}"; then
        bridge_72_fixup_compile_apis "${src_dir}" || return 1
        verify_sm8550_72_compile "${src_dir}" || return 1
    fi

    if [[ "${failed}" -gt 0 ]] && _verify_masi_dtb_sources "${src_dir}" 2>/dev/null; then
        local non_dtb_fail=0 f base
        shopt -s nullglob
        for f in "${OUTPUT_DIR}"/patch-fail-*.txt; do
            base="$(basename "${f}" .txt)"
            base="${base#patch-fail-}"
            [[ "${base}" == *arm64-dts-qcom-Add-AYN-* ]] || non_dtb_fail=1
        done
        shopt -u nullglob
        [[ "${non_dtb_fail}" -eq 0 ]] && failed=0
    fi

    if [[ "${failed}" -gt 0 ]]; then
        if _kernel_is_72_series "${kernel_ver}" && verify_sm8550_72_required "${src_dir}"; then
            echo "  7.2 bridges OK — continuing (Armbian hunks rebased on linux-7.2.x)" >&2
            failed=0
        fi
    fi

    if [[ "${failed}" -gt 0 ]]; then
        echo "BUILD ABORTED — see ${log} and patch-fail-*.txt in ${OUTPUT_DIR}/" >&2
        echo "  Tip: rm -rf ${src_dir} .cache/armbian-patches/${patch_set} if inconsistent." >&2
        [[ "${PATCH_POLICY}" == "tolerant" ]] && return 0
        return 1
    fi

    echo "${list_hash}" > "${stamp}"
}

# HV haptics + gamepad rumble (Batocera-derived DT fragment for all AYN SM8550 boards).
apply_masi_haptics_dtsi() {
    local src_dir="$1"
    local dtsi="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi"
    local frag="${ROOT}/patches/masi/qcs8550-ayn-haptics.dtsi.frag"
    local tmp marker='&pm8550b_eusb2_repeater'

    [[ -f "${dtsi}" && -f "${frag}" ]] || return 0
    if grep -q 'qcom,hv-haptics' "${dtsi}"; then
        # of_property_read_bool: property presence selects ERM (hard).
        # A u32 assignment is invalid YAML; deleting the property used to
        # force LRA/sine (soft) and killed rumble strength.
        if grep -qE 'qcom,use-erm[[:space:]]*=' "${dtsi}"; then
            sed -i 's/qcom,use-erm[[:space:]]*=.*/qcom,use-erm;/' "${dtsi}"
            echo "  FIX  MaSi haptics DT: qcom,use-erm boolean (ERM/hard)" >&2
        elif ! grep -q 'qcom,use-erm' "${dtsi}"; then
            python3 - "${dtsi}" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
old = "\t\tqcom,vmax-mv = <5000>;\n\t\tqcom,brake-mode"
new = "\t\tqcom,vmax-mv = <5000>;\n\t\tqcom,use-erm;\n\t\tqcom,brake-mode"
if old not in t:
    raise SystemExit(1)
p.write_text(t.replace(old, new, 1))
PY
            echo "  FIX  MaSi haptics DT: enable ERM/hard channel" >&2
        else
            echo "  SKIP MaSi haptics DT (already present)" >&2
        fi
        return 0
    fi
    if ! grep -q "${marker}" "${dtsi}"; then
        echo "  FAIL MaSi haptics DT: marker ${marker} not in ${dtsi}" >&2
        return 1
    fi

    if ! grep -q 'dt-bindings/input/qcom,hv-haptics.h' "${dtsi}"; then
        sed -i '/dt-bindings\/leds\/common.h/a #include <dt-bindings/input/qcom,hv-haptics.h>' "${dtsi}"
    fi

    tmp="$(mktemp)"
    awk -v marker="${marker}" -v frag="${frag}" '
        $0 ~ marker && !done {
            while ((getline line < frag) > 0)
                print line
            close(frag)
            done = 1
        }
        { print }
    ' "${dtsi}" > "${tmp}"
    mv "${tmp}" "${dtsi}"
    echo "  OK   MaSi qcs8550-ayn-common haptics DT" >&2
}

# ADSP FastRPC SensorsPD + remote heap for Qualcomm Sensor Core gyro (AYN SM8550).
# Common: heap + PDR only. Thor: also qcom,pd-type banks (Batocera layout).
apply_masi_gyro_fastrpc_dts() {
    local src_dir="$1"
    local frag="${ROOT}/patches/masi/qcs8550-ayn-gyro-fastrpc.dtsi.frag"
    local thor_frag="${ROOT}/patches/masi/qcs8550-ayn-thor-gyro-fastrpc-pd.dtsi.frag"
    local dtsi="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi"
    local thor="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-thor.dts"

    [[ -f "${frag}" ]] || return 0

    if [[ -f "${dtsi}" ]]; then
        if grep -q 'qcom,fastrpc-adsp-sensors-pdr' "${dtsi}"; then
            # Migrate older common frags that forced pd-type on all AYN boards.
            if grep -qE 'qcom,pd-type\s*=' "${dtsi}"; then
                python3 - "${dtsi}" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
# Drop compute-cb pd-type overrides from the MaSi gyro block only.
text2 = re.sub(
    r"\n\t\tcompute-cb@[0-9]+ \{[^}]*qcom,pd-type[^}]*\};\n",
    "\n",
    text,
    flags=re.S,
)
if text2 != text:
    open(path, "w", encoding="utf-8").write(text2)
    print("  OK   stripped PD-type from common DT (Odin2-safe)", file=__import__("sys").stderr)
else:
    print("  SKIP common PD-type strip (no compute-cb overrides matched)", file=__import__("sys").stderr)
PY
            else
                echo "  SKIP MaSi gyro FastRPC DT (already present)" >&2
            fi
        else
            cat "${frag}" >> "${dtsi}"
            echo "  OK   MaSi gyro FastRPC DT (common heap+PDR)" >&2
        fi
    fi

    if [[ -f "${thor}" && -f "${thor_frag}" ]]; then
        if ! grep -qE 'qcom,pd-type\s*=' "${thor}"; then
            cat "${thor_frag}" >> "${thor}"
            echo "  OK   Thor FastRPC PD-type banks" >&2
        else
            echo "  SKIP Thor FastRPC PD-type (already present)" >&2
        fi
    fi

    # Thor stock Android ADSP with SH5001 is split ELF (.mdt + .bXX), not .mbn.
    if [[ -f "${thor}" ]] && grep -q 'ayn/thor/adsp\.mbn' "${thor}"; then
        sed -i \
            -e 's|qcom/sm8550/ayn/thor/adsp\.mbn|qcom/sm8550/ayn/thor/adsp.mdt|g' \
            -e 's|qcom/sm8550/ayn/thor/adsp_dtb\.mbn|qcom/sm8550/ayn/thor/adsp_dtb.mdt|g' \
            "${thor}"
        echo "  OK   Thor ADSP firmware-name → adsp.mdt (SH5001)" >&2
    fi

    return 0
}

verify_masi_gyro_fastrpc_dts() {
    local src_dir="$1"
    local dtsi="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi"
    local thor="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-thor.dts"

    [[ -f "${dtsi}" ]] || return 0

    echo "==> Verify gyro FastRPC DT" >&2
    if ! grep -q 'qcom,fastrpc-adsp-sensors-pdr' "${dtsi}"; then
        echo "  FAIL missing qcom,fastrpc-adsp-sensors-pdr in common DT" >&2
        return 1
    fi
    if ! grep -q 'adsp_rpc_remote_heap_mem' "${dtsi}"; then
        echo "  FAIL missing adsp_rpc_remote_heap_mem" >&2
        return 1
    fi
    if grep -qE 'qcom,pd-type\s*=' "${dtsi}"; then
        echo "  FAIL common DT still forces qcom,pd-type (Odin2 must use first-free CBs)" >&2
        return 1
    fi
    if [[ -f "${thor}" ]]; then
        if ! grep -q 'ayn/thor/adsp\.mdt' "${thor}"; then
            echo "  FAIL Thor still points at adsp.mbn (need .mdt for SH5001)" >&2
            return 1
        fi
        if ! grep -qE 'qcom,pd-type\s*=' "${thor}"; then
            echo "  FAIL Thor missing qcom,pd-type FastRPC banks" >&2
            return 1
        fi
    fi
    echo "  OK   SensorsPD PDR + Thor pd-type/adsp.mdt" >&2
    return 0
}

# Thor main (top) AMOLED touch: Armbian DT omits axis remap; bottom panel already has it.
apply_masi_thor_touch_dts() {
    local src_dir="$1"
    local dts="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-thor.dts"

    [[ -f "${dts}" ]] || return 0

    python3 - "${dts}" <<'PY'
import re
import sys

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
changed = False


def patch_touch_node(lines, compatible, prop_lines):
    global changed
    key = f'compatible = "{compatible}"'
    for i, line in enumerate(lines):
        if key not in line:
            continue
        end = i + 1
        while end < len(lines) and not re.match(r"\t\};", lines[end]):
            end += 1
        if end >= len(lines):
            return lines
        block = "".join(lines[i : end + 1])
        to_insert = []
        for prop in prop_lines:
            needle = prop.strip().rstrip(";")
            if needle in block:
                continue
            to_insert.append(prop if prop.endswith("\n") else prop + "\n")
        if to_insert:
            lines[end:end] = to_insert
            changed = True
        return lines
    return lines


lines = patch_touch_node(
    lines,
    "focaltech,ft5426",
    [
        "\t\ttouchscreen-swapped-x-y;\n",
        "\t\ttouchscreen-inverted-x;\n",
        '\t\tlabel = "top_touchscreen";\n',
    ],
)
lines = patch_touch_node(
    lines,
    "focaltech,ft5452",
    [
        "\t\tedt,retain-power-in-suspend;\n",
        '\t\tlabel = "bottom_touchscreen";\n',
    ],
)

text = "".join(lines)
if not re.search(
    r'compatible\s*=\s*"focaltech,ft5426"[\s\S]{0,800}?touchscreen-swapped-x-y',
    text,
):
    sys.stderr.write("MaSi Thor touch: ft5426 missing axis remap\n")
    sys.exit(1)

if changed:
    open(path, "w", encoding="utf-8").write(text)

sys.exit(0)
PY

    echo "  OK   MaSi Thor touch DTS (labels, axis remap, retain-power)" >&2
}

# Back-compat alias for scripts/docs that still reference the old hook name.
apply_masi_thor_top_touch_orientation() {
    apply_masi_thor_touch_dts "$@"
}

verify_masi_thor_touch_dts() {
    local src_dir="$1"
    local dts="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-thor.dts"

    [[ -f "${dts}" ]] || return 0

    echo "==> Verify Thor touch DTS" >&2

    if ! awk '
        /compatible = "focaltech,ft5426"/ { in_top=1; ok_top=0 }
        in_top && /touchscreen-swapped-x-y/ { ok_top=1 }
        in_top && /touchscreen-inverted-x/ { ok_top=1 }
        in_top && /label = "top_touchscreen"/ { lbl_top=1 }
        in_top && /^[[:space:]]*\};[[:space:]]*$/ { in_top=0 }
        /compatible = "focaltech,ft5452"/ { in_bot=1; ok_bot=0 }
        in_bot && /edt,retain-power-in-suspend/ { ok_bot=1 }
        in_bot && /label = "bottom_touchscreen"/ { lbl_bot=1 }
        in_bot && /^[[:space:]]*\};[[:space:]]*$/ { in_bot=0 }
        END {
            exit((ok_top && ok_bot && lbl_top && lbl_bot) ? 0 : 1)
        }
    ' "${dts}"; then
        echo "  FAIL Thor touch DTS incomplete (top remap/label or bottom retain-power/label)" >&2
        return 1
    fi

    echo "  OK   top_touchscreen + bottom_touchscreen nodes" >&2
    return 0
}

verify_masi_thor_top_touch_orientation() {
    verify_masi_thor_touch_dts "$@"
}

ensure_masi_suspend_patches() {
    local patch_dir="${ROOT}/patches/masi"
    local p need_fetch=0

    [[ "${SUSPEND_DEEP_PATCHES:-1}" == "0" ]] && return 0

    for p in \
        1006-scsi-ufs-drain-relink-completions-out-of-band-pm.patch \
        1007-scsi-ufs-qcom-balance-irq-on-host-reset-error.patch \
        1008-scsi-ufs-qcom-propagate-hibern8-exit-failure-clk-scale.patch \
        1009-scsi-ufs-qcom-auto-hibern8-clk-gating-collision.patch \
        1010-scsi-ufs-qcom-keep-mphy-powered-on-hibern8-park.patch \
        1011-ufs-qcom-qmp-rx-linecfg-link-startup.patch \
        1012-mailbox-qcom-ipcc-remove-irqf-no-suspend.patch \
        1013-thermal-qcom-tsens-skip-ayn-thor-uplow-wake-irq.patch \
        1045-scsi-ufs-recover-hibern8-enter-clk-gating.patch \
        1046-scsi-ufs-hold-clk-gating-across-system-pm.patch; do
        [[ -f "${patch_dir}/${p}" ]] || need_fetch=1
    done
    [[ "${need_fetch}" -eq 0 ]] && return 0

    echo "==> Fetching ROCKNIX suspend patches (1006–1013)…" >&2
    if command -v python3 >/dev/null 2>&1; then
        python3 "${ROOT}/scripts/fetch-rocknix-suspend-patches.py"
    elif [[ -x "${ROOT}/scripts/fetch-rocknix-suspend-patches.sh" ]]; then
        "${ROOT}/scripts/fetch-rocknix-suspend-patches.sh"
    else
        echo "ERROR: missing 1006/1011 — install python3 or run scripts/fetch-rocknix-suspend-patches.py" >&2
        return 1
    fi

    for p in \
        1006-scsi-ufs-drain-relink-completions-out-of-band-pm.patch \
        1007-scsi-ufs-qcom-balance-irq-on-host-reset-error.patch \
        1008-scsi-ufs-qcom-propagate-hibern8-exit-failure-clk-scale.patch \
        1009-scsi-ufs-qcom-auto-hibern8-clk-gating-collision.patch \
        1010-scsi-ufs-qcom-keep-mphy-powered-on-hibern8-park.patch \
        1011-ufs-qcom-qmp-rx-linecfg-link-startup.patch \
        1012-mailbox-qcom-ipcc-remove-irqf-no-suspend.patch \
        1013-thermal-qcom-tsens-skip-ayn-thor-uplow-wake-irq.patch \
        1045-scsi-ufs-recover-hibern8-enter-clk-gating.patch \
        1046-scsi-ufs-hold-clk-gating-across-system-pm.patch; do
        [[ -f "${patch_dir}/${p}" ]] || {
            echo "ERROR: suspend patch download failed (no ${p})" >&2
            return 1
        }
    done
}

verify_masi_suspend_stack() {
    local src_dir="$1" failed=0

    [[ "${SUSPEND_DEEP_PATCHES:-1}" == "0" ]] && return 0

    echo "==> Verify MaSi deep-suspend stack" >&2

    if grep -q 'ufshcd_relinking' "${src_dir}/drivers/ufs/core/ufshcd.c" 2>/dev/null \
        && grep -q 'pm_poll_timer' "${src_dir}/include/ufs/ufshcd.h" 2>/dev/null; then
        echo "  OK   ufshcd PM relink drain" >&2
    else
        echo "  FAIL missing ufshcd PM relink drain (1006)" >&2
        failed=1
    fi

    if grep -q 'UFSHCD_QUIRK_BROKEN_AUTO_HIBERN8' "${src_dir}/drivers/ufs/host/ufs-qcom.c" 2>/dev/null; then
        echo "  OK   ufs-qcom auto-hibern8 quirk" >&2
    else
        echo "  FAIL missing ufs-qcom auto-hibern8 quirk (1009)" >&2
        failed=1
    fi

    if grep -q 'qcom_qmp_ufs_ctrl_rx_linecfg' "${src_dir}/drivers/phy/qualcomm/phy-qcom-qmp-ufs.c" 2>/dev/null; then
        echo "  OK   QMP UFS RX LineCfg helper" >&2
    else
        echo "  FAIL missing QMP UFS LineCfg (1011)" >&2
        failed=1
    fi

    if grep -q 'complete_clkgate_hold' "${src_dir}/include/ufs/ufshcd.h" 2>/dev/null \
        && grep -q 'link recovered; runtime clock gating disabled' \
            "${src_dir}/drivers/ufs/core/ufshcd.c" 2>/dev/null; then
        echo "  OK   ufshcd hibern8-enter recover + PM clk-gating hold (1045/1046)" >&2
    else
        echo "  FAIL missing ufshcd 1045/1046 clk-gating PM (xiaodoudou 1009/1011)" >&2
        failed=1
    fi

    [[ "${failed}" -eq 0 ]]
}

# Deep-suspend stack (ROCKNIX PR #2952). 1011 before 1009/1010: those patches shift
# ufs-qcom.c line numbers and break the upstream ROCKNIX LineCfg hunks on linux-7.0.
_masi_suspend_patch_order() {
    cat <<'EOF'
1006-scsi-ufs-drain-relink-completions-out-of-band-pm.patch
1007-scsi-ufs-qcom-balance-irq-on-host-reset-error.patch
1008-scsi-ufs-qcom-propagate-hibern8-exit-failure-clk-scale.patch
1011-ufs-qcom-qmp-rx-linecfg-link-startup.patch
1009-scsi-ufs-qcom-auto-hibern8-clk-gating-collision.patch
1010-scsi-ufs-qcom-keep-mphy-powered-on-hibern8-park.patch
1012-mailbox-qcom-ipcc-remove-irqf-no-suspend.patch
1013-thermal-qcom-tsens-skip-ayn-thor-uplow-wake-irq.patch
1045-scsi-ufs-recover-hibern8-enter-clk-gating.patch
1046-scsi-ufs-hold-clk-gating-across-system-pm.patch
1047-PCI-qcom-sm8550-skip-l23-and-suspend-opp.patch
1048-arm64-dts-qcom-sm8550-add-a-pcie-suspend-opp.patch
1049-regulator-qcom-rpmh-add-suspend-state-support.patch
1050-thermal-qcom-tsens-mask-lower-irqs-across-suspend.patch
1051-tty-serial-qcom-geni-mask-non-console-irq-on-suspend.patch
1052-input-rsinput-quiesce-mcu-and-drop-vdd-on-suspend.patch
EOF
}

_masi_is_suspend_patch() {
    local base="$1" p
    while IFS= read -r p; do
        [[ -n "${p}" && "${base}" == "${p}" ]] && return 0
    done < <(_masi_suspend_patch_order)
    return 1
}

_masi_patch_already_applied() {
    local src_dir="$1" base="$2"

    case "${base}" in
    1000-add-qcom-haptics-driver.patch|1002-haptics-driver-support-periodic-sine-and-fixes.patch)
        [[ -f "${src_dir}/drivers/input/misc/qcom-hv-haptics.c" ]] \
            && grep -q 'qcom,hv-haptics' "${src_dir}/drivers/input/misc/qcom-hv-haptics.c" 2>/dev/null
        ;;
    1020-drm-panel-ar02-pocket-dmg.patch)
        [[ -f "${src_dir}/drivers/gpu/drm/panel/panel-ar02-3inch.c" ]]
        ;;
    1021-drm-panel-ar11-pocket-ds-secondary.patch)
        [[ -f "${src_dir}/drivers/gpu/drm/panel/panel-ar11-5inch.c" ]]
        ;;
    *)
        return 1
        ;;
    esac
}

_masi_patch_content_present() {
    local src_dir="$1" base="$2"

    case "${base}" in
    1004-haptics-steam-ff-deadlock-fix.patch)
        grep -q 'timeout = min_t(u32, timeout, 32)' \
            "${src_dir}/drivers/input/misc/qcom-hv-haptics.c" 2>/dev/null
        ;;
    1008-scsi-ufs-qcom-propagate-hibern8-exit-failure-clk-scale.patch)
        grep -q 'err = ufshcd_uic_hibern8_exit(hba)' \
            "${src_dir}/drivers/ufs/host/ufs-qcom.c" 2>/dev/null
        ;;
    1009-scsi-ufs-qcom-auto-hibern8-clk-gating-collision.patch)
        grep -q 'UFSHCD_QUIRK_BROKEN_AUTO_HIBERN8' \
            "${src_dir}/drivers/ufs/host/ufs-qcom.c" 2>/dev/null
        ;;
    1010-scsi-ufs-qcom-keep-mphy-powered-on-hibern8-park.patch)
        grep -q 'no_phy_retention hosts can lose calibrated M-PHY' \
            "${src_dir}/drivers/ufs/host/ufs-qcom.c" 2>/dev/null
        ;;
    1011-ufs-qcom-qmp-rx-linecfg-link-startup.patch)
        grep -q 'qcom_qmp_ufs_ctrl_rx_linecfg' \
            "${src_dir}/drivers/phy/qualcomm/phy-qcom-qmp-ufs.c" 2>/dev/null
        ;;
    1014-drm-hdmi-audio-hw-params.patch)
        grep -q '.hw_params = drm_connector_hdmi_audio_prepare' \
            "${src_dir}/drivers/gpu/drm/display/drm_hdmi_audio_helper.c" 2>/dev/null
        ;;
    1022-drm-panel-renesas-r63419.patch)
        [[ -f "${src_dir}/drivers/gpu/drm/panel/panel-renesas-r63419.c" ]]
        ;;
    1023-dt-bindings-panel-renesas-r63419.patch)
        [[ -f "${src_dir}/Documentation/devicetree/bindings/display/panel/renesas,r63419.yaml" ]]
        ;;
    1024-input-edt-ft5x06-retain-power-in-suspend.patch)
        grep -q 'retain_power_in_suspend' \
            "${src_dir}/drivers/input/touchscreen/edt-ft5x06.c" 2>/dev/null
        ;;
    1032-input-rsinput-suspend-resume-center-sticks.patch)
        grep -q 'rsinput_report_sticks_centered' \
            "${src_dir}/drivers/input/joystick/rsinput.c" 2>/dev/null
        ;;
    1032-remoteproc-q6v5-handover-irq-spam.patch)
        grep -q 'disable_irq(q6v5->handover_irq)' \
            "${src_dir}/drivers/remoteproc/qcom_q6v5.c" 2>/dev/null
        ;;
    1033-sound-aw88166-quiet-early-iis-probe.patch)
        grep -q 'pll check failed cannot start' \
            "${src_dir}/sound/soc/codecs/aw88166.c" 2>/dev/null
        ;;
    1034-ufs-quiet-unsupported-timestamp.patch)
        grep -q 'timestamp attr not supported' \
            "${src_dir}/drivers/ufs/core/ufshcd.c" 2>/dev/null
        ;;
    1035-cpufeatures-sm8550-heterogeneous-quiet.patch)
        grep -q 'of_machine_is_compatible("qcom,sm8550")' \
            "${src_dir}/arch/arm64/kernel/cpufeature.c" 2>/dev/null
        ;;
    1036-sound-aw88166-quiet-local-pll-iis.patch)
        grep -q 'dev_dbg(aw_dev->dev, "check pll lock fail, reg_val:0x%04x"' \
            "${src_dir}/sound/soc/codecs/aw88166.c" 2>/dev/null
        ;;
    1037-sound-soc-quiet-einval-probe.patch)
        grep -q 'case -EINVAL:' "${src_dir}/sound/soc/soc-utils.c" 2>/dev/null \
            && grep -A6 'case -EINVAL:' "${src_dir}/sound/soc/soc-utils.c" 2>/dev/null \
            | grep -q 'dev_dbg(dev, "ASoC error'
        ;;
    1038-soundwire-qcom-quiet-port-mismatch.patch)
        grep -q 'dev_dbg(ctrl->dev, "dout-ports (%d) mismatch with controller (%d)"' \
            "${src_dir}/drivers/soundwire/qcom.c" 2>/dev/null
        ;;
    1039-ath12k-wcn7850-keep-aspm-off-old-fw.patch)
        grep -q 'mhi AMSS' "${src_dir}/drivers/net/wireless/ath/ath12k/mhi.c" 2>/dev/null \
            && grep -q 'ab->hw_params->supports_aspm' \
                "${src_dir}/drivers/net/wireless/ath/ath12k/pci.c" 2>/dev/null
        ;;
    1040-ath12k-wcn7850-aspm-parent-port-mhi-timeout.patch)
        grep -q 'pci_upstream_bridge(ab_pci->pdev)' \
            "${src_dir}/drivers/net/wireless/ath/ath12k/pci.c" 2>/dev/null \
            && grep -q 'timeout_ms = 20000' \
                "${src_dir}/drivers/net/wireless/ath/ath12k/wifi7/mhi.c" 2>/dev/null
        ;;
    1041-mhi-host-poll-bhi-bhie-without-irq.patch)
        grep -q 'mhi_fw_poll_status' \
            "${src_dir}/drivers/bus/mhi/host/boot.c" 2>/dev/null &&
        grep -q 'loading AMSS inline' \
            "${src_dir}/drivers/bus/mhi/host/boot.c" 2>/dev/null
        ;;
    1042-mhi-host-noautoen-irq-poll-sbl-ee.patch)
        grep -q 'IRQF_NO_AUTOEN' \
            "${src_dir}/drivers/bus/mhi/host/init.c" 2>/dev/null \
            && grep -q 'Polled EE SBL' \
                "${src_dir}/drivers/bus/mhi/host/boot.c" 2>/dev/null
        ;;
    1043-mhi-ath12k-wcn7850-bhi-full-amss-drain-events.patch)
        grep -q 'drain channel command' \
            "${src_dir}/drivers/bus/mhi/host/main.c" 2>/dev/null \
            && grep -q 'mhi_start_event_poll' \
                "${src_dir}/drivers/bus/mhi/host/pm.c" 2>/dev/null
        ;;
    1044-ath12k-poll-ce-without-msi.patch)
        grep -q 'ath12k_ce_service_all' \
            "${src_dir}/drivers/net/wireless/ath/ath12k/ce.c" 2>/dev/null \
            && grep -q 'CE/DP MSI fallback poller started' \
                "${src_dir}/drivers/net/wireless/ath/ath12k/core.c" 2>/dev/null
        ;;
    1045-scsi-ufs-recover-hibern8-enter-clk-gating.patch)
        grep -q 'link recovered; runtime clock gating disabled' \
            "${src_dir}/drivers/ufs/core/ufshcd.c" 2>/dev/null
        ;;
    1046-scsi-ufs-hold-clk-gating-across-system-pm.patch)
        grep -q 'complete_clkgate_hold' \
            "${src_dir}/include/ufs/ufshcd.h" 2>/dev/null
        ;;
    1047-PCI-qcom-sm8550-skip-l23-and-suspend-opp.patch)
        grep -q 'pp->skip_l23_ready = true' \
            "${src_dir}/drivers/pci/controller/dwc/pcie-qcom.c" 2>/dev/null \
            && grep -q 'qcom_pcie_set_suspend_opp' \
                "${src_dir}/drivers/pci/controller/dwc/pcie-qcom.c" 2>/dev/null
        ;;
    1048-arm64-dts-qcom-sm8550-add-a-pcie-suspend-opp.patch)
        grep -q 'opp-suspend-1' \
            "${src_dir}/arch/arm64/boot/dts/qcom/sm8550.dtsi" 2>/dev/null
        ;;
    1049-regulator-qcom-rpmh-add-suspend-state-support.patch)
        grep -q 'rpmh_regulator_set_suspend_enable' \
            "${src_dir}/drivers/regulator/qcom-rpmh-regulator.c" 2>/dev/null
        ;;
    1050-thermal-qcom-tsens-mask-lower-irqs-across-suspend.patch)
        grep -q 'tsens_prepare' \
            "${src_dir}/drivers/thermal/qcom/tsens.c" 2>/dev/null
        ;;
    1051-tty-serial-qcom-geni-mask-non-console-irq-on-suspend.patch)
        grep -q 'Balance the disable_irq() taken in qcom_geni_serial_suspend' \
            "${src_dir}/drivers/tty/serial/qcom_geni_serial.c" 2>/dev/null
        ;;
    1052-input-rsinput-quiesce-mcu-and-drop-vdd-on-suspend.patch)
        grep -q 'drv->vdd_off = true' \
            "${src_dir}/drivers/input/joystick/rsinput.c" 2>/dev/null
        ;;
    *)
        return 1
        ;;
    esac
}

_masi_apply_single_patch() {
    local src_dir="$1" patch="$2"
    local base rc=0

    base="$(basename "${patch}")"
    if _masi_patch_content_present "${src_dir}" "${base}" \
        || _masi_patch_already_applied "${src_dir}" "${base}"; then
        return 2
    fi
    # linux-7.2.x: apply Python overlays before GNU patch. 1040–1043 are
    # malformed/empty, 1032/1052 miss Armbian abs-params context, and 1042's
    # GNU hunk would skip AMSS when EE is already SBL.
    if _kernel_is_72_series "${KERNEL_VER:-}"; then
        case "${base}" in
        1032-input-rsinput-suspend-resume-center-sticks.patch|\
        1052-input-rsinput-quiesce-mcu-and-drop-vdd-on-suspend.patch)
            _masi_apply_72_overlays "${src_dir}" --rsinput && return 0
            ;;
        1040-ath12k-wcn7850-aspm-parent-port-mhi-timeout.patch|\
        1041-mhi-host-poll-bhi-bhie-without-irq.patch|\
        1042-mhi-host-noautoen-irq-poll-sbl-ee.patch|\
        1043-mhi-ath12k-wcn7850-bhi-full-amss-drain-events.patch)
            _masi_apply_72_overlays "${src_dir}" --mhi && return 0
            ;;
        esac
    fi
    # Reverse without -f: already on the tree (stamped re-run). Must run
    # before forward -f or fuzz will duplicate hunks (see 1037).
    if patch -p1 --dry-run -R -d "${src_dir}" < "${patch}" >/dev/null 2>&1; then
        return 2
    fi
    if patch -p1 --dry-run -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
        patch -p1 -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1
        return $?
    fi
    if patch -p1 --dry-run -l -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
        patch -p1 -l -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1
        return $?
    fi
    case "${base}" in
    1007-scsi-ufs-qcom-balance-irq-on-host-reset-error.patch)
        apply_masi_ufs_host_reset_bridge "${src_dir}" && return 0
        ;;
    1012-mailbox-qcom-ipcc-remove-irqf-no-suspend.patch)
        apply_masi_ipcc_no_suspend_bridge "${src_dir}" && return 0
        ;;
    1045-scsi-ufs-recover-hibern8-enter-clk-gating.patch|1046-scsi-ufs-hold-clk-gating-across-system-pm.patch)
        ensure_masi_ufs_deep_pm "${src_dir}" && return 0
        ;;
    1047-PCI-qcom-sm8550-skip-l23-and-suspend-opp.patch|\
    1048-arm64-dts-qcom-sm8550-add-a-pcie-suspend-opp.patch|\
    1049-regulator-qcom-rpmh-add-suspend-state-support.patch|\
    1050-thermal-qcom-tsens-mask-lower-irqs-across-suspend.patch|\
    1051-tty-serial-qcom-geni-mask-non-console-irq-on-suspend.patch|\
    1052-input-rsinput-quiesce-mcu-and-drop-vdd-on-suspend.patch)
        ensure_masi_armada_energy "${src_dir}" && return 0
        ;;
    1030-drm-msm-a6xx-hfi-retry-slow-gmu-bw-votes.patch)
        apply_masi_gmu_bw_hfi_bridge "${src_dir}" && return 0
        ;;
    1031-drm-msm-a6xx-a740-forbid-gmu-runtime-pm.patch)
        apply_masi_gmu_runtime_pm_bridge "${src_dir}" && return 0
        ;;
    1034-ufs-quiet-unsupported-timestamp.patch)
        _kernel_is_72_series "${KERNEL_VER:-}" \
            && _masi_patch_bridge_72 "${base}" "${src_dir}" && return 0
        ;;
    1035-cpufeatures-sm8550-heterogeneous-quiet.patch)
        _kernel_is_72_series "${KERNEL_VER:-}" \
            && _masi_patch_bridge_72 "${base}" "${src_dir}" && return 0
        ;;
    1036-sound-aw88166-quiet-local-pll-iis.patch)
        _kernel_is_72_series "${KERNEL_VER:-}" \
            && _masi_patch_bridge_72 "${base}" "${src_dir}" && return 0
        ;;
    1037-sound-soc-quiet-einval-probe.patch)
        _kernel_is_72_series "${KERNEL_VER:-}" \
            && _masi_patch_bridge_72 "${base}" "${src_dir}" && return 0
        ;;
    1038-soundwire-qcom-quiet-port-mismatch.patch)
        _kernel_is_72_series "${KERNEL_VER:-}" \
            && _masi_patch_bridge_72 "${base}" "${src_dir}" && return 0
        ;;
    esac
    mkdir -p "${OUTPUT_DIR:-${ROOT}/output}"
    patch -p1 --dry-run -d "${src_dir}" -f < "${patch}" \
        > "${OUTPUT_DIR}/patch-fail-${base}.txt" 2>&1 || true
    return 1
}

_masi_apply_one_masi_patch() {
    local src_dir="$1" patch="$2"
    local base rc

    base="$(basename "${patch}")"
    if [[ "${base}" == "1003-rsinput-add-ff.patch" ]]; then
        apply_masi_rsinput_ff_bridge "${src_dir}"
        return $?
    fi
    _masi_apply_single_patch "${src_dir}" "${patch}"
    rc=$?
    if [[ "${rc}" -ne 0 && "${rc}" -ne 2 ]] && _kernel_is_72_series "${KERNEL_VER:-}" \
        && _masi_patch_bridge_72 "${base}" "${src_dir}"; then
        return 0
    fi
    return "${rc}"
}

apply_masi_ufs_host_reset_bridge() {
    local src_dir="$1" ufs="${src_dir}/drivers/ufs/host/ufs-qcom.c"

    [[ -f "${ufs}" ]] || return 1
    if grep -q 'assert/deassert failure leaks the disable' "${ufs}" 2>/dev/null; then
        return 0
    fi

    python3 - "${ufs}" <<'PY' && return 0
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "\t\treturn ret;\n\t}\n\n\tusleep_range(1000, 1100);\n\n\tif (reenable_intr)"
if needle not in text:
    raise SystemExit(1)
replacement = (
    "\t\tgoto out;\n\t}\n\n\tusleep_range(1000, 1100);\n\n\tret = 0;\nout:\n"
    "\t/*\n\t * Re-enable the IRQ on the error exits too, otherwise a reset\n"
    "\t * assert/deassert failure leaks the disable and leaves the controller\n"
    "\t * IRQ masked. (This path became reachable once ufshcd_disable_irq() stops\n"
    "\t * synchronizing during PM resume.)\n\t */\n\tif (reenable_intr)"
)
text = text.replace(needle, replacement, 1)
text = text.replace(
    "\t\treturn ret;\n\t}\n\n\t/*\n\t * The hardware requirement",
    "\t\tgoto out;\n\t}\n\n\t/*\n\t * The hardware requirement",
    1,
)
text = text.replace(
    "\tif (reenable_intr)\n\t\tufshcd_enable_irq(hba);\n\n\treturn 0;\n}\n\nstatic u32 ufs_qcom_get_hs_gear",
    "\tif (reenable_intr)\n\t\tufshcd_enable_irq(hba);\n\n\treturn ret;\n}\n\nstatic u32 ufs_qcom_get_hs_gear",
    1,
)
if "assert/deassert failure leaks the disable" not in text:
    raise SystemExit(1)
path.write_text(text)
PY
    return 1
}

apply_masi_ipcc_no_suspend_bridge() {
    local src_dir="$1" ipcc="${src_dir}/drivers/mailbox/qcom-ipcc.c"

    [[ -f "${ipcc}" ]] || return 1
    if ! grep -q 'IRQF_NO_SUSPEND' "${ipcc}" 2>/dev/null; then
        return 0
    fi

    python3 - "${ipcc}" <<'PY' && return 0
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "\t\t\t       IRQF_TRIGGER_HIGH | IRQF_NO_SUSPEND |\n\t\t\t       IRQF_NO_THREAD"
new = "\t\t\t       IRQF_TRIGGER_HIGH |\n\t\t\t       IRQF_NO_THREAD"
if old not in text:
    raise SystemExit(1)
path.write_text(text.replace(old, new, 1))
PY
    return 1
}

apply_masi_kernel_patches() {
    local src_dir="$1" patch_dir="${ROOT}/patches/masi"
    local patch base failed=0 applied=0 skipped=0 rc suspend_name

    [[ -d "${patch_dir}" ]] || return 0

    ensure_masi_suspend_patches || return 1

    echo "==> MaSi kernel patches (haptics, Thor, deep suspend, …)" >&2
    shopt -s nullglob
    for patch in "${patch_dir}"/[0-9]*.patch; do
        base="$(basename "${patch}")"
        if [[ "${base}" == "1001-qcom-haptics-trace-7.0.patch" ]]; then
            echo "  SKIP ${base} (folded into 1000 base patch)" >&2
            skipped=$((skipped + 1))
            continue
        fi
        _masi_is_suspend_patch "${base}" && continue
        _masi_apply_one_masi_patch "${src_dir}" "${patch}"
        rc=$?
        if [[ "${rc}" -eq 0 ]]; then
            echo "  OK   ${base}" >&2
            applied=$((applied + 1))
        elif [[ "${rc}" -eq 2 ]]; then
            echo "  SKIP ${base}" >&2
            skipped=$((skipped + 1))
        else
            echo "  FAIL ${base}" >&2
            failed=$((failed + 1))
        fi
    done

    while IFS= read -r suspend_name; do
        [[ -n "${suspend_name}" ]] || continue
        patch="${patch_dir}/${suspend_name}"
        [[ -f "${patch}" ]] || continue
        _masi_apply_one_masi_patch "${src_dir}" "${patch}"
        rc=$?
        if [[ "${rc}" -eq 0 ]]; then
            echo "  OK   ${suspend_name}" >&2
            applied=$((applied + 1))
        elif [[ "${rc}" -eq 2 ]]; then
            echo "  SKIP ${suspend_name}" >&2
            skipped=$((skipped + 1))
        else
            echo "  FAIL ${suspend_name}" >&2
            failed=$((failed + 1))
        fi
    done < <(_masi_suspend_patch_order)

    shopt -u nullglob
    echo "==> MaSi patches: ${applied} ok, ${skipped} skip, ${failed} fail" >&2

    if _kernel_is_72_series "${KERNEL_VER:-}"; then
        bridge_72_ufshcd_1006_intr "${src_dir}" || true
        bridge_72_tsens_1013 "${src_dir}" || true
        _masi_apply_72_overlays "${src_dir}" || failed=1
    fi

    verify_masi_suspend_stack "${src_dir}" || failed=1
    verify_masi_dp_audio_patches "${src_dir}" || failed=1
    verify_masi_gmu_bw_vote_stack "${src_dir}" || failed=1
    verify_masi_rsinput_suspend_stack "${src_dir}" || failed=1
    ensure_masi_compile2_log_quiet "${src_dir}" || failed=1
    ensure_masi_compile3_log_quiet "${src_dir}" || failed=1
    ensure_masi_ath12k_ce_poll "${src_dir}" || failed=1
    ensure_masi_ufs_deep_pm "${src_dir}" || failed=1
    ensure_masi_armada_energy "${src_dir}" || failed=1
    verify_masi_armada_energy_stack "${src_dir}" || failed=1
    [[ "${failed}" -eq 0 ]]
}

# xiaodoudou 1009/1011 — hibern8-enter recover + hold clk-gating across system PM.
ensure_masi_ufs_deep_pm() {
    local src_dir="$1"
    local c="${src_dir}/drivers/ufs/core/ufshcd.c"
    local h="${src_dir}/include/ufs/ufshcd.h"

    [[ -f "${c}" && -f "${h}" ]] || return 0
    if grep -q 'link recovered; runtime clock gating disabled' "${c}" 2>/dev/null \
        && grep -q 'complete_clkgate_hold' "${h}" 2>/dev/null; then
        echo "  OK   1045/1046 UFS clk-gating PM (present)" >&2
        return 0
    fi

    if python3 - "${c}" "${h}" <<'PY'
from pathlib import Path
import sys

cpath, hpath = Path(sys.argv[1]), Path(sys.argv[2])
c, h = cpath.read_text(), hpath.read_text()
changed = False

old_enter = """	if (ufshcd_can_hibern8_during_gating(hba)) {
		ret = ufshcd_uic_hibern8_enter(hba);
		if (ret) {
			hba->clk_gating.state = CLKS_ON;
			dev_err(hba->dev, "%s: hibern8 enter failed %d\\n",
					__func__, ret);
			trace_ufshcd_clk_gating(hba,
						hba->clk_gating.state);
			return;
		}
		ufshcd_set_link_hibern8(hba);
	}
"""
new_enter = r'''	if (ufshcd_can_hibern8_during_gating(hba)) {
		enum clk_gating_state h8_start_state;
		int h8_start_active_reqs;
		bool h8_start_pm;

		scoped_guard(spinlock_irqsave, &hba->clk_gating.lock) {
			h8_start_state = hba->clk_gating.state;
			h8_start_active_reqs = hba->clk_gating.active_reqs;
		}
		h8_start_pm = READ_ONCE(hba->pm_op_in_progress);

		hba->clk_gating.is_suspended = true;
		ret = ufshcd_uic_hibern8_enter(hba);
		if (ret) {
			enum clk_gating_state failed_state;
			int failed_active_reqs;
			bool failed_enabled;
			bool failed_suspended;

			scoped_guard(spinlock_irqsave, &hba->clk_gating.lock) {
				failed_state = hba->clk_gating.state;
				failed_active_reqs = hba->clk_gating.active_reqs;
				failed_enabled = hba->clk_gating.is_enabled;
				failed_suspended = hba->clk_gating.is_suspended;
				hba->clk_gating.state = CLKS_ON;
			}
			dev_err(hba->dev,
				"%s: hibern8 enter failed %d, recovering link\n",
					__func__, ret);
			dev_err(hba->dev,
				"%s: gate race snapshot: admitted state=%d active=%d pm=%d; h8-start state=%d active=%d pm=%d; failed state=%d active=%d enabled=%d suspended=%d pm=%d outstanding=%#lx gate-work=%u ungate-work=%u\n",
				__func__, admitted_state, admitted_active_reqs,
				admitted_pm,
				h8_start_state, h8_start_active_reqs,
				h8_start_pm,
				failed_state, failed_active_reqs,
				failed_enabled, failed_suspended,
				READ_ONCE(hba->pm_op_in_progress),
				READ_ONCE(hba->outstanding_reqs),
				work_busy(&hba->clk_gating.gate_work.work),
				work_busy(&hba->clk_gating.ungate_work));
			trace_ufshcd_clk_gating(hba,
						hba->clk_gating.state);

			ret = ufshcd_link_recovery(hba);

			scoped_guard(spinlock_irqsave, &hba->clk_gating.lock) {
				if (hba->clk_gating.is_enabled) {
					hba->clk_gating.active_reqs++;
					hba->clk_gating.is_enabled = false;
				}
			}
			hba->clk_gating.is_suspended = false;

			if (ret)
				dev_err(hba->dev,
					"%s: link recovery after hibern8 enter failed %d\n",
					__func__, ret);
			else
				dev_warn(hba->dev,
					 "%s: link recovered; runtime clock gating disabled\n",
					 __func__);
			return;
		}
		ufshcd_set_link_hibern8(hba);
		hba->clk_gating.is_suspended = false;
	}
'''

if "link recovered; runtime clock gating disabled" not in c:
    if old_enter not in c:
        sys.exit(1)
    decls = """	enum clk_gating_state admitted_state;
	int admitted_active_reqs;
	bool admitted_pm;
"""
    needle = """	struct ufs_hba *hba = container_of(work, struct ufs_hba,
			clk_gating.gate_work.work);
	int ret;
"""
    repl = """	struct ufs_hba *hba = container_of(work, struct ufs_hba,
			clk_gating.gate_work.work);
	enum clk_gating_state admitted_state;
	int admitted_active_reqs;
	bool admitted_pm;
	int ret;
"""
    if needle not in c:
        sys.exit(1)
    c = c.replace(needle, repl, 1)
    snap = """
		admitted_state = hba->clk_gating.state;
		admitted_active_reqs = hba->clk_gating.active_reqs;
		admitted_pm = READ_ONCE(hba->pm_op_in_progress);
"""
    lock_end = """		if (hba->clk_gating.active_reqs)
			return;
	}
"""
    lock_end_new = """		if (hba->clk_gating.active_reqs)
			return;

		admitted_state = hba->clk_gating.state;
		admitted_active_reqs = hba->clk_gating.active_reqs;
		admitted_pm = READ_ONCE(hba->pm_op_in_progress);
	}
"""
    # Only the gate_work copy: first occurrence after ufshcd_gate_work
    idx = c.find("static void ufshcd_gate_work")
    if idx < 0:
        sys.exit(1)
    head, tail = c[:idx], c[idx:]
    if lock_end not in tail:
        sys.exit(1)
    tail = tail.replace(lock_end, lock_end_new, 1)
    if old_enter not in tail:
        sys.exit(1)
    tail = tail.replace(old_enter, new_enter, 1)
    c = head + tail
    changed = True

if "complete_clkgate_hold" not in h:
    if "\tbool complete_put;\n" not in h:
        sys.exit(1)
    h = h.replace("\tbool complete_put;\n", "\tbool complete_put;\n\tbool complete_clkgate_hold;\n", 1)
    old_doc = """ * @complete_put: whether or not to call ufshcd_rpm_put() from inside
 *	ufshcd_resume_complete()
"""
    new_doc = """ * @complete_put: whether or not to call ufshcd_rpm_put() from inside
 *	ufshcd_resume_complete()
 * @complete_clkgate_hold: whether ufshcd_resume_complete() must release
 *	clock-gating hold acquired by ufshcd_suspend_prepare()
"""
    if old_doc in h:
        h = h.replace(old_doc, new_doc, 1)
    changed = True

old_complete = """void ufshcd_resume_complete(struct device *dev)
{
	struct ufs_hba *hba = dev_get_drvdata(dev);

	if (hba->complete_put) {
"""
new_complete = """void ufshcd_resume_complete(struct device *dev)
{
	struct ufs_hba *hba = dev_get_drvdata(dev);

	if (hba->complete_clkgate_hold) {
		hba->complete_clkgate_hold = false;
		ufshcd_release(hba);
	}
	if (hba->complete_put) {
"""
if "complete_clkgate_hold = false" not in c:
    if old_complete not in c:
        sys.exit(1)
    c = c.replace(old_complete, new_complete, 1)
    changed = True

old_prep = """		if (!rpm_ok_for_spm || !ufshcd_rpm_ok_for_spm(hba)) {
			/* RPM state is not ok for SPM, so runtime resume */
			ret = ufshcd_rpm_resume(hba);
			if (ret < 0 && ret != -EACCES) {
				ufshcd_rpm_put(hba);
				return ret;
			}
		}
		hba->complete_put = true;
"""
new_prep = """		rpm_ready_for_spm = rpm_ok_for_spm && ufshcd_rpm_ok_for_spm(hba);
		if (!rpm_ready_for_spm) {
			/* RPM state is not ok for SPM, so runtime resume */
			ret = ufshcd_rpm_resume(hba);
			if (ret < 0 && ret != -EACCES) {
				ufshcd_rpm_put(hba);
				return ret;
			}

			ufshcd_hold(hba);
			hba->complete_clkgate_hold = true;
		}
		hba->complete_put = true;
"""
if "complete_clkgate_hold = true" not in c:
    if old_prep not in c:
        sys.exit(1)
    c = c.replace(old_prep, new_prep, 1)
    decl_old = """int __ufshcd_suspend_prepare(struct device *dev, bool rpm_ok_for_spm)
{
	struct ufs_hba *hba = dev_get_drvdata(dev);
	int ret;
"""
    decl_new = """int __ufshcd_suspend_prepare(struct device *dev, bool rpm_ok_for_spm)
{
	struct ufs_hba *hba = dev_get_drvdata(dev);
	bool rpm_ready_for_spm;
	int ret;
"""
    if decl_old not in c:
        sys.exit(1)
    c = c.replace(decl_old, decl_new, 1)
    changed = True

if not changed:
    sys.exit(0)
cpath.write_text(c)
hpath.write_text(h)
PY
    then
        echo "  OK   1045/1046 UFS clk-gating PM (bridge)" >&2
        return 0
    fi
    echo "  FAIL 1045/1046 UFS clk-gating PM" >&2
    return 1
}

# Armada SM8550 energy subset (PCIe L23/OPP, RPMH state-mem, TSENS LOWER,
# GENI IRQ mask, rsinput MCU quiesce, dwc3 skip-phy, sdhci IRQ mask).
# Deep/S2RAM policy is unchanged.
ensure_masi_armada_energy() {
    local src_dir="$1"
    local py="${ROOT}/scripts/apply-masi-armada-energy.py"

    [[ -f "${py}" ]] || {
        echo "  FAIL missing ${py}" >&2
        return 1
    }
    # 1052 needs 1032 PM ops first; GNU 1032 misses Armbian 7.2 abs-params.
    if _kernel_is_72_series "${KERNEL_VER:-}"; then
        _masi_apply_72_overlays "${src_dir}" --rsinput || true
    fi
    python3 "${py}" "${src_dir}"
}

verify_masi_armada_energy_stack() {
    local src_dir="$1" failed=0

    echo "==> Verify MaSi Armada SM8550 energy stack (1047–1054)" >&2
    if grep -q 'pp->skip_l23_ready = true' \
            "${src_dir}/drivers/pci/controller/dwc/pcie-qcom.c" 2>/dev/null \
        && grep -q 'qcom_pcie_set_suspend_opp' \
            "${src_dir}/drivers/pci/controller/dwc/pcie-qcom.c" 2>/dev/null \
        && ! grep -q 'masi_s2ram_force_pcie_teardown' \
            "${src_dir}/drivers/pci/controller/dwc/pcie-qcom.c" 2>/dev/null; then
        echo "  OK   PCIe SM8550 skip L23 + suspend OPP (1047)" >&2
    else
        echo "  FAIL missing 1047 PCIe L23/suspend OPP (or leftover 1056 teardown)" >&2
        failed=1
    fi
    if grep -q 'opp-suspend-1' \
            "${src_dir}/arch/arm64/boot/dts/qcom/sm8550.dtsi" 2>/dev/null; then
        echo "  OK   sm8550.dtsi PCIe suspend OPP (1048)" >&2
    else
        echo "  FAIL missing 1048 PCIe suspend OPP DT" >&2
        failed=1
    fi
    if grep -q 'rpmh_regulator_set_suspend_enable' \
            "${src_dir}/drivers/regulator/qcom-rpmh-regulator.c" 2>/dev/null; then
        echo "  OK   RPMH regulator-state-mem (1049)" >&2
    else
        echo "  FAIL missing 1049 RPMH suspend-state" >&2
        failed=1
    fi
    if grep -q 'tsens_prepare' \
            "${src_dir}/drivers/thermal/qcom/tsens.c" 2>/dev/null; then
        echo "  OK   TSENS mask LOWER across suspend (1050)" >&2
    else
        echo "  FAIL missing 1050 TSENS prepare LOWER mask" >&2
        failed=1
    fi
    if grep -q 'Balance the disable_irq() taken in qcom_geni_serial_suspend' \
            "${src_dir}/drivers/tty/serial/qcom_geni_serial.c" 2>/dev/null; then
        echo "  OK   GENI mask non-console IRQ (1051)" >&2
    else
        echo "  FAIL missing 1051 GENI suspend IRQ mask" >&2
        failed=1
    fi
    if grep -q 'drv->vdd_off = true' \
            "${src_dir}/drivers/input/joystick/rsinput.c" 2>/dev/null; then
        echo "  OK   rsinput MCU quiesce + VDD drop (1052)" >&2
    else
        echo "  FAIL missing 1052 rsinput MCU quiesce" >&2
        failed=1
    fi
    if grep -q 'xhci-skip-phy-init-quirk' \
            "${src_dir}/drivers/usb/dwc3/dwc3-qcom.c" 2>/dev/null; then
        echo "  OK   dwc3 skip-phy (1053 / Armada 0522)" >&2
    else
        echo "  FAIL missing 1053 dwc3 skip-phy" >&2
        failed=1
    fi
    if grep -q 'host->ier & SDHCI_INT_CARD_INT' \
            "${src_dir}/drivers/mmc/host/sdhci-msm.c" 2>/dev/null; then
        echo "  OK   sdhci-msm IRQ mask in runtime suspend (1054 / Armada 0521)" >&2
    else
        echo "  FAIL missing 1054 sdhci IRQ mask" >&2
        failed=1
    fi
    [[ "${failed}" -eq 0 ]]
}

# 7.2.8 qcom-pcie MSI does not wake ath12k CE completions (HTT -110).
# Drain copy engines from process context while waiting, plus a 500us poller.
ensure_masi_ath12k_ce_poll() {
    local src_dir="$1"
    local core="${src_dir}/drivers/net/wireless/ath/ath12k/core.c"
    local ce="${src_dir}/drivers/net/wireless/ath/ath12k/ce.c"

    [[ -f "${core}" && -f "${ce}" ]] || return 0
    if grep -q 'CE/DP MSI fallback poller started' "${core}" 2>/dev/null \
        && grep -q 'ath12k_ce_service_all' "${ce}" 2>/dev/null; then
        echo "  OK   1044 ath12k CE MSI poller (present)" >&2
        return 0
    fi

    if python3 - "${src_dir}" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1]) / "drivers/net/wireless/ath/ath12k"
ce_h = (src / "ce.h").read_text()
ce_c = (src / "ce.c").read_text()
core_h = (src / "core.h").read_text()
core_c = (src / "core.c").read_text()
htc = (src / "htc.c").read_text()
changed = False

if "void ath12k_ce_service_all" not in ce_h:
    needle = "void ath12k_ce_per_engine_service(struct ath12k_base *ab, u16 ce_id);\n"
    if needle not in ce_h:
        raise SystemExit(1)
    ce_h = ce_h.replace(
        needle,
        needle + "void ath12k_ce_service_all(struct ath12k_base *ab);\n",
        1,
    )
    changed = True

svc = '''void ath12k_ce_service_all(struct ath12k_base *ab)
{
	int i, n;

	if (!ab->hw_params)
		return;
	n = ab->hw_params->ce_count;
	for (i = 0; i < n; i++)
		ath12k_ce_per_engine_service(ab, i);
}

'''
if "void ath12k_ce_service_all" not in ce_c:
    needle = '''void ath12k_ce_per_engine_service(struct ath12k_base *ab, u16 ce_id)
{
	struct ath12k_ce_pipe *pipe = &ab->ce.ce_pipe[ce_id];

	if (pipe->send_cb)
		pipe->send_cb(pipe);

	if (pipe->recv_cb)
		ath12k_ce_recv_process_cb(pipe);
}
'''
    if needle not in ce_c:
        raise SystemExit(1)
    ce_c = ce_c.replace(needle, needle + "\n" + svc, 1)
    changed = True

if "ce_poll_work" not in core_h:
    needle = "\tstruct work_struct restart_work;\n"
    if needle not in core_h:
        raise SystemExit(1)
    core_h = core_h.replace(
        needle,
        needle + "\tstruct delayed_work ce_poll_work;\n",
        1,
    )
    changed = True

if '#include "ce.h"' not in htc.split("struct sk_buff *ath12k_htc_alloc_skb", 1)[0]:
    old_inc = '#include "debug.h"\n#include "hif.h"\n'
    if old_inc not in htc:
        raise SystemExit(1)
    htc = htc.replace(
        old_inc,
        '#include <linux/delay.h>\n#include <linux/jiffies.h>\n\n'
        '#include "debug.h"\n#include "hif.h"\n#include "ce.h"\n',
        1,
    )
    changed = True

helper = '''static unsigned long ath12k_htc_wait_ctl_resp(struct ath12k_htc *htc,
					      unsigned long timeout)
{
	unsigned long deadline = jiffies + timeout;

	for (;;) {
		if (try_wait_for_completion(&htc->ctl_resp))
			return 1;
		ath12k_ce_service_all(htc->ab);
		if (time_after_eq(jiffies, deadline))
			return try_wait_for_completion(&htc->ctl_resp) ? 1 : 0;
		usleep_range(200, 400);
	}
}

'''
if "ath12k_htc_wait_ctl_resp" not in htc:
    needle = "int ath12k_htc_wait_target(struct ath12k_htc *htc)\n"
    if needle not in htc:
        raise SystemExit(1)
    htc = htc.replace(needle, helper + needle, 1)
    htc = htc.replace(
        "\ttime_left = wait_for_completion_timeout(&htc->ctl_resp,\n"
        "\t\t\t\t\t\tATH12K_HTC_WAIT_TIMEOUT_HZ);\n",
        "\ttime_left = ath12k_htc_wait_ctl_resp(htc, ATH12K_HTC_WAIT_TIMEOUT_HZ);\n",
        1,
    )
    htc = htc.replace(
        "\t\ttime_left =\n"
        "\t\t\twait_for_completion_timeout(&htc->ctl_resp,\n"
        "\t\t\t\t\t    ATH12K_HTC_WAIT_TIMEOUT_HZ);\n",
        "\t\ttime_left = ath12k_htc_wait_ctl_resp(htc, ATH12K_HTC_WAIT_TIMEOUT_HZ);\n",
        1,
    )
    htc = htc.replace(
        "\ttime_left = wait_for_completion_timeout(&htc->ctl_resp,\n"
        "\t\t\t\t\t\tATH12K_HTC_CONN_SVC_TIMEOUT_HZ);\n",
        "\ttime_left = ath12k_htc_wait_ctl_resp(htc, ATH12K_HTC_CONN_SVC_TIMEOUT_HZ);\n",
        1,
    )
    changed = True

if "CE/DP MSI fallback poller started" not in core_c:
    if '#include <linux/workqueue.h>' not in core_c:
        core_c = core_c.replace(
            '#include <linux/of_graph.h>\n',
            '#include <linux/of_graph.h>\n#include <linux/workqueue.h>\n',
            1,
        )
    proto = (
        "static void ath12k_ce_poll_worker(struct work_struct *work);\n"
        "static void ath12k_ce_poll_start(struct ath12k_base *ab);\n"
        "static void ath12k_ce_poll_stop(struct ath12k_base *ab);\n\n"
    )
    if "ath12k_ce_poll_worker" not in core_c.split("static int ath12k_core_start", 1)[0]:
        core_c = core_c.replace(
            "EXPORT_SYMBOL(ath12k_ftm_mode);\n\n",
            "EXPORT_SYMBOL(ath12k_ftm_mode);\n\n" + proto,
            1,
        )
    fns = '''static void ath12k_ce_poll_worker(struct work_struct *work)
{
	struct ath12k_base *ab = container_of(work, struct ath12k_base,
					      ce_poll_work.work);
	int i;

	ath12k_ce_service_all(ab);

	if (test_bit(ATH12K_FLAG_EXT_IRQ_ENABLED, &ab->dev_flags)) {
		for (i = 0; i < ATH12K_EXT_IRQ_GRP_NUM_MAX; i++) {
			struct ath12k_ext_irq_grp *irq_grp = &ab->ext_irq_grp[i];

			if (irq_grp->napi_enabled)
				napi_schedule(&irq_grp->napi);
		}
	}

	queue_delayed_work(system_dfl_wq, &ab->ce_poll_work,
			   usecs_to_jiffies(500));
}

static void ath12k_ce_poll_start(struct ath12k_base *ab)
{
	queue_delayed_work(system_dfl_wq, &ab->ce_poll_work, 0);
	ath12k_info(ab, "CE/DP MSI fallback poller started\\n");
}

static void ath12k_ce_poll_stop(struct ath12k_base *ab)
{
	cancel_delayed_work_sync(&ab->ce_poll_work);
}

'''
    needle = "static int ath12k_core_start(struct ath12k_base *ab)\n"
    if needle not in core_c:
        raise SystemExit(1)
    core_c = core_c.replace(needle, fns + needle, 1)
    core_c = core_c.replace(
        "\t\tgoto err_wmi_detach;\n\t}\n\n\tret = ath12k_htc_wait_target(&ab->htc);\n",
        "\t\tgoto err_wmi_detach;\n\t}\n\n\tath12k_ce_poll_start(ab);\n\n"
        "\tret = ath12k_htc_wait_target(&ab->htc);\n",
        1,
    )
    core_c = core_c.replace(
        "err_hif_stop:\n\tath12k_hif_stop(ab);\n",
        "err_hif_stop:\n\tath12k_ce_poll_stop(ab);\n\tath12k_hif_stop(ab);\n",
        1,
    )
    core_c = core_c.replace(
        "\tath12k_dp_rx_pdev_reo_cleanup(ab);\n\tath12k_hif_stop(ab);\n",
        "\tath12k_dp_rx_pdev_reo_cleanup(ab);\n\tath12k_ce_poll_stop(ab);\n"
        "\tath12k_hif_stop(ab);\n",
        1,
    )
    core_c = core_c.replace(
        "\tINIT_WORK(&ab->restart_work, ath12k_core_restart);\n",
        "\tINIT_WORK(&ab->restart_work, ath12k_core_restart);\n"
        "\tINIT_DELAYED_WORK(&ab->ce_poll_work, ath12k_ce_poll_worker);\n",
        1,
    )
    core_c = core_c.replace(
        "\ttimer_delete_sync(&ab->rx_replenish_retry);\n\tath12k_wmi_free();\n",
        "\ttimer_delete_sync(&ab->rx_replenish_retry);\n"
        "\tcancel_delayed_work_sync(&ab->ce_poll_work);\n\tath12k_wmi_free();\n",
        1,
    )
    changed = True

pci_c_path = src / "pci.c"
if pci_c_path.is_file():
    pci_c = pci_c_path.read_text()
    if "irq_grp->irqs_masked" not in pci_c:
        old_poll = (
            "\t\tnapi_complete_done(napi, work_done);\n"
            "\t\tfor (i = 0; i < irq_grp->num_irq; i++)\n"
            "\t\t\tenable_irq(irq_grp->ab->irq_num[irq_grp->irqs[i]]);\n"
        )
        new_poll = (
            "\t\tnapi_complete_done(napi, work_done);\n"
            "\t\tif (irq_grp->irqs_masked) {\n"
            "\t\t\tirq_grp->irqs_masked = false;\n"
            "\t\t\tfor (i = 0; i < irq_grp->num_irq; i++)\n"
            "\t\t\t\tenable_irq(irq_grp->ab->irq_num[irq_grp->irqs[i]]);\n"
            "\t\t}\n"
        )
        if old_poll not in pci_c:
            raise SystemExit(1)
        pci_c = pci_c.replace(old_poll, new_poll, 1)
        old_h = (
            "\tirq_grp->timestamp = jiffies;\n\n"
            "\tfor (i = 0; i < irq_grp->num_irq; i++)\n"
            "\t\tdisable_irq_nosync(irq_grp->ab->irq_num[irq_grp->irqs[i]]);\n"
        )
        new_h = (
            "\tirq_grp->timestamp = jiffies;\n\n"
            "\tirq_grp->irqs_masked = true;\n"
            "\tfor (i = 0; i < irq_grp->num_irq; i++)\n"
            "\t\tdisable_irq_nosync(irq_grp->ab->irq_num[irq_grp->irqs[i]]);\n"
        )
        if old_h not in pci_c:
            raise SystemExit(1)
        pci_c = pci_c.replace(old_h, new_h, 1)
        pci_c_path.write_text(pci_c)
        changed = True
    if "bool irqs_masked;" not in core_h:
        needle = "\tbool napi_enabled;\n"
        if needle not in core_h:
            raise SystemExit(1)
        core_h = core_h.replace(needle, needle + "\tbool irqs_masked;\n", 1)
        changed = True

if not changed:
    raise SystemExit(1)
(src / "ce.h").write_text(ce_h)
(src / "ce.c").write_text(ce_c)
(src / "core.h").write_text(core_h)
(src / "core.c").write_text(core_c)
(src / "htc.c").write_text(htc)
PY
    then
        echo "  OK   1044 ath12k CE MSI poller (bridge)" >&2
        return 0
    fi
    echo "  FAIL 1044 ath12k CE MSI poller" >&2
    return 1
}

ensure_masi_compile2_log_quiet() {
    local src_dir="$1" ok=1

    if grep -q 'timestamp attr not supported' \
        "${src_dir}/drivers/ufs/core/ufshcd.c" 2>/dev/null; then
        echo "  OK   1034 UFS timestamp quiet (present)" >&2
    elif bridge_72_ufs_quiet_timestamp "${src_dir}"; then
        echo "  OK   1034 UFS timestamp quiet (bridge)" >&2
    else
        echo "  FAIL 1034 UFS timestamp quiet" >&2
        ok=0
    fi

    if grep -q 'of_machine_is_compatible("qcom,sm8550")' \
        "${src_dir}/arch/arm64/kernel/cpufeature.c" 2>/dev/null \
        && grep -q 'heterogeneous %s on CPU' \
            "${src_dir}/arch/arm64/kernel/cpufeature.c" 2>/dev/null; then
        echo "  OK   1035 SM8550 cpufeature quiet (present)" >&2
    elif bridge_72_cpufeature_sm8550_quiet "${src_dir}"; then
        echo "  OK   1035 SM8550 cpufeature quiet (bridge)" >&2
    else
        echo "  FAIL 1035 SM8550 cpufeature quiet" >&2
        ok=0
    fi

    [[ "${ok}" -eq 1 ]]
}

ensure_masi_compile3_log_quiet() {
    local src_dir="$1" ok=1

    if grep -q 'dev_dbg(aw_dev->dev, "check pll lock fail, reg_val:0x%04x"' \
        "${src_dir}/sound/soc/codecs/aw88166.c" 2>/dev/null; then
        echo "  OK   1036 aw88166 PLL/IIS quiet (present)" >&2
    elif bridge_72_aw88166_quiet_pll_iis "${src_dir}"; then
        echo "  OK   1036 aw88166 PLL/IIS quiet (bridge)" >&2
    else
        echo "  FAIL 1036 aw88166 PLL/IIS quiet" >&2
        ok=0
    fi

    if grep -q 'case -EINVAL:' "${src_dir}/sound/soc/soc-utils.c" 2>/dev/null \
        && grep -A6 'case -EINVAL:' "${src_dir}/sound/soc/soc-utils.c" 2>/dev/null \
        | grep -q 'dev_dbg(dev, "ASoC error'; then
        echo "  OK   1037 ASoC -EINVAL quiet (present)" >&2
    elif bridge_72_asoc_quiet_einval "${src_dir}"; then
        echo "  OK   1037 ASoC -EINVAL quiet (bridge)" >&2
    else
        echo "  FAIL 1037 ASoC -EINVAL quiet" >&2
        ok=0
    fi

    if grep -q 'dev_dbg(ctrl->dev, "dout-ports (%d) mismatch with controller (%d)"' \
        "${src_dir}/drivers/soundwire/qcom.c" 2>/dev/null; then
        echo "  OK   1038 soundwire port mismatch quiet (present)" >&2
    elif bridge_72_soundwire_quiet_port_mismatch "${src_dir}"; then
        echo "  OK   1038 soundwire port mismatch quiet (bridge)" >&2
    else
        echo "  FAIL 1038 soundwire port mismatch quiet" >&2
        ok=0
    fi

    [[ "${ok}" -eq 1 ]]
}

# Upgrade / inject A740 GMU GX_BW_PERF_VOTE HFI wait (1030) when hunk context drifted.
apply_masi_gmu_bw_hfi_bridge() {
    local src_dir="$1"
    local hfi="${src_dir}/drivers/gpu/drm/msm/adreno/a6xx_hfi.c"

    [[ -f "${hfi}" ]] || return 1
    if grep -q 'timeout_us = (id == HFI_H2F_MSG_GX_BW_PERF_VOTE)' "${hfi}" \
        && grep -q 'max_slow = (id == HFI_H2F_MSG_GX_BW_PERF_VOTE)' "${hfi}"; then
        return 0
    fi

    python3 - "${hfi}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
fn = re.search(
    r"static int a6xx_hfi_wait_for_msg_interrupt\(struct a6xx_gmu \*gmu, u32 id, u32 seqnum\)\n\{.*?\n\}",
    text,
    re.S,
)
if not fn:
    raise SystemExit(1)
new_fn = r'''static int a6xx_hfi_wait_for_msg_interrupt(struct a6xx_gmu *gmu, u32 id, u32 seqnum)
{
	int ret;
	u32 val;
	struct a6xx_gpu *a6xx_gpu = container_of(gmu, struct a6xx_gpu, gmu);
	unsigned int slow_retries = 0;
	/* A740 BW/perf votes often need >1s; give them headroom without
	 * slowing every other HFI message. */
	unsigned int timeout_us = (id == HFI_H2F_MSG_GX_BW_PERF_VOTE) ?
		2000000 : 1000000;
	unsigned int max_slow = (id == HFI_H2F_MSG_GX_BW_PERF_VOTE) ? 8 : 3;

	do {
		/* Wait for a response */
		ret = gmu_poll_timeout(gmu, REG_A6XX_GMU_GMU2HOST_INTR_INFO, val,
			val & A6XX_GMU_GMU2HOST_INTR_INFO_MSGQ, 100, timeout_us);

		if (!ret)
			break;

		if (!completion_done(&a6xx_gpu->base.fault_coredump_done)) {
			/* We may timeout because the GMU is temporarily wedged from
			 * pending faults from the GPU and we are taking a devcoredump.
			 * Wait until the MMU is resumed and try again.
			 */
			wait_for_completion(&a6xx_gpu->base.fault_coredump_done);
			continue;
		}

		/*
		 * No coredump in progress. A740 GMU GX_BW_PERF_VOTE replies can
		 * land just after the poll window; abandoning them desyncs HFI.
		 */
		if (++slow_retries < max_slow)
			continue;

		break;
	} while (true);

	if (ret) {
		DRM_DEV_ERROR(gmu->dev,
			"Message %s id %d timed out waiting for response\n",
			a6xx_hfi_msg_id[id], seqnum);
		return -ETIMEDOUT;
	}

	/* Clear the interrupt */
	gmu_write(gmu, REG_A6XX_GMU_GMU2HOST_INTR_CLR,
		A6XX_GMU_GMU2HOST_INTR_INFO_MSGQ);

	return 0;
}'''
path.write_text(text[: fn.start()] + new_fn + text[fn.end() :])
PY
}

# Inject A740 pm_runtime_forbid + HFI set_freq error report (1031).
apply_masi_gmu_runtime_pm_bridge() {
    local src_dir="$1"
    local gmu="${src_dir}/drivers/gpu/drm/msm/adreno/a6xx_gmu.c"

    [[ -f "${gmu}" ]] || return 1
    if grep -q 'pm_runtime_forbid(gmu->dev)' "${gmu}" \
        && grep -q 'GMU GX_BW_PERF_VOTE failed' "${gmu}"; then
        return 0
    fi

    python3 - "${gmu}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
changed = False

old_freq = """\tif (!gmu->legacy) {
\t\ta6xx_hfi_set_freq(gmu, perf_index, bw_index);
\t\t/* With Bandwidth voting, we now vote for all resources, so skip OPP set */
\t\tif (!bw_index)
\t\t\tdev_pm_opp_set_opp(&gpu->pdev->dev, opp);
\t\treturn;
\t}
"""
new_freq = """\tif (!gmu->legacy) {
\t\tret = a6xx_hfi_set_freq(gmu, perf_index, bw_index);
\t\tif (ret)
\t\t\tdev_err_ratelimited(gmu->dev,
\t\t\t\t"GMU GX_BW_PERF_VOTE failed: %d (perf=%u bw=0x%x)\\n",
\t\t\t\tret, perf_index, bw_index);
\t\t/* With Bandwidth voting, we now vote for all resources, so skip OPP set */
\t\tif (!bw_index)
\t\t\tdev_pm_opp_set_opp(&gpu->pdev->dev, opp);
\t\treturn;
\t}
"""
if "GMU GX_BW_PERF_VOTE failed" not in text:
    if old_freq not in text:
        raise SystemExit(1)
    text = text.replace(old_freq, new_freq, 1)
    changed = True

old_pm = """\tpm_runtime_enable(gmu->dev);

\t/* Get the list of clocks */
\tret = a6xx_gmu_clocks_probe(gmu);
"""
new_pm = """\tpm_runtime_enable(gmu->dev);
\t/*
\t * A740: runtime suspend of the GMU wakes with a burst of
\t * GX_BW_PERF_VOTE HFI traffic that often times out and desyncs the
\t * response queue. Keep GMU powered (kernel-side; no userspace keepalive).
\t */
\tif (adreno_is_a740_family(adreno_gpu))
\t\tpm_runtime_forbid(gmu->dev);

\t/* Get the list of clocks */
\tret = a6xx_gmu_clocks_probe(gmu);
"""
if "pm_runtime_forbid(gmu->dev)" not in text:
    if old_pm not in text:
        raise SystemExit(1)
    text = text.replace(old_pm, new_pm, 1)
    changed = True

if not changed and "pm_runtime_forbid(gmu->dev)" in text and "GMU GX_BW_PERF_VOTE failed" in text:
    raise SystemExit(0)
path.write_text(text)
PY
}

verify_masi_gmu_bw_vote_stack() {
    local src_dir="$1" failed=0
    local hfi="${src_dir}/drivers/gpu/drm/msm/adreno/a6xx_hfi.c"
    local gmu="${src_dir}/drivers/gpu/drm/msm/adreno/a6xx_gmu.c"

    echo "==> Verify MaSi A740 GMU BW-vote stack (1030/1031)" >&2

    if [[ -f "${hfi}" ]] && grep -q 'timeout_us = (id == HFI_H2F_MSG_GX_BW_PERF_VOTE)' "${hfi}" \
        && grep -q 'max_slow = (id == HFI_H2F_MSG_GX_BW_PERF_VOTE)' "${hfi}"; then
        echo "  OK   HFI wait retries/timeout for GX_BW_PERF_VOTE" >&2
    else
        echo "  FAIL missing 1030 HFI GX_BW_PERF_VOTE wait hardening" >&2
        failed=1
    fi

    if [[ -f "${gmu}" ]] && grep -q 'pm_runtime_forbid(gmu->dev)' "${gmu}" \
        && grep -q 'adreno_is_a740_family(adreno_gpu)' "${gmu}" \
        && grep -q 'GMU GX_BW_PERF_VOTE failed' "${gmu}"; then
        echo "  OK   A740 GMU runtime PM forbid + vote error report" >&2
    else
        echo "  FAIL missing 1031 A740 GMU runtime PM forbid" >&2
        failed=1
    fi

    [[ "${failed}" -eq 0 ]]
}

verify_masi_rsinput_suspend_stack() {
    local src_dir="$1" failed=0
    local rs="${src_dir}/drivers/input/joystick/rsinput.c"

    echo "==> Verify MaSi rsinput suspend/resume stick centering (1032)" >&2
    if [[ -f "${rs}" ]] \
        && grep -q 'rsinput_report_sticks_centered' "${rs}" \
        && grep -q 'DEFINE_SIMPLE_DEV_PM_OPS(rsinput_pm_ops' "${rs}" \
        && grep -q 'pm_ptr(&rsinput_pm_ops)' "${rs}"; then
        echo "  OK   rsinput centers sticks on suspend/resume + PM ops" >&2
    else
        echo "  FAIL missing 1032 rsinput suspend/resume stick centering" >&2
        failed=1
    fi
    [[ "${failed}" -eq 0 ]]
}

apply_masi_rsinput_ff_bridge() {
    local src_dir="$1"
    local rsinput="${src_dir}/drivers/input/joystick/rsinput.c"
    local haptics="${src_dir}/drivers/input/misc/qcom-hv-haptics.c"

    [[ -f "${rsinput}" && -f "${haptics}" ]] || return 1

    python3 - "${rsinput}" "${haptics}" <<'PY'
from pathlib import Path
import sys

rsinput = Path(sys.argv[1])
haptics = Path(sys.argv[2])

def ensure_once(text, needle, insert_before=None, insert_after=None, block=""):
    if needle in text:
        return text, True
    if insert_before and insert_before in text:
        return text.replace(insert_before, block + insert_before, 1), True
    if insert_after and insert_after in text:
        return text.replace(insert_after, insert_after + block, 1), True
    return text, False

ok = True

rt = rsinput.read_text()
rt, found = ensure_once(
    rt,
    'static bool rumble_enable = true;',
    insert_before='static const unsigned int keymap[] = {\n',
    block='static bool rumble_enable = true;\nmodule_param(rumble_enable, bool, 0644);\nMODULE_PARM_DESC(rumble_enable, "Enable gamepad rumble via PMIC haptics");\n\n'
)
ok &= found

rt, found = ensure_once(
    rt,
    'extern int qcom_spmi_haptics_global_set_gain(u16 gain);',
    insert_before='static int rsinput_probe(struct serdev_device *serdev) {\n',
    block=(
        'extern int qcom_spmi_haptics_global_upload(struct ff_effect *effect);\n'
        'extern int qcom_spmi_haptics_global_playback(int effect_id, int val);\n'
        'extern int qcom_spmi_haptics_global_stop(void);\n\n'
        'extern int qcom_spmi_haptics_global_set_gain(u16 gain);\n\n'
        'struct rsinput_rumble_req {\n'
        '\tu16 magnitude;\n'
        '\tu16 length_ms;\n'
        '\tbool stop;\n'
        '};\n\n'
        'static struct rsinput_rumble_req rumble_req;\n'
        'static struct work_struct rumble_work;\n'
        'static DEFINE_MUTEX(rumble_work_lock);\n\n'
        'static void rsinput_rumble_work_fn(struct work_struct *work)\n'
        '{\n'
        '\tstruct rsinput_rumble_req req;\n'
        '\tstruct ff_effect hfx = { 0 };\n'
        '\tu16 level;\n'
        '\tint ret;\n\n'
        '\tmutex_lock(&rumble_work_lock);\n'
        '\treq = rumble_req;\n'
        '\tmutex_unlock(&rumble_work_lock);\n\n'
        '\tif (!rumble_enable)\n'
        '\t\treturn;\n'
        '\tif (req.stop || !req.magnitude) {\n'
        '\t\tqcom_spmi_haptics_global_stop();\n'
        '\t\treturn;\n'
        '\t}\n\n'
        '\thfx.type = FF_CONSTANT;\n'
        '\thfx.id = 0;\n'
        '\thfx.replay.length = req.length_ms ? req.length_ms : 250;\n'
        '\tlevel = max_t(u16, req.magnitude, 0x2000);\n'
        '\thfx.u.constant.level = clamp(level >> 1, 1, 0x7fff);\n\n'
        '\tret = qcom_spmi_haptics_global_upload(&hfx);\n'
        '\tif (ret < 0)\n'
        '\t\treturn;\n'
        '\tret = qcom_spmi_haptics_global_set_gain(level);\n'
        '\tif (ret < 0)\n'
        '\t\treturn;\n'
        '\tqcom_spmi_haptics_global_playback(0, 1);\n'
        '}\n\n'
        'static void rsinput_rumble_cancel(void *unused)\n'
        '{\n'
        '\tcancel_work_sync(&rumble_work);\n'
        '}\n\n'
        'static void rsinput_queue_rumble(u16 magnitude, u16 length_ms, bool stop)\n'
        '{\n'
        '\tmutex_lock(&rumble_work_lock);\n'
        '\trumble_req.magnitude = magnitude;\n'
        '\trumble_req.length_ms = length_ms;\n'
        '\trumble_req.stop = stop;\n'
        '\tmutex_unlock(&rumble_work_lock);\n'
        '\tschedule_work(&rumble_work);\n'
        '}\n\n'
        'static int rsinput_rumble_play_effect(struct input_dev *dev, void *data,\n'
        '\t\t\t\t      struct ff_effect *effect)\n'
        '{\n'
        '\tu16 magnitude = 0;\n'
        '\tu16 length_ms = 0;\n\n'
        '\tif (!rumble_enable)\n'
        '\t\treturn 0;\n\n'
        '\tif (effect->type == FF_RUMBLE) {\n'
        '\t\tmagnitude = max_t(u16, effect->u.rumble.strong_magnitude,\n'
        '\t\t\t\t\t  effect->u.rumble.weak_magnitude);\n'
        '\t\tlength_ms = effect->replay.length;\n'
        '\t} else if (effect->type == FF_PERIODIC) {\n'
        '\t\tmagnitude = abs(effect->u.periodic.magnitude);\n'
        '\t\tlength_ms = effect->replay.length ? effect->replay.length : 30000;\n'
        '\t} else {\n'
        '\t\treturn 0;\n'
        '\t}\n\n'
        '\tif (!magnitude) {\n'
        '\t\trsinput_queue_rumble(0, 0, true);\n'
        '\t\treturn 0;\n'
        '\t}\n\n'
        '\trsinput_queue_rumble(magnitude, length_ms, false);\n'
        '\treturn 0;\n'
        '}\n\n'
    )
)
ok &= found

rt, found = ensure_once(
    rt,
    'INIT_WORK(&rumble_work, rsinput_rumble_work_fn);',
    insert_before='    error = input_register_device(drv->input);\n',
    block=(
        '    INIT_WORK(&rumble_work, rsinput_rumble_work_fn);\n'
        '    devm_add_action(&serdev->dev, rsinput_rumble_cancel, NULL);\n\n'
    )
)
ok &= found

# Replace legacy synchronous play_effect if present from an older bridge revision.
legacy_play_effect = (
    'static int rsinput_rumble_play_effect(struct input_dev *dev, void *data,\n'
    '\t\t\t\t      struct ff_effect *effect)\n'
    '{\n'
    '\tstruct ff_effect hfx = { 0 };\n'
    '\tu16 magnitude;\n'
    '\tint ret;\n\n'
    '\tif (!rumble_enable)\n'
    '\t\treturn 0;\n'
    '\tif (effect->type != FF_RUMBLE)\n'
    '\t\treturn 0;\n\n'
    '\tmagnitude = max_t(u16, effect->u.rumble.strong_magnitude,\n'
    '\t\t\t\t effect->u.rumble.weak_magnitude);\n'
    '\tif (!magnitude)\n'
    '\t\treturn qcom_spmi_haptics_global_playback(0, 0);\n\n'
    '\thfx.type = FF_CONSTANT;\n'
    '\thfx.id = 0;\n'
    '\thfx.replay.length = effect->replay.length ? effect->replay.length : 250;\n'
    '\thfx.u.constant.level = max_t(u16, 1, magnitude >> 1);\n\n'
    '\tret = qcom_spmi_haptics_global_upload(&hfx);\n'
    '\tif (ret < 0)\n'
    '\t\treturn ret;\n'
    '\tret = qcom_spmi_haptics_global_set_gain(magnitude);\n'
    '\tif (ret < 0)\n'
    '\t\treturn ret;\n'
    '\treturn qcom_spmi_haptics_global_playback(0, 1);\n'
    '}\n\n'
)
if legacy_play_effect in rt:
    rt = rt.replace(legacy_play_effect, '')

rt, found = ensure_once(
    rt,
    'input_set_capability(drv->input, EV_FF, FF_RUMBLE);',
    insert_before='    error = input_register_device(drv->input);\n',
    block=(
        '    input_set_capability(drv->input, EV_FF, FF_RUMBLE);\n'
        '    input_set_capability(drv->input, EV_FF, FF_PERIODIC);\n\n'
        '    error = input_ff_create_memless(drv->input, drv, rsinput_rumble_play_effect);\n'
        '    if (error) {\n'
        '        serdev_device_close(serdev);\n'
        '        return dev_err_probe(&serdev->dev, error, "Unable to create force feedback device\\n");\n'
        '    }\n\n'
    )
)
ok &= found

ht = haptics.read_text()
ht, found = ensure_once(
    ht,
    '#include <linux/export.h>\n',
    insert_after='#include <linux/vmalloc.h>\n',
    block='#include <linux/export.h>\n'
)
ok &= found

ht, found = ensure_once(
    ht,
    'static struct haptics_chip *global_haptics;',
    insert_before='static inline int get_max_fifo_samples(struct haptics_chip *chip)\n',
    block='static struct haptics_chip *global_haptics;\n\n'
)
ok &= found

ht, found = ensure_once(
    ht,
    '\tglobal_haptics = chip;\n',
    insert_before='\treturn 0;\n'
                 'destroy_ff:\n',
    block='\tglobal_haptics = chip;\n\n'
)
ok &= found

ht, found = ensure_once(
    ht,
    '\tif (global_haptics == chip)\n'
    '\t\tglobal_haptics = NULL;\n',
    insert_before='\tunregister_hboost_event_notifier(&chip->hboost_nb);\n',
    block='\tif (global_haptics == chip)\n\t\tglobal_haptics = NULL;\n\n'
)
ok &= found

legacy_spinlock_bridge = (
    '\tspin_lock_irq(&global_haptics->input_dev->event_lock);\n'
    '\tret = global_haptics->input_dev->ff->upload(global_haptics->input_dev,\n'
    '\t\t\t\t\t\t    effect, NULL);\n'
    '\tspin_unlock_irq(&global_haptics->input_dev->event_lock);\n'
)
mutex_bridge = (
    '\tmutex_lock(&global_ff_mutex);\n'
    '\tret = global_haptics->input_dev->ff->upload(global_haptics->input_dev,\n'
    '\t\t\t\t\t\t    effect, NULL);\n'
    '\tmutex_unlock(&global_ff_mutex);\n'
)
if legacy_spinlock_bridge in ht:
    ht = ht.replace(legacy_spinlock_bridge, mutex_bridge)
    ht = ht.replace(
        '\tspin_lock_irq(&global_haptics->input_dev->event_lock);\n'
        '\tif (val != 0)\n'
        '\t\tret = global_haptics->input_dev->ff->playback(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t      effect_id, val);\n'
        '\telse\n'
        '\t\tret = global_haptics->input_dev->ff->erase(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t   effect_id);\n'
        '\tspin_unlock_irq(&global_haptics->input_dev->event_lock);\n',
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tif (val != 0) {\n'
        '\t\tret = global_haptics->input_dev->ff->playback(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t      effect_id, val);\n'
        '\t} else if (!global_haptics->chip_is_playing) {\n'
        '\t\tret = 0;\n'
        '\t} else {\n'
        '\t\tret = global_haptics->input_dev->ff->erase(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t   effect_id);\n'
        '\t}\n'
        '\tmutex_unlock(&global_ff_mutex);\n'
    )
    ht = ht.replace(
        '\tspin_lock_irq(&global_haptics->input_dev->event_lock);\n'
        '\tgain = clamp(gain, 0x4000, 0x7fff);\n'
        '\tglobal_haptics->input_dev->ff->set_gain(global_haptics->input_dev, gain);\n'
        '\tspin_unlock_irq(&global_haptics->input_dev->event_lock);\n',
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tgain = clamp(gain, 0x4000, 0x7fff);\n'
        '\tglobal_haptics->input_dev->ff->set_gain(global_haptics->input_dev, gain);\n'
        '\tmutex_unlock(&global_ff_mutex);\n'
    )
    if 'static DEFINE_MUTEX(global_ff_mutex);' not in ht:
        ht = ht.replace(
            'static struct haptics_chip *global_haptics;\n',
            'static struct haptics_chip *global_haptics;\nstatic DEFINE_MUTEX(global_ff_mutex);\n',
            1
        )

ht, found = ensure_once(
    ht,
    'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_playback);',
    insert_before='MODULE_DESCRIPTION("Qualcomm Technologies, Inc. High-Voltage Haptics driver");\n',
    block=(
        'int qcom_spmi_haptics_global_upload(struct ff_effect *effect)\n'
        '{\n'
        '\tint ret;\n\n'
        '\tif (!global_haptics)\n'
        '\t\treturn -ENODEV;\n\n'
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tret = global_haptics->input_dev->ff->upload(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t    effect, NULL);\n'
        '\tmutex_unlock(&global_ff_mutex);\n\n'
        '\treturn ret;\n'
        '}\n'
        'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_upload);\n\n'
        'int qcom_spmi_haptics_global_playback(int effect_id, int val)\n'
        '{\n'
        '\tint ret;\n\n'
        '\tif (!global_haptics)\n'
        '\t\treturn -ENODEV;\n\n'
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tif (val != 0) {\n'
        '\t\tret = global_haptics->input_dev->ff->playback(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t      effect_id, val);\n'
        '\t} else if (!global_haptics->chip_is_playing) {\n'
        '\t\tret = 0;\n'
        '\t} else {\n'
        '\t\tret = global_haptics->input_dev->ff->erase(global_haptics->input_dev,\n'
        '\t\t\t\t\t\t\t   effect_id);\n'
        '\t}\n'
        '\tmutex_unlock(&global_ff_mutex);\n\n'
        '\treturn ret;\n'
        '}\n'
        'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_playback);\n\n'
        'int qcom_spmi_haptics_global_set_gain(u16 gain)\n'
        '{\n'
        '\tif (!global_haptics)\n'
        '\t\treturn -ENODEV;\n\n'
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tgain = clamp(gain, 0x4000, 0x7fff);\n'
        '\tglobal_haptics->input_dev->ff->set_gain(global_haptics->input_dev, gain);\n'
        '\tmutex_unlock(&global_ff_mutex);\n\n'
        '\treturn 0;\n'
        '}\n'
        'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_set_gain);\n\n'
        'int qcom_spmi_haptics_global_stop(void)\n'
        '{\n'
        '\tstruct haptics_play_info *play;\n\n'
        '\tif (!global_haptics)\n'
        '\t\treturn -ENODEV;\n\n'
        '\tplay = &global_haptics->play;\n\n'
        '\tmutex_lock(&global_ff_mutex);\n'
        '\tif (!global_haptics->chip_is_playing) {\n'
        '\t\tglobal_haptics->chip_effect_loaded = false;\n'
        '\t\tmutex_unlock(&global_ff_mutex);\n'
        '\t\treturn 0;\n'
        '\t}\n\n'
        '\tmutex_lock(&play->lock);\n'
        '\tcancel_delayed_work_sync(&global_haptics->stop_work);\n'
        '\thaptics_enable_play(global_haptics, false);\n'
        '\tglobal_haptics->chip_effect_loaded = false;\n'
        '\tmutex_unlock(&play->lock);\n'
        '\tmutex_unlock(&global_ff_mutex);\n\n'
        '\treturn 0;\n'
        '}\n'
        'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_stop);\n\n'
    )
)
ok &= found

ht, found = ensure_once(
    ht,
    'static DEFINE_MUTEX(global_ff_mutex);',
    insert_after='static struct haptics_chip *global_haptics;\n',
    block='static DEFINE_MUTEX(global_ff_mutex);\n'
)
ok &= found

if ok:
    rsinput.write_text(rt)
    haptics.write_text(ht)
    sys.exit(0)
sys.exit(1)
PY
}

verify_masi_thor_panel_reset() {
    local src_dir="$1"
    local panel="${src_dir}/drivers/gpu/drm/panel/panel-ddic-ch13726a.c"
    local chip="${src_dir}/drivers/gpu/drm/panel/panel-chipwealth-ch13726a.c"

    if [[ -f "${chip}" ]]; then
        echo "==> Verify Thor CH13726A reset polarity" >&2
        if grep -q 'devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH)' "${chip}"; then
            echo "  OK   panel-chipwealth-ch13726a reset (mainline 7.2)" >&2
            return 0
        fi
    fi

    [[ -f "${panel}" ]] || return 0

    echo "==> Verify Thor CH13726A reset polarity" >&2

    if grep -q 'devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH)' "${panel}" \
        && ! grep -q 'GPIOD_OUT_LOW' "${panel}"; then
        echo "  OK   panel-ddic-ch13726a reset matches mainline polarity" >&2
        return 0
    fi

    echo "  FAIL panel-ddic-ch13726a still uses inverted reset GPIO" >&2
    return 1
}

verify_masi_dp_audio_patches() {
    local src_dir="$1"
    local drm="${src_dir}/drivers/gpu/drm/display/drm_hdmi_audio_helper.c"
    local q6apm="${src_dir}/sound/soc/qcom/qdsp6/q6apm-lpass-dais.c"
    local failed=0

    [[ -f "${drm}" && -f "${q6apm}" ]] || return 0

    echo "==> Verify DP/HDMI audio patch stack" >&2

    if grep -A8 'drm_connector_hdmi_audio_ops' "${drm}" | grep -q '\.hw_params = drm_connector_hdmi_audio_prepare'; then
        echo "  OK   drm_hdmi_audio: hw_params → DP prepare" >&2
    else
        echo "  FAIL drm_hdmi_audio missing .hw_params callback" >&2
        failed=1
    fi

    if grep -q 'q6apm_lpass_dai_trigger' "${q6apm}" \
        && grep -A6 'q6hdmi_ops' "${q6apm}" | grep -q '\.trigger.*q6apm_lpass_dai_trigger' \
        && ! grep -A20 'q6apm_lpass_dai_prepare' "${q6apm}" | grep -q 'q6apm_graph_start'; then
        echo "  OK   q6apm-lpass-dais: graph start on trigger" >&2
    else
        echo "  FAIL q6apm-lpass-dais missing trigger-based graph start" >&2
        failed=1
    fi

    [[ "${failed}" -eq 0 ]]
}

verify_masi_haptics_stack() {
    local src_dir="$1"
    local rsinput="${src_dir}/drivers/input/joystick/rsinput.c"
    local haptics="${src_dir}/drivers/input/misc/qcom-hv-haptics.c"
    local trace="${src_dir}/include/trace/events/qcom_haptics.h"
    local failed=0

    echo "==> Verify MaSi haptics stack" >&2

    if grep -q 'input_set_capability(drv->input, EV_FF, FF_RUMBLE)' "${rsinput}" \
        && grep -q 'input_ff_create_memless(drv->input, drv, rsinput_rumble_play_effect)' "${rsinput}" \
        && grep -q 'qcom_spmi_haptics_global_set_gain' "${rsinput}" \
        && grep -q 'schedule_work(&rumble_work)' "${rsinput}" \
        && grep -q 'qcom_spmi_haptics_global_stop' "${rsinput}"; then
        echo "  OK   rsinput exposes EV_FF" >&2
    else
        echo "  FAIL rsinput missing EV_FF integration" >&2
        failed=1
    fi

    if grep -q 'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_playback)' "${haptics}" \
        && grep -q 'static struct haptics_chip \*global_haptics' "${haptics}" \
        && grep -q 'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_stop)' "${haptics}" \
        && { grep -q 'mutex_lock(&global_ff_mutex)' "${haptics}" \
             || grep -q 'mutex_lock(&chip->global_ff_lock)' "${haptics}"; }; then
        echo "  OK   qcom-hv-haptics exports mutex-safe global playback hooks" >&2
    else
        echo "  FAIL qcom-hv-haptics missing mutex-safe exported playback hooks" >&2
        failed=1
    fi

    if grep -q '__assign_str(id_name);' "${trace}"; then
        echo "  OK   qcom_haptics trace API matches kernel 7.0" >&2
    else
        echo "  FAIL qcom_haptics trace API not fixed for kernel 7.0" >&2
        failed=1
    fi

    if grep -q 'qcom,use-erm' "${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi" 2>/dev/null \
        && ! grep -qE 'qcom,use-erm[[:space:]]*=' \
            "${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi" 2>/dev/null; then
        echo "  OK   haptics DT ERM/hard (qcom,use-erm)" >&2
    else
        echo "  FAIL haptics DT missing boolean qcom,use-erm (ERM/hard)" >&2
        failed=1
    fi

    [[ "${failed}" -eq 0 ]]
}


# AYANEO SM8550 Pocket family (ACE/DMG/DS/EVO/S 2K) — Armbian sm8550-6.18 DTS + MaSi S1.
apply_masi_ayaneo_dts() {
    local src_dir="$1"
    local src="${ROOT}/patches/masi/ayaneo"
    local qcom="${src_dir}/arch/arm64/boot/dts/qcom"
    local mk="${qcom}/Makefile"
    local f dtb

    [[ -d "${src}" && -f "${mk}" ]] || return 0

    for f in \
        qcs8550-ayaneo-pocket-common.dtsi \
        qcs8550-ayaneo-pocketace.dts \
        qcs8550-ayaneo-pocketdmg.dts \
        qcs8550-ayaneo-pocketds.dts \
        qcs8550-ayaneo-pocketevo.dts \
        qcs8550-ayaneo-pockets1.dts
    do
        [[ -f "${src}/${f}" ]] || {
            echo "ERROR: missing ${src}/${f}" >&2
            return 1
        }
        cp -f "${src}/${f}" "${qcom}/${f}"
    done

    for dtb in \
        qcs8550-ayaneo-pocketace.dtb \
        qcs8550-ayaneo-pocketdmg.dtb \
        qcs8550-ayaneo-pocketds.dtb \
        qcs8550-ayaneo-pocketevo.dtb \
        qcs8550-ayaneo-pockets1.dtb
    do
        if ! grep -q "${dtb}" "${mk}"; then
            if grep -q 'qcs8550-retroidpocket-rp6\.dtb' "${mk}"; then
                sed -i "/qcs8550-retroidpocket-rp6\.dtb/a dtb-\$(CONFIG_ARCH_QCOM) += ${dtb}" "${mk}"
            else
                _ensure_dtb_in_makefile "${mk}" "${dtb}"
            fi
        fi
    done
    echo "  OK   MaSi AYANEO Pocket ACE/DMG/DS/EVO/S1 DTS" >&2
}

# Retroid Pocket 6 DTB — public DTS (LineageOS kernel-ack, adapted for Armbian ayn-common).
# Slot 6 ABL: TOP-DPAD variant (dtb-chain.map name is topdpad, not Armbian top-dpad).
apply_masi_extra_dts() {
    local src_dir="$1"
    local mk="${src_dir}/arch/arm64/boot/dts/qcom/Makefile"
    local qcom="${src_dir}/arch/arm64/boot/dts/qcom"
    local f dtb

    [[ -f "${mk}" ]] || return 1

    for f in qcs8550-retroidpocket-rp6.dts qcs8550-retroidpocket-rp6-topdpad.dts; do
        [[ -f "${ROOT}/patches/masi/${f}" ]] || {
            echo "ERROR: missing ${ROOT}/patches/masi/${f}" >&2
            return 1
        }
        cp -f "${ROOT}/patches/masi/${f}" "${qcom}/${f}"
        dtb="${f%.dts}.dtb"
        if ! grep -q "${dtb}" "${mk}"; then
            _ensure_dtb_in_makefile "${mk}" "${dtb}"
        fi
        echo "  OK   MaSi ${f}" >&2
    done
}

warn_config_source() {
    local base="$1"
    echo "==> Config: ${base}" >&2
    case "${base}" in
        *"/config/golden.config") echo "  MaSi-OS gaming profile" >&2 ;;
        *linux-sm8550-edge.config) echo "  WARNING: fallback defconfig Armbian" >&2 ;;
    esac
}

apply_gaming_kconfig_overrides() {
    local src_dir="$1" cfg="${src_dir}/.config" sc="${src_dir}/scripts/config"
    local gov="${CPUFREQ_GOVERNOR:-performance}"
    [[ -f "${cfg}" && -x "${sc}" ]] || return 0

    echo "==> Overrides gaming kconfig (cpufreq: ${gov})" >&2
    "${sc}" --file "${cfg}" \
        --enable SCHED_SMT --enable SCHED_MC --enable SCHED_CLUSTER \
        --disable PSI \
        --enable MMC_SDHCI_MSM_DOWNSTREAM \
        --enable ENERGY_MODEL \
        --enable CC_OPTIMIZE_FOR_PERFORMANCE \
        --disable CC_OPTIMIZE_FOR_SIZE 2>/dev/null || true

    case "${gov}" in
        performance)
            "${sc}" --file "${cfg}" \
                --enable CPU_FREQ_DEFAULT_GOV_PERFORMANCE \
                --disable CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
                --enable CPU_FREQ_GOV_PERFORMANCE 2>/dev/null || true
            ;;
        *)
            "${sc}" --file "${cfg}" \
                --enable CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
                --disable CPU_FREQ_DEFAULT_GOV_PERFORMANCE \
                --enable CPU_FREQ_GOV_SCHEDUTIL 2>/dev/null || true
            ;;
    esac

    "${sc}" --file "${cfg}" --module DRM_LONTIUM_LT8912B 2>/dev/null || \
        "${sc}" --file "${cfg}" --disable DRM_LONTIUM_LT8912B 2>/dev/null || true

    make -C "${src_dir}" ARCH=arm64 olddefconfig
}

apply_ayn_family_kconfig() {
    local src_dir="$1" cfg="${src_dir}/.config" sc="${src_dir}/scripts/config" sym
    [[ -f "${cfg}" && -x "${sc}" ]] || return 0
    [[ "${AYN_FAMILY_DRIVERS:-1}" == "0" ]] && return 0

    echo "==> AYN SM8550 family drivers" >&2
    for sym in \
        DRM_PANEL_SYNAPTICS_TD4328 DRM_PANEL_BOE_XM91080G \
        DRM_PANEL_CHIPONE_ICNA3512 DRM_PANEL_CHIPONE_ICNA35XX \
        DRM_PANEL_DDIC_CH13726A \
        DRM_PANEL_AR06_4INCH DRM_PANEL_AR02_3INCH DRM_PANEL_AR11_5INCH \
        DRM_PANEL_RENESAS_R63419 \
        TOUCHSCREEN_HYNITRON_CSTXXX TOUCHSCREEN_HYNITRON_ALL \
        TOUCHSCREEN_FOCALTECH_FT5426 TOUCHSCREEN_FOCALTECH_FT5X06 \
        TOUCHSCREEN_EDT_FT5X06 TOUCHSCREEN_GOODIX RMI4_CORE RMI4_I2C RMI4_F12 \
        BACKLIGHT_ODIN2MINI BACKLIGHT_SY7758 \
        DRM_PANEL_RETROID_POCKET_6 \
        JOYSTICK_RSINPUT LEDS_HTR3212 INPUT_FF_MEMLESS \
        INPUT_QCOM_HV_HAPTICS SERIAL_DEV_BUS
    do
        "${sc}" --file "${cfg}" --enable "${sym}" 2>/dev/null || true
    done
    for sym in QCOM_Q6V5_ADSP SND_SOC_SC8280XP SOUNDWIRE SOUNDWIRE_QCOM SND_SOC_QCOM_SDW; do
        "${sc}" --file "${cfg}" --module "${sym}" 2>/dev/null || true
    done
    for sym in SND_SOC_QDSP6_CORE SND_SOC_QDSP6_AFE SND_SOC_QDSP6_ROUTING SND_SOC_QDSP6_APM; do
        "${sc}" --file "${cfg}" --module "${sym}" 2>/dev/null || true
    done
    "${sc}" --file "${cfg}" --enable DRM_MSM_DP 2>/dev/null || true
    make -C "${src_dir}" ARCH=arm64 olddefconfig
}

apply_gaming_config_tweaks() {
    local src_dir="$1"
    [[ "${GAMING_TUNING:-1}" == "0" ]] && return 0
    apply_gaming_kconfig_overrides "${src_dir}"
    apply_ayn_family_kconfig "${src_dir}"
}

prepare_kernel_config() {
    local src_dir="$1" kernel_ver="$2" base
    base="$(resolve_kernel_config "${kernel_ver}")"
    [[ -f "${base}" ]] || base="$(fetch_armbian_defconfig)"

    warn_config_source "${base}"
    cp "${base}" "${src_dir}/.config"
    make -C "${src_dir}" ARCH=arm64 olddefconfig
    "${src_dir}/scripts/config" --file "${src_dir}/.config" \
        --set-str LOCALVERSION "${KERNEL_LOCALVERSION}"
    make -C "${src_dir}" ARCH=arm64 olddefconfig
    apply_gaming_config_tweaks "${src_dir}"
}
