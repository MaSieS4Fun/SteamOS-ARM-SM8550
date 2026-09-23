#!/usr/bin/env bash
# Fetch Armbian kernel patches without relying on the GitHub REST API (403/rate limits).
set -euo pipefail

ARMBIAN_BUILD_GIT_URL="${ARMBIAN_BUILD_GIT_URL:-https://github.com/armbian/build.git}"
ARMBIAN_BUILD_GIT_REF="${ARMBIAN_BUILD_GIT_REF:-main}"

_armbian_patch_manifest_path() {
    local patch_set="$1"
    echo "${ROOT}/config/armbian-manifests/${patch_set}.txt"
}

# Bootstrap sets (sm8550-7.2) reuse Armbian sm8550-7.0 until published upstream.
_armbian_patch_set_upstream() {
    local patch_set="$1" manifest line upstream=""
    manifest="$(_armbian_patch_manifest_path "${patch_set}")"
    if [[ -f "${manifest}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ "${line}" =~ ^#[[:space:]]*upstream:[[:space:]]*(sm8550-[0-9.]+)[[:space:]]*$ ]] || continue
            upstream="${BASH_REMATCH[1]}"
            break
        done < "${manifest}"
    fi
    if [[ -n "${upstream}" ]]; then
        echo "${upstream}"
        return 0
    fi
    case "${patch_set}" in
        sm8550-7.2) echo "sm8550-7.0" ;;
        *) echo "${patch_set}" ;;
    esac
}

_armbian_seed_patch_cache_from_upstream() {
    local patch_set="$1" dest="$2" upstream="$3"
    local up_dir="${PATCH_CACHE}/${upstream}"

    [[ "${upstream}" != "${patch_set}" ]] || return 1
    [[ -d "${up_dir}" ]] || return 1

    shopt -s nullglob
    local -a up_patches=("${up_dir}"/*.patch)
    shopt -u nullglob
    [[ ${#up_patches[@]} -gt 0 ]] || return 1

    mkdir -p "${dest}"
    cp -f "${up_dir}"/*.patch "${dest}/"
    echo "  seeded ${patch_set} from cached ${upstream} (${#up_patches[@]} patches)" >&2
    return 0
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

_armbian_patch_names_from_api() {
    local patch_set="$1"
    local api="https://api.github.com/repos/armbian/build/contents/patch/kernel/archive/${patch_set}"
    curl -fsSL --connect-timeout 15 --max-time 60 \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: MaSi-OS-Kernel-Updater" \
        "${api}" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in sorted(data, key=lambda x: x['name']):
    if item['name'].endswith('.patch'):
        print(item['name'])
"
}

_armbian_patch_names_from_cache() {
    local dest="$1"
    shopt -s nullglob
    local -a patches=("${dest}"/*.patch)
    shopt -u nullglob
    [[ ${#patches[@]} -gt 0 ]] || return 1
    local p
    for p in "${patches[@]}"; do
        basename "${p}"
    done | sort
}

_armbian_patch_names_from_git_sparse() {
    local patch_set="$1" dest="$2"
    local repo="${CACHE_DIR}/armbian-build-ref"
    local src

    command -v git >/dev/null 2>&1 || return 1

    if [[ ! -d "${repo}/.git" ]]; then
        echo "==> Cloning Armbian build repo (sparse, for ${patch_set})..." >&2
        git clone --depth 1 --filter=blob:none --sparse \
            --branch "${ARMBIAN_BUILD_GIT_REF}" \
            "${ARMBIAN_BUILD_GIT_URL}" "${repo}" 2>/dev/null || return 1
    fi

    git -C "${repo}" fetch --depth 1 origin "${ARMBIAN_BUILD_GIT_REF}" 2>/dev/null || true
    git -C "${repo}" checkout "${ARMBIAN_BUILD_GIT_REF}" 2>/dev/null || \
        git -C "${repo}" checkout -B "${ARMBIAN_BUILD_GIT_REF}" "origin/${ARMBIAN_BUILD_GIT_REF}" 2>/dev/null || true

    if ! git -C "${repo}" sparse-checkout list 2>/dev/null | grep -q "patch/kernel/archive/${patch_set}"; then
        git -C "${repo}" sparse-checkout set "patch/kernel/archive/${patch_set}" 2>/dev/null || {
            git -C "${repo}" sparse-checkout init --cone 2>/dev/null || true
            git -C "${repo}" sparse-checkout set "patch/kernel/archive/${patch_set}" 2>/dev/null || return 1
        }
    fi

    git -C "${repo}" pull --ff-only --depth 1 2>/dev/null || true

    src="${repo}/patch/kernel/archive/${patch_set}"
    [[ -d "${src}" ]] || return 1

    mkdir -p "${dest}"
    cp -f "${src}"/*.patch "${dest}/" 2>/dev/null || return 1
    _armbian_patch_names_from_cache "${dest}"
}

_armbian_resolve_patch_names() {
    local patch_set="$1" dest="$2" names=""

    names="$(_armbian_patch_names_from_api "${patch_set}" 2>/dev/null)" && {
        echo "${names}"
        return 0
    }

    echo "  GitHub API unavailable for ${patch_set}; using offline manifest/git fallback" >&2
    names="$(_armbian_patch_names_from_manifest "${patch_set}" 2>/dev/null)" && {
        echo "${names}"
        return 0
    }

    names="$(_armbian_patch_names_from_git_sparse "${patch_set}" "${dest}" 2>/dev/null)" && {
        echo "${names}"
        return 0
    }

    _armbian_patch_names_from_cache "${dest}" 2>/dev/null
}
