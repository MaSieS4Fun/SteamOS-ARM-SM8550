#!/usr/bin/env bash
# Discover SM8550 kernel series supported by Armbian patches.
set -euo pipefail

ARMBIAN_ARCHIVE_API="https://api.github.com/repos/armbian/build/contents/patch/kernel/archive"
ARMBIAN_SUPPORT_CACHE="${CACHE_DIR}/armbian-support.env"
ARMBIAN_SUPPORT_TTL="${ARMBIAN_SUPPORT_TTL:-43200}"

declare -ga ARMBIAN_KERNEL_SERIES=()
declare -gA ARMBIAN_SERIES_PATCH_SET=()
declare -g ARMBIAN_EDGE_SERIES=""
declare -g ARMBIAN_SUPPORT_MODE=""

# Offline fallback — newest first (edge 7.2 target, then 7.0, 6.18).
FALLBACK_KERNEL_SERIES=(7.2 7.0 6.18)
declare -gA FALLBACK_SERIES_PATCH_SET=(
    ["7.2"]="sm8550-7.2"
    ["7.0"]="sm8550-7.0"
    ["6.18"]="sm8550-6.18"
)

# Optional: move PREFERRED_KERNEL_SERIES to index 0 when set (e.g. 7.0 or 6.18).
_prefer_kernel_series() {
    local prefer="${PREFERRED_KERNEL_SERIES:-}" s
    local -a rest=()
    [[ -n "${prefer}" ]] || return 0
    _kernel_series_is_listed "${prefer}" || return 0
    for s in "${ARMBIAN_KERNEL_SERIES[@]}"; do
        [[ "${s}" == "${prefer}" ]] || rest+=("${s}")
    done
    ARMBIAN_KERNEL_SERIES=("${prefer}" "${rest[@]}")
    ARMBIAN_EDGE_SERIES="${prefer}"
}

# Shown in menus when Armbian has not published the patch set yet.
WITHHELD_KERNEL_SERIES=(7.1)

_expected_patch_set_for_series() {
    echo "sm8550-${1}"
}

_patch_set_matches_kernel_series() {
    local ver="$1" ps="$2"
    [[ "${ps}" == "$(_expected_patch_set_for_series "$(kernel_major_minor "${ver}")")" ]]
}

_kernel_series_is_listed() {
    local series="$1" s
    for s in "${ARMBIAN_KERNEL_SERIES[@]}"; do
        [[ "${s}" == "${series}" ]] && return 0
    done
    return 1
}

