#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# install-masios-to-internal.sh
#
# Install MaSi-OS (or any Armbian SM8550 image with ROCKNIX ABL) on internal UFS
# alongside Android (dual-boot).
#
# Partition layout (ROCKNIX ABL compatible):
#   userdata  -> Android (resized, all data erased)
#   ROCKNIX   -> 2 GiB FAT32: kernel/boot (KERNEL + KERNEL.md5)
#   STORAGE   -> ext4: full Linux root filesystem
#
# Requirements:
#   - Run as root from MaSi-OS/Armbian on microSD
#   - ROCKNIX ABL installed on the device
#   - /boot/KERNEL (MaSi-OS multidevice ROCKNIX ABL bootimg — same file for SD and UFS)
#   - Qualcomm SM8550 SoC (AYN Odin 2, Thor, Odin 2 Mini/Portal, etc.)
#
# Usage:
#   sudo ./install-masios-to-internal.sh
#   sudo ./install-masios-to-internal.sh --android-gb 64
#   sudo ./install-masios-to-internal.sh --resume

set -euo pipefail

VERSION="1.7.1"

# shellcheck source=ufs-bootimg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ufs-bootimg.sh"

BOOT_SRC="/boot"

# Partition constants (same as ROCKNIX installtointernal)
BOOT_PART_MIB=2048              # ROCKNIX boot partition (fixed)
BOOT_PART_GIB=2
MIN_ANDROID_GIB=16              # mandatory minimum for Android
RECOMMENDED_ANDROID_GIB=64      # suggested for apps, games, media
MIN_LINUX_ROOT_GIB=16           # mandatory minimum for Linux rootfs
IO_TIMEOUT_SEC=30               # timeout for UFS read probes
PARTED_TIMEOUT_SEC=120          # timeout per parted write operation

ROOT_SRC="/"
TMP_BOOT="/tmp/masios-intboot"
TMP_ROOT="/tmp/masios-introot"

DRY_RUN=0
ANDROID_GB=""
FORCE=0
RESUME=0
DEPLOY_ONLY=0

