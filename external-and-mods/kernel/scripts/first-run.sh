#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT

# shellcheck source=config/defaults.conf
source "${ROOT}/config/defaults.conf"
# shellcheck source=lib/preflight.sh
source "${ROOT}/lib/preflight.sh"

echo "==> MaSi-OS Kernel Updater — first-run"
echo ""
preflight_sm8550_build
echo "Ready: ./make.sh"
