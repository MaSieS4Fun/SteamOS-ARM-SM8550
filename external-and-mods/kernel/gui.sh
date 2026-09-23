#!/usr/bin/env bash
# Launch Easy Kernel Updater GUI from the kernel tree.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export EASY_KERNEL_TREE="${EASY_KERNEL_TREE:-${ROOT}}"
export EASY_KERNEL_UPDATER_ROOT="${EASY_KERNEL_UPDATER_ROOT:-${ROOT}/gui}"
export PYTHONPATH="${EASY_KERNEL_UPDATER_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m easy_kernel_updater "$@"
