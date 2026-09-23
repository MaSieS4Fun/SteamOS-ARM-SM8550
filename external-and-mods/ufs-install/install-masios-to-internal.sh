#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# install-masios-to-internal.sh
#
# Install this project's SteamOS SM8550 userspace on internal UFS alongside
# Android (ROCKNIX ABL 1.1.8 dual-boot).
#
# Partition layout (SteamOS 3 Linux partitions + Android userdata):
#   userdata  -> Android (resized, all data erased)
#   ROCKNIX   -> 2 GiB FAT32: KERNEL + KERNEL.md5  (ABL reads this)
#   STORAGE   -> 16 GiB ext4: SteamOS root (system)
#   HOME      -> remaining ext4: /home (Steam, games, user data)
#
# Kernel cmdline on ROCKNIX: root=PARTLABEL=STORAGE
# /home is a separate filesystem (PARTLABEL=HOME), same idea as the microSD image.
#
# Requirements:
#   - Run as root from SteamOS on microSD (not from an existing UFS root)
#   - ROCKNIX ABL installed (1.1.8 or compatible)
#   - /boot/KERNEL with UFS support (root=UUID= + masi.ufsroot=PARTLABEL=STORAGE)
#   - unpack_bootimg + mkbootimg (SteamOS) or abootimg
#
# Usage:
#   sudo ./install-masios-to-internal.sh
#   sudo ./install-masios-to-internal.sh --android-gb 64
#   sudo ./install-masios-to-internal.sh --resume

set -euo pipefail

VERSION="2.0.0"

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# shellcheck source=ufs-bootimg.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ufs-bootimg.sh"

BOOT_SRC="/boot"

# ROCKNIX ABL 1.1.8 reads the ROCKNIX FAT partition (2 GiB, same as installtointernal).
BOOT_PART_MIB=2048
BOOT_PART_GIB=2
# SteamOS root size matches the published image (ROOT_MIB=16384).
ROOT_PART_GIB="${ROOT_PART_GIB:-16}"
ROOT_PART_MIB=$(( ROOT_PART_GIB * 1024 ))
MIN_HOME_GIB="${MIN_HOME_GIB:-16}"
MIN_ANDROID_GIB=16
RECOMMENDED_ANDROID_GIB=64
IO_TIMEOUT_SEC=30
PARTED_TIMEOUT_SEC=120

ROOT_SRC="/"
TMP_BOOT="/tmp/steamos-intboot"
TMP_ROOT="/tmp/steamos-introot"
TMP_HOME="/tmp/steamos-inthome"

DRY_RUN=0
ANDROID_GB=""
FORCE=0
RESUME=0
DEPLOY_ONLY=0

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
HOME_GIB=""
UD_PART_DEV=""
RK_PART_DEV=""
ST_PART_DEV=""
HM_PART_DEV=""
RK_NUM=""
ST_NUM=""
HM_NUM=""

log()  { printf '\033[1;34m[ufs-steamos]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ufs-steamos]\033[0m WARNING: %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ufs-steamos]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }

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
  if [[ "$device" == /dev/mmcblk* || "$device" == /dev/nvme* ]]; then
    echo "${device}p${num}"
  else
    echo "${device}${num}"
  fi
}

part_by_label() {
  local device=$1 label=$2
  lsblk -rn -o NAME,PARTLABEL "$device" | awk -v l="$label" '$2==l {print "/dev/"$1; exit}'
}

linux_reserve_gib() {
  echo $(( BOOT_PART_GIB + ROOT_PART_GIB + MIN_HOME_GIB ))
}

usage() {
  cat <<EOF
SteamOS SM8550 UFS install-to-internal v${VERSION}

Install the running SteamOS system on internal UFS alongside Android.
Creates three Linux partitions (ROCKNIX boot + STORAGE root + HOME).

Options:
  --android-gb N   Android userdata size in GB (skips interactive prompt)
  --dry-run        Simulate without writing to disk
  --force          Skip final confirmation prompt
  --resume         Skip repartitioning; copy onto existing ROCKNIX/STORAGE/HOME
  --deploy-only    Same as --resume
  -h, --help       Show this help

Example:
  sudo $0
  sudo $0 --android-gb 64
  sudo $0 --dry-run --android-gb 64

EOF
}

read_device_model() {
  if [[ -r /proc/device-tree/model ]]; then
    tr -d '\0' < /proc/device-tree/model
    return
  fi
  echo "unknown"
}