# Set during runtime
DEVICE=""
DISK_NAME=""
UD_NUM=""
UD_START_MB=""
UD_END_MB=""
DISK_END_MB=""
DISK_TOTAL_GIB=""
ORIG_ANDROID_GIB=""
MAX_ANDROID_GIB=""
ANDROID_GIB=""
LINUX_GIB=""
UD_PART_DEV=""
RK_PART_DEV=""
ST_PART_DEV=""
RK_NUM=""
ST_NUM=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { printf '\033[1;34m[ufs-linux]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ufs-linux]\033[0m WARNING: %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ufs-linux]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

run() {
  if (( DRY_RUN )); then
    log "[dry-run] $*"
  else
    log "$*"
    "$@"
  fi
}

run_parted() {
  if (( DRY_RUN )); then
    log "[dry-run] parted ${DEVICE} $*"
    return 0
  fi
  log "parted: $*"
  timeout "$PARTED_TIMEOUT_SEC" parted -s "$DEVICE" "$@" \
    || die "parted timed out or failed after ${PARTED_TIMEOUT_SEC}s: $*"
}

get_gb() {
  local dev=$1 bytes
  if bytes=$(timeout "$IO_TIMEOUT_SEC" blockdev --getsize64 "$dev" 2>/dev/null); then
    echo $(( bytes / 1024**3 ))
  else
    echo "N/A"
  fi
}

part_dev() {
  local device=$1 num=$2
  if [[ "$device" == /dev/mmcblk* ]]; then
    echo "${device}p${num}"
  else
    echo "${device}${num}"
  fi
}

part_by_label() {
  local device=$1 label=$2
  lsblk -rn -o NAME,PARTLABEL "$device" | awk -v l="$label" '$2==l {print "/dev/"$1; exit}'
}

usage() {
  cat <<EOF
MaSi-OS / UFS Linux install-to-internal v${VERSION}

Install the current Linux system on internal UFS alongside Android.

Options:
  --android-gb N   Android userdata size in GB (skips interactive prompt)
  --dry-run        Simulate without writing to disk
  --force          Skip final confirmation prompt
  --resume         Skip repartitioning; copy boot+rootfs onto existing ROCKNIX/STORAGE
  --deploy-only    Same as --resume (partitions exist; copy KERNEL + rootfs only)
                   (use after a failed install that created partitions but did not finish)
  -h, --help       Show this help

Example:
  sudo $0
  sudo $0 --android-gb 64
  sudo $0 --dry-run --android-gb 64

EOF
}

# ---------------------------------------------------------------------------
# Hardware detection
# ---------------------------------------------------------------------------

read_device_model() {
  if [[ -r /proc/device-tree/model ]]; then
    tr -d '\0' < /proc/device-tree/model
    return
  fi
  if [[ -f /etc/armbian-release ]]; then
    awk -F= '/^BOARD_NAME=/{gsub(/"/,"",$2); print $2}' /etc/armbian-release
    return
  fi
  echo "unknown"
}

read_board_id() {
  if [[ -f /etc/armbian-release ]]; then
    awk -F= '/^BOARD=/{print $2}' /etc/armbian-release
    return
  fi
  echo ""
}

detect_soc_family() {
  local family=""
  if [[ -f /etc/armbian-release ]]; then
    family=$(awk -F= '/^BOARDFAMILY=|^LINUXFAMILY=/{print $2; exit}' /etc/armbian-release)
  fi
  if [[ -z "$family" && -f /sys/firmware/devicetree/base/compatible ]]; then
    if tr '\0' '\n' < /sys/firmware/devicetree/base/compatible | grep -q 'qcom,sm8550'; then
      family="sm8550"
    fi
  fi
  echo "$family"
}

detect_ufs_device() {
  local soc dev
  soc=$(detect_soc_family)

  # SM8550 AYN handhelds: Android UFS is almost always /dev/sda
  case "$soc" in
    sm8550|SM8550)
      if [[ -b /dev/sda ]] && lsblk -rn -o PARTLABEL /dev/sda 2>/dev/null | grep -qx userdata; then
        echo /dev/sda
        return
      fi
      ;;
  esac

  # Fallback: any block device with a userdata partition label
  for dev in /dev/sd? /dev/mmcblk?; do
    [[ -b "$dev" ]] || continue
    if timeout 5 lsblk -rn -o PARTLABEL "$dev" 2>/dev/null | grep -qx userdata; then
      echo "$dev"
      return
    fi
  done

  echo ""
}

validate_supported_board() {
  local board="$1"
  case "$board" in
    ayn-odin2|ayn-odin2mini|ayn-odin2portal|ayn-thor|ayn-odin2ex|retroidpocket6)
      return 0
      ;;
    "")
      warn "Could not read BOARD from /etc/armbian-release; continuing with caution."
      return 0
      ;;
    *)
      warn "Board '${board}' is not on the verified MaSi-OS device list."
      warn "Tested: ayn-odin2, ayn-odin2mini, ayn-odin2portal, ayn-thor"
      read -rp "Continue anyway? [y/N]: " ans
      [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted by user."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# UFS access (avoid hanging parted for read-only queries)
# ---------------------------------------------------------------------------

wake_ufs() {
  local disk=$1
  local host power

  log "Waking UFS controller (${disk})..."
  for host in /sys/class/scsi_host/host*/; do
    [[ -d "$host" ]] || continue
    if [[ -w "${host}power/control" ]]; then
      echo on > "${host}power/control" 2>/dev/null || true
    fi
  done
  for power in /sys/block/${disk}/device/power/control \
               /sys/block/${disk}/queue/iosched; do
    [[ -w "$power" ]] || continue
    echo on > "$power" 2>/dev/null || true
  done
}

probe_ufs_access() {
  local device=$1 disk size

  disk=${device##*/}
  DISK_NAME=$disk

  log "Probing UFS access on ${device}..."
  wake_ufs "$disk"

  if ! timeout "$IO_TIMEOUT_SEC" blockdev --getsize64 "$device" >/dev/null 2>&1; then
    die "UFS ${device} is not responding (timed out after ${IO_TIMEOUT_SEC}s).
The internal storage may be asleep or locked by the kernel.
Try: reboot, boot from microSD again, then re-run this script.
If the problem persists, boot Android once and retry."
  fi

  size=$(timeout "$IO_TIMEOUT_SEC" blockdev --getsize64 "$device")
  log "UFS online: ${device} ($(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size} bytes"))"

  if ! timeout "$IO_TIMEOUT_SEC" lsblk -rn -o PARTLABEL "$device" | grep -qx userdata; then
    die "Partition label 'userdata' not found on ${device}."
  fi
  log "Partition label 'userdata' found on ${device}"
}

