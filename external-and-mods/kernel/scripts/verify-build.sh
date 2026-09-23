#!/usr/bin/env bash
# Run ship gate on latest build (or BUILD_OUT_DIR=...).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
# shellcheck source=config/defaults.conf
source "${ROOT}/config/defaults.conf"
# shellcheck source=lib/output.sh
source "${ROOT}/lib/output.sh"
# shellcheck source=lib/verify-build.sh
source "${ROOT}/lib/verify-build.sh"

out="${BUILD_OUT_DIR:-}"
if [[ -z "${out}" ]]; then
    out="$(find "${OUTPUT_DIR:-${ROOT}/output}" -maxdepth 1 -type d -name "*-${OUTPUT_SUFFIX:-kbase}" 2>/dev/null | sort -V | tail -1)"
fi
[[ -n "${out}" && -d "${out}" ]] || { echo "No build in output/"; exit 1; }
rel="$(basename "$(find "${out}/modules" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)")"
verify_build_output "${out}" "${rel}"
