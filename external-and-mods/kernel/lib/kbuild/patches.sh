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

apply_armbian_patches() {
    local src_dir="$1" patch_set="$2" kernel_ver="$3"
    local patch_dir failed=0 applied=0 skipped=0 denied=0
    local stamp="${src_dir}/.masi-patched-${patch_set}-ok"
    patch_dir="$(fetch_armbian_patches "${patch_set}")"
    mkdir -p "${OUTPUT_DIR}"
    local log="${OUTPUT_DIR}/patch-log-${patch_set}.txt"
    : > "${log}"

    if [[ -f "${stamp}" ]]; then
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
        if _kernel_is_72_series "${kernel_ver}"; then
            bridge_72_fixup_compile_apis "${src_dir}" || return 1
            verify_sm8550_72_compile "${src_dir}" || return 1
        fi
        echo "==> Patches ${patch_set} already applied (linux-${kernel_ver})" >&2
        return 0
    fi

    reset_kernel_source_from_tarball "${kernel_ver}" || return 1

    echo "==> Applying patches ${patch_set} (linux-${kernel_ver})" >&2
    shopt -s nullglob
    local patch base fail_log
    for patch in "${patch_dir}"/*.patch; do
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
    done
    shopt -u nullglob

    echo "==> Patches: ${applied} ok, ${skipped} skip, ${denied} deny, ${failed} fail" >&2

    if _kernel_is_72_series "${kernel_ver}"; then
        apply_sm8550_72_patch_bridges "${src_dir}" "${patch_dir}" "${kernel_ver}" || true
    fi

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

    touch "${stamp}"
}

# HV haptics + gamepad rumble (Batocera-derived DT fragment for all AYN SM8550 boards).
apply_masi_haptics_dtsi() {
    local src_dir="$1"
    local dtsi="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi"
    local frag="${ROOT}/patches/masi/qcs8550-ayn-haptics.dtsi.frag"
    local tmp marker='&pm8550b_eusb2_repeater'

    [[ -f "${dtsi}" && -f "${frag}" ]] || return 0
    if grep -q 'qcom,hv-haptics' "${dtsi}"; then
        if grep -qE 'qcom,use-erm[[:space:]]*=' "${dtsi}"; then
            sed -i '/qcom,use-erm[[:space:]]*=/d' "${dtsi}"
            echo "  FIX  MaSi haptics DT: drop invalid qcom,use-erm value" >&2
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
        1013-thermal-qcom-tsens-skip-ayn-thor-uplow-wake-irq.patch; do
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
        1013-thermal-qcom-tsens-skip-ayn-thor-uplow-wake-irq.patch; do
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
    esac
}

_masi_patch_content_present() {
    local src_dir="$1" base="$2"

    case "${base}" in
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
    *)
        return 1
        ;;
    esac
}

_masi_apply_single_patch() {
    local src_dir="$1" patch="$2"
    local base rc=0

    base="$(basename "${patch}")"
    if patch -p1 --dry-run -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
        patch -p1 -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1
        return $?
    fi
    if patch -p1 --dry-run -l -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1; then
        patch -p1 -l -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1
        return $?
    fi
    if patch -p1 --dry-run -R -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1 \
        && _masi_patch_content_present "${src_dir}" "${base}"; then
        return 2
    fi
    if _masi_patch_already_applied "${src_dir}" "${base}"; then
        return 2
    fi
    case "${base}" in
    1007-scsi-ufs-qcom-balance-irq-on-host-reset-error.patch)
        apply_masi_ufs_host_reset_bridge "${src_dir}" && return 0
        ;;
    1012-mailbox-qcom-ipcc-remove-irqf-no-suspend.patch)
        apply_masi_ipcc_no_suspend_bridge "${src_dir}" && return 0
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
    fi

    verify_masi_suspend_stack "${src_dir}" || failed=1
    verify_masi_dp_audio_patches "${src_dir}" || failed=1
    verify_masi_gmu_bw_vote_stack "${src_dir}" || failed=1
    verify_masi_rsinput_suspend_stack "${src_dir}" || failed=1
    ensure_masi_compile2_log_quiet "${src_dir}" || failed=1
    ensure_masi_compile3_log_quiet "${src_dir}" || failed=1
    [[ "${failed}" -eq 0 ]]
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
        && grep -q 'mutex_lock(&global_ff_mutex)' "${haptics}" \
        && grep -q 'EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_stop)' "${haptics}"; then
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
apply_masi_extra_dts() {
    local src_dir="$1"
    local extra="${ROOT}/patches/masi/qcs8550-retroidpocket-rp6.dts"
    local mk="${src_dir}/arch/arm64/boot/dts/qcom/Makefile"
    local dest="${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-retroidpocket-rp6.dts"

    [[ -f "${extra}" ]] || return 0
    [[ -f "${mk}" ]] || return 1

    cp -f "${extra}" "${dest}"
    if ! grep -q 'qcs8550-retroidpocket-rp6\.dtb' "${mk}"; then
        sed -i '/qcs8550-ayn-thor\.dtb/a dtb-$(CONFIG_ARCH_QCOM) += qcs8550-retroidpocket-rp6.dtb' "${mk}"
    fi
    echo "  OK   MaSi qcs8550-retroidpocket-rp6.dts" >&2
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
