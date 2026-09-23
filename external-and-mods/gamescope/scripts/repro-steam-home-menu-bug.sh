#!/bin/bash
# Reproduce the Steam Home/Home+A shrink bug in the real path:
# windowed/nested gamescope + Steam Big Picture + game launch.
#
# What it does:
# - runs the debug gamescope build by default
# - enables focused compositor/DRM/Vulkan logs
# - captures everything to a timestamped log file
# - launches Steam close to the real failing flow
# - lets us toggle the likely-different knobs for comparison
#
# Usage:
#   ./scripts/repro-steam-home-menu-bug.sh
#   STEAM_GAME_ID=227600 AUTO_LAUNCH_GAME=1 ./scripts/repro-steam-home-menu-bug.sh
#   GAMESCOPE_BIN=/usr/local/bin/gamescope ./scripts/repro-steam-home-menu-bug.sh
#
# Repro steps once Steam is up:
#   1. Launch the target game from Big Picture
#   2. Wait until the game is visible
#   3. Press HOME
#   4. If needed, press HOME + A
#   5. Exit gamescope and share the log path printed below

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${GAMESCOPE_BUILD_DEBUG:-$ROOT/build-debug}"
GAMESCOPE_BIN="${GAMESCOPE_BIN:-$BUILD/src/gamescope}"

if [[ ! -x "$GAMESCOPE_BIN" ]]; then
  echo "gamescope binary not found: $GAMESCOPE_BIN" >&2
  echo "Run: $ROOT/scripts/build-debug.sh" >&2
  exit 1
fi

LOG_DIR="${GAMESCOPE_REPRO_LOG_DIR:-$HOME/gamescope-repro-logs}"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${GAMESCOPE_REPRO_LOG_FILE:-$LOG_DIR/steam-home-bug-$STAMP.log}"

W="${GAMESCOPE_WIDTH:-1280}"
H="${GAMESCOPE_HEIGHT:-800}"
REFRESH_HZ="${GAMESCOPE_REFRESH:-60}"
XWAYLAND_COUNT="${GAMESCOPE_XWAYLAND_COUNT:-2}"
ENABLE_MANGOAPP="${ENABLE_MANGOAPP:-0}"
ENABLE_MULTI_XWAYLANDS="${ENABLE_MULTI_XWAYLANDS:-1}"
STEAM_GAME_ID="${STEAM_GAME_ID:-227600}"
AUTO_LAUNCH_GAME="${AUTO_LAUNCH_GAME:-0}"

export GAMESCOPE_DEBUG_PAINT="${GAMESCOPE_DEBUG_PAINT:-1}"
export GAMESCOPE_WSI_BYPASS_DEBUG="${GAMESCOPE_WSI_BYPASS_DEBUG:-1}"
export log_xwm="${log_xwm:-info}"
export log_drm="${log_drm:-info}"
export log_vulkan="${log_vulkan:-info}"
export log_wlserver="${log_wlserver:-warning}"
export log_liftoff="${log_liftoff:-warning}"

echo "Log file: $LOG_FILE"
echo "gamescope bin: $GAMESCOPE_BIN"
echo ""
echo "When Steam is ready:"
if [[ "$AUTO_LAUNCH_GAME" == "1" ]]; then
  echo "Target game id: $STEAM_GAME_ID"
  echo "  Steam launch mode: auto-open steam://rungameid/$STEAM_GAME_ID"
else
  echo "  Steam launch mode: manual (matches: gamescope -e -- steam -gamepadui -steamdeck)"
fi
echo "  1. Launch the game from Big Picture"
echo "  2. Press HOME"
echo "  3. Press HOME + A if needed"
echo "  4. Exit and share: $LOG_FILE"
echo ""
echo "  Window size: ${W}x${H}@${REFRESH_HZ}"
echo "  Xwayland count: ${XWAYLAND_COUNT}"
echo "  STEAM_MULTIPLE_XWAYLANDS: ${ENABLE_MULTI_XWAYLANDS}"
echo "  Mangoapp: ${ENABLE_MANGOAPP}"
echo ""

STEAM_ARGS=( steam -gamepadui -steamdeck )
if [[ "$AUTO_LAUNCH_GAME" == "1" ]]; then
  STEAM_ARGS+=( "steam://rungameid/$STEAM_GAME_ID" )
fi

GAMESCOPE_ARGS=(
  -W "$W" -H "$H" -r "$REFRESH_HZ"
  --xwayland-count "$XWAYLAND_COUNT"
  -e
)

if [[ "$ENABLE_MANGOAPP" == "1" ]]; then
  GAMESCOPE_ARGS+=( --mangoapp )
fi

if [[ "$ENABLE_MULTI_XWAYLANDS" == "1" ]]; then
  export STEAM_MULTIPLE_XWAYLANDS=1
else
  unset STEAM_MULTIPLE_XWAYLANDS || true
fi

exec env \
  "$GAMESCOPE_BIN" \
    "${GAMESCOPE_ARGS[@]}" \
    -- "${STEAM_ARGS[@]}" \
  2>&1 | tee "$LOG_FILE"
