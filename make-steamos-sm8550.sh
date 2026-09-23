#!/usr/bin/env bash
# Build a flashable SteamOS SM8550 image:
#   p1 vfat BOOT  — ABL KERNEL
#   p2 ext4 root  — system
#   p3 ext4 home  — user data, grown to the end of the card on first boot
#
# Layout matches SteamOS PC/handheld (root + home), not Steam Deck A/B.
# ABL cannot use EFI, so p1 is FAT with KERNEL instead of an ESP.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${ROOT}/scripts"
R="${ROOT}/rootfs"
MOD="${ROOT}/external-and-mods"
OVL="${ROOT}/odin-overlay"
KOUT="${MOD}/kernel/output/7.0.14-edge-sm8550"
BOX64_SRC="${MOD}/BOX64/box64"
BOX64_BUILD="${BOX64_SRC}/build"
IMG="${STEAMOS_SM8550_IMG:-${ROOT}/steamos-sm8550.img}"
MNT="${ROOT}/.image-mnt"
LOOPDEV=""

BOOT_MIB="${BOOT_MIB:-512}"
# Empty ROOT_MIB / HOME_MIB → pack-time size. Home grows to the card on first boot.
AUTO_ROOT=0
if [[ -z "${ROOT_MIB:-}" ]]; then
  AUTO_ROOT=1
  ROOT_MIB=16384
fi
AUTO_HOME=0
if [[ -z "${HOME_MIB:-}" ]]; then
  AUTO_HOME=1
  HOME_MIB=1024
fi

SKIP_DOWNLOAD=0
SKIP_APPLY=0
SKIP_BOX64=0
IMAGE_ONLY=0

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

sudo_run() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
    return
  fi
  if sudo -n true 2>/dev/null; then
    sudo "$@"
    return
  fi
  printf 'steam\n' | sudo -S -p '' "$@"
}

usage() {
  cat <<EOF
Usage: $0 [options]

  --skip-download   Reuse existing official rootfs/ chunks
  --skip-apply      Do not re-run scripts/apply-odin-mods.sh
  --skip-box64      Do not rebuild Box64
  --image-only      Only pack the .img from the current rootfs
  --img PATH        Output image (default: ${IMG})

Env: BOOT_MIB ROOT_MIB HOME_MIB STEAMOS_SM8550_IMG
     empty ROOT_MIB/HOME_MIB = auto (tight pack; home grows on first boot)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-download) SKIP_DOWNLOAD=1 ;;
    --skip-apply) SKIP_APPLY=1 ;;
    --skip-box64) SKIP_BOX64=1 ;;
    --image-only) IMAGE_ONLY=1; SKIP_DOWNLOAD=1; SKIP_APPLY=1; SKIP_BOX64=1 ;;
    --img) IMG="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

ensure_official_rootfs() {
  if [[ -x "${R}/usr/bin/bash" ]]; then
    log "Official rootfs already extracted"
    return 0
  fi
  [[ "$SKIP_DOWNLOAD" -eq 1 ]] && die "rootfs missing and --skip-download set"
  [[ -x "${SCRIPTS}/extract_rootfs.py" ]] || die "missing scripts/extract_rootfs.py"
  log "Assembling official rootfs.img from casync chunks"
  python3 "${SCRIPTS}/extract_rootfs.py"
  die "extract produced rootfs.img — unpack it to ${R} before re-running (btrfs restore)"
}

apply_mods() {
  [[ "$SKIP_APPLY" -eq 1 ]] && { log "Skipping apply-odin-mods"; return 0; }
  [[ -x "${SCRIPTS}/apply-odin-mods.sh" ]] || die "missing scripts/apply-odin-mods.sh"
  log "Applying kernel / gamescope / MangoHud / Mesa / Decky / apps"
  "${SCRIPTS}/apply-odin-mods.sh"
}

