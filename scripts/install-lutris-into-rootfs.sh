#!/usr/bin/env bash
# Install Lutris (and Holo/ALARM dependencies) into a SteamOS Frame rootfs.
# Lutris is not in Holo extra; the package comes from Arch Linux ARM extra.
# Dependencies prefer Holo repos when indexed first (same as install-plasma-extras).
#
# Usage: install-lutris-into-rootfs.sh [rootfs]
#
# Env:
#   SKIP_LUTRIS=1  — no-op (also honored when invoked from install-vendor-apps.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
R="$(cd "$R" && pwd)"

log() { printf '==> [lutris] %s\n' "$*"; }
die() { printf 'ERROR: [lutris] %s\n' "$*" >&2; exit 1; }

[[ "${SKIP_LUTRIS:-0}" == "1" ]] && { log "SKIP_LUTRIS=1"; exit 0; }
[[ -d "$R/usr" ]] || die "missing rootfs $R"
if [[ "${EUID}" -ne 0 && "${ALLOW_NON_ROOT:-0}" != "1" ]]; then
  die "run as root (sudo) — packages install into ${R}/usr"
fi

target_python="$(basename "$(readlink -f "$R/usr/bin/python3" 2>/dev/null || true)")"
target_site="$R/usr/lib/${target_python}/site-packages"

if [[ -x "$R/usr/bin/lutris" && -d "$target_site/lutris" ]] \
  && chroot "$R" /usr/bin/python3 -c 'import lutris, requests' >/dev/null 2>&1; then
  log "already installed: $R/usr/bin/lutris"
  exit 0
fi

# shellcheck source=lib/holo-pkg-install.sh
source "${SCRIPT_DIR}/lib/holo-pkg-install.sh"
wayland_client_target="$(readlink "$R/usr/lib/libwayland-client.so.0" 2>/dev/null || true)"
cleanup() {
  holo_pkg_cleanup
  if [[ -n "$wayland_client_target" && -e "$R/usr/lib/$wayland_client_target" ]]; then
    ln -sfn "$wayland_client_target" "$R/usr/lib/libwayland-client.so.0"
  fi
}
trap cleanup EXIT

holo_pkg_init "$R"
log "index Holo + ALARM package databases"
holo_pkg_index_repos

# Some Frame images retain stale pacman metadata for python-requests after its
# files disappeared. Lutris imports it during startup, so verify/install it
# explicitly instead of trusting the package database.
holo_pkg_install_tree python-requests \
  || die "python-requests dependency install failed"

if holo_pkg_satisfies lutris; then
  log "package files already present; repairing Python integration"
else
  if [[ -z "${HOLO_PKG_URL[lutris]:-}" ]]; then
    die "lutris not found in indexed repos (need network for ALARM extra.db)"
  fi

  log "install lutris + dependencies (may take a few minutes)"
  if ! holo_pkg_install_tree lutris; then
    die "lutris install failed"
  fi
fi

[[ -x "$R/usr/bin/lutris" ]] || die "lutris binary missing after install"

# ALARM's current noarch Lutris package may target a newer Python than the
# SteamOS base. Its Python modules are portable (native curl_cffi uses abi3),
# so merge them into the interpreter actually selected by /usr/bin/python3.
[[ "$target_python" =~ ^python3\.[0-9]+$ ]] \
  || die "cannot determine target Python from $R/usr/bin/python3"
mkdir -p "$target_site"
for foreign_site in "$R"/usr/lib/python3.*/site-packages; do
  [[ -d "$foreign_site" && "$foreign_site" != "$target_site" ]] || continue
  [[ -d "$foreign_site/lutris" ]] || continue
  cp -a "$foreign_site/." "$target_site/"
done

chroot "$R" /usr/bin/python3 -c 'import lutris, requests' \
  || die "Lutris Python module is not usable by ${target_python}"
log "done: $R/usr/bin/lutris"
