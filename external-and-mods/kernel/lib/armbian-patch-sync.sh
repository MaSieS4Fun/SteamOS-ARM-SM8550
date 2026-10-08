#!/usr/bin/env bash
# Fetch Armbian SM8550 kernel patches from the live archive (and retired series).
#
# linux-<major.minor.x> uses patch/kernel/archive/sm8550-<major.minor> on
# origin/main (today: 7.2.8 → sm8550-7.2), including board DTS copied from dt/.
# Retired series (sm8550-7.0): still fetched from a pinned git commit after
# Armbian deleted the folder from main (2026-09-25).
set -euo pipefail

ARMBIAN_BUILD_GIT_URL="${ARMBIAN_BUILD_GIT_URL:-https://github.com/armbian/build.git}"
ARMBIAN_BUILD_GIT_REF="${ARMBIAN_BUILD_GIT_REF:-main}"
ARMBIAN_RAW_HOST="${ARMBIAN_RAW_HOST:-https://raw.githubusercontent.com/armbian/build}"
# Last commit that still contained patch/kernel/archive/sm8550-7.0
ARMBIAN_ARCHIVE_FALLBACK_SM8550_7_0="${ARMBIAN_ARCHIVE_FALLBACK_SM8550_7_0:-967ae191dbc495a766aeba3b195beff7c3fb46aa}"

_armbian_patch_manifest_path() {
    local patch_set="$1"
    echo "${ROOT}/config/armbian-manifests/${patch_set}.txt"
}

# Same as the requested set. Historical alias files may still say "upstream:".
_armbian_patch_set_upstream() {
    echo "$1"
}

# ARMBIAN_ARCHIVE_FALLBACK_SM8550_7_0, or ARMBIAN_ARCHIVE_FALLBACK_<SET> with ./- → _.
_armbian_fallback_ref() {
    local patch_set="$1"
    local env_name="ARMBIAN_ARCHIVE_FALLBACK_${patch_set^^}"
    env_name="${env_name//[.-]/_}"
    echo "${!env_name:-}"
}

_armbian_contents_api_url() {
    local patch_set="$1" ref="${2:-${ARMBIAN_BUILD_GIT_REF}}" extra="${3:-}"
    local url="https://api.github.com/repos/armbian/build/contents/patch/kernel/archive/${patch_set}"
    [[ -n "${extra}" ]] && url="${url}/${extra}"
    url="${url}?ref=${ref}"
    echo "${url}"
}

# Writes body to $2. Return 0=HTTP 200, 2=404, 1=other/network.
_armbian_http_get_file() {
    local url="$1" out="$2" http
    http="$(curl -sS -L --connect-timeout 15 --max-time 60 \
        -A "MaSi-OS-Kernel-Updater" \
        -H "Accept: application/vnd.github+json" \
        -o "${out}" -w '%{http_code}' "${url}" 2>/dev/null || true)"
    [[ "${http}" == "200" ]] && return 0
    [[ "${http}" == "404" ]] && return 2
    return 1
}

_armbian_json_is_list() {
    python3 -c "
import json,sys
data=json.load(sys.stdin)
sys.exit(0 if isinstance(data, list) else 1)
"
}

# Prints git ref (main or fallback SHA). Empty + exit 1 if the archive is gone.
_armbian_resolve_archive_ref() {
    local patch_set="$1"
    local tmp rc=1 fallback
    local ref="${ARMBIAN_BUILD_GIT_REF}"

    tmp="$(mktemp)"
    _armbian_http_get_file "$(_armbian_contents_api_url "${patch_set}" "${ref}")" "${tmp}" && rc=0 || rc=$?
    if [[ "${rc}" -eq 0 ]] && _armbian_json_is_list < "${tmp}"; then
        rm -f "${tmp}"
        echo "${ref}"
        return 0
    fi
    rm -f "${tmp}"

    fallback="$(_armbian_fallback_ref "${patch_set}")"
    if [[ -n "${fallback}" ]]; then
        if [[ "${rc}" -eq 2 ]]; then
            echo "  ${patch_set}: not on ${ARMBIAN_BUILD_GIT_REF}; using git ${fallback:0:12}" >&2
        else
            echo "  ${patch_set}: ${ARMBIAN_BUILD_GIT_REF} unreachable; using git ${fallback:0:12}" >&2
        fi
        echo "${fallback}"
        return 0
    fi

    # Live series: GitHub rate-limit/network — raw.githubusercontent.com may still work.
    if [[ "${rc}" -ne 2 ]]; then
        echo "${ref}"
        return 0
    fi
    return 1
}