build_box64() {
  if [[ -x "${R}/usr/local/bin/box64" ]] \
      && ! strings "${R}/usr/local/bin/box64" | grep -q 'GLIBC_2\.43'; then
    log "Box64 already in rootfs (Frame glibc) — skip rebuild"
    return 0
  fi
  if [[ "$SKIP_BOX64" -eq 1 ]]; then
    die "Box64 missing or needs GLIBC_2.43, and --skip-box64 is set"
  fi
  if [[ ! -d "${BOX64_SRC}/.git" && ! -f "${BOX64_SRC}/CMakeLists.txt" ]]; then
    log "Cloning ptitSeb/box64"
    git clone --recursive --depth 1 https://github.com/ptitSeb/box64 "${BOX64_SRC}"
  fi
  log "Building Box64 inside Frame rootfs (glibc 2.39, SD8G2)"
  "${SCRIPTS}/build-box64-in-rootfs.sh" "${R}"
}

install_box64_rootfs() {
  [[ -x "${BOX64_BUILD}/box64" ]] || die "box64 binary missing — build first"
  log "Installing Box64 into rootfs (no menu / no updater)"
  DESTDIR="${R}" cmake --install "${BOX64_BUILD}"
  rm -f "${R}/usr/local/share/applications/box64-configurator.desktop"
  rm -f "${R}/usr/local/bin/box64-configurator"
  rmdir "${R}/usr/local/share/applications" 2>/dev/null || true
  ln -sfn /usr/local/bin/box64 "${R}/usr/bin/box64"
  if [[ -f "${R}/etc/binfmt.d/box64.conf" ]]; then
    mkdir -p "${R}/usr/lib/binfmt.d"
    cp -a "${R}/etc/binfmt.d/box64.conf" "${R}/usr/lib/binfmt.d/box64.conf"
  fi
}

