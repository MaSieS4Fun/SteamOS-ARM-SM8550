#!/usr/bin/env bash
# Overlay Kernel-ODIN3 (SM8750 ABL) onto a SteamOS rootfs.
# Does not compile the kernel. Installs modules/firmware + ALSA UCM.
# ABL KERNEL is packed onto the FAT BOOT partition at image time.
#
#   sudo ./scripts/apply-odin3-kernel.sh /path/to/rootfs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
KSRC="${ROOT}/external-and-mods/Kernel-ODIN3"
KOUT="${KOUT:-${KSRC}/output/7.1.4-edge-sm8750}"
RELEASE="${ODIN3_KERNEL_RELEASE:-7.1.4-edge-sm8750}"

log() { printf '==> [odin3-kernel] %s\n' "$*"; }
die() { printf 'ERROR: [odin3-kernel] %s\n' "$*" >&2; exit 1; }

[[ -d "${R}/usr" ]] || die "not a rootfs: ${R}"
[[ -f "${KOUT}/boot/KERNEL" ]] || die "missing ${KOUT}/boot/KERNEL"
[[ -d "${KOUT}/ucm/AYN/Odin3" ]] || die "missing UCM ${KOUT}/ucm/AYN/Odin3"

if [[ -d "${KOUT}/modules/${RELEASE}" ]]; then
  MODS="${KOUT}/modules/${RELEASE}"
else
  MODS="$(find "${KOUT}/modules" -mindepth 1 -maxdepth 1 -type d | head -1 || true)"
  [[ -n "${MODS}" ]] || die "no modules under ${KOUT}/modules"
  RELEASE="$(basename "${MODS}")"
fi

log "rootfs=${R}"
log "build=${KOUT} release=${RELEASE}"

log "modules → ${R}/usr/lib/modules/${RELEASE}/"
mkdir -p "${R}/usr/lib/modules"
rm -rf "${R}/usr/lib/modules/${RELEASE}"
cp -a "${MODS}" "${R}/usr/lib/modules/${RELEASE}"

if [[ -d "${KOUT}/firmware" ]]; then
  log "firmware → ${R}/usr/lib/firmware/ (merge, SM8750 + ath12k WCN7860)"
  mkdir -p "${R}/usr/lib/firmware"
  cp -a "${KOUT}/firmware/." "${R}/usr/lib/firmware/"
fi
# WCN7850 (Odin 2) always uses the 7.0.14 blobs. Harmless extra files on Odin 3.
if [[ -x "${SCRIPT_DIR}/install-ath12k-wcn7850-7014.sh" ]]; then
  "${SCRIPT_DIR}/install-ath12k-wcn7850-7014.sh" "${R}"
fi

log "ALSA UCM AYN/Odin3 → ${R}/usr/share/alsa/ucm2/"
mkdir -p "${R}/usr/share/alsa/ucm2/AYN" "${R}/usr/share/alsa/ucm2/conf.d/sm8750"
rm -rf "${R}/usr/share/alsa/ucm2/AYN/Odin3"
cp -a "${KOUT}/ucm/AYN/Odin3" "${R}/usr/share/alsa/ucm2/AYN/"
if [[ -d "${KOUT}/ucm/conf.d/sm8750" ]]; then
  cp -a "${KOUT}/ucm/conf.d/sm8750/." "${R}/usr/share/alsa/ucm2/conf.d/sm8750/"
fi
ln -sfn ../../AYN/Odin3/AYN-Odin3.conf \
  "${R}/usr/share/alsa/ucm2/conf.d/sm8750/SM8750-AYN.conf"
ln -sfn ../../AYN/Odin3/AYN-Odin3.conf \
  "${R}/usr/share/alsa/ucm2/conf.d/sm8750/ayn-AYNOdin3-.conf"
ln -sfn ../../AYN/Odin3/AYN-Odin3.conf \
  "${R}/usr/share/alsa/ucm2/conf.d/sm8750/SM8750AYN.conf"
chown -R root:root "${R}/usr/share/alsa/ucm2/AYN/Odin3" \
  "${R}/usr/share/alsa/ucm2/conf.d/sm8750" 2>/dev/null || true
find "${R}/usr/share/alsa/ucm2/AYN/Odin3" -type d -exec chmod 0755 {} +
find "${R}/usr/share/alsa/ucm2/AYN/Odin3" -type f -exec chmod 0644 {} +

if [[ -x "${KSRC}/scripts/enable-odin3-audio.sh" ]]; then
  install -D -m0755 "${KSRC}/scripts/enable-odin3-audio.sh" \
    "${R}/usr/lib/steamos/enable-odin3-audio"
fi
if [[ -x "${KSRC}/scripts/verify-devices.sh" ]]; then
  install -D -m0755 "${KSRC}/scripts/verify-devices.sh" \
    "${R}/usr/share/steamos-odin/odin3-verify-devices.sh"
fi

mkdir -p "${R}/usr/share/steamos-odin" "${R}/opt/masi-kernel-odin3"
cat > "${R}/usr/share/steamos-odin/odin3-preview.txt" <<TXT
preview=sm8750-odin3
boot=ABL KERNEL (not EFI/GRUB)
kernel=${RELEASE}
audio=UCM AYN/Odin3 (speakers / headphones)
hdmi_dp=not working
mesa=mesa-sm8750 Turnip A830 (patch SM8750 only; not mesa-sm8550)
input=rsinput + InputPlumber deck-uhid (AYN Odin 3)
TXT

for item in update.sh README.md LICENSE CREDITS.md; do
  [[ -e "${KSRC}/${item}" ]] && cp -a "${KSRC}/${item}" "${R}/opt/masi-kernel-odin3/"
done
chmod 0755 "${R}/opt/masi-kernel-odin3/update.sh" 2>/dev/null || true

mkdir -p "${R}/boot"
# ABL reads KERNEL from the FAT BOOT partition at pack time.
# Keep a copy on rootfs for diagnostics / UFS helpers.
install -D -m0644 "${KOUT}/boot/KERNEL" "${R}/boot/KERNEL"

log "OK: ${RELEASE} + UCM AYN/Odin3"
