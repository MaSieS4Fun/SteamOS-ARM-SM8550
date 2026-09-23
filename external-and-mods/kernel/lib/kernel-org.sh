#!/usr/bin/env bash
set -euo pipefail

KERNEL_CDN_UA="${KERNEL_CDN_UA:-Mozilla/5.0 (compatible; Kernel-MaSi-OS/1.0; +https://kernel.org)}"
KERNEL_CDN="${KERNEL_CDN:-https://cdn.kernel.org/pub/linux/kernel}"
KERNEL_CDN_MIRROR="${KERNEL_CDN_MIRROR:-https://mirrors.edge.kernel.org/pub/linux/kernel}"

_curl_cdn() {
    curl -fsSL --connect-timeout 15 --max-time 120 -A "${KERNEL_CDN_UA}" "$@"
}

kernel_version_to_series() {
    echo "v${1%%.*}.x"
}

cdn_series_for_mm() {
    local mm="$1"
    echo "v${mm%%.*}.x"
}

kernel_version_matches_series() {
    local ver="$1" series="$2"
    [[ -n "${ver}" && -n "${series}" ]] || return 1
    [[ "${ver}" == "${series}."* ]]
}

KERNEL_GITHUB_STABLE="${KERNEL_GITHUB_STABLE:-https://github.com/gregkh/linux/archive/refs/tags}"

kernel_github_stable_url() {
    echo "${KERNEL_GITHUB_STABLE}/v${1}.tar.gz"
}

kernel_tarball_validate() {
    local tar="$1"
    [[ -s "${tar}" ]] || return 1
    if head -c 64 "${tar}" | grep -qE '^[[:space:]]*<(html|!DOCTYPE)'; then
        return 1
    fi
    local magic
    magic="$(head -c 6 "${tar}" | od -An -tx1 | tr -d ' \n')"
    case "${magic}" in
        1f8b*) gzip -t "${tar}" 2>/dev/null ;;
        fd377a*)
            command -v xz >/dev/null 2>&1 || return 1
            xz -t "${tar}" 2>/dev/null
            ;;
        *) return 1 ;;
    esac
}

kernel_tarball_urls() {
    local ver="$1" series rel base src
    local -a urls=()

    series="$(kernel_version_to_series "${ver}")"
    rel="${series}/linux-${ver}.tar.xz"

    src="$(kernel_release_source_url "${ver}" 2>/dev/null || true)"
    [[ -n "${src}" ]] && urls+=("${src}")

    for base in "${KERNEL_CDN}" "${KERNEL_CDN_MIRROR}"; do
        [[ -n "${base}" ]] || continue
        urls+=("${base}/${rel}")
    done

    urls+=("$(kernel_github_stable_url "${ver}")")
    printf '%s\n' "${urls[@]}" | awk '!seen[$0]++'
}

kernel_release_source_url() {
    local ver="$1" json
    json="$(_kernel_releases_json_path 2>/dev/null || true)"
    [[ -n "${json}" && -f "${json}" ]] || return 1
    python3 - "${ver}" "${json}" <<'PY'
import json, sys
ver, path = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
for item in data.get("releases") or []:
    if item.get("version") == ver and item.get("source"):
        print(item["source"])
        break
else:
    latest = data.get("latest_stable")
    if isinstance(latest, dict) and latest.get("version") == ver and latest.get("source"):
        print(latest["source"])
PY
}

kernel_tarball_archive_path() {
    local ver="$1" url="$2"
    case "${url}" in
        *.tar.xz) echo "${CACHE_DIR:-/tmp}/linux-${ver}.tar.xz" ;;
        *.tar.gz) echo "${CACHE_DIR:-/tmp}/linux-${ver}.tar.gz" ;;
        *) echo "${CACHE_DIR:-/tmp}/linux-${ver}.tar" ;;
    esac
}

extract_kernel_tarball() {
    local tar="$1" cache="$2" ver="$3"
    local dest="${cache}/linux-${ver}" top

    kernel_tarball_validate "${tar}" || {
        echo "Error: ${tar} is not a valid tarball (error HTML?)" >&2
        return 1
    }

    rm -rf "${dest}"
    case "${tar}" in
        *.tar.xz) tar -xJf "${tar}" -C "${cache}" ;;
        *.tar.gz) tar -xzf "${tar}" -C "${cache}" ;;
        *) tar -xf "${tar}" -C "${cache}" ;;
    esac

    if [[ -f "${dest}/Makefile" ]]; then
        top="${dest}"
    else
        top="$(find "${cache}" -maxdepth 1 -mindepth 1 -type d ! -name '.*' | head -1)"
        if [[ -n "${top}" && -f "${top}/Makefile" ]]; then
            mv "${top}" "${dest}"
        fi
    fi

    [[ -f "${dest}/Makefile" ]] || {
        echo "Error: linux-${ver} extraction missing Makefile in ${cache}" >&2
        return 1
    }

    chmod -R u+w "${dest}"
    echo "${dest}"
}

kernel_tarball_for_version() {
    local ver="$1" ext
    for ext in tar.xz tar.gz; do
        [[ -f "${CACHE_DIR}/linux-${ver}.${ext}" ]] && {
            echo "${CACHE_DIR}/linux-${ver}.${ext}"
            return 0
        }
    done
    return 1
}

