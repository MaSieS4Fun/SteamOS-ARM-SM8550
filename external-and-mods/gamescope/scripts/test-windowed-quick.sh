#!/bin/bash
# Short test: gamescope + Castle of Illusion (or vkcube) in windowed mode.
# No Steam Big Picture. Logs paint/composite dimensions to stderr.
#
# Usage:
#   ./scripts/test-windowed-quick.sh              # wine + COI.exe if found
#   ./scripts/test-windowed-quick.sh vkcube       # compositor-only smoke test
#   GAMESCOPE_BIN=... ./scripts/test-windowed-quick.sh
#
# Capture log:
#   ./scripts/test-windowed-quick.sh 2>&1 | tee /tmp/gamescope-debug.log
#   grep '\[paint\]\|\[present\]\|\[composite\]' /tmp/gamescope-debug.log

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${GAMESCOPE_BUILD_DEBUG:-$ROOT/build-debug}"
BIN="${GAMESCOPE_BIN:-$BUILD/src/gamescope}"

if [[ ! -x "$BIN" ]]; then
  echo "gamescope not found: $BIN" >&2
  echo "Run: $ROOT/scripts/build-debug.sh" >&2
  exit 1
fi

W="${GAMESCOPE_WIDTH:-2560}"
H="${GAMESCOPE_HEIGHT:-1600}"
REFRESH_HZ="${GAMESCOPE_REFRESH:-120}"
FORCE_ORIENTATION="${GAMESCOPE_FORCE_ORIENTATION:-left}"
LOG_FILE="${GAMESCOPE_DEBUG_LOG:-/tmp/gamescope-paint-debug.log}"

export GAMESCOPE_DEBUG_PAINT=1
export GAMESCOPE_WSI_BYPASS_DEBUG=1
export log_xwm=info
export log_drm=info
export log_vulkan=info
export log_liftoff=warning

# Unset host Wayland for DRM session (same as production script).
unset WAYLAND_DISPLAY

run_gamescope() {
  exec "$BIN" \
    -W "$W" -H "$H" -r "$REFRESH_HZ" \
    --backend drm \
    --force-orientation "$FORCE_ORIENTATION" \
    --use-rotation-shader \
    --composite-debug \
    "$@"
}

pick_wine() {
  if [[ -n "${WINE:-}" && -x "${WINE}" ]]; then
    echo "$WINE"
    return
  fi
  local w
  w="$(find "${HOME}/.local/share/Steam" -path '*/bin/wine' -type f 2>/dev/null | head -1)"
  if [[ -n "$w" ]]; then
    echo "$w"
    return
  fi
  command -v wine64 2>/dev/null || command -v wine 2>/dev/null || true
}

GAME_DIR="${GAME_DIR:-$HOME/.local/share/Steam/steamapps/common/Castle of Illusion}"
GAME_EXE="${GAME_EXE:-$GAME_DIR/COI.exe}"
STEAM_RUNTIME_RUN="${STEAM_RUNTIME_RUN:-$HOME/.local/share/Steam/ubuntu12_64/steam-runtime/run.sh}"

echo "gamescope: $BIN"
echo "log file: $LOG_FILE (stderr + file)"
echo "grep hints: [paint] [present] [composite] Composite output dimensions"
echo ""

if [[ "${1:-}" == "vkcube" ]]; then
  if ! command -v vkcube >/dev/null 2>&1; then
    echo "vkcube not installed. Try: sudo apt install vulkan-tools" >&2
    exit 1
  fi
  echo "==> vkcube smoke test (windowed Vulkan, ~15s then exit)"
  run_gamescope -- vkcube &
  GS_PID=$!
  sleep 15
  kill "$GS_PID" 2>/dev/null || true
  wait "$GS_PID" 2>/dev/null || true
  exit 0
fi

if [[ ! -f "$GAME_EXE" ]]; then
  echo "Game not found: $GAME_EXE" >&2
  echo "Set GAME_EXE= or install Castle of Illusion (Steam app 227600)." >&2
  exit 1
fi

WINE_BIN="$(pick_wine)"
if [[ -z "$WINE_BIN" ]]; then
  echo "wine not found under Steam and not in PATH." >&2
  exit 1
fi

echo "==> wine game: $GAME_EXE"
echo "    wine: $WINE_BIN"
echo "    Close the game window or Ctrl+C to stop."
echo ""

cd "$GAME_DIR"
if [[ -x "$STEAM_RUNTIME_RUN" ]]; then
  run_gamescope -- "$STEAM_RUNTIME_RUN" "$WINE_BIN" "$GAME_EXE" 2>&1 | tee "$LOG_FILE"
else
  run_gamescope -- "$WINE_BIN" "$GAME_EXE" 2>&1 | tee "$LOG_FILE"
fi
