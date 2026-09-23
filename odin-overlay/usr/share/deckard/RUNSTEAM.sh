#!/bin/bash
# Handheld SM8550 launcher. Do not pass -deckard / -vrgamepadui: those switch
# the client beta to the internal Steam Frame build and wait on SteamVR.

set -euo pipefail
STEAMROOT="$( cd -- "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

IS_SIDELOAD=0
SIDELOADED_STEAMROOT="${HOME}/devkit-game/steam"
if [ "${STEAMROOT}" == "${SIDELOADED_STEAMROOT}" ]; then
  echo "Running sideloaded Steam client in ${STEAMROOT}"
  IS_SIDELOAD=1
  export SUPPRESS_STEAM_OVERLAY=1
fi

STEAM_RT_ARM64=steamrtarm64
STEAM_SDK_ARM64=linuxarm64

if [[ ! -d "${STEAMROOT}/${STEAM_RT_ARM64}" ]]; then
  if [[ -d "${STEAMROOT}/linuxarm64" ]]; then
    STEAM_RT_ARM64="linuxarm64"
  fi
fi

if [[ ! -d "${STEAMROOT}/${STEAM_SDK_ARM64}" ]]; then
  if [[ -d "${STEAMROOT}/steamrtarm64" ]]; then
    STEAM_SDK_ARM64="steamrtarm64"
  fi
fi

export LD_LIBRARY_PATH="${STEAMROOT}/${STEAM_RT_ARM64}"
export SteamDeck="${SteamDeck:-1}"
export QT_QPA_PLATFORM=xcb
export _STEAM_SETENV_MANAGER=1
export DISPLAY="${DISPLAY:-:0}"
if [[ -z "${GAMESCOPE_WAYLAND_DISPLAY:-}" ]]; then
  if [[ -S "${XDG_RUNTIME_DIR:-/run/user/1000}/gamescope-0" ]]; then
    export GAMESCOPE_WAYLAND_DISPLAY=gamescope-0
  fi
fi
export GAMESCOPE_WAYLAND_DISPLAY="${GAMESCOPE_WAYLAND_DISPLAY:-gamescope-0}"
unset WAYLAND_DISPLAY XDG_SESSION_TYPE || true
for _i in $(seq 1 50); do
  [[ -S /tmp/.X11-unix/X0 ]] && break
  sleep 0.1
done
# Force-off leaves .crash; Steam then opens -child-update-ui (the wheel)
# and logs "Looks like steam didn't shutdown cleanly".
rm -f "${STEAMROOT}/.crash" "${STEAMROOT}/steam.pid" 2>/dev/null || true
printf '%s\n' \
  'BootStrapperInhibitAll=enable' \
  'BootStrapperForceSelfUpdate=disable' \
  'BootStrapperInhibitClientChecksum=enable' \
  'BootStrapperInhibitBootstrapperChecksum=enable' \
  'BootStrapperInhibitUpdateOnLaunch=enable' \
  >"${STEAMROOT}/steam.cfg" 2>/dev/null || true
# Version 0 / "no bootstrapper found" keeps Gamepad UI on the update spinner.
if [[ ! -s "${STEAMROOT}/steam.inf" ]]; then
  ver=1788652215
  [[ -r "${STEAMROOT}/.odin-handheld-client" ]] \
    && ver="$(awk 'NR==2 && /^[0-9]+$/{print; exit}' "${STEAMROOT}/.odin-handheld-client")"
  printf 'ClientVersion=%s\n' "${ver:-1788652215}" >"${STEAMROOT}/steam.inf"
  cp -f "${STEAMROOT}/steam.inf" "${STEAMROOT}/steamrtarm64/steam.inf" 2>/dev/null || true
fi
# Force-off leaves Chrome singleton locks + a half-written htmlcache.
# Then index.html paints and never pulls libraries.js (no Gamepad window).
htmlcache="${STEAMROOT}/config/htmlcache"
if [[ -L "${htmlcache}/SingletonLock" || -e "${htmlcache}/SingletonLock" ]]; then
  rm -f "${htmlcache}/SingletonLock" "${htmlcache}/SingletonCookie" \
        "${htmlcache}/SingletonSocket" 2>/dev/null || true
fi
# ResourceHandler serves on-disk steamui/ when present. 0-byte stubs or a
# missing tree produce a blank steamloopback page (no libraries.js).
# The Frame tarball client never finishes the library. Prefer the handheld
# ARM client extracted by apply-odin-mods / install-steam-client-arm64.
steam_tar=/usr/lib/steam/steam.tar.zst
if [[ ! -e "${STEAMROOT}/.odin-handheld-client" && -f "$steam_tar" ]]; then
  if [[ ! -s "${STEAMROOT}/steamui/index.html" ]] \
     || ! grep -q 'libraries~' "${STEAMROOT}/steamui/index.html" 2>/dev/null; then
    rm -rf "${STEAMROOT}/steamui"
    tar --zstd -xf "$steam_tar" -C "${STEAMROOT}" ./steamui 2>/dev/null || true
  fi
fi
if [[ -x /usr/lib/steamos/sm8550-patch-steamui ]]; then
  /usr/lib/steamos/sm8550-patch-steamui "${STEAMROOT}/steamui" >/dev/null 2>&1 || true
