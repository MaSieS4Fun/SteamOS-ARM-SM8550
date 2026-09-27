#!/usr/bin/env bash
# Build vendor MangoHud (+ mangoapp) inside Frame rootfs and install Holo layout:
#   /usr/lib/mangohud/lib64/libMangoHud*.so
#   /usr/share/vulkan/implicit_layer.d/MangoHud.aarch64.json → that path
#   /usr/bin/mangohud  (wrapper with correct LD_PRELOAD path)
#
# Usage: ./scripts/build-vendor-mangohud.sh [/path/to/rootfs]
# Env:   MANGOHUD_SRC  MANGOHUD_BUILD  JOBS  FORCE_REBUILD=1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
SRC="${MANGOHUD_SRC:-${ROOT}/external-and-mods/MangoHud}"
BUILD="${MANGOHUD_BUILD:-/tmp/mangohud-vendor-build}"
BIND="/tmp/mangohud-vendor-src"
JOBS="${JOBS:-$(nproc)}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
STOCK="${R}/opt/stock-steamos"
OVL="${ROOT}/odin-overlay"

log() { printf '==> [mangohud] %s\n' "$*"; }
die() { printf 'ERROR: [mangohud] %s\n' "$*" >&2; exit 1; }

[[ -d "${R}/usr/lib" ]] || die "Missing rootfs: ${R}"
[[ -f "${SRC}/meson.build" ]] || die "Missing MangoHud source: ${SRC}"

backup_once() {
  local rel="$1"
  [[ -e "${R}/${rel}" ]] || return 0
  mkdir -p "${STOCK}/$(dirname "${rel}")"
  [[ -e "${STOCK}/${rel}" ]] || cp -a "${R}/${rel}" "${STOCK}/${rel}"
}

mount_chroot() {
  mountpoint -q "${R}/proc" || mount -t proc proc "${R}/proc"
  mountpoint -q "${R}/dev" || mount --bind /dev "${R}/dev"
  mountpoint -q "${R}/sys" || mount -t sysfs sys "${R}/sys"
  mkdir -p "${R}${BIND}"
  mountpoint -q "${R}${BIND}" || mount --bind "${SRC}" "${R}${BIND}"
}

MESON_VENV="/tmp/mangohud-meson-venv"
MESON_WHEEL_DIR="${MESON_WHEEL_DIR:-/tmp/meson-wheels}"

wheels_ok_for_chroot() {
  local py_ver="$1" cp_tag="$2"
  compgen -G "${MESON_WHEEL_DIR}/meson-*.whl" >/dev/null || return 1
  compgen -G "${MESON_WHEEL_DIR}/mako-*.whl" >/dev/null || return 1
  compgen -G "${MESON_WHEEL_DIR}/markupsafe-*-${cp_tag}-*.whl" >/dev/null \
    || compgen -G "${MESON_WHEEL_DIR}/markupsafe-*-py3-none-any.whl" >/dev/null
}

download_meson_wheels_for_chroot() {
  local py_ver="$1"
  log "Downloading meson + mako wheels for chroot Python ${py_ver} (aarch64)..."
  mkdir -p "${MESON_WHEEL_DIR}"
  rm -f "${MESON_WHEEL_DIR}/"*.whl
  pip3 download -d "${MESON_WHEEL_DIR}" \
    --python-version "${py_ver}" \
    --platform manylinux2014_aarch64 \
    --only-binary=:all: \
    'meson>=1.7' mako markupsafe \
    || pip download -d "${MESON_WHEEL_DIR}" \
    --python-version "${py_ver}" \
    --platform manylinux2014_aarch64 \
    --only-binary=:all: \
    'meson>=1.7' mako markupsafe
}