detect_soc_family() {
  if [[ -f /sys/firmware/devicetree/base/compatible ]]; then
    if tr '\0' '\n' < /sys/firmware/devicetree/base/compatible | grep -q 'qcom,sm8550'; then
      echo "sm8550"
      return
    fi
  fi
  echo ""
}

detect_ufs_device() {
  local soc dev
  soc=$(detect_soc_family)

  case "$soc" in
    sm8550|SM8550)
      if [[ -b /dev/sda ]] && lsblk -rn -o PARTLABEL /dev/sda 2>/dev/null | grep -qx userdata; then
        echo /dev/sda
        return
      fi
      ;;
  esac

  for dev in /dev/sd? /dev/nvme0n1 /dev/mmcblk?; do
    [[ -b "$dev" ]] || continue
    if timeout 5 lsblk -rn -o PARTLABEL "$dev" 2>/dev/null | grep -qx userdata; then
      echo "$dev"
      return
    fi
  done

  echo ""
}

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

  local min_linux_reserve_gib
  min_linux_reserve_gib=$(linux_reserve_gib)
  MAX_ANDROID_GIB=$(( ORIG_ANDROID_GIB - min_linux_reserve_gib ))
  (( MAX_ANDROID_GIB >= MIN_ANDROID_GIB )) \
    || die "Not enough free space on userdata. Need at least $(( MIN_ANDROID_GIB + min_linux_reserve_gib )) GB total."

  log "userdata: partition #${UD_NUM}, ${ORIG_ANDROID_GIB} GB (${UD_START_MB}-${UD_END_MB} MiB)"
}

check_root() {
  [[ $EUID -eq 0 ]] || die "Run as root: sudo $0"
}

check_boot_files() {
  [[ -f "${BOOT_SRC}/KERNEL" ]] || die "Missing ${BOOT_SRC}/KERNEL on the microSD boot partition."
  local ksize
  ksize=$(stat -c%s "${BOOT_SRC}/KERNEL")
  if (( ksize < 1000000 )); then
    die "${BOOT_SRC}/KERNEL looks too small (${ksize} bytes)"
  fi
  if ! read_bootimg_cmdline "${BOOT_SRC}/KERNEL" 2>/dev/null | grep -qE 'masi\.ufsroot=PARTLABEL=STORAGE|root=PARTLABEL=STORAGE'; then
    die "This /boot/KERNEL has no UFS root target (need masi.ufsroot=PARTLABEL=STORAGE or root=PARTLABEL=STORAGE)."
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

  if [[ "$root_disk" != "$ufs_disk" ]]; then
    log "Source system: /dev/${root_disk}  |  Target UFS: ${DEVICE}"
    return
  fi

  warn "Root filesystem is on ${DEVICE} (same disk as Android UFS)."
  warn "This script is intended to run from microSD BEFORE migrating SteamOS to UFS."
  warn "Continuing may destroy your current Linux installation on internal storage."
  read -rp "Continue anyway? [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."
}

check_existing_install() {
  local device=$1 rk st hm

  log "Checking for existing internal Linux partitions (ROCKNIX, STORAGE, HOME)..."
  rk=$(part_by_label "$device" ROCKNIX || true)
  st=$(part_by_label "$device" STORAGE || true)
  hm=$(part_by_label "$device" HOME || true)

  if [[ -n "$rk" && -n "$st" && -z "$hm" ]]; then
    die "Old two-partition layout found (ROCKNIX + STORAGE, no HOME).
This SteamOS installer needs three Linux partitions.
Use ABL 'Uninstall ROCKNIX', then run a fresh install."
  fi

  if [[ -n "$rk" && -n "$st" && -n "$hm" ]]; then
    if (( RESUME )); then
      warn "Resume mode: using existing ROCKNIX (${rk}), STORAGE (${st}), HOME (${hm})."
      RK_PART_DEV="$rk"
      ST_PART_DEV="$st"
      HM_PART_DEV="$hm"
      RK_NUM="${rk##*[!0-9]}"
      ST_NUM="${st##*[!0-9]}"
      HM_NUM="${hm##*[!0-9]}"
      return 0
    fi
    die "Internal SteamOS partitions already exist (ROCKNIX + STORAGE + HOME).
If a previous install failed partway through, re-run with:
  sudo $0 --resume
Otherwise use ABL 'Uninstall ROCKNIX' before a fresh install.
Note: ABL may leave the HOME partition; delete it if Uninstall does not."
  fi

  if [[ -n "$rk" || -n "$st" || -n "$hm" ]]; then
    die "Partial internal Linux layout (ROCKNIX='${rk:-missing}' STORAGE='${st:-missing}' HOME='${hm:-missing}').
Use ABL 'Uninstall ROCKNIX' (and remove a leftover HOME if needed) before a fresh install."
  fi

  log "No ROCKNIX/STORAGE/HOME partition labels on UFS (OK for first install)."
}