prepare_runtime() {
  log "Installing SM8550 runtime (fstab template, expand-home, growpart, pad)"
  install -D -m0755 "${OVL}/usr/lib/steamos/steamos-sm8550-expand-home" \
    "${R}/usr/lib/steamos/steamos-sm8550-expand-home"
  install -D -m0644 "${OVL}/usr/lib/systemd/system/steamos-sm8550-expand-home.service" \
    "${R}/usr/lib/systemd/system/steamos-sm8550-expand-home.service"
  mkdir -p "${R}/etc/systemd/system/multi-user.target.wants" \
    "${R}/etc/systemd/system/local-fs.target.wants" \
    "${R}/usr/lib/systemd/system/multi-user.target.wants" \
    "${R}/usr/lib/systemd/system/local-fs.target.wants"
  ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
    "${R}/etc/systemd/system/multi-user.target.wants/steamos-sm8550-expand-home.service"
  ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
    "${R}/etc/systemd/system/local-fs.target.wants/steamos-sm8550-expand-home.service"
  ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
    "${R}/usr/lib/systemd/system/multi-user.target.wants/steamos-sm8550-expand-home.service"
  ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
    "${R}/usr/lib/systemd/system/local-fs.target.wants/steamos-sm8550-expand-home.service"
  if [[ -x /usr/bin/growpart ]]; then
    install -D -m0755 /usr/bin/growpart "${R}/usr/bin/growpart"
  fi
  install -D -m0755 "${OVL}/usr/lib/steamos/sm8550-fixpad" \
    "${R}/usr/lib/steamos/sm8550-fixpad"
  install -D -m0644 "${OVL}/usr/lib/systemd/system/sm8550-fixpad.service" \
    "${R}/usr/lib/systemd/system/sm8550-fixpad.service"
  ln -sfn /usr/lib/systemd/system/sm8550-fixpad.service \
    "${R}/etc/systemd/system/multi-user.target.wants/sm8550-fixpad.service"
  install -D -m0644 "${OVL}/usr/lib/udev/rules.d/70-sm8550-gamepad.rules" \
    "${R}/usr/lib/udev/rules.d/70-sm8550-gamepad.rules"
  install -D -m0644 "${OVL}/usr/lib/udev/rules.d/70-sm8550-gamepad.rules" \
    "${R}/lib/udev/rules.d/70-sm8550-gamepad.rules"
  install -D -m0644 "${OVL}/etc/sdl2/qcom-gamecontrollerdb.txt" \
    "${R}/etc/sdl2/qcom-gamecontrollerdb.txt"
  install -D -m0644 "${OVL}/usr/lib/environment.d/60-sm8550-gamepad.conf" \
    "${R}/usr/lib/environment.d/60-sm8550-gamepad.conf"
  install -D -m0644 "${OVL}/etc/profile.d/sm8550-gamepad.sh" \
    "${R}/etc/profile.d/sm8550-gamepad.sh"
  install -D -m0755 "${OVL}/usr/lib/steamos/gamescope-session" \
    "${R}/usr/lib/steamos/gamescope-session"
  install -D -m0644 "${OVL}/home-steamos/LEEME-ODIN.txt" \
    "${R}/home/steamos/LEEME-ODIN.txt"
  install -D -m0644 "${OVL}/home-steamos/README-ODIN.txt" \
    "${R}/home/steamos/README-ODIN.txt"
  install -D -m0644 "${OVL}/etc/systemd/journald.conf.d/99-sm8550-persist.conf" \
    "${R}/etc/systemd/journald.conf.d/99-sm8550-persist.conf"
  mkdir -p "${R}/var/log/journal" \
    "${R}/etc/systemd/system/graphical.target.wants"
  rm -f "${R}/usr/lib/steamos/sm8550-hide-console" \
        "${R}/usr/lib/systemd/system/sm8550-hide-console.service" \
        "${R}/lib/systemd/system/sm8550-hide-console.service" \
        "${R}/etc/systemd/system/graphical.target.wants/sm8550-hide-console.service" \
        "${R}/etc/systemd/system/sysinit.target.wants/sm8550-hide-console.service" \
        "${R}/etc/systemd/system/multi-user.target.wants/sm8550-hide-console.service" \
        "${R}/usr/lib/systemd/system/graphical.target.wants/sm8550-hide-console.service" \
        "${R}/usr/lib/systemd/system/sysinit.target.wants/sm8550-hide-console.service" \
        "${R}/usr/lib/systemd/system/multi-user.target.wants/sm8550-hide-console.service" \
        "${R}/etc/systemd/system/multi-user.target.wants/sm8550-boot-debug.service" \
        "${R}/etc/systemd/system/graphical.target.wants/sm8550-boot-debug-late.service"
  "${SCRIPTS}/install-inputplumber-sm8550.sh" "${R}"

  # pkexec/sudo lose setuid when the rootfs is copied as a normal user.
  # Keep the boot oneshot even for --image-only.
  if [[ -x "${OVL}/usr/lib/steamos/sm8550-restore-privs" ]]; then
    install -D -m0755 "${OVL}/usr/lib/steamos/sm8550-restore-privs" \
      "${R}/usr/lib/steamos/sm8550-restore-privs"
    install -D -m0644 "${OVL}/usr/lib/systemd/system/sm8550-restore-privs.service" \
      "${R}/usr/lib/systemd/system/sm8550-restore-privs.service"
    mkdir -p "${R}/etc/systemd/system/multi-user.target.wants"
    ln -sfn /usr/lib/systemd/system/sm8550-restore-privs.service \
      "${R}/etc/systemd/system/multi-user.target.wants/sm8550-restore-privs.service"
    if [[ -d "${R}/var/lib/overlays/etc/upper" ]]; then
      mkdir -p "${R}/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants"
      ln -sfn /usr/lib/systemd/system/sm8550-restore-privs.service \
        "${R}/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/sm8550-restore-privs.service" \
        || true
    fi
  fi
  if [[ -x "${OVL}/usr/bin/steamos-set-root-password" ]]; then
    install -D -m0755 "${OVL}/usr/bin/steamos-set-root-password" \
      "${R}/usr/bin/steamos-set-root-password"
  fi
}

