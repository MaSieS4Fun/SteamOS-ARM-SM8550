#!/usr/bin/env bash
# Build official Plasma plasma-nm 6.2.5 (Wi-Fi KCM + panel applet)
# inside the Frame rootfs. ALARM plasma-nm is 6.7 and will not load on 6.2.5.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
R="$(cd "$R" && pwd)"
SRC_TGZ="${PLASMA_NM_TGZ:-/tmp/plasma-nm-src/plasma-nm-6.2.5.tar.xz}"
SRC="${PLASMA_NM_SRC:-/tmp/plasma-nm-src/plasma-nm-6.2.5}"
BUILD="${PLASMA_NM_BUILD:-/tmp/plasma-nm-build-6.2.5}"

mkdir -p /tmp/plasma-nm-src
if [[ ! -f "$SRC/CMakeLists.txt" ]]; then
  if [[ ! -f "$SRC_TGZ" ]]; then
    curl -fsSL --max-time 120 -o "$SRC_TGZ" \
      "https://download.kde.org/stable/plasma/6.2.5/plasma-nm-6.2.5.tar.xz"
  fi
  tar -xJf "$SRC_TGZ" -C /tmp/plasma-nm-src
fi
[[ -f "$SRC/CMakeLists.txt" ]] || {
  echo "ERROR: missing plasma-nm source at $SRC" >&2
  exit 1
}
command -v bwrap >/dev/null 2>&1 || {
  echo "ERROR: bwrap is required to build against the rootfs glibc" >&2
  exit 1
}

"${SCRIPT_DIR}/lib/ensure-ecm-rootfs.sh" "$R"

rm -rf "$BUILD"
mkdir -p "$BUILD"

run_in_rootfs() {
  bwrap --bind "$R" / \
    --bind /tmp /tmp \
    --dev /dev \
    --proc /proc \
    --tmpfs /run \
    --unshare-pid \
    --die-with-parent \
    --chdir /tmp \
    "$@"
}

# OpenConnect VPN needs extra libs; Wi-Fi/ethernet KCM does not.
run_in_rootfs /usr/bin/cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_TESTING=OFF \
  -DBUILD_OPENCONNECT=OFF

run_in_rootfs /usr/bin/cmake --build "$BUILD" -j"$(nproc)"
run_in_rootfs /usr/bin/cmake --install "$BUILD"
[[ -f "$R/usr/lib/qt6/plugins/plasma/kcms/systemsettings_qwidgets/kcm_networkmanagement.so" ]] \
  || { echo "ERROR: kcm_networkmanagement.so missing after install" >&2; exit 1; }
echo "OK: installed official plasma-nm 6.2.5 into $R"
