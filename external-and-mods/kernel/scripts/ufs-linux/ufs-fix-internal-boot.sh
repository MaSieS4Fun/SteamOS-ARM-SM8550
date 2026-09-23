#!/usr/bin/env bash
# Repair MaSi-OS / ROCKNIX internal boot on UFS (run as root from microSD).
set -euo pipefail

VERSION="1.3.0"

# shellcheck source=ufs-bootimg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ufs-bootimg.sh"
INTERNAL_CMDLINE="$UFS_INTERNAL_CMDLINE"

FIX_KERNEL=1
FIX_FSTAB=1
DRY_RUN=0
FORCE=0

log()  { printf '\033[1;34m[ufs-fix]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ufs-fix]\033[0m WARNING: %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ufs-fix]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
ufs-fix-internal-boot v${VERSION}

Repair MaSi-OS / ROCKNIX internal boot (copy KERNEL + optional fstab).
Copies /boot/KERNEL to ROCKNIX — same file as microSD (no cmdline patch on current builds).

Options:
  --kernel-only   Copy KERNEL to ROCKNIX partition only
  --fstab-only    Fix /etc/fstab on STORAGE only
  --dry-run       Show actions without writing
  --force         Skip confirmation
  -h, --help      Show help

EOF
}

detect_ufs_device() {
  local dev
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

detect_layout() {
  local device=$1
  HAS_ROCKNIX=0 HAS_STORAGE=0 HAS_ALT_BOOT=0 HAS_ALT_ROOT=0

  [[ -n $(part_by_label "$device" ROCKNIX || true) ]] && HAS_ROCKNIX=1
  [[ -n $(part_by_label "$device" STORAGE || true) ]] && HAS_STORAGE=1
  [[ -n $(part_by_label "$device" "$(printf '\x41\x52\x4d\x41\x44\x41_BOOT')" || true) ]] && HAS_ALT_BOOT=1
  [[ -n $(part_by_label "$device" "$(printf '\x41\x52\x4d\x41\x44\x41_ROOT')" || true) ]] && HAS_ALT_ROOT=1

  if (( HAS_ALT_BOOT || HAS_ALT_ROOT )); then
    echo "alt3"
  elif (( HAS_ROCKNIX && HAS_STORAGE )); then
    echo "masios-rocknix"
  elif (( HAS_ROCKNIX && ! HAS_STORAGE )); then
    echo "partial"
  else
    echo "none"
  fi
}

root_on_same_disk() {
  local device=$1 src pk
  src=$(findmnt -no SOURCE /)
  pk=$(lsblk -no PKNAME "$src" 2>/dev/null || true)
  [[ -n "$pk" && "/dev/${pk}" == "$device" ]]
}

patch_kernel() {
  local rk_dev=$1 tmp=$2
  if (( DRY_RUN )); then
    log "[dry-run] copy /boot/KERNEL → ROCKNIX/KERNEL"
    return
  fi
  if read_bootimg_cmdline /boot/KERNEL 2>/dev/null | grep -qE 'masi\.ufsroot=PARTLABEL=STORAGE|root=PARTLABEL=STORAGE'; then
    log "Copying /boot/KERNEL to ROCKNIX (same file as microSD)..."
    cp -a /boot/KERNEL "${tmp}/KERNEL"
  else
    log "Legacy KERNEL — patching cmdline (needs abootimg)..."
    command -v abootimg >/dev/null || die "Install abootimg: sudo apt install abootimg"
    patch_kernel_for_internal_boot /boot/KERNEL "${tmp}/KERNEL" "$INTERNAL_CMDLINE" \
      || die "abootimg failed"
  fi
  md5sum "${tmp}/KERNEL" | awk '{print $1}' > "${tmp}/KERNEL.md5"
  verify_internal_kernel_cmdline "${tmp}/KERNEL" \
    || die "KERNEL cmdline still wrong after repair"
}

fix_fstab_on_storage() {
  local st_dev=$1 tmp=$2
  if (( DRY_RUN )); then
    log "[dry-run] write internal fstab on ${st_dev}"
    return
  fi
  log "Fixing /etc/fstab on ${st_dev}..."
  mkdir -p "${tmp}/etc"
  cat > "${tmp}/etc/fstab" <<'EOF'
# Repaired by ufs-fix-internal-boot.sh
PARTLABEL=STORAGE  /      ext4  defaults,noatime,commit=120,errors=remount-ro  0 1
PARTLABEL=ROCKNIX  /boot  vfat  defaults                                          0 2
tmpfs              /tmp   tmpfs defaults,nosuid                                   0 0
EOF
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kernel-only) FIX_FSTAB=0; shift ;;
      --fstab-only)  FIX_KERNEL=0; shift ;;
      --dry-run)     DRY_RUN=1; shift ;;
      --force)       FORCE=1; shift ;;
      -h|--help)     usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  [[ $EUID -eq 0 ]] || die "Run as root: sudo $0"
  [[ -f /boot/KERNEL ]] || die "Missing /boot/KERNEL on SD (boot MaSi-OS from microSD first)"

  DEVICE=$(detect_ufs_device)
  [[ -n "$DEVICE" ]] || die "No UFS with userdata partition found."

  if root_on_same_disk "$DEVICE"; then
    die "You are booted from ${DEVICE}. Boot from microSD before running this fix."
  fi

  LAYOUT=$(detect_layout "$DEVICE")
  RK_DEV=$(part_by_label "$DEVICE" ROCKNIX || true)
  ST_DEV=$(part_by_label "$DEVICE" STORAGE || true)

  log "UFS device: ${DEVICE}"
  log "Layout:     ${LAYOUT}"

  case "$LAYOUT" in
    alt3)
      die "3-partition vendor layout detected. Use the image installer instead."
      ;;
    partial)
      die "Partial install: ROCKNIX exists but STORAGE is missing.
Re-run: sudo ./install-masios-to-internal.sh --deploy-only"
      ;;
    none)
      die "No MaSi-OS / ROCKNIX internal partitions found."
      ;;
  esac

  echo
  echo "This fix will copy /boot/KERNEL to ROCKNIX/KERNEL (same file as microSD)."
  echo

  if (( ! FORCE && ! DRY_RUN )); then
    read -rp "Proceed? [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."
  fi

  TMP_BOOT=$(mktemp -d /tmp/ufs-fix-boot.XXXXXX)
  TMP_ROOT=$(mktemp -d /tmp/ufs-fix-root.XXXXXX)
  trap 'umount "$TMP_BOOT" 2>/dev/null; umount "$TMP_ROOT" 2>/dev/null; rmdir "$TMP_BOOT" "$TMP_ROOT" 2>/dev/null' EXIT

  if (( FIX_KERNEL )); then
    mount "$RK_DEV" "$TMP_BOOT"
    patch_kernel "$RK_DEV" "$TMP_BOOT"
    sync
    umount "$TMP_BOOT"
    log "KERNEL fixed on ${RK_DEV}"
  fi

  if (( FIX_FSTAB )); then
    if mount "$ST_DEV" "$TMP_ROOT" 2>/dev/null; then
      fix_fstab_on_storage "$ST_DEV" "$TMP_ROOT"
      sync
      umount "$TMP_ROOT"
      log "fstab fixed on ${ST_DEV}"
    else
      warn "Could not mount ${ST_DEV}; skipped fstab repair"
    fi
  fi

  echo
  log "Done. Reboot with ABL in Linux mode (keep SD inserted for first test)."
}

main "$@"
