#!/usr/bin/env bash
set -euo pipefail

verify_eas_in_dtsi() {
    local dtsi="$1"
    [[ -f "${dtsi}" ]] || { echo "EAS: missing ${dtsi}" >&2; return 1; }

    local -a expect=(
        "cpu@0|326" "cpu@100|326" "cpu@200|326"
        "cpu@300|693" "cpu@700|1024"
    )
    local entry cpu cap block failed=0

    echo "==> EAS sm8550.dtsi (gaming capacities)" >&2
    for entry in "${expect[@]}"; do
        cpu="${entry%%|*}"
        cap="${entry#*|}"
        block="$(awk -v cpu="${cpu}" '
            $0 ~ cpu "[[:space:]]*\\{" { found=1; next }
            found && /capacity-dmips-mhz/ { gsub(/[^0-9]/, "", $0); print; exit }
            found && /^[[:space:]]*}[[:space:]]*$/ { exit }
        ' "${dtsi}")"
        if [[ "${block}" == "${cap}" ]]; then
            echo "  OK  ${cpu}=${cap}" >&2
        else
            echo "  !!  ${cpu}=${block:-?} (expected ${cap})" >&2
            failed=1
        fi
    done

    [[ "${failed}" -eq 0 ]] || {
        echo "  Gaming performance at risk if EAS patch did not apply." >&2
        return 1
    }
}

resolve_dtb_targets() {
    local choice="${1:-all}"
    if [[ "${choice}" == "all" ]]; then
        # shellcheck source=lib/dtb-chain/targets.sh
        source "${ROOT}/lib/dtb-chain/targets.sh"
        dtb_chain_all_compile_targets
        return 0
    fi
    while IFS='|' read -r id dtb label; do
        [[ -z "${id}" || "${id}" =~ ^# ]] && continue
        [[ "${id}" == "${choice}" ]] && echo "${dtb}" && return 0
    done < "${ROOT}/config/devices.conf"
    echo "Unknown device: ${choice}" >&2
    return 1
}

compile_kernel_tree() {
    local src_dir="$1" ver="$2" device_choice="${3:-all}"
    local release="${ver}${KERNEL_LOCALVERSION}"
    local out="${OUTPUT_DIR}/${release}-${OUTPUT_SUFFIX:-kbase}"
    local staging
    staging="$(build_staging_dir "${release}")"
    local dtb_staging="${staging}/dtbs"
    local modules_out="${out}/modules/${release}"
    local -a dtb_targets=() dtb base

    rm -rf "${staging}" "${out}/modules" "${out}/.staging" "${out}/meta"
    mkdir -p "${dtb_staging}" "${modules_out}"

    while IFS= read -r dtb; do
        [[ -n "${dtb}" ]] && dtb_targets+=("qcom/${dtb}")
    done < <(resolve_dtb_targets "${device_choice}")

    echo "==> Building ${release} (${JOBS} jobs, ${#dtb_targets[@]} DTBs)" >&2

    make -C "${src_dir}" ARCH=arm64 -j"${JOBS}" Image modules
    make -C "${src_dir}" ARCH=arm64 -j"${JOBS}" "${dtb_targets[@]}"

    [[ -f "${src_dir}/arch/arm64/boot/Image" ]] || {
        echo "Error: Image not generated" >&2
        return 1
    }

    cp -f "${src_dir}/arch/arm64/boot/Image" "${staging}/Image"
    cp -f "${src_dir}/System.map" "${staging}/System.map"
    cp -f "${src_dir}/.config" "${staging}/config-${release}"

    for dtb in "${dtb_targets[@]}"; do
        base="$(basename "${dtb}")"
        if [[ -f "${src_dir}/arch/arm64/boot/dts/qcom/${base}" ]]; then
            cp -f "${src_dir}/arch/arm64/boot/dts/qcom/${base}" "${dtb_staging}/${base}"
            echo "  DTB ${base}" >&2
        else
            echo "  MISSING DTB: ${base}" >&2
            return 1
        fi
    done

    rm -rf "${staging}/.modules-staging"
    make -C "${src_dir}" ARCH=arm64 \
        modules_install INSTALL_MOD_PATH="${staging}/.modules-staging" INSTALL_MOD_STRIP=1

    rm -rf "${modules_out}"
    mv "${staging}/.modules-staging/lib/modules/${release}" "${modules_out}/"
    rm -rf "${staging}/.modules-staging"

    # Source tree symlinks — must not ship to the device.
    rm -f "${modules_out}/source" "${modules_out}/build"

    local nko
    nko="$(find "${modules_out}" -name '*.ko' 2>/dev/null | wc -l)"
    echo "  modules/${release}/ (${nko} .ko)" >&2

    BUILD_OUT_DIR="${out}"
    BUILD_RELEASE="${release}"
    BUILD_KERNEL_VER="${ver}"
}

write_kbuild_manifest() {
    local out_dir="${BUILD_OUT_DIR:-}" ver="${BUILD_KERNEL_VER:-}"
    [[ -n "${out_dir}" ]] || return 0
    local manifest="${out_dir}/MANIFEST.txt"
    cat > "${manifest}" <<EOF
Kernel_MaSi-OS — kbuild
kernel: linux-${ver}
release: ${BUILD_RELEASE:-}
output: ${out_dir}
date: $(date -Iseconds)
jobs: ${JOBS}
gaming_tuning: ${GAMING_TUNING:-1}
device_target: ${DEVICE_TARGET:-all}
EOF
    echo "==> ${manifest}" >&2
}