check_dependencies() {
  local dep
  for dep in parted mkfs.vfat mkfs.ext4 rsync findmnt blockdev timeout lsblk; do
    command -v "$dep" >/dev/null 2>&1 || die "Missing dependency: ${dep}"
  done
  have_bootimg_tools || die "Need unpack_bootimg+mkbootimg (SteamOS) or abootimg to pack ROCKNIX KERNEL."
}

wait_blockdev() {
  local dev=$1 i
  for i in $(seq 1 40); do
    [[ -b "$dev" ]] && return 0
    sleep 0.25
    partprobe "$DEVICE" 2>/dev/null || true
  done
  die "Partition ${dev} did not appear after parted."
}

compute_home_size() {
  local new_ud_end_mb st_end_mb
  new_ud_end_mb=$(( UD_START_MB + ANDROID_GB * 1024 ))
  st_end_mb=$(( new_ud_end_mb + BOOT_PART_MIB + ROOT_PART_MIB ))
  HOME_GIB=$(( (DISK_END_MB - st_end_mb + 1023) / 1024 ))
}

show_storage_overview() {
  echo
  echo "================================================================"
  echo "  UFS STORAGE OVERVIEW"
  echo "================================================================"
  echo
  echo "  Device:              $(read_device_model)"
  echo "  Internal UFS:        ${DEVICE}"
  echo "  Total UFS capacity:  ${DISK_TOTAL_GIB} GB"
  echo
  echo "  Your Android userdata partition is currently:"
  echo "    Size:              ${ORIG_ANDROID_GIB} GB  (partition #${UD_NUM}, label: userdata)"
  echo
  echo "  This script will SPLIT that region into four partitions:"
  echo
  echo "    [ Android userdata ]  size YOU choose  (all Android data will be erased)"
  echo "    [ ROCKNIX boot     ]  ${BOOT_PART_GIB} GB fixed   (ABL KERNEL)"
  echo "    [ SteamOS STORAGE  ]  ${ROOT_PART_GIB} GB fixed   (system root)"
  echo "    [ SteamOS HOME     ]  remaining space  (/home — Steam, games)"
  echo
  echo "================================================================"
  echo
}

prompt_android_size() {
  local reserve
  reserve=$(linux_reserve_gib)

  if [[ -n "$ANDROID_GB" ]]; then
    if ! [[ "$ANDROID_GB" =~ ^[0-9]+$ ]]; then
      die "--android-gb must be an integer"
    fi
    if (( ANDROID_GB < MIN_ANDROID_GIB || ANDROID_GB > MAX_ANDROID_GIB )); then
      die "--android-gb=${ANDROID_GB} out of range (${MIN_ANDROID_GIB}-${MAX_ANDROID_GIB})"
    fi
    compute_home_size
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
  echo "  Linux reserve:       ${reserve} GB  (boot ${BOOT_PART_GIB} + root ${ROOT_PART_GIB} + home min ${MIN_HOME_GIB})"
  echo "  Tip: lower Android = more space for SteamOS /home."
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
      echo "  Too large. Maximum is ${MAX_ANDROID_GIB} GB (Linux needs at least ${reserve} GB)."
      continue
    fi
    break
  done

  compute_home_size
}

