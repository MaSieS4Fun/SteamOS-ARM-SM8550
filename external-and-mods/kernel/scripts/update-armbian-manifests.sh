#!/usr/bin/env bash
# Refresh config/armbian-manifests/*.txt from the live Armbian archive.
# ./make.sh already fetches via API; this only updates the offline fallback lists.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
# shellcheck source=lib/armbian-patch-sync.sh
source "${ROOT}/lib/armbian-patch-sync.sh"

PATCH_CACHE="${PATCH_CACHE:-${ROOT}/.cache/armbian-patches}"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.cache}"
export PATCH_CACHE CACHE_DIR

write_manifest() {
    local patch_set="$1"
    local dest="${ROOT}/config/armbian-manifests/${patch_set}.txt"
    local ref names header

    ref="$(_armbian_resolve_archive_ref "${patch_set}")" || {
        echo "SKIP ${patch_set}: archive not on ${ARMBIAN_BUILD_GIT_REF} and no fallback SHA" >&2
        return 1
    }
    names="$(_armbian_patch_names_from_api "${patch_set}" "${ref}")" || {
        echo "SKIP ${patch_set}: could not list patches (ref=${ref})" >&2
        return 1
    }
    [[ -n "${names}" ]] || {
        echo "SKIP ${patch_set}: empty list" >&2
        return 1
    }

    header="# Offline fallback for ${patch_set} (Armbian ${ref})."
    header+=$'\n'"# ./make.sh prefers GitHub API; refresh this file with $0"
    {
        echo "${header}"
        printf '%s\n' "${names}"
    } > "${dest}.tmp"
    mv "${dest}.tmp" "${dest}"
    echo "OK ${patch_set} (${ref}): $(printf '%s\n' "${names}" | grep -c . || true) patches → ${dest}" >&2
}

mkdir -p "${ROOT}/config/armbian-manifests"
sets=("$@")
if [[ ${#sets[@]} -eq 0 ]]; then
    sets=(sm8550-7.2 sm8550-7.0 sm8550-6.18)
fi

rc=0
for patch_set in "${sets[@]}"; do
    write_manifest "${patch_set}" || rc=1
done
exit "${rc}"
