#!/usr/bin/env bash
# kernel-new-base — SM8550 gaming kernel + ABL bootimg (standalone project)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT

exec "${ROOT}/lib/kbuild.sh" "$@"