show_allocation_plan() {
  RK_NUM=$(( UD_NUM + 1 ))
  ST_NUM=$(( UD_NUM + 2 ))
  HM_NUM=$(( UD_NUM + 3 ))
  UD_PART_DEV=$(part_dev "$DEVICE" "$UD_NUM")
  RK_PART_DEV=$(part_dev "$DEVICE" "$RK_NUM")
  ST_PART_DEV=$(part_dev "$DEVICE" "$ST_NUM")
  HM_PART_DEV=$(part_dev "$DEVICE" "$HM_NUM")

  (( HOME_GIB >= MIN_HOME_GIB )) \
    || die "Only ${HOME_GIB} GB left for /home. Minimum is ${MIN_HOME_GIB} GB. Choose a smaller Android size."

  echo
  echo "================================================================"
  echo "  FINAL STORAGE ALLOCATION"
  echo "================================================================"
  echo
  printf "  %-22s %6s GB   %s\n" "Android (userdata):" "${ANDROID_GB}" "${UD_PART_DEV}"
  printf "  %-22s %6s GB   %s  [KERNEL]\n" "Boot (ROCKNIX):" "${BOOT_PART_GIB}" "${RK_PART_DEV}"
  printf "  %-22s %6s GB   %s  [SteamOS root]\n" "System (STORAGE):" "${ROOT_PART_GIB}" "${ST_PART_DEV}"
  printf "  %-22s %6s GB   %s  [/home]\n" "Home (HOME):" "${HOME_GIB}" "${HM_PART_DEV}"
  echo "  ─────────────────────────────────────────────────────────────"
  printf "  %-22s %6s GB\n" "Total allocated:" "$(( ANDROID_GB + BOOT_PART_GIB + ROOT_PART_GIB + HOME_GIB ))"
  echo
  echo "  WARNING: All Android data on userdata will be permanently erased."
  echo "           Android will start fresh (like a factory reset)."
  echo
  echo "================================================================"
  echo
}

