#!/usr/bin/env bash
# Build Decky frontend (dist/index.js). Requires Node 18+ and pnpm or npm.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

prepend_node_path() {
  local d
  for d in \
    "$HOME/.local/node-"*"-linux-arm64/bin" \
    "$HOME/.local/node-"*"-linux-arm64" \
    /usr/local/bin \
    /usr/bin; do
  if [[ -d "$d" && -x "$d/node" ]]; then
    export PATH="$d:$PATH"
    break
  fi
  done
}

prepend_node_path

if command -v corepack >/dev/null 2>&1; then
  corepack enable >/dev/null 2>&1 || true
fi

if command -v pnpm >/dev/null 2>&1; then
  pnpm install --frozen-lockfile 2>/dev/null || pnpm install
  pnpm run build
elif command -v npm >/dev/null 2>&1; then
  npm install
  npm run build
else
  echo "ERROR: install pnpm or npm to build dist/index.js" >&2
  echo "Hint: Node may be at ~/.local/node-*-linux-arm64/bin" >&2
  exit 1
fi

[[ -f dist/index.js ]] || { echo "ERROR: build did not produce dist/index.js" >&2; exit 1; }
echo "OK: dist/index.js ($(wc -c < dist/index.js) bytes)"