_armbian_patch_set_published() {
    local ps="$1" dir manifest
    dir="${PATCH_CACHE:-${CACHE_DIR}/armbian-patches}/${ps}"

    shopt -s nullglob
    local -a cached=("${dir}"/*.patch)
    shopt -u nullglob
    [[ ${#cached[@]} -gt 0 ]] && return 0

    manifest="${ROOT}/config/armbian-manifests/${ps}.txt"
    [[ -f "${manifest}" ]] && return 0
    return 1
}

_series_patch_mapping_valid() {
    local series="$1" ps="${2:-}"
    [[ -n "${ps}" ]] || return 1
    [[ "${ps}" == "$(_expected_patch_set_for_series "${series}")" ]]
}

_filter_published_kernel_series() {
    local trust_listed="${1:-0}"
    local -a kept=()
    local s ps

    for s in "${ARMBIAN_KERNEL_SERIES[@]}"; do
        ps="${ARMBIAN_SERIES_PATCH_SET[$s]:-}"
        if ! _series_patch_mapping_valid "${s}" "${ps}"; then
            echo "  skip ${s}.x: unexpected patch set ${ps:-<none>}" >&2
            continue
        fi
        if [[ "${trust_listed}" == "1" || "${ARMBIAN_SUPPORT_MODE}" == "fallback" ]]; then
            kept+=("${s}")
            continue
        fi
        if _armbian_patch_set_published "${ps}"; then
            kept+=("${s}")
        else
            echo "  skip ${s}.x: ${ps} not published on Armbian" >&2
        fi
    done

    ARMBIAN_KERNEL_SERIES=("${kept[@]}")
    [[ ${#ARMBIAN_KERNEL_SERIES[@]} -gt 0 ]] && ARMBIAN_EDGE_SERIES="${ARMBIAN_KERNEL_SERIES[0]}"
    _prefer_kernel_series
}

_log_withheld_kernel_series() {
    local s ps
    for s in "${WITHHELD_KERNEL_SERIES[@]}"; do
        [[ -n "${s}" ]] || continue
        if _kernel_series_is_listed "${s}"; then
            continue
        fi
        ps="$(_expected_patch_set_for_series "${s}")"
        echo "  withheld: linux-${s}.x until Armbian publishes ${ps}" >&2
    done
}

_merge_fallback_kernel_series() {
    local s ps changed=0
    for s in "${FALLBACK_KERNEL_SERIES[@]}"; do
        ps="${FALLBACK_SERIES_PATCH_SET[$s]}"
        _kernel_series_is_listed "${s}" && continue
        _armbian_patch_set_published "${ps}" || continue
        ARMBIAN_KERNEL_SERIES+=("${s}")
        ARMBIAN_SERIES_PATCH_SET["${s}"]="${ps}"
        changed=1
        echo "  merged fallback: linux-${s}.x (${ps})" >&2
    done
    if [[ "${changed}" -eq 1 ]]; then
        readarray -t ARMBIAN_KERNEL_SERIES < <(printf '%s\n' "${ARMBIAN_KERNEL_SERIES[@]}" | sort -Vr)
        ARMBIAN_EDGE_SERIES="${ARMBIAN_KERNEL_SERIES[0]}"
        _prefer_kernel_series
    fi
}

_load_support_from_cache() {
    [[ -f "${ARMBIAN_SUPPORT_CACHE}" ]] || return 1
    # shellcheck source=/dev/null
    source "${ARMBIAN_SUPPORT_CACHE}"
    [[ ${#ARMBIAN_KERNEL_SERIES[@]} -gt 0 ]] || return 1
    # Cache stores ARMBIAN_SERIES_PATCH_SET_<series> scalars — rebuild the assoc map.
    _rebuild_patch_set_map_from_cache_vars
    return 0
}

_save_support_cache() {
    {
        echo "# Armbian SM8550 — $(date -Iseconds)"
        echo "ARMBIAN_SUPPORT_MODE=\"${ARMBIAN_SUPPORT_MODE}\""
        echo "ARMBIAN_EDGE_SERIES=\"${ARMBIAN_EDGE_SERIES}\""
        echo -n "ARMBIAN_KERNEL_SERIES=("
        printf '%s ' "${ARMBIAN_KERNEL_SERIES[@]}"
        echo ")"
        local s
        for s in "${ARMBIAN_KERNEL_SERIES[@]}"; do
            echo "ARMBIAN_SERIES_PATCH_SET_${s//./_}=\"${ARMBIAN_SERIES_PATCH_SET[$s]}\""
        done
    } > "${ARMBIAN_SUPPORT_CACHE}.tmp"
    mv "${ARMBIAN_SUPPORT_CACHE}.tmp" "${ARMBIAN_SUPPORT_CACHE}"
}

_fetch_patch_sets_from_github() {
    local json
    json="$(curl -fsSL --connect-timeout 15 --max-time 45 \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: MaSi-OS-Kernel-Updater" \
        "${ARMBIAN_ARCHIVE_API}" 2>/dev/null)" || return 1
    printf '%s' "${json}" | python3 -c "
import sys, json, re
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(data, list):
    sys.exit(1)
for item in sorted(data, key=lambda x: x.get('name', '')):
    m = re.match(r'^sm8550-(\d+(?:\.\d+)?)$', item.get('name', ''))
    if m:
        print(f\"{m.group(1)} {item['name']}\")
" || return 1
}

_rebuild_patch_set_map_from_cache_vars() {
    ARMBIAN_SERIES_PATCH_SET=()
    local s key
    for s in "${ARMBIAN_KERNEL_SERIES[@]}"; do
        key="ARMBIAN_SERIES_PATCH_SET_${s//./_}"
        ARMBIAN_SERIES_PATCH_SET["${s}"]="${!key:-sm8550-${s}}"
    done
    _log_withheld_kernel_series
}

_use_fallback_support() {
    ARMBIAN_SUPPORT_MODE="fallback"
    ARMBIAN_KERNEL_SERIES=("${FALLBACK_KERNEL_SERIES[@]}")
    ARMBIAN_SERIES_PATCH_SET=()
    local s
    for s in "${FALLBACK_KERNEL_SERIES[@]}"; do
        ARMBIAN_SERIES_PATCH_SET["${s}"]="${FALLBACK_SERIES_PATCH_SET[$s]}"
    done
    ARMBIAN_EDGE_SERIES="${FALLBACK_KERNEL_SERIES[0]}"
    _filter_published_kernel_series
    _prefer_kernel_series
    _log_withheld_kernel_series
    echo "  fallback: ${ARMBIAN_KERNEL_SERIES[*]} (prefer ${PREFERRED_KERNEL_SERIES:-none})" >&2
}

refresh_armbian_support() {
    local cache_age=999999
    if [[ -f "${ARMBIAN_SUPPORT_CACHE}" ]]; then
        cache_age=$(( $(date +%s) - $(stat -c %Y "${ARMBIAN_SUPPORT_CACHE}" 2>/dev/null || echo 0) ))
    fi

    if [[ "${cache_age}" -lt "${ARMBIAN_SUPPORT_TTL}" ]] && _load_support_from_cache; then
        _merge_fallback_kernel_series
        _save_support_cache
        return 0
    fi

    echo "==> Querying Armbian SM8550 patches..." >&2
    local -a series=() patch_sets=() line mm ps
    local fetch_out="" fetch_rc=0

    # Capture exit status (process substitution alone hides curl/API failures).
    fetch_out="$(_fetch_patch_sets_from_github)" || fetch_rc=$?
    if [[ "${fetch_rc}" -ne 0 ]]; then
        echo "WARNING: GitHub Armbian inaccessible (rate-limit/network) — using cache/fallback." >&2
        if _load_support_from_cache; then
            _merge_fallback_kernel_series
            _save_support_cache
            return 0
        fi
        _use_fallback_support
        _save_support_cache
        return 0
    fi

    while IFS= read -r line; do
        [[ -z "${line}" ]] || continue
        mm="${line%% *}"
        ps="${line#* }"
        series+=("${mm}")
        patch_sets+=("${ps}")
    done <<< "${fetch_out}"

    if [[ ${#series[@]} -eq 0 ]]; then
        echo "WARNING: Armbian returned no sm8550-* patch sets — using cache/fallback." >&2
        if _load_support_from_cache; then
            _merge_fallback_kernel_series
            _save_support_cache
            return 0
        fi
        _use_fallback_support
        _save_support_cache
        return 0
    fi

    ARMBIAN_SUPPORT_MODE="github"
    ARMBIAN_KERNEL_SERIES=()
    ARMBIAN_SERIES_PATCH_SET=()
    local i
    for i in "${!series[@]}"; do
        ARMBIAN_SERIES_PATCH_SET["${series[$i]}"]="${patch_sets[$i]}"
    done
    readarray -t ARMBIAN_KERNEL_SERIES < <(printf '%s\n' "${series[@]}" | sort -Vr)
    ARMBIAN_EDGE_SERIES="${ARMBIAN_KERNEL_SERIES[0]}"
    _filter_published_kernel_series 1
    _merge_fallback_kernel_series
    _prefer_kernel_series
    _log_withheld_kernel_series
    _save_support_cache
    echo "  published: ${ARMBIAN_KERNEL_SERIES[*]} (prefer ${PREFERRED_KERNEL_SERIES:-none})" >&2
}

unsupported_kernel_reason() {
    local ver="$1" series ps expected
    series="$(kernel_major_minor "${ver}")"
    expected="$(_expected_patch_set_for_series "${series}")"
    ps="${ARMBIAN_SERIES_PATCH_SET[$series]:-}"

    if ! _kernel_series_is_listed "${series}"; then
        echo "linux-${ver}: series ${series}.x is not in the supported Armbian SM8550 list (requires ${expected})."
        return 0
    fi
    if [[ -z "${ps}" ]]; then
        echo "linux-${ver}: no Armbian SM8550 patch set mapped for ${series}.x (requires ${expected})."
        return 0
    fi
    if [[ "${ps}" != "${expected}" ]]; then
        echo "linux-${ver}: patch set ${ps} does not match ${expected}."
        return 0
    fi
    echo "linux-${ver}: not supported."
}

patch_set_for_version() {
    local ver="$1" series ps
    series="$(kernel_major_minor "${ver}")"
    ps="${ARMBIAN_SERIES_PATCH_SET[$series]:-}"

    if ! _kernel_series_is_listed "${series}"; then
        unsupported_kernel_reason "${ver}" >&2
        return 1
    fi
    if [[ -z "${ps}" ]] || ! _patch_set_matches_kernel_series "${ver}" "${ps}"; then
        unsupported_kernel_reason "${ver}" >&2
        return 1
    fi
    echo "${ps}"
}

kernel_is_supported() {
    patch_set_for_version "$1" >/dev/null 2>&1
}

armbian_support_summary() {
    local s parts=()
    for s in "${ARMBIAN_KERNEL_SERIES[@]}"; do
        if [[ "${s}" == *.* ]]; then
            parts+=("${s}.x (${ARMBIAN_SERIES_PATCH_SET[$s]:-?})")
        else
            parts+=("${s}.x+ (${ARMBIAN_SERIES_PATCH_SET[$s]:-?})")
        fi
    done
    local IFS=', '
    echo "${parts[*]}"
}

_try_kernel_version() {
    local ver="$1"
    kernel_is_supported "${ver}" || return 1
    kernel_source_cached "${ver}" && return 0
    kernel_tarball_exists "${ver}"
}

enumerate_kernel_menu_versions() {
    local -a versions=()
    local series ver max per n

    refresh_armbian_support
    max="${KERNEL_VERSIONS_PER_SERIES:-8}"
    per=$(( max * ${#ARMBIAN_KERNEL_SERIES[@]} + 4 ))

    for series in "${ARMBIAN_KERNEL_SERIES[@]}"; do
        echo "  → ${series}.x (${ARMBIAN_SERIES_PATCH_SET[$series]:-?}) ..." >&2
        n=0
        while IFS= read -r ver; do
            [[ -n "${ver}" ]] || continue
            kernel_is_supported "${ver}" || continue
            versions+=("${ver}")
            n=$((n + 1))
            [[ "${n}" -ge "${max}" ]] && break
        done < <(kernel_list_versions_for_series "${series}")
    done

    ver="$(uname -r 2>/dev/null | cut -d- -f1 || true)"
    if [[ -n "${ver}" ]] && kernel_is_supported "${ver}"; then
        versions+=("${ver}")
    fi

    if [[ ${#versions[@]} -eq 0 ]]; then
        for ver in ${FALLBACK_KERNEL_VERSIONS:-}; do
            [[ -n "${ver}" ]] || continue
            kernel_is_supported "${ver}" || continue
            versions+=("${ver}")
        done
    fi

    [[ ${#versions[@]} -gt 0 ]] || return 1

    while IFS= read -r ver; do
        [[ -n "${ver}" ]] && echo "${ver}"
    done < <(printf '%s\n' "${versions[@]}" | sort -rVu | head -n "${per}")
}

enumerate_downloadable_kernels() {
    local ver
    while IFS= read -r ver; do
        [[ -n "${ver}" ]] || continue
        _try_kernel_version "${ver}" && echo "${ver}"
    done < <(enumerate_kernel_menu_versions) || return 1
}

resolve_kernel_version() {
    if [[ -n "${KERNEL_VER:-}" ]]; then
        kernel_is_supported "${KERNEL_VER}" || {
            unsupported_kernel_reason "${KERNEL_VER}" >&2
            echo "  Only kernels with a matching Armbian sm8550-<series> patch set are allowed." >&2
            return 1
        }
        echo "${KERNEL_VER}"
        return 0
    fi

    local ver=""
    # Do not use `cmd | head -1` under pipefail: head closes early → SIGPIPE → false failure.
    while IFS= read -r ver; do
        [[ -n "${ver}" ]] && break
    done < <(enumerate_downloadable_kernels 2>/dev/null || true)
    if [[ -n "${ver}" ]]; then
        echo "  auto: linux-${ver}" >&2
        echo "${ver}"
        return 0
    fi

    ver=""
    while IFS= read -r ver; do
        [[ -n "${ver}" ]] && break
    done < <(enumerate_kernel_menu_versions 2>/dev/null || true)
    if [[ -n "${ver}" ]]; then
        echo "  auto: linux-${ver} (download without CDN verify)" >&2
        echo "${ver}"
        return 0
    fi

    echo "No compatible versions (need published Armbian sm8550-* patches)." >&2
    echo "Try: KERNEL_VER=7.2.2 ./make.sh  (needs config/armbian-manifests/sm8550-7.2.txt)" >&2
    return 1
}
