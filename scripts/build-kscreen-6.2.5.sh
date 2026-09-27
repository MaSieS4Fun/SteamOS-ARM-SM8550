#!/usr/bin/env bash
# Build official KDE kscreen 6.2.5 (Plasma Display Configuration KCM)
# inside the Frame rootfs via bubblewrap so gcc/Qt match glibc 2.39.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
R="$(cd "$R" && pwd)"
SRC_TGZ="${KSCREEN_TGZ:-/tmp/kscreen-src/kscreen-6.2.5.tar.xz}"
SRC="${KSCREEN_SRC:-/tmp/kscreen-src/kscreen-6.2.5}"
BUILD="${KSCREEN_BUILD:-/tmp/kscreen-build-6.2.5}"

mkdir -p /tmp/kscreen-src
if [[ ! -f "$SRC/CMakeLists.txt" ]]; then
  if [[ ! -f "$SRC_TGZ" ]]; then
    curl -fsSL --max-time 120 -o "$SRC_TGZ" \
      "https://download.kde.org/stable/plasma/6.2.5/kscreen-6.2.5.tar.xz"
  fi
  tar -xJf "$SRC_TGZ" -C /tmp/kscreen-src
fi
[[ -f "$SRC/CMakeLists.txt" ]] || {
  echo "ERROR: missing kscreen source at $SRC" >&2
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

run_in_rootfs /usr/bin/cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_TESTING=OFF \
  -DWITH_X11=ON

run_in_rootfs /usr/bin/cmake --build "$BUILD" -j"$(nproc)"
run_in_rootfs /usr/bin/cmake --install "$BUILD"
[[ -f "$R/usr/lib/qt6/plugins/plasma/kcms/systemsettings/kcm_kscreen.so" ]] \
  || { echo "ERROR: kcm_kscreen.so missing after install" >&2; exit 1; }
echo "OK: installed official kscreen 6.2.5 into $R"
