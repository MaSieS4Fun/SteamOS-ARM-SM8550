#!/usr/bin/env bash
# Build one KDE Gear 26.04.2 app against Frame Qt 6.8 (not ALARM Qt 6.11).
# Usage: build-kde-gear-26.04.2.sh <rootfs> <ark|kcalc|filelight|gwenview|okular>
set -euo pipefail

R="${1:-}"
NAME="${2:-}"
[[ -n "$R" && -d "$R/usr" && -n "$NAME" ]] || {
  echo "Usage: $0 <rootfs> <ark|kcalc|filelight|gwenview|okular>" >&2
  exit 1
}
R="$(cd "$R" && pwd)"
# 26.04.2 wants Poppler >= 24.08; Frame only has 24.03.0.
VER="26.04.2"
[[ "$NAME" == okular ]] && VER="${OKULAR_VER:-24.12.3}"
SRC_TGZ="/tmp/kde-gear-src/${NAME}-${VER}.tar.xz"
SRC_DIR="/tmp/kde-gear-src/${NAME}-${VER}"
BUILD="/tmp/kde-gear-build/${NAME}-${VER}"

mkdir -p /tmp/kde-gear-src /tmp/kde-gear-build
if [[ ! -f "$SRC_DIR/CMakeLists.txt" ]]; then
  if [[ ! -f "$SRC_TGZ" ]]; then
    curl -fsSL --max-time 180 -o "$SRC_TGZ" \
      "https://download.kde.org/stable/release-service/${VER}/src/${NAME}-${VER}.tar.xz"
  fi
  tar -xJf "$SRC_TGZ" -C /tmp/kde-gear-src
fi
# Frame Qt is 6.8.0. filelight 26.04.2 advertises 6.9 but does not need it.
if [[ -f "$SRC_DIR/CMakeLists.txt" ]]; then
  sed -i 's/set(QT_REQUIRED_VERSION "6.9.0")/set(QT_REQUIRED_VERSION "6.8.0")/' \
    "$SRC_DIR/CMakeLists.txt"
fi
command -v bwrap >/dev/null 2>&1 || { echo "ERROR: bwrap required" >&2; exit 1; }

if [[ ! -f "$R/usr/share/ECM/cmake/ECMConfig.cmake" ]]; then
  echo "ERROR: extra-cmake-modules missing in rootfs" >&2
  exit 1
fi

rm -rf "$BUILD"
mkdir -p "$BUILD"

run() {
  bwrap --bind "$R" / \
    --bind /tmp /tmp --dev /dev --proc /proc --tmpfs /run \
    --unshare-pid --die-with-parent --chdir /tmp \
    "$@"
}

# Okular needs KF6 ThreadWeaver (not in the stripped Frame extra).
if [[ "$NAME" == okular && ! -f "$R/usr/lib/cmake/KF6ThreadWeaver/KF6ThreadWeaverConfig.cmake" ]]; then
  TW_VER="6.14.0"
  TW_SRC="/tmp/kf6-src/threadweaver-${TW_VER}"
  TW_BUILD="/tmp/kf6-build/threadweaver-${TW_VER}"
  mkdir -p /tmp/kf6-src /tmp/kf6-build
  if [[ ! -f "$TW_SRC/CMakeLists.txt" ]]; then
    curl -fsSL --max-time 120 -o "/tmp/kf6-src/threadweaver-${TW_VER}.tar.xz" \
      "https://download.kde.org/stable/frameworks/6.14/threadweaver-${TW_VER}.tar.xz"
    tar -xJf "/tmp/kf6-src/threadweaver-${TW_VER}.tar.xz" -C /tmp/kf6-src
  fi
  rm -rf "$TW_BUILD"
  mkdir -p "$TW_BUILD"
  echo "==> cmake threadweaver ${TW_VER} (okular dep)"
  run /usr/bin/cmake -S "$TW_SRC" -B "$TW_BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_TESTING=OFF
  run /usr/bin/cmake --build "$TW_BUILD" -j"$(nproc)"
  run /usr/bin/cmake --install "$TW_BUILD"
fi

CMAKE_EXTRA=()
# Annotation tools need kImageAnnotator (not on Frame). Viewer still works.
[[ "$NAME" == gwenview ]] && CMAKE_EXTRA+=(-DGWENVIEW_IMAGEANNOTATOR=OFF)
# Docs/PS/DjVu are optional; PDF stays required.
[[ "$NAME" == okular ]] && CMAKE_EXTRA+=(
  -DFORCE_NOT_REQUIRED_DEPENDENCIES="KF6DocTools;LibSpectre;DjVuLibre;QMobipocket6"
)

echo "==> cmake ${NAME} ${VER}"
run /usr/bin/cmake -S "$SRC_DIR" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_TESTING=OFF \
  -DBUILD_DOC=OFF \
  "${CMAKE_EXTRA[@]}"
run /usr/bin/cmake --build "$BUILD" -j"$(nproc)"
run /usr/bin/cmake --install "$BUILD"
if strings "$R/usr/bin/${NAME}" 2>/dev/null | grep -q 'Qt_6\.11'; then
  echo "ERROR: ${NAME} still linked against Qt_6.11" >&2
  exit 1
fi
echo "OK: ${NAME} ${VER} installed into $R"