reset_kernel_source_from_tarball() {
    local ver="$1"
    local tar dest="${CACHE_DIR}/linux-${ver}"

    tar="$(kernel_tarball_for_version "${ver}")" || {
        echo "ERROR: no tarball in cache for linux-${ver}" >&2
        echo "  Remove ${dest} and run ./make.sh again to re-download." >&2
        return 1
    }

    echo "==> Restoring clean linux-${ver} from tarball" >&2
    if [[ -d "${dest}" ]]; then
        chmod -R u+w "${dest}" 2>/dev/null || true
        rm -rf "${dest}"
    fi

    extract_kernel_tarball "${tar}" "${CACHE_DIR}" "${ver}" >/dev/null
}

kernel_source_cached() {
    local ver="$1"
    [[ -f "${CACHE_DIR:-/tmp}/linux-${ver}/Makefile" ]]
}

kernel_tarball_exists() {
    local ver="$1" url
    kernel_source_cached "${ver}" && return 0
    while IFS= read -r url; do
        [[ -n "${url}" ]] || continue
        _curl_cdn -I "${url}" >/dev/null 2>&1 && return 0
        _curl_cdn --range 0-4095 -o /dev/null "${url}" 2>/dev/null && return 0
    done < <(kernel_tarball_urls "${ver}")
    return 1
}

kernel_cdn_list_versions() {
    local series="$1" base
    for base in "${KERNEL_CDN}" "${KERNEL_CDN_MIRROR}"; do
        [[ -n "${base}" ]] || continue
        _curl_cdn "${base}/${series}/" 2>/dev/null \
            | grep -oE "linux-[0-9]+\.[0-9]+\.[0-9]+\.tar\.xz" \
            | sed 's/linux-//;s/\.tar\.xz//' \
            | sort -Vu && return 0
    done
    return 0
}

KERNEL_RELEASES_JSON="${KERNEL_RELEASES_JSON:-https://www.kernel.org/releases.json}"
KERNEL_RELEASES_CACHE="${KERNEL_RELEASES_CACHE:-${CACHE_DIR:-/tmp}/kernel-releases.json}"
KERNEL_RELEASES_TTL="${KERNEL_RELEASES_TTL:-43200}"

_kernel_releases_json_path() {
    local cache_age=999999
    if [[ -f "${KERNEL_RELEASES_CACHE}" ]]; then
        cache_age=$(( $(date +%s) - $(stat -c %Y "${KERNEL_RELEASES_CACHE}" 2>/dev/null || echo 0) ))
    fi
    if [[ "${cache_age}" -lt "${KERNEL_RELEASES_TTL}" && -s "${KERNEL_RELEASES_CACHE}" ]]; then
        echo "${KERNEL_RELEASES_CACHE}"
        return 0
    fi
    mkdir -p "$(dirname "${KERNEL_RELEASES_CACHE}")"
    if _curl_cdn -o "${KERNEL_RELEASES_CACHE}.tmp" "${KERNEL_RELEASES_JSON}" 2>/dev/null \
        && [[ -s "${KERNEL_RELEASES_CACHE}.tmp" ]]; then
        mv "${KERNEL_RELEASES_CACHE}.tmp" "${KERNEL_RELEASES_CACHE}"
        echo "${KERNEL_RELEASES_CACHE}"
        return 0
    fi
    rm -f "${KERNEL_RELEASES_CACHE}.tmp"
    [[ -s "${KERNEL_RELEASES_CACHE}" ]] && echo "${KERNEL_RELEASES_CACHE}"
}

kernel_releases_list_versions() {
    local json
    json="$(_kernel_releases_json_path)" || return 0
    [[ -n "${json}" && -f "${json}" ]] || return 0
    python3 - "${json}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
versions = []
item = data.get("latest_stable")
if isinstance(item, dict) and item.get("version"):
    versions.append(item["version"])
for item in data.get("releases") or []:
    v = item.get("version") if isinstance(item, dict) else None
    if v:
        versions.append(v)
for v in sorted(set(versions), key=lambda s: [int(x) for x in s.split(".")]):
    print(v)
PY
}

kernel_cached_versions() {
    local dir ver
    [[ -d "${CACHE_DIR:-}" ]] || return 0
    for dir in "${CACHE_DIR}"/linux-*; do
        [[ -d "${dir}/Makefile" ]] || continue
        ver="${dir##*/linux-}"
        [[ "${ver}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        echo "${ver}"
    done
}

kernel_list_versions_for_series() {
    local series="$1" ver
    local -a found=()

    while IFS= read -r ver; do
        [[ -n "${ver}" ]] || continue
        kernel_version_matches_series "${ver}" "${series}" && found+=("${ver}")
    done < <(kernel_cdn_list_versions "$(cdn_series_for_mm "${series}")" 2>/dev/null || true)

    while IFS= read -r ver; do
        [[ -n "${ver}" ]] || continue
        kernel_version_matches_series "${ver}" "${series}" && found+=("${ver}")
    done < <(kernel_releases_list_versions 2>/dev/null || true)

    for ver in ${FALLBACK_KERNEL_VERSIONS:-}; do
        kernel_version_matches_series "${ver}" "${series}" && found+=("${ver}")
    done

    while IFS= read -r ver; do
        [[ -n "${ver}" ]] || continue
        kernel_version_matches_series "${ver}" "${series}" && found+=("${ver}")
    done < <(kernel_cached_versions 2>/dev/null || true)

    [[ ${#found[@]} -eq 0 ]] && return 0
    printf '%s\n' "${found[@]}" | sort -rVu
}