confirm_destructive() {
  (( FORCE )) && return 0
  echo
  echo "================================================================"
  echo "  FINAL CONFIRMATION — AT YOUR OWN RISK"
  echo "================================================================"
  echo "  This operation can PERMANENTLY DESTROY data on internal UFS."
  echo "  Android userdata will be wiped. Linux on SD is not backed up"
  echo "  automatically. Android OR Linux (or BOTH) may fail to boot."
  echo "  You accept full responsibility. No warranty. No support guarantee."
  echo "================================================================"
  echo
  if (( RESUME )); then
    read -rp "Copy boot+root+home to existing ROCKNIX/STORAGE/HOME (no repartition)? [y/N]: " ans
  else
    read -rp "I understand the risks. Proceed with install? [y/N]: " ans
  fi
  [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted by user."
}

show_risk_disclaimer() {
  cat <<'EOF'

================================================================
  RISK WARNING — READ BEFORE CONTINUING
================================================================

  This tool REPARTITIONS the internal UFS storage on your device.

  YOU MAY LOSE DATA, INCLUDING:
    - All Android apps, photos, saves, and settings (userdata wipe)
    - Any files already on internal storage
    - The ability to boot Android, Linux, or BOTH if something fails

  REQUIREMENTS:
    - ROCKNIX ABL bootloader already installed (1.1.8 or compatible)
    - SteamOS SM8550 running from microSD
    - A tested /boot/KERNEL with UFS support
    - Supported board: AYN Odin 2 family (SM8550)

  THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY.
  YOU USE IT ENTIRELY AT YOUR OWN RISK.

================================================================

EOF
}

partition_ufs() {
  local new_ud_end_mb rk_start_mb rk_end_mb st_end_mb

  new_ud_end_mb=$(( UD_START_MB + ANDROID_GB * 1024 ))
  rk_start_mb=$new_ud_end_mb
  rk_end_mb=$(( rk_start_mb + BOOT_PART_MIB ))
  st_end_mb=$(( rk_end_mb + ROOT_PART_MIB ))

  log "Repartitioning ${DEVICE} (userdata + ROCKNIX + STORAGE + HOME)..."

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

  run_parted -a optimal mkpart primary ext4 "${rk_end_mb}MiB" "${st_end_mb}MiB"
  run_parted name "$ST_NUM" STORAGE

  run_parted -a optimal mkpart primary ext4 "${st_end_mb}MiB" 100%
  run_parted name "$HM_NUM" HOME

  if (( ! DRY_RUN )); then
    partprobe "$DEVICE" 2>/dev/null || true
    sleep 2
    wait_blockdev "$RK_PART_DEV"
    wait_blockdev "$ST_PART_DEV"
    wait_blockdev "$HM_PART_DEV"
  fi

  if (( DRY_RUN )); then
    log "[dry-run] mkfs.vfat -F 32 -S 4096 -s 4 -n ROCKNIX ${RK_PART_DEV}"
    log "[dry-run] mkfs.ext4 -L STORAGE ${ST_PART_DEV}"
    log "[dry-run] mkfs.ext4 -L home ${HM_PART_DEV}"
    return
  fi

  mkfs.vfat -F 32 -S 4096 -s 4 -n ROCKNIX "$RK_PART_DEV"
  run mkfs.ext4 -F -q -L STORAGE -T ext4 -O ^orphan_file -m 1 "$ST_PART_DEV"
  run mkfs.ext4 -F -q -L home -T ext4 -O ^orphan_file -m 0 "$HM_PART_DEV"
}

mount_target_partitions() {
  if (( DRY_RUN )); then
    log "[dry-run] mount ${RK_PART_DEV} -> ${TMP_BOOT}"
    log "[dry-run] mount ${ST_PART_DEV} -> ${TMP_ROOT}"
    log "[dry-run] mount ${HM_PART_DEV} -> ${TMP_HOME}"
    return
  fi
  mkdir -p "$TMP_BOOT" "$TMP_ROOT" "$TMP_HOME"
  for dev in "$RK_PART_DEV" "$ST_PART_DEV" "$HM_PART_DEV"; do
    if mount | awk '{print $1}' | grep -qx "$dev"; then
      umount "$dev"
    fi
  done
  mount "$RK_PART_DEV" "$TMP_BOOT"
  mount "$ST_PART_DEV" "$TMP_ROOT"
  mount "$HM_PART_DEV" "$TMP_HOME"
}

copy_boot() {
  if (( DRY_RUN )); then
    log "[dry-run] pack ${BOOT_SRC}/KERNEL → ROCKNIX/KERNEL (root=PARTLABEL=STORAGE)"
    return
  fi
  log "Installing KERNEL on ROCKNIX with root=PARTLABEL=STORAGE (UFS-safe)..."
  install_kernel_for_ufs_rocknix "${BOOT_SRC}/KERNEL" "${TMP_BOOT}/KERNEL" \
    || die "Failed to pack UFS KERNEL (need unpack_bootimg+mkbootimg or abootimg)"
  md5sum "${TMP_BOOT}/KERNEL" | awk '{print $1}' > "${TMP_BOOT}/KERNEL.md5"
  [[ -f "${TMP_BOOT}/KERNEL" ]] || die "KERNEL was not written to ROCKNIX partition"
  verify_ufs_rocknix_kernel_cmdline "${TMP_BOOT}/KERNEL" \
    || die "Verify failed: ROCKNIX KERNEL must use root=PARTLABEL=STORAGE (not SD root=UUID=)"
  log "ROCKNIX KERNEL: $(describe_kernel_root "${TMP_BOOT}/KERNEL")"
  sync
}

copy_rootfs() {
  log "Copying SteamOS root to STORAGE (excludes /home and /boot)..."
  if (( DRY_RUN )); then
    log "[dry-run] rsync ${ROOT_SRC} -> ${TMP_ROOT}"
    return
  fi
  rsync -aAXH --info=progress2 \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/boot/*","/home/*"} \
    "${ROOT_SRC}/" "${TMP_ROOT}/"
  mkdir -p "${TMP_ROOT}/boot" "${TMP_ROOT}/home" \
    "${TMP_ROOT}/dev" "${TMP_ROOT}/proc" "${TMP_ROOT}/sys" \
    "${TMP_ROOT}/tmp" "${TMP_ROOT}/run"
  sync
}

copy_home() {
  log "Copying /home to HOME partition..."
  if (( DRY_RUN )); then
    log "[dry-run] rsync ${ROOT_SRC}/home/ -> ${TMP_HOME}/"
    return
  fi
  if [[ -d "${ROOT_SRC}/home" ]]; then
    rsync -aAXH --info=progress2 \
      --exclude={"/lost+found"} \
      "${ROOT_SRC}/home/" "${TMP_HOME}/"
  fi
  mkdir -p "${TMP_HOME}/steamos"
  if id steamos >/dev/null 2>&1; then
    chown -R steamos:steamos "${TMP_HOME}/steamos" || true
  elif [[ -d "${TMP_HOME}/steamos" ]]; then
    chown -R 1000:1000 "${TMP_HOME}/steamos" || true
  fi
  sync
}

write_fstab() {
  log "Writing /etc/fstab for internal UFS (STORAGE + ROCKNIX + HOME)..."
  if (( DRY_RUN )); then
    log "[dry-run] write fstab on STORAGE (+ overlay upper if present)"
    return
  fi
  write_ufs_fstab_tree "$TMP_ROOT"
  sync
}

verify_install() {
  if (( DRY_RUN )); then
    return
  fi
  log "Verifying installation before reboot..."
  [[ -f "${TMP_BOOT}/KERNEL" ]] || die "Verify failed: no KERNEL on ROCKNIX partition"
  verify_ufs_rocknix_kernel_cmdline "${TMP_BOOT}/KERNEL" \
    || die "Verify failed: ROCKNIX KERNEL cmdline is not UFS-safe (need root=PARTLABEL=STORAGE, no root=UUID=)"
  [[ -d "${TMP_ROOT}/etc" ]] || die "Verify failed: STORAGE rootfs looks empty"
  [[ -f "${TMP_ROOT}/sbin/init" || -e "${TMP_ROOT}/sbin/init" || -L "${TMP_ROOT}/sbin/init" ]] \
    || die "Verify failed: STORAGE missing /sbin/init (rootfs copy incomplete?)"
  [[ -f "${TMP_ROOT}/etc/fstab" ]] || die "Verify failed: missing /etc/fstab on STORAGE"
  grep -q 'PARTLABEL=STORAGE' "${TMP_ROOT}/etc/fstab" \
    || die "Verify failed: fstab does not reference PARTLABEL=STORAGE"
  grep -q 'PARTLABEL=HOME' "${TMP_ROOT}/etc/fstab" \
    || die "Verify failed: fstab does not reference PARTLABEL=HOME"
  [[ -d "${TMP_HOME}/steamos" ]] || die "Verify failed: HOME missing /home/steamos"
  log "Verification passed (KERNEL + STORAGE + HOME + fstab OK)."
}

cleanup_mounts() {
  if (( DRY_RUN )); then
    return
  fi
  umount "$TMP_BOOT" 2>/dev/null || true
  umount "$TMP_ROOT" 2>/dev/null || true
  umount "$TMP_HOME" 2>/dev/null || true
  rmdir "$TMP_BOOT" "$TMP_ROOT" "$TMP_HOME" 2>/dev/null || true
}

print_summary() {
  local ud_sz rk_sz st_sz hm_sz
  rk_sz=$(get_gb "$RK_PART_DEV")
  st_sz=$(get_gb "$ST_PART_DEV")
  hm_sz=$(get_gb "$HM_PART_DEV")
  ud_sz=""
  [[ -n "${UD_PART_DEV:-}" ]] && ud_sz=$(get_gb "$UD_PART_DEV")

  echo
  log "Installation complete."
  echo
  echo "  Partitions on ${DEVICE}:"
  if [[ -n "${UD_PART_DEV:-}" ]]; then
    echo "    Android userdata : ${UD_PART_DEV}  (${ud_sz} GB)"
  fi
  echo "    Boot / kernel    : ${RK_PART_DEV}  (${rk_sz} GB)  ROCKNIX"
  echo "    SteamOS system   : ${ST_PART_DEV}  (${st_sz} GB)  STORAGE"
  echo "    SteamOS home     : ${HM_PART_DEV}  (${hm_sz} GB)  HOME"
  echo
  echo "  Boot:"
  echo "    ABL Linux mode, no SD card  ->  SteamOS from UFS"
  echo "    Hold Vol+ while powering on ->  force Android"
  echo "    First Android boot          ->  setup wizard (expected)"
  echo
  if (( DRY_RUN )); then
    warn "Dry-run mode: nothing was written to disk."
  else
    echo "  IMPORTANT:"
    echo "    1. ROCKNIX KERNEL uses root=PARTLABEL=STORAGE (independent of microSD)."
    echo "    2. /home is PARTLABEL=HOME (Steam and games live there)."
    echo "    3. First UFS Linux test: remove microSD, ABL Linux mode, power on."
    echo "    4. Android: recovery -> Factory data reset (userdata was wiped)."
    echo "  If Linux black-screens: sudo ./ufs-diagnose.sh"
    echo "  Quick repair (partitions OK): sudo ./ufs-fix-internal-boot.sh"
  fi
}

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

  show_risk_disclaimer

  (( DEPLOY_ONLY )) && RESUME=1

  log "SteamOS UFS installer v${VERSION}"
  log "Device: $(read_device_model)"

  local soc
  soc=$(detect_soc_family)
  [[ "$soc" == "sm8550" || "$soc" == "SM8550" ]] || die "Unsupported SoC (${soc:-unknown}). SM8550 required."

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
    [[ -n "$HM_PART_DEV" ]] || die "Resume requires ROCKNIX + STORAGE + HOME."
    (( FORCE )) || confirm_destructive
  fi
  mount_target_partitions
  copy_boot
  copy_rootfs
  copy_home
  write_fstab
  verify_install
  cleanup_mounts
  print_summary
}

trap 'cleanup_mounts 2>/dev/null || true' EXIT
main "$@"
