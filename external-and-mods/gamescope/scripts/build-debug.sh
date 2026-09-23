#!/bin/bash
# Debug build: symbols + same tree, separate build dir (does not touch release build/).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${GAMESCOPE_BUILD_DEBUG:-$ROOT/build-debug}"

cd "$ROOT"

if [[ ! -f "$BUILD/build.ninja" ]]; then
  echo "==> meson setup $BUILD (debug)"
  meson setup "$BUILD" --buildtype=debug -Dstrip=false
else
  echo "==> reconfigure $BUILD (debug)"
  meson setup "$BUILD" --reconfigure --buildtype=debug -Dstrip=false
fi

echo "==> ninja -C $BUILD"
ninja -C "$BUILD"

echo ""
echo "OK: $BUILD/src/gamescope"
echo "Install (optional): sudo meson install -C $BUILD --skip-subprojects"
