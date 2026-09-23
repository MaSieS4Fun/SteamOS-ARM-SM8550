#!/usr/bin/env bash
# Verify dist/index.js, then install to ~/homebrew/plugins/.
set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-$SELF}"
STEAM_USER="${STEAM_USER:-steam}"
STEAM_HOME="${STEAM_HOME:-/home/${STEAM_USER}}"
NAME="$(basename "$SRC")"
DEST="${STEAM_HOME}/homebrew/plugins/${NAME}"

[[ -f "${SRC}/plugin.json" ]] || { echo "ERROR: missing plugin.json in ${SRC}" >&2; exit 1; }
[[ -f "${SRC}/dist/index.js" ]] || { echo "ERROR: missing dist/index.js" >&2; exit 1; }
[[ -f "${SRC}/main.py" ]] || { echo "ERROR: missing main.py" >&2; exit 1; }
[[ -d "${SRC}/py_modules/sm8550_led" ]] || { echo "ERROR: missing py_modules/sm8550_led" >&2; exit 1; }
[[ -f "${SRC}/package.json" ]] || { echo "ERROR: missing package.json (required for ESM load type)" >&2; exit 1; }

if ! python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); sys.exit(0 if p.get("api_version",0)>=1 else 1)' "${SRC}/plugin.json"; then
  echo "ERROR: plugin.json must set \"api_version\": 1 for @decky/api callable()." >&2
  exit 1
fi

if ! python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); sys.exit(0 if p.get("type")=="module" else 1)' "${SRC}/package.json"; then
  echo "ERROR: package.json must set \"type\": \"module\" so Decky loads dist/index.js as ESM." >&2
  exit 1
fi

if grep -qE '^[[:space:]]*import[[:space:]]+(react|@decky/ui)' "${SRC}/dist/index.js"; then
  echo "ERROR: dist/index.js imports react/@decky/ui (must be bundled as SP_REACT/DFL globals)." >&2
  echo "Run ./build.sh (rollup)." >&2
  exit 1
fi
if grep -qE 'React\.createElement' "${SRC}/dist/index.js"; then
  echo "ERROR: dist/index.js uses React.createElement (React is undefined in Decky)." >&2
  echo "Set tsconfig jsx to react-jsx and run ./build.sh." >&2
  exit 1
fi

PLUGIN_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "${SRC}/plugin.json")"
if [[ "$PLUGIN_NAME" == *" "* ]]; then
  echo "WARNING: plugin.json name contains spaces (${PLUGIN_NAME}) — Decky URLs may break." >&2
fi

if [[ ! -x "${STEAM_HOME}/homebrew/services/PluginLoader" ]]; then
  echo "ERROR: Decky not installed (${STEAM_HOME}/homebrew/services/PluginLoader missing)" >&2
  exit 1
fi

run_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

echo "==> Installing ${NAME} (${PLUGIN_NAME}) → ${DEST}"
run_root mkdir -p "$DEST"
run_root rsync -a --delete \
  --exclude node_modules \
  --exclude src \
  --exclude .pnpm-store \
  "${SRC}/" "${DEST}/"
run_root chown -R "${STEAM_USER}:${STEAM_USER}" "${STEAM_HOME}/homebrew"

echo "==> Restarting plugin_loader"
run_root systemctl restart plugin_loader.service

echo "OK. Enable «${PLUGIN_NAME}» in Decky → Plugins."
