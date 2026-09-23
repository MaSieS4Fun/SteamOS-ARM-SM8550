#!/usr/bin/env bash
# Build Box64 *inside* the Frame rootfs (glibc 2.39).
# Host Ubuntu is glibc 2.43 — a host-linked box64 dies on the device with
#   /usr/lib/libm.so.6: version `GLIBC_2.43' not found
# and plugin_loader.service never starts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
R="$(cd "$R" && pwd)"
SRC="${BOX64_SRC:-${ROOT}/external-and-mods/BOX64/box64}"
BUILD="${BOX64_BUILD_FRAME:-/tmp/box64-build-frame}"

[[ -d "$R/usr" ]] || { echo "ERROR: bad rootfs $R" >&2; exit 1; }
[[ -f "$SRC/CMakeLists.txt" ]] || { echo "ERROR: missing box64 source $SRC" >&2; exit 1; }
[[ -x "$R/usr/bin/cmake" && -x "$R/usr/bin/gcc" ]] || {
  echo "ERROR: rootfs needs gcc+cmake (build against Frame, not the host)" >&2
  exit 1
}
command -v bwrap >/dev/null 2>&1 || { echo "ERROR: bwrap required" >&2; exit 1; }

run() {
  bwrap --bind "$R" / \
    --bind /tmp /tmp \
    --bind "$SRC" /src/box64 \
    --dev /dev --proc /proc --tmpfs /run \
    --unshare-pid --die-with-parent --chdir /tmp \
    "$@"
}

echo "==> cmake Box64 (SD8G2) against $R"
rm -rf "$BUILD"
mkdir -p "$BUILD"
run /usr/bin/cmake -S /src/box64 -B "$BUILD" -G Ninja \
  -DSD8G2=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local

echo "==> build Box64"
run /usr/bin/cmake --build "$BUILD" -j"$(nproc)"
echo "==> install Box64 into $R"
run /usr/bin/cmake --install "$BUILD"
ln -sfn /usr/local/bin/box64 "$R/usr/bin/box64"
if [[ -f "$R/etc/binfmt.d/box64.conf" ]]; then
  mkdir -p "$R/usr/lib/binfmt.d"
  cp -a "$R/etc/binfmt.d/box64.conf" "$R/usr/lib/binfmt.d/box64.conf"
fi

if strings "$R/usr/local/bin/box64" | grep -q 'GLIBC_2\.43'; then
  echo "ERROR: box64 still needs GLIBC_2.43 — not a Frame build" >&2
  exit 1
fi
echo "OK: Box64 installed into $R (no GLIBC_2.43)"