repack_kernel_uuid() {
  local src="$1" dest="$2" uuid="$3"
  local cmdline
  # shellcheck source=external-and-mods/kernel/lib/cmdline.sh
  source "${MOD}/kernel/lib/cmdline.sh"
  cmdline="$(build_unified_abl_cmdline "${uuid}")"
  # Patch ANDROID! cmdline in place so the DTB chain / padding stays intact.
  python3 - "${src}" "${dest}" "${cmdline}" <<'PY'
import sys
from pathlib import Path
src, dest, cmdline = sys.argv[1], sys.argv[2], sys.argv[3]
data = bytearray(Path(src).read_bytes())
if data[:8] != b"ANDROID!":
    raise SystemExit("not an ANDROID bootimg")
cmd = cmdline.encode("ascii")
if len(cmd) >= 512:
    raise SystemExit(f"cmdline too long ({len(cmd)})")
data[0x40:0x40 + 512] = cmd.ljust(512, b"\x00")
Path(dest).write_bytes(data)
print(cmdline)
PY
  log "KERNEL cmdline: ${cmdline}"
}

restore_image_suid() {
  local dest="$1" p
  [[ -d "${dest}/usr/bin" ]] || return 0
  log "Restoring setuid root on pkexec/sudo in the image"
  for p in \
    usr/bin/pkexec usr/sbin/pkexec usr/bin/sudo usr/sbin/sudo \
    usr/lib/polkit-1/polkit-agent-helper-1 \
    usr/bin/su usr/bin/passwd usr/bin/newgrp usr/bin/chsh usr/bin/chfn \
    usr/bin/gpasswd usr/bin/unix_chkpwd usr/bin/mount usr/bin/umount
  do
    [[ -e "${dest}/${p}" ]] || continue
    sudo_run chown root:root "${dest}/${p}"
    sudo_run chmod 4755 "${dest}/${p}"
  done
  if [[ -e "${dest}/usr/lib/dbus-1.0/dbus-daemon-launch-helper" ]]; then
    sudo_run chown root:root "${dest}/usr/lib/dbus-1.0/dbus-daemon-launch-helper"
    sudo_run chmod 4750 "${dest}/usr/lib/dbus-1.0/dbus-daemon-launch-helper"
  fi
}

wait_loop_parts() {
  local dev="$1" i
  for i in $(seq 1 50); do
    [[ -b "${dev}p1" && -b "${dev}p2" && -b "${dev}p3" ]] && return 0
    sleep 0.1
  done
  die "loop partitions did not appear on ${dev}"
}

cleanup_image() {
  sync || true
  sudo_run umount "${MNT}/boot" 2>/dev/null || true
  sudo_run umount "${MNT}/home" 2>/dev/null || true
  sudo_run umount "${MNT}/root" 2>/dev/null || true
  if [[ -n "${LOOPDEV:-}" ]]; then
    sudo_run losetup -d "${LOOPDEV}" 2>/dev/null || true
    LOOPDEV=""
  fi
}

detach_img_loops() {
  local dev
  sudo_run umount "${MNT}/boot" 2>/dev/null || true
  sudo_run umount "${MNT}/home" 2>/dev/null || true
  sudo_run umount "${MNT}/root" 2>/dev/null || true
  while read -r dev; do
    [[ -n "${dev}" ]] || continue
    sudo_run losetup -d "${dev}" 2>/dev/null || true
  done < <(losetup -j "${IMG}" -O NAME -n 2>/dev/null || true)
}

