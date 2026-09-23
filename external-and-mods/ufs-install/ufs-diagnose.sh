#!/usr/bin/env bash
# UFS / dual-boot diagnostic (run as root from SteamOS on microSD)
set -euo pipefail

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# shellcheck source=ufs-bootimg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ufs-bootimg.sh"

log()  { printf '\033[1;34m[ufs-diagnose]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ufs-diagnose]\033[0m %s\n' "$*" >&2; }

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }

detect_ufs_device() {
  local dev
  for dev in /dev/sd? /dev/nvme0n1 /dev/mmcblk?; do
    [[ -b "$dev" ]] || continue
    if lsblk -rn -o PARTLABEL "$dev" 2>/dev/null | grep -qx userdata; then
      echo "$dev"
      return
    fi
  done
  echo ""
}

part_by_label() {
  local device=$1 label=$2
  lsblk -rn -o NAME,PARTLABEL "$device" | awk -v l="$label" '$2==l {print "/dev/"$1; exit}'
}

DEVICE=$(detect_ufs_device)
LAYOUT="unknown"

echo "================================================================"
echo "  UFS / DUAL-BOOT DIAGNOSTIC"
echo "================================================================"
echo

log "Device: $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
log "Root:   $(findmnt -no SOURCE /)  ($(findmnt -no FSTYPE /))"

if [[ -z "$DEVICE" ]]; then
  warn "Could not find internal UFS with a userdata partition."
  exit 1
fi

log "Internal UFS: ${DEVICE}"

echo
echo "--- Partition table ---"
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$DEVICE"

RK=$(part_by_label "$DEVICE" ROCKNIX || true)
ST=$(part_by_label "$DEVICE" STORAGE || true)
HM=$(part_by_label "$DEVICE" HOME || true)
UD=$(part_by_label "$DEVICE" userdata || true)

if [[ -n "$RK" && -n "$ST" && -n "$HM" ]]; then
  LAYOUT="steamos-3part"
elif [[ -n "$RK" && -n "$ST" ]]; then
  LAYOUT="old-2part"
elif [[ -n "$RK" && -z "$ST" ]]; then
  LAYOUT="incompatible-or-partial"
elif [[ -z "$RK" && -z "$ST" ]]; then
  LAYOUT="android-only"
else
  LAYOUT="mixed-or-unknown"
fi

echo
echo "--- Detected layout: ${LAYOUT} ---"
case "$LAYOUT" in
  steamos-3part)
    echo "  SteamOS / ROCKNIX ABL (3 Linux partitions):"
    echo "    ROCKNIX  = boot / KERNEL  (${RK})"
    echo "    STORAGE  = SteamOS root   (${ST})"
    echo "    HOME     = /home          (${HM})"
    ;;
  old-2part)
    echo "  Old MaSi-OS / ROCKNIX style (2 Linux partitions, no HOME):"
    echo "    ROCKNIX  = boot / KERNEL  (${RK})"
    echo "    STORAGE  = Linux rootfs  (${ST})"
    echo "  This SteamOS installer will not reuse that layout. Uninstall ROCKNIX first."
    ;;
  incompatible-or-partial)
    echo "  ROCKNIX present but STORAGE/HOME missing, or layout is incomplete."
    echo "    ROCKNIX  = boot / KERNEL  (${RK:-missing})"
    echo "    STORAGE  = SteamOS root   (${ST:-missing})"
    echo "    HOME     = /home          (${HM:-missing})"
    ;;
  android-only)
    echo "  No internal Linux partitions. Android-only or after factory reset."
    ;;
  *)
    warn "Unusual partition mix. Manual inspection recommended."
    ;;
esac

echo
echo "--- SD boot KERNEL (reference) ---"
if [[ -f /boot/KERNEL ]]; then
  file /boot/KERNEL
  echo "SD /boot/KERNEL: $(describe_kernel_root /boot/KERNEL)"
else
  warn "/boot/KERNEL not found on SD"
fi

