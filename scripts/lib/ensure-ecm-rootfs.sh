#!/usr/bin/env bash
# Ensure Extra CMake Modules >= 6.5 in a Frame rootfs (kscreen / plasma-nm need it).
# Holo extra ships ECM 6.1.0 — replace with ALARM any-arch 6.30 when too old.
#
# Usage: ensure-ecm-rootfs.sh [rootfs] [min_version]
set -euo pipefail

R="${1:-}"
MIN_VER="${2:-6.5.0}"
[[ -n "$R" && -d "$R/usr" ]] || { echo "ERROR: bad rootfs: ${R:-empty}" >&2; exit 1; }

ecm_version() {
  local vf="$R/usr/share/ECM/cmake/ECMConfigVersion.cmake"
  [[ -f "$vf" ]] || return 1
  grep -m1 'set(PACKAGE_VERSION' "$vf" | sed -n 's/.*"\([^"]*\)".*/\1/p'
}

version_ge() {
  [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

install_ecm_alarm() {
  local pkg="${ECM_PKG:-/tmp/extra-cmake-modules-6.30.0-1-any.pkg.tar.xz}"
  if [[ ! -f "$pkg" ]]; then
    echo "==> [ecm] downloading extra-cmake-modules 6.30.0 (ALARM)"
    curl -fsSL --max-time 120 -o "$pkg" \
      "http://mirror.archlinuxarm.org/aarch64/extra/extra-cmake-modules-6.30.0-1-any.pkg.tar.xz"
  fi
  local tmp
  tmp="$(mktemp -d)"
  tar -C "$tmp" -xf "$pkg"
  mkdir -p "$R/usr/share/ECM"
  cp -a "$tmp/usr/share/ECM/." "$R/usr/share/ECM/"
  rm -rf "$tmp"
}

cur="$(ecm_version || true)"
if [[ -n "$cur" ]] && version_ge "$MIN_VER" "$cur"; then
  echo "==> [ecm] OK: ${cur} (need >= ${MIN_VER})"
  exit 0
fi

echo "==> [ecm] upgrading ECM (${cur:-missing} → >= ${MIN_VER})"
install_ecm_alarm
cur="$(ecm_version || true)"
[[ -n "$cur" ]] || { echo "ERROR: ECM missing after install" >&2; exit 1; }
version_ge "$MIN_VER" "$cur" || {
  echo "ERROR: ECM ${cur} still below ${MIN_VER}" >&2
  exit 1
}
echo "==> [ecm] installed ${cur}"