build_image() {
  local total_mib root_uuid home_uuid
  local boot_dev root_dev home_dev
  command -v sfdisk >/dev/null || die "sfdisk missing"
  command -v mkfs.vfat >/dev/null || die "mkfs.vfat missing"
  command -v mkfs.ext4 >/dev/null || die "mkfs.ext4 missing"
  command -v uuidgen >/dev/null || die "uuidgen missing"
  [[ -x "${R}/usr/bin/bash" ]] || die "rootfs not ready"
  [[ -f "${KOUT}/boot/KERNEL" ]] || die "missing ${KOUT}/boot/KERNEL"

  if [[ "${AUTO_ROOT}" -eq 1 ]]; then
    local used_mib
    used_mib="$(du -sm \
      --exclude=home --exclude=boot --exclude=proc --exclude=sys \
      --exclude=dev --exclude=tmp --exclude=run --exclude='.image-mnt' \
      "${R}" | awk '{print $1}')"
    # ~500 MiB free after 1% reserved blocks + a little slack for first boot.
    # 1.5 GiB free at pack: 500 MiB filled on first boot last time (root 100%).
    ROOT_MIB=$((used_mib + 1536 + used_mib / 100 + 128))
    log "root auto-size ${ROOT_MIB} MiB (rootfs ${used_mib} MiB, ~1.5 GiB free)"
  fi
  if [[ "${AUTO_HOME}" -eq 1 ]]; then
    local home_mib
    home_mib="$(du -sm "${R}/home" 2>/dev/null | awk '{print $1}')"
    home_mib="${home_mib:-1}"
    HOME_MIB=$((home_mib + 256 + home_mib / 100 + 32))
    log "home auto-size ${HOME_MIB} MiB (payload ${home_mib} MiB; grows on first boot)"
  fi

  total_mib=$((BOOT_MIB + ROOT_MIB + HOME_MIB + 2))
  root_uuid="$(uuidgen)"
  home_uuid="$(uuidgen)"

  log "Creating ${IMG} (${total_mib} MiB sparse)"
  log "  p1 BOOT ${BOOT_MIB}M vfat"
  log "  p2 root ${ROOT_MIB}M ext4 UUID=${root_uuid}"
  log "  p3 home ${HOME_MIB}M ext4 UUID=${home_uuid} (grows on first boot)"

  detach_img_loops
  rm -f "${IMG}"
  truncate -s "${total_mib}M" "${IMG}"

  # util-linux 2.41+ sfdisk dump format only accepts unit: sectors (not MiB).
  # 1 MiB = 2048 × 512-byte sectors. Layout is unchanged: 1MiB gap, BOOT, root, home.
  sfdisk "${IMG}" <<EOF
label: dos
unit: sectors

start=2048, size=$((BOOT_MIB * 2048)), type=c, bootable
size=$((ROOT_MIB * 2048)), type=83
type=83
EOF

  LOOPDEV="$(sudo_run losetup -f --show -P "${IMG}")"
  [[ -n "${LOOPDEV}" ]] || die "losetup failed"
  log "loop ${LOOPDEV}"
  wait_loop_parts "${LOOPDEV}"
  boot_dev="${LOOPDEV}p1"
  root_dev="${LOOPDEV}p2"
  home_dev="${LOOPDEV}p3"

  trap cleanup_image EXIT

  sudo_run mkfs.vfat -F 32 -n BOOT "${boot_dev}"
  sudo_run mkfs.ext4 -F -L root -U "${root_uuid}" -m 1 "${root_dev}"
  sudo_run mkfs.ext4 -F -L home -U "${home_uuid}" -m 1 "${home_dev}"

  mkdir -p "${MNT}/boot" "${MNT}/root" "${MNT}/home"
  sudo_run mount "${root_dev}" "${MNT}/root"
  sudo_run mount "${home_dev}" "${MNT}/home"
  sudo_run mount "${boot_dev}" "${MNT}/boot"

  log "Copying root filesystem"
  sudo_run rsync -aHAX --numeric-ids --info=progress2 \
    --exclude='/home/**' \
    --exclude='/boot/**' \
    --exclude='/dev/**' \
    --exclude='/proc/**' \
    --exclude='/sys/**' \
    --exclude='/tmp/**' \
    --exclude='/run/**' \
    "${R}/" "${MNT}/root/"

  sudo_run mkdir -p "${MNT}/root/boot" "${MNT}/root/home" \
    "${MNT}/root/dev" "${MNT}/root/proc" "${MNT}/root/sys" \
    "${MNT}/root/tmp" "${MNT}/root/run"

  # rsync as root can copy steam:steam binaries; restore setuid now so
  # Decky / MESA / UFS ask for the user password on first boot.
  restore_image_suid "${MNT}/root"

  # Workspace /usr/bin copies can stay root-owned and stale; the image
  # must ship the 3-partition SteamOS UFS installer from this project.
  log "Installing SteamOS UFS installer (ROCKNIX + STORAGE + HOME)"
  sudo_run mkdir -p "${MNT}/root/usr/share/easy-ufs-install"
  sudo_run cp -a "${MOD}/ufs-install/." "${MNT}/root/usr/share/easy-ufs-install/"
  sudo_run bash -c "chmod 0755 '${MNT}/root/usr/share/easy-ufs-install/'*.sh '${MNT}/root/usr/share/easy-ufs-install/'*.py"
  sudo_run rm -rf "${MNT}/root/usr/share/easy-ufs-install/__pycache__"
  for s in install-masios-to-internal ufs-bootimg ufs-diagnose ufs-fix-internal-boot ufs-probe-sizes; do
    sudo_run install -m0755 "${MOD}/ufs-install/${s}.sh" "${MNT}/root/usr/bin/${s}.sh"
    sudo_run ln -sfn "${s}.sh" "${MNT}/root/usr/bin/${s}"
  done

  log "Copying /home/steamos"
  if [[ -d "${R}/home/steamos" ]]; then
    sudo_run mkdir -p "${MNT}/home/steamos"
    sudo_run rsync -aHAX --numeric-ids "${R}/home/steamos/" "${MNT}/home/steamos/"
    sudo_run chown -R 1000:1000 "${MNT}/home/steamos"
  fi

  log "Writing fstab and KERNEL (root UUID ${root_uuid})"
  # SteamOS mounts /etc from the overlay. Write both layers so first boot
  # actually uses this 3-partition layout (and home can grow).
  sudo_run tee "${MNT}/root/etc/fstab" >/dev/null <<EOF
# SteamOS SM8550 — PC/handheld layout (not Steam Deck A/B)
UUID=${root_uuid}  /      ext4  defaults,noatime                         0 1
LABEL=BOOT         /boot  vfat  defaults,umask=0077,nofail               0 2
UUID=${home_uuid}  /home  ext4  defaults,noatime,x-systemd.growfs        0 2
EOF
  sudo_run mkdir -p "${MNT}/root/var/lib/overlays/etc/upper"
  sudo_run cp -a "${MNT}/root/etc/fstab" "${MNT}/root/var/lib/overlays/etc/upper/fstab"

  local ktmp
  ktmp="$(mktemp)"
  repack_kernel_uuid "${KOUT}/boot/KERNEL" "${ktmp}" "${root_uuid}"
  # vfat cannot store Unix owner/mode — cp -a fails with EPERM
  sudo_run install -m0644 "${ktmp}" "${MNT}/boot/KERNEL"
  sudo_run bash -c "cd '${MNT}/boot' && md5sum KERNEL > KERNEL.md5"
  rm -f "${ktmp}"

  sudo_run tee "${MNT}/root/opt/masi-kernel/IMAGE.txt" >/dev/null <<EOF
image=$(basename "${IMG}")
built=$(date -Iseconds)
root_uuid=${root_uuid}
home_uuid=${home_uuid}
boot_label=BOOT
layout=vfat-boot + ext4-root + ext4-home
expand=steamos-sm8550-expand-home.service
EOF

  sudo_run tee "${MNT}/boot/README.txt" >/dev/null <<EOF
ABL reads KERNEL from this FAT partition.
Do not rename KERNEL. After flashing to a bigger card, home grows on first boot.
root=UUID=${root_uuid}
EOF

  sync
  cleanup_image
  trap - EXIT

  log "Image ready: ${IMG}"
  log "$(ls -lh "${IMG}")"
  log "Flash: sudo dd if='${IMG}' of=/dev/sdX bs=4M status=progress conv=fsync"
}

if [[ "$IMAGE_ONLY" -eq 0 ]]; then
  ensure_official_rootfs
  apply_mods
  build_box64
fi
# Always refresh runtime bits before packing
[[ -x "${R}/usr/local/bin/box64" ]] || install_box64_rootfs
prepare_runtime
build_image