_armbian_patch_names_from_json() {
    python3 -c "
import json,sys
data=json.load(sys.stdin)
if not isinstance(data, list):
    sys.exit(1)
for item in sorted(data, key=lambda x: x.get('name','')):
    name=item.get('name','')
    if name.endswith('.patch'):
        print(name)
"
}

_armbian_names_from_contents_file() {
    local json_file="$1" suffix="$2"
    python3 - "${json_file}" "${suffix}" <<'PY'
import json,sys
path, suffix = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
if not isinstance(data, list):
    sys.exit(1)
exts = tuple(suffix.split(","))
for item in sorted(data, key=lambda x: x.get("name", "")):
    name = item.get("name", "")
    if name.endswith(exts):
        print(f"{name}\t{item.get('sha', '')}")
PY
}

_armbian_index_names() {
    cut -f1
}

_armbian_local_blob_sha() {
    git hash-object "$1" 2>/dev/null || echo ""
}

# Re-download when missing or GitHub blob sha changed (same filename, new patch).
_armbian_blob_outdated() {
    local dest="$1" name="$2" remote_sha="${3:-}"
    local path="${dest}/${name}" local_sha
    [[ -f "${path}" ]] || return 0
    [[ -n "${remote_sha}" ]] || return 1
    local_sha="$(_armbian_local_blob_sha "${path}")"
    [[ "${local_sha}" != "${remote_sha}" ]]
}

_armbian_patch_names_from_api() {
    local patch_set="$1" ref="${2:-}"
    local tmp rc=1
    [[ -n "${ref}" ]] || ref="$(_armbian_resolve_archive_ref "${patch_set}")" || return 1
    tmp="$(mktemp)"
    _armbian_http_get_file "$(_armbian_contents_api_url "${patch_set}" "${ref}")" "${tmp}" && rc=0 || rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        rm -f "${tmp}"
        return 1
    fi
    _armbian_names_from_contents_file "${tmp}" ".patch" | _armbian_index_names || {
        rm -f "${tmp}"
        return 1
    }
    rm -f "${tmp}"
}

_armbian_patch_index_from_api() {
    local patch_set="$1" ref="${2:-}"
    local tmp rc=1
    [[ -n "${ref}" ]] || ref="$(_armbian_resolve_archive_ref "${patch_set}")" || return 1
    tmp="$(mktemp)"
    _armbian_http_get_file "$(_armbian_contents_api_url "${patch_set}" "${ref}")" "${tmp}" && rc=0 || rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        rm -f "${tmp}"
        return 1
    fi
    _armbian_names_from_contents_file "${tmp}" ".patch" || {
        rm -f "${tmp}"
        return 1
    }
    rm -f "${tmp}"
}

_armbian_dt_names_from_api() {
    local patch_set="$1" ref="$2"
    local tmp rc=1
    tmp="$(mktemp)"
    _armbian_http_get_file "$(_armbian_contents_api_url "${patch_set}" "${ref}" "dt")" "${tmp}" && rc=0 || rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        rm -f "${tmp}"
        return 1
    fi
    _armbian_names_from_contents_file "${tmp}" ".dts,.dtsi" | _armbian_index_names || {
        rm -f "${tmp}"
        return 1
    }
    rm -f "${tmp}"
}

_armbian_dt_index_from_api() {
    local patch_set="$1" ref="$2"
    local tmp rc=1
    tmp="$(mktemp)"
    _armbian_http_get_file "$(_armbian_contents_api_url "${patch_set}" "${ref}" "dt")" "${tmp}" && rc=0 || rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        rm -f "${tmp}"
        return 1
    fi
    _armbian_names_from_contents_file "${tmp}" ".dts,.dtsi" || {
        rm -f "${tmp}"
        return 1
    }
    rm -f "${tmp}"
}

