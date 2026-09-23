#!/usr/bin/env bash
# Restore SteamOS-stock MangoHud (glibc 2.39) and raise gamescope start timeout.
# Default: mounted SD root. Also updates the extracted rootfs if present.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
OVL="${PROJ}/odin-overlay"
TARGETS=()
if [[ -n "${1:-}" ]]; then
  TARGETS+=("$1")
else
  [[ -d /run/media/steam/root/usr/bin ]] && TARGETS+=(/run/media/steam/root)
  [[ -d ${PROJ}/rootfs/usr/bin ]] && TARGETS+=("${PROJ}/rootfs")
fi
[[ ${#TARGETS[@]} -gt 0 ]] || { echo "no rootfs"; exit 1; }

restore_one() {
  local R="$1"
  local STOCK="${R}/opt/stock-steamos"
  echo "==> restore MangoHud in ${R}"
  for b in mangohud mangoapp mangohudctl; do
    [[ -f "${STOCK}/usr/bin/${b}" ]] || continue
    cp -a "${STOCK}/usr/bin/${b}" "${R}/usr/bin/${b}"
    chmod 0755 "${R}/usr/bin/${b}"
  done
  for lib in libMangoHud.so libMangoHud_opengl.so libMangoHud_shim.so libMangoHud-next.so; do
    [[ -f "${STOCK}/usr/lib/${lib}" ]] || continue
    cp -a "${STOCK}/usr/lib/${lib}" "${R}/usr/lib/${lib}"
    chmod 0755 "${R}/usr/lib/${lib}"
  done
  install -D -m0644 "${OVL}/usr/lib/systemd/user/gamescope-session.service.d/99-odin.conf" \
    "${R}/usr/lib/systemd/user/gamescope-session.service.d/99-odin.conf"
}

for t in "${TARGETS[@]}"; do
  restore_one "$t"
done
echo "OK: stock MangoHud + TimeoutStartSec=45"
