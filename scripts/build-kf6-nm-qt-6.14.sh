#!/usr/bin/env bash
# Build KF6 NetworkManagerQt + ModemManagerQt 6.14.0 (same train as Frame KF6).
# SteamOS extra only ships 6.1.0; plasma-nm 6.2.5 requires >= 6.5.0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
R="$(cd "$R" && pwd)"
VER="6.14.0"

command -v bwrap >/dev/null 2>&1 || { echo "ERROR: bwrap required" >&2; exit 1; }

if [[ ! -f "$R/usr/share/ECM/cmake/ECMConfig.cmake" ]]; then
  ECM_PKG="${ECM_PKG:-/tmp/extra-cmake-modules-6.30.0-1-any.pkg.tar.xz}"
  if [[ ! -f "$ECM_PKG" ]]; then
    curl -fsSL --max-time 60 -o "$ECM_PKG" \
      "http://mirror.archlinuxarm.org/aarch64/extra/extra-cmake-modules-6.30.0-1-any.pkg.tar.xz"
  fi
  tmp="$(mktemp -d)"
  tar -C "$tmp" -xf "$ECM_PKG"
  mkdir -p "$R/usr/share"
  cp -a "$tmp/usr/share/ECM" "$R/usr/share/"
  rm -rf "$tmp"
fi

run() {
  bwrap --bind "$R" / \
    --bind /tmp /tmp --dev /dev --proc /proc --tmpfs /run \
    --unshare-pid --die-with-parent --chdir /tmp \
    "$@"
}

build_fw() {
  local name="$1"
  local tgz="/tmp/kf6-src/${name}-${VER}.tar.xz"
  local src="/tmp/kf6-src/${name}-${VER}"
  local build="/tmp/kf6-build/${name}-${VER}"
  mkdir -p /tmp/kf6-src /tmp/kf6-build
  if [[ ! -f "$src/CMakeLists.txt" ]]; then
    if [[ ! -f "$tgz" ]]; then
      curl -fsSL --max-time 120 -o "$tgz" \
        "https://download.kde.org/stable/frameworks/6.14/${name}-${VER}.tar.xz"
    fi
    tar -xJf "$tgz" -C /tmp/kf6-src
  fi
  rm -rf "$build"
  mkdir -p "$build"
  echo "==> cmake ${name} ${VER}"
  run /usr/bin/cmake -S "$src" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_TESTING=OFF
  run /usr/bin/cmake --build "$build" -j"$(nproc)"
  run /usr/bin/cmake --install "$build"
}

need_nm=0
need_mm=0
if ! grep -q '6\.14' "$R/usr/lib/cmake/KF6NetworkManagerQt/KF6NetworkManagerQtConfigVersion.cmake" 2>/dev/null; then
  need_nm=1
fi
if ! grep -q '6\.14' "$R/usr/lib/cmake/KF6ModemManagerQt/KF6ModemManagerQtConfigVersion.cmake" 2>/dev/null; then
  need_mm=1
fi
(( need_nm )) && build_fw networkmanager-qt
(( need_mm )) && build_fw modemmanager-qt
echo "OK: KF6 NetworkManagerQt/ModemManagerQt ${VER}"
