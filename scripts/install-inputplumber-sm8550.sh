#!/usr/bin/env bash
# Install ShadowBlip InputPlumber + SM8550 deck-uhid composite into a SteamOS rootfs.
# deck-uhid + keyboard (OSK haptics). Dupes fixed by 72-sm8550-touch-dedupe udev.
# USB/Bluetooth HID is ignored in the composite so it is not grabbed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
OVL="${ROOT}/odin-overlay"
CACHE="${ROOT}/external-and-mods/InputPlumber"
IP_VER="${INPUTPLUMBER_VERSION:-0.78.1}"
TGZ="${CACHE}/inputplumber-aarch64.tar.gz"
TGZ_URL="https://github.com/ShadowBlip/InputPlumber/releases/download/v${IP_VER}/inputplumber-aarch64.tar.gz"

log() { printf '==> [inputplumber] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "${R}/usr" ]] || die "not a rootfs: ${R}"
mkdir -p "${CACHE}"

fetch() {
  local url="$1" dest="$2"
  [[ -s "$dest" ]] && return 0
  log "Downloading ${url}"
  if command -v curl >/dev/null; then
    curl -fL --retry 3 -o "${dest}.part" "$url"
  else
    wget -O "${dest}.part" "$url"
  fi
  mv -f "${dest}.part" "$dest"
}

install_tarball() {
  if [[ ! -s "$TGZ" ]]; then
    fetch "$TGZ_URL" "$TGZ"
  fi
  [[ -s "$TGZ" ]] || die "missing ${TGZ}"
  local stage="${CACHE}/extract"
  rm -rf "$stage"
  mkdir -p "$stage"
  tar -C "$stage" -xzf "$TGZ"
  local src="$stage"
  if [[ ! -x "${src}/usr/bin/inputplumber" ]]; then
    local inner
    inner="$(find "$stage" -type f -name inputplumber -path '*/usr/bin/*' | head -1)"
    [[ -n "$inner" ]] || die "tarball has no usr/bin/inputplumber"
    src="$(cd "$(dirname "$inner")/../.." && pwd)"
  fi
  log "Installing InputPlumber files from ${src}"
  mkdir -p "${R}/usr" "${R}/etc"
  cp -a "${src}/usr/." "${R}/usr/"
  if [[ -d "${src}/etc" ]]; then
    cp -a "${src}/etc/." "${R}/etc/"
  fi
  [[ -x "${R}/usr/bin/inputplumber" ]] || die "inputplumber binary missing after extract"
}

install_libiio() {
  if [[ -e "${R}/usr/lib/libiio.so.0" || -e "${R}/usr/lib/libiio.so" ]]; then
    log "libiio already in rootfs"
    return 0
  fi
  # Minimal local-backend libiio — InputPlumber links it even without IMU.
  local src="${CACHE}/libiio-src"
  if [[ ! -f "${src}/CMakeLists.txt" ]]; then
    rm -rf "$src"
    fetch "https://github.com/analogdevicesinc/libiio/archive/refs/tags/v0.26.tar.gz" \
      "${CACHE}/libiio-0.26.tar.gz"
    mkdir -p "$src"
    tar -C "$src" --strip-components=1 -xzf "${CACHE}/libiio-0.26.tar.gz"
  fi
  command -v cmake >/dev/null || die "cmake required to build libiio"
  local bld="${CACHE}/libiio-src/build-steamos"
  cmake -S "$src" -B "$bld" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DWITH_LOCAL_BACKEND=ON \
    -DWITH_XML_BACKEND=OFF \
    -DWITH_NETWORK_BACKEND=OFF \
    -DWITH_USB_BACKEND=OFF \
    -DWITH_SERIAL_BACKEND=OFF \
    -DHAVE_DNS_SD=OFF \
    -DWITH_ZSTD=OFF \
    -DWITH_EXAMPLES=OFF \
    -DWITH_TESTS=OFF \
    -DWITH_IIOD=OFF \
    -DWITH_AIO=OFF \
    -DWITH_HWMON=ON
  cmake --build "$bld" -j"$(nproc)"
  DESTDIR="$R" cmake --install "$bld"
  if [[ -e "${R}/usr/lib/aarch64-linux-gnu/libiio.so.0" && ! -e "${R}/usr/lib/libiio.so.0" ]]; then
    ln -sfn aarch64-linux-gnu/libiio.so.0 "${R}/usr/lib/libiio.so.0"
  fi
  if [[ -e "${R}/usr/lib/libiio.so" && ! -e "${R}/usr/lib/libiio.so.0" ]]; then
    ln -sfn "$(basename "$(readlink -f "${R}/usr/lib/libiio.so")")" "${R}/usr/lib/libiio.so.0"
  fi
  [[ -e "${R}/usr/lib/libiio.so.0" || -e "${R}/usr/lib64/libiio.so.0" ]] \
    || die "libiio.so.0 missing after build"
  if [[ -e "${R}/usr/lib64/libiio.so.0" && ! -e "${R}/usr/lib/libiio.so.0" ]]; then
    ln -sfn ../lib64/libiio.so.0 "${R}/usr/lib/libiio.so.0"
  fi
  log "Built local-backend libiio into rootfs"
}

install_odin_composite() {
  "${SCRIPT_DIR}/install-sm8550-input-overlay.sh" "${R}"
  mkdir -p "${R}/etc/systemd/system/multi-user.target.wants"
  ln -sfn /usr/lib/systemd/system/inputplumber.service \
    "${R}/etc/systemd/system/multi-user.target.wants/inputplumber.service"
}

verify_needed() {
  python3 - "${R}/usr/bin/inputplumber" "${R}" <<'PY'
import pathlib, struct, sys
binary, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
data = binary.read_bytes()
if data[:4] != b"\x7fELF":
    raise SystemExit("not ELF")
needed = []
# Parse DT_NEEDED via a cheap scan of dynamic strings after readelf-less fallback
try:
    import subprocess
    out = subprocess.check_output(["readelf", "-d", str(binary)], text=True)
    for line in out.splitlines():
        if "NEEDED" in line and "[" in line:
            needed.append(line.split("[", 1)[1].split("]", 1)[0])
except Exception:
    pass
missing = []
libdirs = [root / "usr/lib", root / "usr/lib64", root / "lib"]
for soname in needed:
    if soname in {"linux-vdso.so.1", "ld-linux-aarch64.so.1"}:
        continue
    if any((d / soname).exists() for d in libdirs):
        continue
    missing.append(soname)
print("NEEDED:", ", ".join(needed) or "(unknown)")
if missing:
    raise SystemExit("missing libraries in rootfs: " + ", ".join(missing))
print("all NEEDED libs present in rootfs")
PY
}

install_tarball
install_libiio
install_odin_composite
verify_needed
log "Steam will see Valve Steam Deck Controller (deck-uhid + keyboard haptics)"
log "Touch dedupe baked in udev: 72-sm8550-touch-dedupe.rules"
