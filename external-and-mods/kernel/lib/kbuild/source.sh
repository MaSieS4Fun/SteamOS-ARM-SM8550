#!/usr/bin/env bash
set -euo pipefail

download_kernel_source() {
    local ver="$1" dest tar src_dir url ok=0
    dest="${CACHE_DIR}/linux-${ver}"
    src_dir="${dest}"

    if [[ -f "${src_dir}/Makefile" ]]; then
        local mkver
        mkver="$(make -s -C "${src_dir}" kernelversion 2>/dev/null || true)"
        if [[ "${mkver}" == "${ver}" ]]; then
            echo "==> Kernel source: linux-${ver} (cached, originally from kernel.org CDN)" >&2
            echo "${src_dir}"
            return 0
        fi
    fi

    if tar="$(kernel_tarball_for_version "${ver}" 2>/dev/null)" && [[ -n "${tar}" ]]; then
        echo "==> Kernel source: linux-${ver} (tarball cached — kernel.org CDN)" >&2
    else
        echo "==> Kernel source: linux-${ver} (will download from kernel.org CDN + mirrors)" >&2
    fi

    echo "==> Downloading linux-${ver}" >&2
    while IFS= read -r url; do
        [[ -n "${url}" ]] || continue
        tar="$(kernel_tarball_archive_path "${ver}" "${url}")"
        if [[ -f "${tar}" ]]; then
            if kernel_tarball_validate "${tar}"; then
                ok=1
                break
            fi
            echo "  invalid cache (${tar}), re-downloading ..." >&2
            rm -f "${tar}"
        fi
        echo "  trying ${url} ..." >&2
        if curl -fsSL --connect-timeout 15 --max-time 600 -A "${KERNEL_CDN_UA}" -L -o "${tar}.partial" "${url}" \
            && kernel_tarball_validate "${tar}.partial"; then
            mv "${tar}.partial" "${tar}"
            ok=1
            break
        fi
        rm -f "${tar}.partial"
    done < <(kernel_tarball_urls "${ver}")

    [[ "${ok}" == "1" ]] || {
        echo "Error: could not download linux-${ver} (CDN + GitHub gregkh/linux)" >&2
        return 1
    }

    echo "==> Extracting linux-${ver}" >&2
    src_dir="$(extract_kernel_tarball "${tar}" "${CACHE_DIR}" "${ver}")" || return 1
    echo "${src_dir}"
}

fetch_armbian_defconfig() {
    local dest="${CACHE_DIR}/linux-sm8550-edge.config"
    if [[ ! -f "${dest}" ]]; then
        echo "==> Downloading Armbian sm8550 defconfig" >&2
        curl -fsSL --max-time 30 \
            "${ARMBIAN_PATCH_RAW}/config/kernel/linux-sm8550-edge.config" \
            -o "${dest}"
    fi
    echo "${dest}"
}

fetch_armbian_patches() {
    local patch_set="$1" dest="${PATCH_CACHE}/${patch_set}"
    local upstream names name raw_url

    upstream="$(_armbian_patch_set_upstream "${patch_set}")"
    if [[ "${upstream}" != "${patch_set}" ]]; then
        echo "  ${patch_set}: not on Armbian yet — download source ${upstream}" >&2
    fi

    mkdir -p "${dest}"

    names="$(_armbian_resolve_patch_names "${patch_set}" "${dest}")" || {
        echo "ERROR: could not resolve patch list for ${patch_set}" >&2
        echo "  Tip: rm -rf ${dest} .cache/armbian-build-ref and re-run ./make.sh" >&2
        return 1
    }

    [[ -n "${names}" ]] || {
        echo "ERROR: patch set ${patch_set} is empty" >&2
        return 1
    }

    local -a expected=() missing=()
    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        expected+=("${name}")
        [[ -f "${dest}/${name}" ]] || missing+=("${name}")
    done <<< "${names}"

    if [[ ${#missing[@]} -gt 0 ]]; then
        if [[ ${#missing[@]} -eq ${#expected[@]} ]] \
            && _armbian_seed_patch_cache_from_upstream "${patch_set}" "${dest}" "${upstream}"; then
            missing=()
            for name in "${expected[@]}"; do
                [[ -f "${dest}/${name}" ]] || missing+=("${name}")
            done
        fi
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        if [[ ${#missing[@]} -eq ${#expected[@]} ]]; then
            echo "==> Downloading patches ${patch_set} (${#expected[@]} files from ${upstream} via raw.githubusercontent.com)" >&2
        else
            echo "==> Syncing ${#missing[@]} missing patch(es) for ${patch_set} (from ${upstream})" >&2
        fi
        local dl_fail=0 name
        for name in "${missing[@]}"; do
            raw_url="${ARMBIAN_PATCH_RAW}/patch/kernel/archive/${upstream}/${name}"
            if curl -fsSL --connect-timeout 15 --max-time 180 \
                -A "MaSi-OS-Kernel-Updater" \
                -o "${dest}/${name}.partial" "${raw_url}" \
                && [[ -s "${dest}/${name}.partial" ]]; then
                mv "${dest}/${name}.partial" "${dest}/${name}"
            else
                rm -f "${dest}/${name}.partial"
                dl_fail=1
            fi
        done
        if [[ "${dl_fail}" -eq 1 ]]; then
            echo "  raw download failed; trying git sparse checkout (${upstream})..." >&2
            _armbian_patch_names_from_git_sparse "${upstream}" "${dest}" >/dev/null || {
                echo "ERROR: could not download ${patch_set} patches (source ${upstream}; API/raw/git)" >&2
                return 1
            }
        fi
    fi

    shopt -s nullglob
    local -a patches=("${dest}"/*.patch)
    shopt -u nullglob
    [[ ${#patches[@]} -ge ${#expected[@]} ]] || {
        echo "ERROR: patch cache incomplete for ${patch_set} (${#patches[@]}/${#expected[@]} in ${dest})" >&2
        echo "  Tip: rm -rf ${dest} and re-run ./make.sh" >&2
        return 1
    }

    echo "${dest}"
}
