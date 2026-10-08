#!/usr/bin/env bash
# Pin WCN7850 Wi-Fi firmware from 7.0.14-edge-sm8550 (Nov 2025 HMT.1.0.c5).
# The later 2.2M Armbian board-2 lists 5 GHz on 7.2.8 but flaps; this set
# scans and associates stably.
#
# Usage:
#   sudo ./scripts/install-ath12k-wcn7850-7014.sh /path/to/rootfs
#   sudo ./scripts/install-ath12k-wcn7850-7014.sh --firmware-root /usr/lib/firmware
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${ROOT}/external-and-mods/firmware/ath12k/WCN7850/hw2.0"

log() { printf '==> [wcn7850-7014] %s\n' "$*"; }
die() { printf 'ERROR: [wcn7850-7014] %s\n' "$*" >&2; exit 1; }

want_md5() {
  case "$1" in
    amss.bin) echo d3750b67b1013fe82358d0538fb131b0 ;;
    board-2.bin) echo c561004dff34720e8d388191830050e4 ;;
    m3.bin) echo 73056f1d2aff886ce9bff313f455e963 ;;
    regdb.bin) echo e84783a5bcd720fa2634dd5f4192b046 ;;
    *) return 1 ;;
  esac
}

resolve_fw_root() {
  if [[ "${1:-}" == "--firmware-root" ]]; then
    [[ -n "${2:-}" ]] || die "missing path after --firmware-root"
    printf '%s\n' "$2"
    return 0
  fi
  local r="${1:-}"
  [[ -n "$r" ]] || die "usage: $0 <rootfs> | --firmware-root <dir>"
  if [[ -d "$r/usr/lib/firmware" || -d "$r/usr" ]]; then
    printf '%s\n' "$r/usr/lib/firmware"
    return 0
  fi
  die "not a rootfs: $r"
}

[[ -f "${SRC}/amss.bin" && -f "${SRC}/board-2.bin" ]] \
  || die "missing pin tree ${SRC}"

for f in amss.bin board-2.bin m3.bin regdb.bin; do
  have="$(md5sum "${SRC}/${f}" | awk '{print $1}')"
  want="$(want_md5 "$f")"
  [[ "$have" == "$want" ]] || die "${SRC}/${f} md5 ${have} != ${want}"
done

FW="$(resolve_fw_root "${1:-}" "${2:-}")"
DEST="${FW}/ath12k/WCN7850/hw2.0"
rm -rf "${DEST}"
mkdir -p "${DEST}"
cp -a "${SRC}/." "${DEST}/"
chmod -R a+rX "${DEST}"

if [[ "${FW}" == */usr/lib/firmware ]]; then
  marker="$(dirname "$(dirname "${FW}")")/share/steamos-odin/ath12k-wcn7850-7014.txt"
  mkdir -p "$(dirname "${marker}")"
  {
    date -Iseconds
    echo "source=external-and-mods/firmware/ath12k/WCN7850 (7.0.14-edge-sm8550 HMT.1.0.c5)"
    echo "note=WLAN.HMT.1.0.c5-00481; 5 GHz stable on 7.2.8 (not the 2.2M Armbian board-2)"
    md5sum "${DEST}/amss.bin" "${DEST}/board-2.bin" "${DEST}/m3.bin" "${DEST}/regdb.bin"
  } > "${marker}"
fi

log "WCN7850 ← HMT.1.0.c5-00481 (${DEST})"
md5sum "${DEST}/amss.bin" "${DEST}/board-2.bin"
