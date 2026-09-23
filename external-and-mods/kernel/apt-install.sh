#!/usr/bin/env bash
# Apt postinst path: repack KERNEL for this SD UUID, install boot/firmware/modules only.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    exec sudo -- "$0" "$@"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT
export OUTPUT_DIR="${OUTPUT_DIR:-/var/lib/masi/kernel/staging}"
export INSTALL_MINIMAL=1
export UPDATE_BUILD="${UPDATE_BUILD:-/usr/share/masi/kernel-bundles/current}"
mkdir -p "${OUTPUT_DIR}"

# shellcheck source=config/defaults.conf
source "${ROOT}/config/defaults.conf"
# shellcheck source=lib/install.sh
source "${ROOT}/lib/install.sh"

install_system_paths

build="$(readlink -f "${UPDATE_BUILD}")"
[[ -f "${build}/boot/KERNEL" ]] || {
    echo "ERROR: missing ${build}/boot/KERNEL" >&2
    exit 1
}

release="$(install_resolve_release "${build}")" || exit 1
echo "masi-kernel: installing ${release}"
echo "  /boot/KERNEL"
echo "  /usr/lib/firmware/"
echo "  /usr/lib/modules/${release}/"

install_from_build "${build}"

[[ -f "${INSTALL_BOOT_DST}/KERNEL" ]] || {
    echo "ERROR: /boot/KERNEL missing after install" >&2
    exit 1
}

echo "masi-kernel: install complete — reboot to activate (sudo reboot)"
