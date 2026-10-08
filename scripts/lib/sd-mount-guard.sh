# shellcheck shell=bash
# Source from deploy/analyze/fix scripts. Sets WARN if R/H are loop-backed.
sd_mount_guard() {
  local r="$1" h="$2"
  local rs hs
  rs="$(findmnt -n -o SOURCE "$r" 2>/dev/null || true)"
  hs="$(findmnt -n -o SOURCE "$(dirname "$h")" 2>/dev/null || true)"
  if [[ "$rs" == /dev/loop* ]]; then
    local img
    img="$(losetup -n -o 0 "$rs" 2>/dev/null || true)"
    echo "ERROR: ROOT ($r) is loop-mounted ($rs${img:+ → $img})." >&2
    echo "  The Odin boots the physical SD, not a .img open in the file manager." >&2
    echo "  Run: ./scripts/resolve-frame-sd-mounts.sh --check" >&2
    echo "  Then: sudo ./scripts/fix-qam-log-perms-on-sd.sh SD_HOME SD_ROOT" >&2
    return 1
  fi
  if [[ "$hs" == /dev/loop* ]]; then
    echo "ERROR: HOME partition for $h is loop-mounted ($hs)." >&2
    return 1
  fi
  return 0
}
