#!/usr/bin/env bash
# Restore Frame Wayland 0.26 SONAME links after a Lutris/ALARM merge.
# Lutris can drop libwayland-*.0.22.0 and retarget cursor/server/egl to 0.22
# while kwin still needs 0.26 — compositor then dies immediately
# (undefined symbol wl_display_set_default_max_buffer_size).
#
# install-lutris-into-rootfs.sh runs this on already-installed Lutris and on EXIT.
# apply-odin-mods.sh runs this again before verify-qam-image-contract.sh.
#
# Usage: sudo ./scripts/restore-wayland-after-lutris.sh <rootfs>
set -euo pipefail

R="${1:?rootfs mount}"
R="$(cd "$R" && pwd)"
LIB="$R/usr/lib"

[[ "${EUID}" -eq 0 ]] || { echo "sudo $0 $R" >&2; exit 1; }
[[ -d "$LIB" ]] || { echo "not a rootfs: $R" >&2; exit 1; }

missing=0
restore() {
  local link="$1" target="$2"
  if [[ ! -e "$LIB/$target" ]]; then
    echo "ERROR: missing $LIB/$target (need Frame Wayland 0.26)" >&2
    missing=1
    return 0
  fi
  ln -sfn "$target" "$LIB/$link"
  echo "OK $link -> $target"
}

restore libwayland-client.so.0 libwayland-client.so.0.26.0
restore libwayland-cursor.so.0 libwayland-cursor.so.0.26.0
restore libwayland-server.so.0 libwayland-server.so.0.26.0
restore libwayland-egl.so.1 libwayland-egl.so.1.26.0

echo "---"
ls -l "$LIB"/libwayland-client.so.0 "$LIB"/libwayland-cursor.so.0 \
  "$LIB"/libwayland-server.so.0 "$LIB"/libwayland-egl.so.1

[[ "$missing" -eq 0 ]] || exit 1