ensure_meson_in_chroot() {
  local chroot_py chroot_cp
  chroot_py="$(chroot "${R}" python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  chroot_cp="$(chroot "${R}" python3 -c 'import sys; print(f"cp{sys.version_info.major}{sys.version_info.minor}")')"

  if ! wheels_ok_for_chroot "${chroot_py}" "${chroot_cp}"; then
    download_meson_wheels_for_chroot "${chroot_py}"
  fi
  mkdir -p "${R}/tmp/meson-wheels"
  rm -f "${R}/tmp/meson-wheels/"*.whl
  cp -a "${MESON_WHEEL_DIR}/"*.whl "${R}/tmp/meson-wheels/"

  chroot "${R}" bash -c "
set -e
if ! python3 -c 'import mako' 2>/dev/null; then
  if compgen -G '/tmp/meson-wheels/mako-*.whl' >/dev/null; then
    pip3 install --break-system-packages --no-index --find-links=/tmp/meson-wheels mako 2>/dev/null \
      || pip3 install --no-index --find-links=/tmp/meson-wheels mako
  else
    echo 'Missing mako for python3 in chroot' >&2
    exit 1
  fi
fi
python3 -c 'import mako'
"

  chroot "${R}" bash -c "
set -e
MESON_VENV='${MESON_VENV}'
meson_ge_17() {
  local m=\"\$1\" v
  [[ -x \"\$m\" ]] || return 1
  v=\"\$(\"\$m\" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\\.[0-9]+(\\.[0-9]+)?' | head -1)\"
  [[ -n \"\$v\" ]] || return 1
  [[ \"\$(printf '%s\\n' '1.7' \"\$v\" | sort -V | head -1)\" == \"1.7\" ]]
}
venv_meson_ready() {
  meson_ge_17 \"\${MESON_VENV}/bin/meson\" \
    && \"\${MESON_VENV}/bin/python\" -c 'import mako' 2>/dev/null
}
install_mako_in_venv() {
  if compgen -G '/tmp/meson-wheels/mako-*.whl' >/dev/null; then
    \"\${MESON_VENV}/bin/pip\" install --no-index --find-links=/tmp/meson-wheels mako
  else
    echo 'Missing mako wheels in /tmp/meson-wheels' >&2
    exit 1
  fi
}
if venv_meson_ready; then
  exit 0
fi
echo '==> preparing meson venv ${MESON_VENV}'
if ! meson_ge_17 \"\${MESON_VENV}/bin/meson\" 2>/dev/null; then
  rm -rf \"\${MESON_VENV}\"
  python3 -m venv \"\${MESON_VENV}\"
  if compgen -G '/tmp/meson-wheels/meson-*.whl' >/dev/null; then
    \"\${MESON_VENV}/bin/pip\" install --no-index --find-links=/tmp/meson-wheels meson
  else
    \"\${MESON_VENV}/bin/pip\" install --break-system-packages 'meson>=1.7' 2>/dev/null \
      || \"\${MESON_VENV}/bin/pip\" install 'meson>=1.7'
  fi
fi
# Meson from the venv uses venv python for the mako module check.
install_mako_in_venv
\"\${MESON_VENV}/bin/python\" -c 'import mako'
meson_ge_17 \"\${MESON_VENV}/bin/meson\" || exit 1
"
}

log "Rootfs: ${R}"
log "Source: ${SRC}"

# Backup Holo/stock MangoHud pieces once (for restore-frame-opengl-style rollback).
for item in \
  usr/bin/mangohud usr/bin/mangohud-next usr/bin/mangoapp usr/bin/mangohudctl \
  usr/lib/mangohud \
  usr/share/vulkan/implicit_layer.d/MangoHud.aarch64.json \
  usr/share/vulkan/implicit_layer.d/MangoHud-next.aarch64.json
do
  [[ -e "${R}/${item}" ]] && backup_once "${item}"
done
for lib in libMangoHud.so libMangoHud_opengl.so libMangoHud_shim.so libMangoHud-next.so; do
  [[ -f "${R}/usr/lib/${lib}" ]] && backup_once "usr/lib/${lib}"
done

(
  cd "${SRC}"
  git submodule update --init --recursive 2>/dev/null || true
)

mount_chroot
ensure_meson_in_chroot

if [[ "${FORCE_REBUILD}" == "1" ]]; then
  chroot "${R}" rm -rf "${BUILD}"
fi

log "Meson build inside chroot (mangoapp=true, libdir=lib/mangohud/lib64)"
chroot "${R}" bash -c "
set -e
export PATH=\"${MESON_VENV}/bin:/usr/local/bin:/usr/bin:/bin:\${PATH}\"
pkg-config --exists glfw3 || { echo 'Missing glfw3 in rootfs'; exit 1; }
pkg-config --exists dbus-1 || { echo 'Missing dbus-1 in rootfs'; exit 1; }
pkg-config --exists x11 || { echo 'Missing x11 in rootfs'; exit 1; }
command -v ninja >/dev/null || { echo 'Missing ninja in rootfs'; exit 1; }

if [[ ! -f '${BUILD}/build.ninja' ]]; then
  meson setup '${BUILD}' '${BIND}' \
    --prefix=/usr \
    --libdir=lib/mangohud/lib64 \
    --buildtype=release \
    -Dappend_libdir_mangohud=false \
    -Dwith_xnvctrl=disabled \
    -Dwith_x11=enabled \
    -Dwith_mangohud_next=false \
    -Dwith_server=false \
    -Dmangoapp=true \
    -Dmangohudctl=true
else
  meson setup --reconfigure '${BUILD}' '${BIND}' \
    --prefix=/usr \
    --libdir=lib/mangohud/lib64 \
    --buildtype=release \
    -Dappend_libdir_mangohud=false \
    -Dwith_xnvctrl=disabled \
    -Dwith_x11=enabled \
    -Dwith_mangohud_next=false \
    -Dwith_server=false \
    -Dmangoapp=true \
    -Dmangohudctl=true
fi
ninja -C '${BUILD}' -j${JOBS}
meson install -C '${BUILD}' --no-rebuild
test -x /usr/bin/mangohud
test -f /usr/lib/mangohud/lib64/libMangoHud.so
test -f /usr/share/vulkan/implicit_layer.d/MangoHud.aarch64.json
GLIBC_MAX=\$(objdump -T /usr/lib/mangohud/lib64/libMangoHud.so | sed -n 's/.*GLIBC_\\([0-9.]*\\).*/\\1/p' | sort -V | tail -1)
echo \"libMangoHud GLIBC max: \${GLIBC_MAX}\"
[[ \"\$(printf '%s\\n' '2.39' \"\${GLIBC_MAX}\" | sort -V | head -1)\" == \"\${GLIBC_MAX}\" ]] \
  || { echo \"GLIBC \${GLIBC_MAX} too new for Frame rootfs (max 2.39)\"; exit 1; }
"

# Stale manual copies break the Holo loader (layer → mangohud/lib64, shim in wrong dir).
rm -f "${R}/usr/lib/libMangoHud.so" "${R}/usr/lib/libMangoHud_shim.so" \
      "${R}/usr/lib/libMangoHud_opengl.so" "${R}/usr/lib/libMangoHud-next.so" 2>/dev/null || true
# We build with -Dwith_mangohud_next=false; drop layer JSON pointing at missing .so.
rm -f "${R}/usr/share/vulkan/implicit_layer.d/MangoHud-next.aarch64.json" 2>/dev/null || true

# Gaming / QAM overlay configs (sm8550-mango-config seeds these on first boot).
mkdir -p "${R}/usr/share/steamos-odin/MangoHud/steam"
if [[ -d "${OVL}/usr/share/steamos-odin/MangoHud/steam" ]]; then
  cp -a "${OVL}/usr/share/steamos-odin/MangoHud/steam/." \
    "${R}/usr/share/steamos-odin/MangoHud/steam/"
fi
if [[ -d "${SRC}/MangoHud" ]]; then
  mkdir -p "${R}/etc/skel/.config/MangoHud"
  cp -a "${SRC}/MangoHud/." "${R}/etc/skel/.config/MangoHud/"
fi

if [[ -x "${R}/usr/bin/mangoapp" && ! -e "${R}/usr/bin/mangoapp-steam" ]]; then
  ln -sf mangoapp "${R}/usr/bin/mangoapp-steam"
fi

log "Installed:"
ls -la "${R}/usr/bin/mangohud" "${R}/usr/bin/mangoapp" 2>/dev/null || true
ls -la "${R}/usr/lib/mangohud/lib64/libMangoHud"*.so 2>/dev/null || true
ls -la "${R}/usr/share/vulkan/implicit_layer.d/MangoHud"*.json 2>/dev/null || true
log "Vendor MangoHud + mangoapp OK"
