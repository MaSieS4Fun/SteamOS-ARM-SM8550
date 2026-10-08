#!/usr/bin/env bash
# Apply native SteamOS profiles and the unprivileged Decky power plugin to the
# project rootfs and optionally to a mounted SteamOS card.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERLAY="${PROJECT}/odin-overlay"
PROJECT_ROOTFS="${PROJECT}/rootfs"
MOUNTED_ROOT="${1:-/run/media/masies/root}"
MOUNTED_HOME="${2:-/run/media/masies/home/steamos}"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

install_power_fix() {
  local root="$1"
  [[ -d "${root}/usr/lib/systemd" ]] || {
    echo "ERROR: invalid SteamOS root: ${root}" >&2
    return 1
  }
  install -D -o root -g root -m0644 \
    "${OVERLAY}/usr/lib/systemd/user/sm8550-plugin-loader.service" \
    "${root}/usr/lib/systemd/user/sm8550-plugin-loader.service"
  rm -f "${root}/usr/lib/systemd/system/sm8550-plugin-loader-root.service" \
    "${root}/etc/sudoers.d/sm8550-plugin-loader"
  install -D -o root -g root -m0644 \
    "${OVERLAY}/usr/share/steamos-manager/devices/ayn-odin2.toml" \
    "${root}/usr/share/steamos-manager/devices/ayn-odin2.toml"
  install -D -o root -g root -m0755 \
    "${OVERLAY}/usr/bin/install-decky" \
    "${root}/usr/bin/install-decky"
}

install_power_fix "${PROJECT_ROOTFS}"
install_power_fix "${MOUNTED_ROOT}"

BUNDLED="${MOUNTED_ROOT}/usr/share/steamos-odin/decky-plugins/power-managment"
PLUGIN_SOURCE="${PROJECT}/external-and-mods/Decky/sm8550/power-managment"
[[ -f "${PLUGIN_SOURCE}/plugin.json" && -f "${PLUGIN_SOURCE}/dist/index.js" ]] || {
  echo "ERROR: built power plugin missing under ${PLUGIN_SOURCE}" >&2
  exit 1
}
mkdir -p "${PROJECT_ROOTFS}/usr/share/steamos-odin/decky-plugins/power-managment" \
  "${BUNDLED}"
rsync -a --delete --exclude node_modules --exclude src --exclude .pnpm-store \
  "${PLUGIN_SOURCE}/" \
  "${PROJECT_ROOTFS}/usr/share/steamos-odin/decky-plugins/power-managment/"
rsync -a --delete --exclude node_modules --exclude src --exclude .pnpm-store \
  "${PLUGIN_SOURCE}/" "${BUNDLED}/"
mkdir -p "${MOUNTED_HOME}/homebrew/plugins/power-managment"
rsync -a --delete "${BUNDLED}/" \
  "${MOUNTED_HOME}/homebrew/plugins/power-managment/"
chown -R 1000:1000 "${MOUNTED_HOME}/homebrew/plugins/power-managment"

cmp -s \
  "${OVERLAY}/usr/lib/systemd/user/sm8550-plugin-loader.service" \
  "${MOUNTED_ROOT}/usr/lib/systemd/user/sm8550-plugin-loader.service"
cmp -s \
  "${OVERLAY}/usr/share/steamos-manager/devices/ayn-odin2.toml" \
  "${MOUNTED_ROOT}/usr/share/steamos-manager/devices/ayn-odin2.toml"
test -f "${MOUNTED_HOME}/homebrew/plugins/power-managment/plugin.json"

sync
echo "OK: native profiles and unprivileged Decky power plugin installed"
