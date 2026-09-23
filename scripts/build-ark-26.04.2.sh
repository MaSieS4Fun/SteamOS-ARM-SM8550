#!/usr/bin/env bash
# Build official KDE Ark 26.04.2 (same Gear train as hotfix kate) for Qt 6.8.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="${1:-}"
[[ -n "$R" && -d "$R/usr" ]] || { echo "Usage: $0 <rootfs>" >&2; exit 1; }
R="$(cd "$R" && pwd)"
SRC_TGZ="${ARK_SRC:-/tmp/ark-src/ark-26.04.2.tar.xz}"
SRC_DIR="/tmp/ark-src/ark-26.04.2"
BUILD="/tmp/ark-build-26.04.2"

mkdir -p /tmp/ark-src
if [[ ! -f "$SRC_TGZ" ]]; then
  curl -fsSL --max-time 120 -o "$SRC_TGZ" \
    "https://download.kde.org/stable/release-service/26.04.2/src/ark-26.04.2.tar.xz"
fi
if [[ ! -f "$SRC_DIR/CMakeLists.txt" ]]; then
  tar -xJf "$SRC_TGZ" -C /tmp/ark-src
fi
command -v bwrap >/dev/null 2>&1 || { echo "ERROR: bwrap required" >&2; exit 1; }

rm -rf "$BUILD"
mkdir -p "$BUILD"

run() {
  bwrap --bind "$R" / \
    --bind /tmp /tmp \
    --dev /dev --proc /proc --tmpfs /run \
    --unshare-pid --die-with-parent --chdir /tmp \
    "$@"
}

run /usr/bin/cmake -S "$SRC_DIR" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_TESTING=OFF \
  -DBUILD_DOC=OFF
run /usr/bin/cmake --build "$BUILD" -j"$(nproc)"
run /usr/bin/cmake --install "$BUILD"
echo "OK: Ark 26.04.2 installed into $R"