_armbian_patch_names_from_manifest() {
    local patch_set="$1" manifest line
    manifest="$(_armbian_patch_manifest_path "${patch_set}")"
    [[ -f "${manifest}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="${line// /}"
        [[ -n "${line}" ]] || continue
        [[ "${line}" == *.patch ]] && echo "${line}"
    done < "${manifest}"
}

_armbian_patch_names_from_cache() {
    local dest="$1"
    if [[ -s "${dest}/.patch-list" ]]; then
        cat "${dest}/.patch-list"
        return 0
    fi
    shopt -s nullglob
    local -a patches=("${dest}"/*.patch)
    shopt -u nullglob
    [[ ${#patches[@]} -gt 0 ]] || return 1
    local p
    for p in "${patches[@]}"; do
        basename "${p}"
    done | sort
}

_armbian_raw_url() {
    local ref="$1" patch_set="$2" rel="$3"
    echo "${ARMBIAN_RAW_HOST}/${ref}/patch/kernel/archive/${patch_set}/${rel}"
}

_armbian_download_file() {
    local url="$1" dest="$2"
    mkdir -p "$(dirname "${dest}")"
    if curl -fsSL --connect-timeout 15 --max-time 180 \
        -A "MaSi-OS-Kernel-Updater" \
        -o "${dest}.partial" "${url}" \
        && [[ -s "${dest}.partial" ]]; then
        mv "${dest}.partial" "${dest}"
        return 0
    fi
    rm -f "${dest}.partial"
    return 1
}

_armbian_dt_names_from_cache() {
    local dest="$1"
    if [[ -s "${dest}/.dt-list" ]]; then
        cat "${dest}/.dt-list"
        return 0
    fi
    shopt -s nullglob
    local -a files=("${dest}/dt"/*.dts "${dest}/dt"/*.dtsi)
    shopt -u nullglob
    [[ ${#files[@]} -gt 0 ]] || return 1
    local f
    for f in "${files[@]}"; do
        basename "${f}"
    done | sort
}

_armbian_sync_dt_bundle() {
    local patch_set="$1" dest="$2" ref="$3"
    local name sha dt_dir="${dest}/dt" index
    local -a dt_files=() missing=()
    local names
    declare -A dt_blobs=()

    index="$(_armbian_dt_index_from_api "${patch_set}" "${ref}" 2>/dev/null)" || index=""
    if [[ -n "${index}" ]]; then
        names="$(printf '%s\n' "${index}" | _armbian_index_names)"
        while IFS=$'\t' read -r name sha; do
            [[ -n "${name}" ]] || continue
            dt_blobs["${name}"]="${sha}"
        done <<< "${index}"
    else
        names="$(_armbian_dt_names_from_api "${patch_set}" "${ref}" 2>/dev/null)" || names=""
    fi

    if [[ -z "${names}" ]]; then
        names="$(_armbian_dt_names_from_cache "${dest}" 2>/dev/null)" || names=""
        [[ -n "${names}" ]] || return 0
        echo "  ${patch_set}: using cached dt/ (API listing unavailable)" >&2
        printf '%s\n' "${names}" > "${dest}/.dt-list"
        return 0
    fi

    mkdir -p "${dt_dir}"
    while IFS= read -r name; do
        [[ -n "${name}" ]] || continue
        dt_files+=("${name}")
        if _armbian_blob_outdated "${dt_dir}" "${name}" "${dt_blobs[${name}]:-}"; then
            missing+=("${name}")
        fi
    done <<< "${names}"

    local dl_fail=0
    if [[ ${#missing[@]} -gt 0 ]]; then
        for name in "${missing[@]}"; do
            _armbian_download_file \
                "$(_armbian_raw_url "${ref}" "${patch_set}" "dt/${name}")" \
                "${dt_dir}/${name}" || dl_fail=1
        done
    fi

    if [[ "${dl_fail}" -eq 1 ]]; then
        echo "  dt/ raw download failed; trying git sparse checkout..." >&2
        _armbian_patch_names_from_git_sparse "${patch_set}" "${dest}" "${ref}" >/dev/null || true
    fi

    missing=()
    for name in "${dt_files[@]}"; do
        if _armbian_blob_outdated "${dt_dir}" "${name}" "${dt_blobs[${name}]:-}"; then
            missing+=("${name}")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: dt/ incomplete for ${patch_set} (missing ${#missing[@]})" >&2
        return 1
    fi

    printf '%s\n' "${dt_files[@]}" > "${dest}/.dt-list"
    echo "  ${patch_set}: ${#dt_files[@]} board DTS from dt/ (${ref})" >&2
}

_armbian_copy_sparse_tree() {
    local patch_set="$1" dest="$2" src="$3"
    [[ -d "${src}" ]] || return 1
    mkdir -p "${dest}"
    cp -f "${src}"/*.patch "${dest}/" 2>/dev/null || return 1
    if [[ -d "${src}/dt" ]]; then
        mkdir -p "${dest}/dt"
        cp -f "${src}/dt"/*.dts "${src}/dt"/*.dtsi "${dest}/dt/" 2>/dev/null || true
    fi
    return 0
}

_armbian_patch_names_from_git_sparse() {
    local patch_set="$1" dest="$2" ref="${3:-}"
    local repo="${CACHE_DIR}/armbian-build-ref"
    local src

    command -v git >/dev/null 2>&1 || return 1
    [[ -n "${ref}" ]] || ref="$(_armbian_resolve_archive_ref "${patch_set}" 2>/dev/null)" || \
        ref="${ARMBIAN_BUILD_GIT_REF}"

    mkdir -p "$(dirname "${repo}")"
    if [[ ! -d "${repo}/.git" ]]; then
        echo "==> Cloning Armbian build repo (sparse, for ${patch_set})..." >&2
        git clone --filter=blob:none --sparse --no-checkout \
            "${ARMBIAN_BUILD_GIT_URL}" "${repo}" 2>/dev/null || return 1
    fi

    git -C "${repo}" sparse-checkout init --cone 2>/dev/null || true
    git -C "${repo}" sparse-checkout set "patch/kernel/archive/${patch_set}" 2>/dev/null || return 1

    if [[ "${ref}" == "${ARMBIAN_BUILD_GIT_REF}" ]]; then
        git -C "${repo}" fetch --depth 1 origin "${ref}" 2>/dev/null || return 1
        git -C "${repo}" checkout -B "${ref}" "origin/${ref}" 2>/dev/null || \
            git -C "${repo}" checkout -B "${ref}" FETCH_HEAD 2>/dev/null || return 1
    else
        git -C "${repo}" fetch --depth 1 origin "${ref}" 2>/dev/null || \
            git -C "${repo}" fetch origin "${ref}" 2>/dev/null || return 1
        git -C "${repo}" checkout --detach FETCH_HEAD 2>/dev/null || \
            git -C "${repo}" checkout --detach "${ref}" 2>/dev/null || return 1
    fi

    src="${repo}/patch/kernel/archive/${patch_set}"
    _armbian_copy_sparse_tree "${patch_set}" "${dest}" "${src}" || return 1
    _armbian_patch_names_from_cache "${dest}"
}

_armbian_resolve_patch_names() {
    local patch_set="$1" dest="$2" names="" ref=""

    ref="$(_armbian_resolve_archive_ref "${patch_set}" 2>/dev/null)" || ref=""
    if [[ -n "${ref}" ]]; then
        names="$(_armbian_patch_names_from_api "${patch_set}" "${ref}" 2>/dev/null)" && {
            echo "${names}"
            return 0
        }
    fi

    echo "  GitHub API unavailable for ${patch_set}; trying git/manifest/cache" >&2
    names="$(_armbian_patch_names_from_git_sparse "${patch_set}" "${dest}" "${ref}" 2>/dev/null)" && {
        echo "${names}"
        return 0
    }
    names="$(_armbian_patch_names_from_manifest "${patch_set}" 2>/dev/null)" && {
        echo "${names}"
        return 0
    }
    _armbian_patch_names_from_cache "${dest}" 2>/dev/null
}

# Apply only the resolved series list (ignore leftover files from an older set).
_armbian_patch_paths_to_apply() {
    local patch_dir="$1" name
    if [[ -s "${patch_dir}/.patch-list" ]]; then
        while IFS= read -r name || [[ -n "${name}" ]]; do
            name="${name%%#*}"
            name="${name// /}"
            [[ -n "${name}" ]] || continue
            [[ -f "${patch_dir}/${name}" ]] && printf '%s\n' "${patch_dir}/${name}"
        done < "${patch_dir}/.patch-list"
        return 0
    fi
    shopt -s nullglob
    local p
    for p in "${patch_dir}"/*.patch; do
        printf '%s\n' "${p}"
    done
    shopt -u nullglob
}

_armbian_patch_list_stamp() {
    local patch_dir="$1" name f
    {
        [[ -s "${patch_dir}/.patch-list" ]] && cat "${patch_dir}/.patch-list"
        if [[ -s "${patch_dir}/.patch-list" ]]; then
            while IFS= read -r name; do
                [[ -n "${name}" && -f "${patch_dir}/${name}" ]] || continue
                git hash-object "${patch_dir}/${name}"
            done < "${patch_dir}/.patch-list"
        fi
        if [[ -d "${patch_dir}/dt" ]]; then
            while IFS= read -r f; do
                [[ -f "${f}" ]] || continue
                git hash-object "${f}"
            done < <(find "${patch_dir}/dt" -type f | sort)
        fi
    } | sha256sum | awk '{print $1}'
}

_armbian_seed_patch_cache_from_upstream() {
    return 1
}
