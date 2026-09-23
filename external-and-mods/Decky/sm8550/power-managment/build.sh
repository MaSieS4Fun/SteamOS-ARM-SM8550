#!/usr/bin/env bash
# Build Decky frontend (dist/index.js). Requires Node 18+ and pnpm or npm.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if command -v pnpm >/dev/null 2>&1; then
  pnpm install --frozen-lockfile 2>/dev/null || pnpm install
  pnpm run build
elif command -v npm >/dev/null 2>&1; then
  npm install
  npm run build
else
  echo "ERROR: install pnpm or npm to build dist/index.js" >&2
  exit 1
fi

[[ -f dist/index.js ]] || { echo "ERROR: build did not produce dist/index.js" >&2; exit 1; }
echo "OK: dist/index.js"
