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

_armbian_copy_missing_patches() {
    local dest="$1" src="$2"
    shift 2
    local name copied=0
    [[ -d "${src}" ]] || return 1
    for name in "$@"; do
        [[ -f "${dest}/${name}" ]] && continue
        [[ -f "${src}/${name}" ]] || continue
        cp -f "${src}/${name}" "${dest}/${name}"
        copied=$((copied + 1))
    done
    [[ "${copied}" -gt 0 ]]
}

fetch_armbian_patches() {
    local patch_set="$1"
    local dest="${PATCH_CACHE}/${patch_set}"
    local names name raw_url ref index sha

    if ! mkdir -p "${dest}" 2>/dev/null || ! touch "${dest}/.writable" 2>/dev/null; then
        echo "ERROR: cannot write ${dest} (directory not writable — often left as root from a sudo build)" >&2
        echo "  Fix: sudo chown -R \"\$USER:\$USER\" \"${PATCH_CACHE}\"" >&2
        return 1
    fi
    rm -f "${dest}/.writable"

    ref="$(_armbian_resolve_archive_ref "${patch_set}")" || {
        echo "ERROR: Armbian archive ${patch_set} is not on ${ARMBIAN_BUILD_GIT_REF} and has no fallback git ref" >&2
        echo "  Tip: keep ${dest} if you still have a working cache" >&2
        return 1
    }

    declare -A blobs=()
    index="$(_armbian_patch_index_from_api "${patch_set}" "${ref}" 2>/dev/null)" || index=""
    if [[ -n "${index}" ]]; then
        names="$(printf '%s\n' "${index}" | _armbian_index_names)"
        while IFS=$'\t' read -r name sha; do
            [[ -n "${name}" ]] || continue
            blobs["${name}"]="${sha}"
        done <<< "${index}"
    else
        names="$(_armbian_resolve_patch_names "${patch_set}" "${dest}")" || {
            echo "ERROR: could not resolve patch list for ${patch_set}" >&2
            echo "  Tip: keep ${dest} (do not delete a working cache)" >&2
            return 1
        }
    fi

    [[ -n "${names}" ]] || {
        echo "ERROR: patch set ${patch_set} is empty" >&2
        return 1
    }

    local -a expected=() missing=()
    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        expected+=("${name}")
        if _armbian_blob_outdated "${dest}" "${name}" "${blobs[${name}]:-}"; then
            missing+=("${name}")
        fi
    done <<< "${names}"

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "  ${patch_set}: ${#expected[@]} patches from local cache (${ref})" >&2
        printf '%s\n' "${expected[@]}" > "${dest}/.patch-list"
        printf '%s\n' "${ref}" > "${dest}/.armbian-ref"
        _armbian_sync_dt_bundle "${patch_set}" "${dest}" "${ref}" || return 1
        echo "${dest}"
        return 0
    fi

    local -a seed_dirs=(
        "${CACHE_DIR}/armbian-build-ref/patch/kernel/archive/${patch_set}"
        "${ROOT}/patches/armbian/${patch_set}"
    )
    local seed
    for seed in "${seed_dirs[@]}"; do
        [[ ${#missing[@]} -gt 0 ]] || break
        _armbian_copy_missing_patches "${dest}" "${seed}" "${missing[@]}" || true
        missing=()
        for name in "${expected[@]}"; do
            if _armbian_blob_outdated "${dest}" "${name}" "${blobs[${name}]:-}"; then
                missing+=("${name}")
            fi
        done
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "==> Syncing ${#missing[@]} patch(es) for ${patch_set} (Armbian ${ref})" >&2
        local dl_fail=0
        for name in "${missing[@]}"; do
            raw_url="$(_armbian_raw_url "${ref}" "${patch_set}" "${name}")"
            if _armbian_download_file "${raw_url}" "${dest}/${name}"; then
                :
            else
                dl_fail=1
            fi
        done
        if [[ "${dl_fail}" -eq 1 ]]; then
            echo "  raw download failed; trying git sparse checkout (${patch_set} @ ${ref})..." >&2
            _armbian_patch_names_from_git_sparse "${patch_set}" "${dest}" "${ref}" >/dev/null || true
        fi
        missing=()
        for name in "${expected[@]}"; do
            if _armbian_blob_outdated "${dest}" "${name}" "${blobs[${name}]:-}"; then
                missing+=("${name}")
            fi
        done
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: patch cache incomplete for ${patch_set} (missing ${#missing[@]}/${#expected[@]} in ${dest})" >&2
        echo "  ref=${ref}  url=$(_armbian_raw_url "${ref}" "${patch_set}" "<name>.patch")" >&2
        return 1
    fi

    printf '%s\n' "${expected[@]}" > "${dest}/.patch-list"
    printf '%s\n' "${ref}" > "${dest}/.armbian-ref"
    _armbian_sync_dt_bundle "${patch_set}" "${dest}" "${ref}" || return 1
    echo "  ${patch_set}: ${#expected[@]} patches ready (${ref})" >&2
    echo "${dest}"
}

