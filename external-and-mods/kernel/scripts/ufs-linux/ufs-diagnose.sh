#!/usr/bin/env bash
# UFS / dual-boot diagnostic (run as root from MaSi-OS on microSD)
set -euo pipefail

# shellcheck source=ufs-bootimg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ufs-bootimg.sh"

log()  { printf '\033[1;34m[ufs-diagnose]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ufs-diagnose]\033[0m %s\n' "$*" >&2; }

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }

detect_ufs_device() {
  local dev label
  for dev in /dev/sd? /dev/mmcblk?; do
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
# On-disk GPT names of the 3-partition vendor layout (must match the image)
AB=$(part_by_label "$DEVICE" "$(printf '\x41\x52\x4d\x41\x44\x41_BOOT')" || true)
AR=$(part_by_label "$DEVICE" "$(printf '\x41\x52\x4d\x41\x44\x41_ROOT')" || true)
UD=$(part_by_label "$DEVICE" userdata || true)

if [[ -n "$RK" && -n "$ST" && -z "$AB" && -z "$AR" ]]; then
  LAYOUT="masios-rocknix"
elif [[ -n "$RK" && -n "$AB" && -n "$AR" ]]; then
  LAYOUT="alt3"
elif [[ -n "$RK" && -z "$ST" && -z "$AR" ]]; then
  LAYOUT="partial-boot-only"
elif [[ -z "$RK" && -z "$ST" && -z "$AB" && -z "$AR" ]]; then
  LAYOUT="android-only"
else
  LAYOUT="mixed-or-unknown"
fi

echo
echo "--- Detected layout: ${LAYOUT} ---"
case "$LAYOUT" in
  masios-rocknix)
    echo "  MaSi-OS / ROCKNIX style (2 Linux partitions):"
    echo "    ROCKNIX  = boot / KERNEL  (${RK})"
    echo "    STORAGE  = Linux rootfs  (${ST})"
    ;;
  alt3)
    echo "  3-partition vendor style (3 Linux partitions):"
    echo "    ROCKNIX     = ESP / ABL reads KERNEL  (${RK})"
    echo "    BOOT = /boot (ext4)             (${AB})"
    echo "    ROOT = root (btrfs)             (${AR})"
    echo "  MaSi-OS fix scripts do NOT apply to that 3-partition root layout."
    ;;
  partial-boot-only)
    warn "Only ROCKNIX exists; STORAGE/alt-root missing (partial/failed install)."
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
      if verify_internal_kernel_cmdline /tmp/rkdiag/KERNEL 2>/dev/null; then
        log "Internal KERNEL cmdline OK for UFS boot"
      else
        warn "Internal KERNEL still points at microSD UUID or wrong root — Linux will not boot from UFS"
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

if [[ -n "$AR" && -b "$AR" ]]; then
  echo
  echo "--- Internal alt-root partition (${AR}) ---"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID "$AR"
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
  masios-rocknix)
    echo "  Fresh tutorial:     sudo ./install-masios-to-internal.sh"
    echo "  Failed mid-install: sudo ./install-masios-to-internal.sh --resume"
    echo "  Boot/cmdline fix:   sudo ./ufs-fix-internal-boot.sh"
    echo "  Android recovery:   Factory data reset (userdata was wiped on install)"
    ;;
  alt3)
    echo "  This is a 3-partition vendor layout. Do not use MaSi-OS UFS fix scripts."
    echo "  Use that image's own installer/reset tools, or EDL flash."
    ;;
  partial-boot-only|mixed-or-unknown)
    echo "  Partial install:    re-run install OR ABL 'Uninstall ROCKNIX'"
    echo "                      OR that image's own installer reset / EDL flash"
    ;;
  android-only)
    echo "  Ready for fresh install: sudo ./install-masios-to-internal.sh"
    ;;
esac
echo
echo "  Restore full Android userdata size (expand partition):"
echo "    NOT done by ufs-fix-internal-boot.sh"
echo "    Use ABL 'Uninstall ROCKNIX' OR that image's installer reset OR EDL flash"
echo "================================================================"