fi
# Frame tarball leaves linuxarm64/steamclient.so as 0 bytes. webhelper
# dlmopens that path and Gamepad UI never creates the BPM window.
if [[ -d "${STEAMROOT}/linuxarm64" && -d "${STEAMROOT}/steamrtarm64" ]]; then
  for _lib in steamclient.so crashhandler.so steam-launch-wrapper; do
    _src="${STEAMROOT}/steamrtarm64/${_lib}"
    _dst="${STEAMROOT}/linuxarm64/${_lib}"
    if [[ -s "$_src" && ! -s "$_dst" ]]; then
      cp -f "$_src" "$_dst" 2>/dev/null || true
    fi
  done
  unset _lib _src _dst
fi
echo "RUNSTEAM: DISPLAY=${DISPLAY} GAMESCOPE_WAYLAND_DISPLAY=${GAMESCOPE_WAYLAND_DISPLAY} QT_QPA_PLATFORM=${QT_QPA_PLATFORM}"

function ln_for_real()
{
  if [[ -d "${2}" ]]; then
    rm -rf "${2}"
  fi
  ln -sTfn "${1}" "${2}"
}

mkdir -p ~/.steam
if [[ "${IS_SIDELOAD}" == "0" ]]; then
  ln_for_real "${STEAMROOT}" ~/.steam/steam
else
  ln_for_real ~/.local/share/Steam ~/.steam/steam
fi
ln_for_real "${STEAMROOT}" ~/.steam/root
ln_for_real "${STEAMROOT}/linux32" ~/.steam/sdk32
ln_for_real "${STEAMROOT}/linux64" ~/.steam/sdk64
ln_for_real "${STEAMROOT}/${STEAM_SDK_ARM64}" ~/.steam/sdkarm64
ln_for_real "${STEAMROOT}/${STEAM_RT_ARM64}" ~/.steam/binarm64
ln_for_real "${STEAMROOT}/ubuntu12_32" ~/.steam/bin32
ln_for_real "${STEAMROOT}/ubuntu12_64" ~/.steam/bin64

export STEAM_RUNTIME="$STEAMROOT/ubuntu12_32/steam-runtime"
if [ -f $STEAMROOT/steamapps/common/FEX-Emu/fex-compat-tool ]; then
  export STEAM_RUNTIME_LIBRARY_PATH=$($STEAMROOT/steamapps/common/FEX-Emu/fex-compat-tool run -- $STEAMROOT/ubuntu12_32/steam-runtime/run.sh --print-steam-runtime-library-paths)
  echo "setting STEAM_RUNTIME_LIBRARY_PATH via FEX-Emu: ${STEAM_RUNTIME_LIBRARY_PATH}"
else
  export STEAM_RUNTIME_LIBRARY_PATH=$STEAM_RUNTIME/pinned_libs_32:$STEAM_RUNTIME/pinned_libs_64:/usr/local/lib/i386-linux-gnu:/lib/i386-linux-gnu:/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu:/lib:$STEAM_RUNTIME/lib/i386-linux-gnu:$STEAM_RUNTIME/usr/lib/i386-linux-gnu:$STEAM_RUNTIME/lib/x86_64-linux-gnu:$STEAM_RUNTIME/usr/lib/x86_64-linux-gnu:$STEAM_RUNTIME/lib:$STEAM_RUNTIME/usr/lib
  echo "setting STEAM_RUNTIME_LIBRARY_PATH copied from legacy LDLP: ${STEAM_RUNTIME_LIBRARY_PATH}"
fi

if [[ "${IS_SIDELOAD}" == "0" ]]; then
  STEAM_ARGS=(
    -cef-enable-debugging
    -gamepadui
    -steamos3
    -steampal
    -steamdeck
    -noverifyfiles
    -noshaders
    -inhibitbootstrap
    -nobootstrapperupdate
    ${STEAM_EXTRA_ARGS:-}
  )
else
  SIDELOADED_CMDLINE_ARGS_FILE="${HOME}/devkit-game/steamdeckard-argv.json"
  read -ra STEAM_ARGS <<< "$(jq -r '.[0]' "${SIDELOADED_CMDLINE_ARGS_FILE}")"
fi

STEAM_COMMAND=(
    "${STEAMROOT}/${STEAM_RT_ARM64}/steam" "${STEAM_ARGS[@]}"
)

if [[ "${IS_SIDELOAD}" == "1" ]]; then
  SIDELOADED_SETTINGS_FILE="${HOME}/devkit-game/steamdeckard-settings.json"
  if [[ "$(jq -r '.gdbserver // "0"' "${SIDELOADED_SETTINGS_FILE}")" == "1" ]]; then
    STEAM_COMMAND=(
      gdbserver 127.0.0.1:2345 "${STEAM_COMMAND[@]}"
    )
  fi
fi

cd ${STEAMROOT}
mkdir -p "${HOME}/.local/share/Steam/logs"
# Steam refuses LD_PRELOAD (unsafe unsetenv) and aborts its own startup UI.
unset LD_PRELOAD || true

exec "${STEAM_COMMAND[@]}" >"${HOME}/.local/share/Steam/logs/steam_output.log" 2>&1