read_part_field() {
  local part_sysfs=$1 field=$2
  local uevent="${part_sysfs}/uevent"
  [[ -r "$uevent" ]] || return 1
  awk -F= -v k="$field" '$1==k {print $2; exit}' "$uevent"
}

# Read partition table from sysfs (fast, does not hang like parted on some UFS setups)
find_userdata_partition() {
  local device=$1 disk part_sysfs part_name part_num
  local part_start_sect part_size_sect part_label found=0

  disk=${device##*/}
  log "Reading partition table from sysfs (this avoids parted hangs on UFS)..."

  for part_sysfs in "/sys/block/${disk}/${disk}"*; do
    [[ -d "$part_sysfs" ]] || continue
    [[ -r "${part_sysfs}/start" ]] || continue

    part_label=$(read_part_field "$part_sysfs" PARTNAME || true)
    [[ "$part_label" == "userdata" ]] || continue

    part_name=$(basename "$part_sysfs")
    part_num=${part_name#"${disk}"}
    [[ "$part_num" =~ ^[0-9]+$ ]] || die "Could not parse partition number from ${part_name}"
    part_start_sect=$(< "${part_sysfs}/start")
    part_size_sect=$(< "${part_sysfs}/size")

    UD_NUM=$part_num
    UD_START_MB=$(( (part_start_sect * 512 + 1048575) / 1048576 ))
    UD_END_MB=$(( (part_start_sect * 512 + part_size_sect * 512) / 1048576 ))

    found=1
    break
  done

  (( found )) || die "Could not find userdata partition on ${device} via sysfs."

  local disk_size_bytes
  disk_size_bytes=$(timeout "$IO_TIMEOUT_SEC" blockdev --getsize64 "$device")
  DISK_END_MB=$(( disk_size_bytes / 1048576 ))
  DISK_TOTAL_GIB=$(( (DISK_END_MB + 1023) / 1024 ))
  ORIG_ANDROID_GIB=$(( (UD_END_MB - UD_START_MB + 1023) / 1024 ))

  local min_linux_reserve_gib=$(( BOOT_PART_GIB + MIN_LINUX_ROOT_GIB ))
  MAX_ANDROID_GIB=$(( ORIG_ANDROID_GIB - min_linux_reserve_gib ))
  (( MAX_ANDROID_GIB >= MIN_ANDROID_GIB )) || die "Not enough free space on userdata. Need at least $(( MIN_ANDROID_GIB + min_linux_reserve_gib )) GB total."

  log "userdata: partition #${UD_NUM}, ${ORIG_ANDROID_GIB} GB (${UD_START_MB}-${UD_END_MB} MiB)"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

check_root() {
  [[ $EUID -eq 0 ]] || die "Run as root: sudo $0"
}

check_boot_files() {
  [[ -f "${BOOT_SRC}/KERNEL" ]] || die "Missing ${BOOT_SRC}/KERNEL — run MaSi-OS ./make.sh && sudo ./update.sh first"
  local ksize cmdline
  ksize=$(stat -c%s "${BOOT_SRC}/KERNEL")
  if (( ksize < 1000000 )); then
    die "${BOOT_SRC}/KERNEL looks too small (${ksize} bytes)"
  fi
  cmdline="$(read_bootimg_cmdline "${BOOT_SRC}/KERNEL" 2>/dev/null || true)"
  if ! verify_internal_kernel_cmdline "${BOOT_SRC}/KERNEL"; then
    die "Outdated ${BOOT_SRC}/KERNEL (need dual-boot cmdline).
Expected either:
  root=UUID=<microSD> masi.ufsroot=PARTLABEL=STORAGE
or legacy:
  root=PARTLABEL=STORAGE
Got: $(read_bootimg_cmdline "${BOOT_SRC}/KERNEL" 2>/dev/null || echo '(unreadable)')
Rebuild and install on THIS device:
  cd ~/Projects/kernel-new-base   # or MaSi-OS-Kernel-Updater checkout
  ./make.sh && sudo ./update.sh"
  fi
  log "Boot files OK: ${BOOT_SRC}/KERNEL ($(numfmt --to=iec-i --suffix=B "$ksize" 2>/dev/null || echo "${ksize} B"))"
  log "KERNEL root: $(describe_kernel_root "${BOOT_SRC}/KERNEL")"
}

check_running_from_removable() {
  local root_src root_disk ufs_disk

  root_src=$(findmnt -no SOURCE /)
  root_disk=$(lsblk -no PKNAME "$root_src" 2>/dev/null || true)
  ufs_disk=${DEVICE##*/}

  if [[ -z "$root_disk" ]]; then
    warn "Could not determine the block device hosting /."
    return
  fi

  # Correct setup: Linux on microSD (mmcblk*), UFS is a different disk (sda)
  if [[ "$root_disk" != "$ufs_disk" ]]; then
    log "Source system: /dev/${root_disk}  |  Target UFS: ${DEVICE}"
    return
  fi

  # Root is already on the UFS disk — dangerous / usually wrong for first install
  warn "Root filesystem is on ${DEVICE} (same disk as Android UFS)."
  warn "This script is intended to run from microSD BEFORE migrating Linux to UFS."
  warn "Continuing may destroy your current Linux installation on internal storage."
  read -rp "Continue anyway? [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."
}

check_existing_install() {
  local device=$1 label rk st

  log "Checking for existing internal Linux partitions (labels: ROCKNIX, STORAGE)..."
  rk=$(part_by_label "$device" ROCKNIX || true)
  st=$(part_by_label "$device" STORAGE || true)

  if [[ -n "$rk" && -n "$st" ]]; then
    if (( RESUME )); then
      warn "Resume mode: using existing ROCKNIX (${rk}) and STORAGE (${st}) — no repartitioning."
      RK_PART_DEV="$rk"
      ST_PART_DEV="$st"
      RK_NUM="${rk##*[!0-9]}"
      ST_NUM="${st##*[!0-9]}"
      return 0
    fi
    die "Internal Linux partitions already exist (ROCKNIX + STORAGE).
If a previous install failed partway through, re-run with:
  sudo $0 --resume
Otherwise use ABL 'Uninstall ROCKNIX' before a fresh install."
  fi

  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    if [[ "$label" == "ROCKNIX" || "$label" == "STORAGE" ]]; then
      die "Partial internal Linux layout (label '${label}' only).
Re-run with --resume after fixing partitions, or use ABL 'Uninstall ROCKNIX'."
    fi
  done < <(timeout "$IO_TIMEOUT_SEC" lsblk -rn -o PARTLABEL "$device")
  log "No ROCKNIX/STORAGE partition labels on UFS (OK for first install)."
}

check_dependencies() {
  local dep
  for dep in parted mkfs.vfat mkfs.ext4 rsync findmnt blockdev timeout lsblk; do
    command -v "$dep" >/dev/null 2>&1 || die "Missing dependency: ${dep}"
  done
}

# ---------------------------------------------------------------------------
# Storage info & sizing
# ---------------------------------------------------------------------------

compute_linux_size() {
  local new_ud_end_mb rk_end_mb
  new_ud_end_mb=$(( UD_START_MB + ANDROID_GB * 1024 ))
  rk_end_mb=$(( new_ud_end_mb + BOOT_PART_MIB ))
  LINUX_GIB=$(( (DISK_END_MB - rk_end_mb + 1023) / 1024 ))
}

show_storage_overview() {
  echo
  echo "================================================================"
  echo "  UFS STORAGE OVERVIEW"
  echo "================================================================"
  echo
  echo "  Device:              $(read_device_model)"
  echo "  Board:               $(read_board_id)"
  echo "  Internal UFS:        ${DEVICE}"
  echo "  Total UFS capacity:  ${DISK_TOTAL_GIB} GB"
  echo
  echo "  Your Android userdata partition is currently:"
  echo "    Size:              ${ORIG_ANDROID_GIB} GB  (partition #${UD_NUM}, label: userdata)"
  echo
  echo "  This script will SPLIT that region into three partitions:"
  echo
  echo "    [ Android userdata ]  size YOU choose  (all Android data will be erased)"
  echo "    [ ROCKNIX boot     ]  ${BOOT_PART_GIB} GB fixed   (kernel: KERNEL file)"
  echo "    [ Linux STORAGE    ]  remaining space  (full MaSi-OS system)"
  echo
  echo "  You control how much goes to Android."
  echo "    Boot + Linux automatically get everything left over."
  echo
  echo "================================================================"
  echo
}

prompt_android_size() {
  if [[ -n "$ANDROID_GB" ]]; then
    if ! [[ "$ANDROID_GB" =~ ^[0-9]+$ ]]; then
      die "--android-gb must be an integer"
    fi
    if (( ANDROID_GB < MIN_ANDROID_GIB || ANDROID_GB > MAX_ANDROID_GIB )); then
      die "--android-gb=${ANDROID_GB} out of range (${MIN_ANDROID_GIB}-${MAX_ANDROID_GIB})"
    fi
    compute_linux_size
    return
  fi

  echo "----------------------------------------------------------------"
  echo "  ANDROID PARTITION SIZE"
  echo "----------------------------------------------------------------"
  echo
  echo "  How much space do you want to assign to Android?"
  echo
  echo "  Minimum (required):  ${MIN_ANDROID_GIB} GB"
  echo "  Recommended:         ${RECOMMENDED_ANDROID_GIB} GB  (apps, games, media)"
  echo "  Maximum allowed:     ${MAX_ANDROID_GIB} GB"
  echo
  echo "  Tip: lower Android = more space for Linux."
  echo

  while :; do
    read -rp "  Enter Android size in GB [recommended: ${RECOMMENDED_ANDROID_GIB}]: " ANDROID_GB
    if [[ -z "$ANDROID_GB" ]]; then
      ANDROID_GB=$RECOMMENDED_ANDROID_GIB
      log "Using recommended size: ${ANDROID_GB} GB"
    fi
    if ! [[ "$ANDROID_GB" =~ ^[0-9]+$ ]]; then
      echo "  Please enter a whole number."
      continue
    fi
    if (( ANDROID_GB < MIN_ANDROID_GIB )); then
      echo "  Too small. Minimum for Android is ${MIN_ANDROID_GIB} GB."
      continue
    fi
    if (( ANDROID_GB > MAX_ANDROID_GIB )); then
      echo "  Too large. Maximum is ${MAX_ANDROID_GIB} GB (Linux needs at least ${BOOT_PART_GIB} + ${MIN_LINUX_ROOT_GIB} GB)."
      continue
    fi
    break
  done

  compute_linux_size
}

show_allocation_plan() {
  RK_NUM=$(( UD_NUM + 1 ))
  ST_NUM=$(( UD_NUM + 2 ))
  UD_PART_DEV=$(part_dev "$DEVICE" "$UD_NUM")
  RK_PART_DEV=$(part_dev "$DEVICE" "$RK_NUM")
  ST_PART_DEV=$(part_dev "$DEVICE" "$ST_NUM")

  (( LINUX_GIB >= MIN_LINUX_ROOT_GIB )) || die "Only ${LINUX_GIB} GB left for Linux. Minimum is ${MIN_LINUX_ROOT_GIB} GB. Choose a smaller Android size."

  echo
  echo "================================================================"
  echo "  FINAL STORAGE ALLOCATION"
  echo "================================================================"
  echo
  printf "  %-22s %6s GB   %s\n" "Android (userdata):" "${ANDROID_GB}" "${UD_PART_DEV}"
  printf "  %-22s %6s GB   %s  [KERNEL, KERNEL.md5]\n" "Boot (ROCKNIX):" "${BOOT_PART_GIB}" "${RK_PART_DEV}"
  printf "  %-22s %6s GB   %s  [MaSi-OS rootfs]\n" "Linux (STORAGE):" "${LINUX_GIB}" "${ST_PART_DEV}"
  echo "  ─────────────────────────────────────────────────────────────"
  printf "  %-22s %6s GB\n" "Total allocated:" "$(( ANDROID_GB + BOOT_PART_GIB + LINUX_GIB ))"
  echo
  echo "  WARNING: All Android data on userdata will be permanently erased."
  echo "           Android will start fresh (like a factory reset)."
  echo
  echo "================================================================"
  echo
}

confirm_destructive() {
  (( FORCE )) && return 0
  if (( RESUME )); then
    read -rp "Copy boot+rootfs to existing ROCKNIX/STORAGE (no repartition)? [y/N]: " ans
  else
    read -rp "Proceed with partitioning and installation? [y/N]: " ans
  fi
  [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted by user."
}

# ---------------------------------------------------------------------------
# Partitioning (parted only for writes, with timeout)
# ---------------------------------------------------------------------------

partition_ufs() {
  local new_ud_end_mb rk_start_mb rk_end_mb

  new_ud_end_mb=$(( UD_START_MB + ANDROID_GB * 1024 ))
  rk_start_mb=$new_ud_end_mb
  rk_end_mb=$(( rk_start_mb + BOOT_PART_MIB ))

  log "Repartitioning ${DEVICE} (this modifies the GPT table)..."

  run_parted rm "$UD_NUM"
  run_parted -a optimal mkpart primary ext4 "${UD_START_MB}MiB" "${new_ud_end_mb}MiB"
  run_parted name "$UD_NUM" userdata

  if (( ! DRY_RUN )); then
    log "Wiping Android userdata header on ${UD_PART_DEV}..."
    dd if=/dev/zero of="$UD_PART_DEV" bs=1M count=8 status=none
  fi

  run_parted -a optimal mkpart primary fat32 "${rk_start_mb}MiB" "${rk_end_mb}MiB"
  run_parted name "$RK_NUM" ROCKNIX
  run_parted set "$RK_NUM" msftdata on
  run_parted set "$RK_NUM" boot on

  run_parted -a optimal mkpart primary ext4 "${rk_end_mb}MiB" 100%
  run_parted name "$ST_NUM" STORAGE

  if (( ! DRY_RUN )); then
    partprobe "$DEVICE" 2>/dev/null || true
    sleep 2
  fi

  # Match ROCKNIX installtointernal FAT layout (4096-byte clusters)
  if (( DRY_RUN )); then
    log "[dry-run] mkfs.vfat -F 32 -S 4096 -s 4 -n ROCKNIX ${RK_PART_DEV}"
  else
    mkfs.vfat -F 32 -S 4096 -s 4 -n ROCKNIX "$RK_PART_DEV"
  fi
  run mkfs.ext4 -F -q -L STORAGE -T ext4 -O ^orphan_file -m 0 "$ST_PART_DEV"
}

# ---------------------------------------------------------------------------
# System copy
# ---------------------------------------------------------------------------

mount_target_partitions() {
  if (( DRY_RUN )); then
    log "[dry-run] mount ${RK_PART_DEV} -> ${TMP_BOOT}"
    log "[dry-run] mount ${ST_PART_DEV} -> ${TMP_ROOT}"
    return
  fi
  mkdir -p "$TMP_BOOT" "$TMP_ROOT"
  for dev in "$RK_PART_DEV" "$ST_PART_DEV"; do
    if mount | awk '{print $1}' | grep -qx "$dev"; then
      umount "$dev"
    fi
  done
  mount "$RK_PART_DEV" "$TMP_BOOT"
  mount "$ST_PART_DEV" "$TMP_ROOT"
}

copy_boot() {
  if (( DRY_RUN )); then
    log "[dry-run] copy ${BOOT_SRC}/KERNEL → ROCKNIX/KERNEL (same file as microSD)"
    return
  fi
  log "Copying KERNEL to ROCKNIX (same bootimg as microSD — no cmdline patch)..."
  cp -a "${BOOT_SRC}/KERNEL" "${TMP_BOOT}/KERNEL"
  md5sum "${TMP_BOOT}/KERNEL" | awk '{print $1}' > "${TMP_BOOT}/KERNEL.md5"
  [[ -f "${TMP_BOOT}/KERNEL" ]] || die "KERNEL was not written to ROCKNIX partition"
  verify_internal_kernel_cmdline "${TMP_BOOT}/KERNEL" \
    || die "Verify failed: KERNEL not dual-boot capable (need root=UUID + masi.ufsroot=PARTLABEL=STORAGE, or root=PARTLABEL=STORAGE). Run ./make.sh && sudo ./update.sh"
  sync
}

verify_install() {
  if (( DRY_RUN )); then
    return
  fi
  log "Verifying installation before reboot..."
  [[ -f "${TMP_BOOT}/KERNEL" ]] || die "Verify failed: no KERNEL on ROCKNIX partition"
  verify_internal_kernel_cmdline "${TMP_BOOT}/KERNEL" \
    || die "Verify failed: KERNEL cmdline is not dual-boot (need root=UUID + masi.ufsroot, or root=PARTLABEL=STORAGE)"
  [[ -d "${TMP_ROOT}/etc" ]] || die "Verify failed: STORAGE rootfs looks empty"
  [[ -f "${TMP_ROOT}/etc/fstab" ]] || die "Verify failed: missing /etc/fstab on STORAGE"
  grep -q 'PARTLABEL=STORAGE' "${TMP_ROOT}/etc/fstab" \
    || die "Verify failed: fstab does not reference PARTLABEL=STORAGE"
  log "Verification passed (internal KERNEL cmdline + fstab OK)."
}

copy_rootfs() {
  log "Copying Linux rootfs to STORAGE partition (may take 30-90 minutes)..."
  if (( DRY_RUN )); then
    log "[dry-run] rsync ${ROOT_SRC} -> ${TMP_ROOT}"
    return
  fi
  rsync -aAXH --info=progress2 \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/boot/*"} \
    "${ROOT_SRC}/" "${TMP_ROOT}/"
  sync
}

write_fstab() {
  log "Writing /etc/fstab for internal UFS boot..."
  if (( DRY_RUN )); then
    log "[dry-run] write ${TMP_ROOT}/etc/fstab"
    return
  fi
  cat > "${TMP_ROOT}/etc/fstab" <<'EOF'
# Generated by install-masios-to-internal.sh — internal UFS boot
PARTLABEL=STORAGE  /      ext4  defaults,noatime,commit=120,errors=remount-ro  0 1
PARTLABEL=ROCKNIX  /boot  vfat  defaults                                          0 2
tmpfs              /tmp   tmpfs defaults,nosuid                                   0 0
EOF
  sync
}

cleanup_mounts() {
  if (( DRY_RUN )); then
    return
  fi
  umount "$TMP_BOOT" 2>/dev/null || true
  umount "$TMP_ROOT" 2>/dev/null || true
  rmdir "$TMP_BOOT" "$TMP_ROOT" 2>/dev/null || true
}

print_summary() {
  local ud_sz rk_sz st_sz
  rk_sz=$(get_gb "$RK_PART_DEV")
  st_sz=$(get_gb "$ST_PART_DEV")
  ud_sz=""
  [[ -n "${UD_PART_DEV:-}" ]] && ud_sz=$(get_gb "$UD_PART_DEV")

  echo
  log "Installation complete."
  echo
  echo "  Partitions on ${DEVICE}:"
  if [[ -n "${UD_PART_DEV:-}" ]]; then
    echo "    Android userdata : ${UD_PART_DEV}  (${ud_sz} GB)"
  fi
  echo "    Boot / kernel    : ${RK_PART_DEV}  (${rk_sz} GB)"
  echo "    Linux system     : ${ST_PART_DEV}  (${st_sz} GB)"
  echo
  echo "  Boot:"
  echo "    ABL Linux mode, no SD card  ->  MaSi-OS from UFS"
  echo "    Hold Vol+ while powering on ->  force Android"
  echo "    First Android boot          ->  setup wizard (expected)"
  echo
  if (( DRY_RUN )); then
    warn "Dry-run mode: nothing was written to disk."
  else
    echo "  IMPORTANT:"
    echo "    1. Same KERNEL on SD and ROCKNIX (root=PARTLABEL=STORAGE + masi.sdroot)."
    echo "    2. First internal Linux test: remove microSD if boot fails (see docs)."
    echo "    3. Android: boot recovery -> Factory data reset (userdata was wiped)."
    echo "  If Linux black-screens: sudo masi-ufs-diagnose"
    echo "  Quick repair (partitions OK): sudo ufs-fix-internal-boot.sh"
    echo "  Kernel update later: cd Kernel_MaSi-OS && sudo ./update.sh"
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --android-gb) ANDROID_GB="${2:-}"; shift 2 ;;
      --dry-run)    DRY_RUN=1; shift ;;
      --force)      FORCE=1; shift ;;
      --resume)     RESUME=1; shift ;;
      --deploy-only) DEPLOY_ONLY=1; RESUME=1; shift ;;
      -h|--help)    usage; exit 0 ;;
      *) die "Unknown option: $1 (try --help)" ;;
    esac
  done

  check_root
  check_dependencies

  (( DEPLOY_ONLY )) && RESUME=1

  log "UFS Linux installer v${VERSION}"
  log "Device: $(read_device_model)"

  local soc board
  soc=$(detect_soc_family)
  board=$(read_board_id)

  [[ "$soc" == "sm8550" || "$soc" == "SM8550" ]] || die "Unsupported SoC (${soc:-unknown}). SM8550 required."
  validate_supported_board "$board"

  DEVICE=$(detect_ufs_device)
  [[ -n "$DEVICE" ]] || die "Could not find internal UFS with a userdata partition."

  check_boot_files
  check_running_from_removable
  probe_ufs_access "$DEVICE"
  check_existing_install "$DEVICE"
  if (( ! RESUME )); then
    find_userdata_partition "$DEVICE"
    show_storage_overview
    prompt_android_size
    show_allocation_plan
    confirm_destructive
    partition_ufs
  else
    (( FORCE )) || confirm_destructive
  fi
  mount_target_partitions
  copy_boot
  copy_rootfs
  write_fstab
  verify_install
  cleanup_mounts
  print_summary
}

trap 'cleanup_mounts 2>/dev/null || true' EXIT
main "$@"