if [[ -n "$RK" && -b "$RK" ]]; then
  echo
  echo "--- Internal ROCKNIX partition (${RK}) ---"
  mkdir -p /tmp/rkdiag
  if mount "$RK" /tmp/rkdiag 2>/dev/null; then
    ls -la /tmp/rkdiag/
    if [[ -f /tmp/rkdiag/KERNEL ]]; then
      echo "Internal KERNEL root target: $(describe_kernel_root /tmp/rkdiag/KERNEL)"
      if verify_ufs_rocknix_kernel_cmdline /tmp/rkdiag/KERNEL 2>/dev/null; then
        log "Internal KERNEL cmdline OK for UFS boot (root=PARTLABEL=STORAGE)"
      elif verify_internal_kernel_cmdline /tmp/rkdiag/KERNEL 2>/dev/null; then
        warn "Internal KERNEL still has SD root=UUID= — UFS boot may black-screen without SD"
        warn "Fix: sudo ./ufs-fix-internal-boot.sh --kernel-only"
      else
        warn "Internal KERNEL cmdline wrong — Linux will not boot from UFS"
        warn "Fix: sudo ./ufs-fix-internal-boot.sh --kernel-only"
      fi
    else
      warn "NO KERNEL on ROCKNIX partition (Linux will black-screen)"
    fi
    umount /tmp/rkdiag
  else
    warn "Could not mount ${RK}"
  fi
fi

if [[ -n "$ST" && -b "$ST" ]]; then
  echo
  echo "--- Internal STORAGE partition (${ST}) ---"
  mkdir -p /tmp/stdiag
  if mount "$ST" /tmp/stdiag 2>/dev/null; then
    df -h /tmp/stdiag
    [[ -f /tmp/stdiag/etc/fstab ]] && { echo "fstab:"; cat /tmp/stdiag/etc/fstab; }
    umount /tmp/stdiag
  else
    warn "Could not mount ${ST} (empty or corrupt?)"
  fi
fi

if [[ -n "$HM" && -b "$HM" ]]; then
  echo
  echo "--- Internal HOME partition (${HM}) ---"
  mkdir -p /tmp/hmdiag
  if mount "$HM" /tmp/hmdiag 2>/dev/null; then
    df -h /tmp/hmdiag
    ls -la /tmp/hmdiag | head
    [[ -d /tmp/hmdiag/steamos ]] || warn "HOME is missing /home/steamos"
    umount /tmp/hmdiag
  else
    warn "Could not mount ${HM} (empty or corrupt?)"
  fi
fi

if [[ -n "$UD" ]]; then
  echo
  log "Android userdata: ${UD} ($(lsblk -rn -o SIZE "$UD"))"
fi

echo
echo "================================================================"
echo "  WHAT TO DO"
echo "================================================================"
case "$LAYOUT" in
  steamos-3part)
    echo "  Fresh tutorial:     sudo ./install-masios-to-internal.sh"
    echo "  Failed mid-install: sudo ./install-masios-to-internal.sh --resume"
    echo "  Boot/cmdline fix:   sudo ./ufs-fix-internal-boot.sh"
    echo "  Android recovery:   Factory data reset (userdata was wiped on install)"
    ;;
  old-2part)
    echo "  Expected layout:    ROCKNIX + STORAGE + HOME"
    echo "  This device has:    ROCKNIX + STORAGE only"
    echo "  Action:             ABL 'Uninstall ROCKNIX', then fresh SteamOS UFS install"
    ;;
  incompatible-or-partial|mixed-or-unknown)
    echo "  Expected layout:    ROCKNIX + STORAGE + HOME"
    echo "  Partial install:    sudo ./install-masios-to-internal.sh --deploy-only"
    echo "  Other layouts:      ABL 'Uninstall ROCKNIX' (remove leftover HOME if needed)"
    echo "  Boot/cmdline fix:   only if ROCKNIX + STORAGE + HOME already exist"
    ;;
  android-only)
    echo "  Ready for fresh install: sudo ./install-masios-to-internal.sh"
    ;;
esac
echo
echo "  Restore full Android userdata size (expand partition):"
echo "    NOT done by ufs-fix-internal-boot.sh"
echo "    Use ABL 'Uninstall ROCKNIX' OR EDL flash"
echo "    ABL Uninstall may leave HOME; delete that partition if it remains."
echo "================================================================"
