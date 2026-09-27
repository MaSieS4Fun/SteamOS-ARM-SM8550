#!/usr/bin/env bash
# Build Box64 (SD8G2) inside a SteamOS Frame rootfs for Decky PluginLoader.
#
# Usage: ./scripts/build-box64-sm8550.sh [/path/to/rootfs]
# Env:   BOX64_SRC  JOBS  FORCE_REBUILD=1  SKIP_BOX64_BUILD=1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
JOBS="${JOBS:-$(nproc)}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
BOX64_SRC="${BOX64_SRC:-${ROOT}/external-and-mods/BOX64/box64-src}"
WORK="${BOX64_BUILD:-/tmp/box64-sm8550-build}"
BIND="/tmp/box64-vendor-src"

log() { printf '==> [box64] %s\n' "$*"; }
die() { printf 'ERROR: [box64] %s\n' "$*" >&2; exit 1; }

[[ -d "${R}/usr/lib" ]] || die "Missing rootfs: ${R}"
[[ "${SKIP_BOX64_BUILD:-0}" == "1" ]] && { log "SKIP_BOX64_BUILD=1"; exit 0; }

if [[ -x "${R}/usr/local/bin/box64" && "${FORCE_REBUILD}" != "1" ]]; then
  log "box64 already present in rootfs — skip"
  exit 0
fi

mount_chroot() {
  mountpoint -q "${R}/proc" || mount -t proc proc "${R}/proc"
  mountpoint -q "${R}/dev" || mount --bind /dev "${R}/dev"
  mountpoint -q "${R}/sys" || mount -t sysfs sys "${R}/sys"
}

ensure_source() {
  if [[ -f "${BOX64_SRC}/CMakeLists.txt" ]]; then
    log "Using vendored source ${BOX64_SRC}"
    return 0
  fi
  mkdir -p "${WORK}"
  if [[ ! -d "${WORK}/box64/.git" ]]; then
    log "Cloning box64 from upstream..."
    rm -rf "${WORK}/box64"
    git clone --recursive --depth 1 https://github.com/ptitSeb/box64 "${WORK}/box64"
  fi
  BOX64_SRC="${WORK}/box64"
}

build_in_chroot() {
  mount_chroot
  mkdir -p "${R}${BIND}"
  mountpoint -q "${R}${BIND}" || mount --bind "${BOX64_SRC}" "${R}${BIND}"

  chroot "${R}" bash -c "
set -euo pipefail
for cmd in cmake make gcc g++; do
  command -v \"\$cmd\" >/dev/null || { echo \"missing \$cmd in rootfs\"; exit 1; }
done
gcc_major=\"\$(gcc -dumpversion | cut -d. -f1)\"
if (( gcc_major < 12 )); then
  echo \"GCC 12+ required (found \$gcc_major)\"
  exit 1
fi
build_dir=\"/tmp/box64-build\"
rm -rf \"\$build_dir\"
cmake -S '${BIND}' -B \"\$build_dir\" -DSD8G2=1 -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build \"\$build_dir\" -j${JOBS}
cmake --install \"\$build_dir\"
if [[ -f \"\$build_dir/install_manifest.txt\" ]]; then
  mkdir -p /usr/local/share/box64
  cp -f \"\$build_dir/install_manifest.txt\" /usr/local/share/box64/install_manifest.txt
fi
rm -rf \"\$build_dir\"
"

  if mountpoint -q "${R}${BIND}"; then umount "${R}${BIND}"; fi
}

install_manifest() {
  local manifest="${ROOT}/external-and-mods/BOX64/install_manifest.txt"
  [[ -f "$manifest" ]] || return 0
  mkdir -p "${R}/usr/local/share/box64"
  grep -v 'box64-configurator\.desktop' "$manifest" \
    >"${R}/usr/local/share/box64/install_manifest.txt"
}

ensure_source
build_in_chroot
install_manifest

if [[ -x "${R}/usr/local/bin/box64" ]]; then
  log "OK: $(file -b "${R}/usr/local/bin/box64")"
else
  die "box64 build finished but /usr/local/bin/box64 is missing"
fi
