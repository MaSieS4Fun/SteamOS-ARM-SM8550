#!/usr/bin/env bash
# Put a *complete* Steam ARM client into STEAM_HOME.
#
# Frame steam.tar.zst is not enough (version 0, missing package zips, spinner).
# The working client is the one vendor/SteamARM builds: download the ARM zip,
# run steam once (-steamdeck -exitsteam) until it says it will restart, then
# it just exits. That tree has steamui.so + package/*.installed.
#
# Usage:
#   install-complete-steam-client.sh <STEAM_HOME>
#
# Env:
#   STEAM_ARM_SCRIPT   override path to install-steam-arm
#   STEAM_ARM_SEED     complete client to copy (default: host ~/.local/share/Steam)
#   STEAM_ARM_CHANNEL  default steamdeck_publicbeta
#   STEAM_ARM_SKIP_BOOTSTRAP_RUN=1  download/copy only
#
# Always strips login/account data after copy so the image first-boots
# like a new Steam Deck (login screen, no host account).
set -euo pipefail

STEAM_HOME="${1:?STEAM_HOME}"
HERE="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "${HERE}/.." && pwd)"
CHANNEL="${STEAM_ARM_CHANNEL:-steamdeck_publicbeta}"
SEED="${STEAM_ARM_SEED:-/home/steam/.local/share/Steam}"
UBUNTU_ARM="${STEAM_ARM_SCRIPT:-/home/steam/Desktop/SteamOS-Ubuntu/vendor/SteamARM/install-steam-arm}"

log() { printf '==> [steam-complete] %s\n' "$*"; }

is_complete() {
  local d="$1"
  [[ -x "${d}/steamrtarm64/steam" ]] || return 1
  [[ -s "${d}/steamrtarm64/steamui.so" ]] || return 1
  compgen -G "${d}/package/steam_client_*_linuxarm64.installed" >/dev/null \
    || [[ -s "${d}/.odin-complete-client" ]]
}

# Remove host login, tokens, userdata. Keep the ARM client (steamui, steamrt, packages).
sanitize_steam_user_data() {
  local d="$1"
  [[ -d "$d" ]] || return 0
  log "stripping Steam account data (first-boot login, like a new Deck)"
  rm -rf \
    "${d}/userdata" \
    "${d}/logs" \
    "${d}/dumps" \
    "${d}/config/htmlcache" \
    "${d}/config/avatarcache" \
    "${d}/appcache/httpcache" \
    "${d}/appcache/cefdata" \
    "${d}/steamapps/common" \
    "${d}/steamapps/compatdata" \
    "${d}/steamapps/shadercache" \
    "${d}/steamapps/workshop"
  rm -f \
    "${d}"/ssfn* \
    "${d}/config/loginusers.vdf" \
    "${d}/config/config.vdf" \
    "${d}/config/DialogConfig.vdf" \
    "${d}/config/remoteclients.vdf" \
    "${d}/config/libraryfolders.vdf" \
    "${d}/registry.vdf" \
    "${d}/steam.pid" \
    "${d}/.crash"
  mkdir -p "${d}/userdata" "${d}/steamapps"
  # ARM CDN self-update fails (http error 0) and OOBE sits on Retry.
  printf '%s\n' \
    'BootStrapperInhibitAll=enable' \
    'BootStrapperForceSelfUpdate=disable' \
    'BootStrapperInhibitClientChecksum=enable' \
    'BootStrapperInhibitBootstrapperChecksum=enable' \
    'BootStrapperInhibitUpdateOnLaunch=enable' \
    >"${d}/steam.cfg"
  mkdir -p "${d}/steamrtarm64"
  cp -f "${d}/steam.cfg" "${d}/steamrtarm64/steam.cfg" 2>/dev/null || true
}

mkdir -p "$STEAM_HOME"

if is_complete "$STEAM_HOME"; then
  log "already complete: $STEAM_HOME"
  sanitize_steam_user_data "$STEAM_HOME"
  touch "${STEAM_HOME}/.install-complete" "${STEAM_HOME}/.odin-complete-client"
  exit 0
fi

# Host tree the user already bootstrapped (binaries only — never keep accounts).
if [[ -n "${SEED}" && -d "${SEED}" && "$SEED" != /dev/null ]] && is_complete "$SEED"; then
  log "seeding complete client from $SEED (account data excluded)"
  mkdir -p "$STEAM_HOME"
  rsync -a --delete \
    --exclude 'logs/' \
    --exclude 'dumps/' \
    --exclude 'userdata/' \
    --exclude 'ssfn*' \
    --exclude 'config/loginusers.vdf' \
    --exclude 'config/config.vdf' \
    --exclude 'config/DialogConfig.vdf' \
    --exclude 'config/remoteclients.vdf' \
    --exclude 'config/htmlcache/' \
    --exclude 'config/avatarcache/' \
    --exclude 'registry.vdf' \
    --exclude 'appcache/httpcache/' \
    --exclude 'appcache/cefdata/' \
    --exclude 'steamapps/common/' \
    --exclude 'steamapps/compatdata/' \
    --exclude 'steamapps/shadercache/' \
    --exclude 'steamapps/workshop/' \
    --exclude '.crash' \
    --exclude 'steam.pid' \
    "$SEED/" "$STEAM_HOME/"
  sanitize_steam_user_data "$STEAM_HOME"
  touch "${STEAM_HOME}/.install-complete" "${STEAM_HOME}/.odin-complete-client"
  log "seeded $(du -sh "$STEAM_HOME" | awk '{print $1}')"
  exit 0
fi

if [[ ! -x "$UBUNTU_ARM" ]]; then
  log "ERROR: no complete seed and missing $UBUNTU_ARM"
  exit 1
fi

log "running SteamARM ($UBUNTU_ARM) channel=${CHANNEL}"
mkdir -p "$(dirname "$STEAM_HOME")"
export HOME="$(cd -- "$(dirname "$(dirname "$STEAM_HOME")")" && pwd)"
# STEAM_HOME is ~/.local/share/Steam — HOME is ~ 
if [[ "$(basename "$(dirname "$STEAM_HOME")")" == share ]]; then
  HOME="$(cd -- "$STEAM_HOME/../../.." && pwd)"
fi
export HOME
export STEAM_ARM_CHANNEL="$CHANNEL"
export STEAM_ARM_NONINTERACTIVE=1
export STEAM_ARM_SKIP_SYSTEM=1
export STEAM_ARM_SKIP_BOOTSTRAP_RUN="${STEAM_ARM_SKIP_BOOTSTRAP_RUN:-0}"
# install-steam-arm always uses ~/.local/share/Steam
if [[ "$STEAM_HOME" != "${HOME}/.local/share/Steam" ]]; then
  log "SteamARM writes \$HOME/.local/share/Steam; HOME=$HOME"
fi
bash "$UBUNTU_ARM"

if [[ -d "${HOME}/.local/share/Steam" && "$STEAM_HOME" != "${HOME}/.local/share/Steam" ]]; then
  rsync -a "${HOME}/.local/share/Steam/" "$STEAM_HOME/"
fi

if ! is_complete "$STEAM_HOME"; then
  log "WARN: client still incomplete after SteamARM (need a DISPLAY bootstrap run)"
  exit 1
fi
sanitize_steam_user_data "$STEAM_HOME"
touch "${STEAM_HOME}/.install-complete" "${STEAM_HOME}/.odin-complete-client"
log "SteamARM client complete"
