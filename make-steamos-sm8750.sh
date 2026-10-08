#!/usr/bin/env bash
# Build a flashable SteamOS SM8750 *preview* image for AYN Odin 3:
#   p1 vfat BOOT  — ABL KERNEL (new ABL has no EFI/GRUB)
#   p2 ext4 root  — SteamOS userspace + 7.1.4-edge-sm8750 + UCM audio
#   p3 ext4 home  — user data, grown to the end of the card on first boot
#
# HDMI/DP are known-broken in this kernel pack.
# Mesa is SM8750 Turnip (A830 chip-id); not the SM8550 A740 pack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${ROOT}/scripts"
R="${ROOT}/rootfs"
MOD="${ROOT}/external-and-mods"
OVL="${ROOT}/odin-overlay"
# Preview boot: Kernel-ODIN3 7.1.4 ABL KERNEL. Never the SM8550 7.2.8 pack.
KOUT="${KOUT:-${MOD}/Kernel-ODIN3/output/7.1.4-edge-sm8750}"
IMG="${STEAMOS_SM8750_IMG:-${ROOT}/steamos-sm8750.img}"
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
SKIP_BUILD=0
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

  Preview image for AYN Odin 3 (SM8750 ABL). Does not compile the kernel.

  --skip-download   Reuse existing official rootfs/ chunks
  --skip-apply      Do not re-run scripts/apply-odin-mods.sh
  --skip-build      Do not recompile gamescope/MangoHud (use existing binaries)
  --image-only      Only pack the .img from the current rootfs
  --img PATH        Output image (default: ${IMG})

  Fast path when SteamOS userspace is already applied:
    sudo ./make-steamos-sm8750.sh --skip-download --skip-apply --skip-build

Env: BOOT_MIB ROOT_MIB HOME_MIB STEAMOS_SM8750_IMG
     SKIP_GAMESCOPE_BUILD=1 SKIP_MANGOHUD_BUILD=1  (same as --skip-build)
     SKIP_ODIN3_KERNEL=1  skip SM8750 modules/firmware/UCM overlay
     empty ROOT_MIB/HOME_MIB = auto (tight pack; home grows on first boot)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-download) SKIP_DOWNLOAD=1 ;;
    --skip-apply) SKIP_APPLY=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --skip-box64) log "Box64 is not used (Valve FEX only); --skip-box64 ignored" ;;
    --image-only) IMAGE_ONLY=1; SKIP_DOWNLOAD=1; SKIP_APPLY=1; SKIP_BUILD=1 ;;
    --img) IMG="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

unpack_rootfs_img() {
  local img="$1" dest="$2"
  local mnt="${ROOT}/.rootfs-unpack-mnt"
  [[ -f "$img" ]] || die "missing ${img}"
  mkdir -p "$dest" "$mnt"
  log "Unpacking ${img} → ${dest}"
  rm -rf "${dest:?}/"*
  modprobe loop 2>/dev/null || true

  if mount -o loop,compress=zstd,ro "$img" "$mnt" 2>/dev/null; then
    log "Copying from loop-mounted btrfs (rsync; may take several minutes)"
    # Dest is usually ext4 on the build host — skip btrfs xattrs (compression).
    rsync -aH --numeric-ids \
      --exclude='/dev/**' --exclude='/proc/**' --exclude='/sys/**' \
      --exclude='/tmp/**' --exclude='/run/**' \
      "${mnt}/" "${dest}/"
    umount "$mnt" || die "failed to umount ${mnt}"
  else
    command -v btrfs >/dev/null || die "need loop mount or btrfs-progs to unpack ${img}"
    log "Loop mount failed — falling back to btrfs restore (slow)"
    btrfs restore -r 5 -S -m -i "$img" "$dest"
  fi

  [[ -x "${dest}/usr/bin/bash" ]] || die "unpack finished but ${dest}/usr/bin/bash missing"
}

ensure_official_rootfs() {
  if [[ -x "${R}/usr/bin/bash" ]]; then
    log "Official rootfs already extracted"
    return 0
  fi

  local caibx="${ROOT}/bundle/rootfs.img.caibx"
  local img="${ROOT}/rootfs.img"
  local chunks="${ROOT}/chunks"
  local expected_sha256=""

  if [[ -f "${ROOT}/bundle/manifest.raucm" ]]; then
    expected_sha256="$(awk -F= '/^sha256=/{print $2; exit}' "${ROOT}/bundle/manifest.raucm")"
  fi
  expected_sha256="${expected_sha256:-5c53ff2ed7dc78f313a19fc9224aa07e7fb63271b811a4ada295441a0361e6a8}"

  if [[ -f "$img" ]]; then
    log "Reusing existing ${img}"
  else
    [[ "$SKIP_DOWNLOAD" -eq 1 ]] && die "rootfs missing, no ${img}, and --skip-download set"
    [[ -f "$caibx" ]] || die "missing ${caibx} (official casync index)"
    [[ -x "${SCRIPTS}/extract_rootfs.py" ]] || die "missing scripts/extract_rootfs.py"
    log "Assembling official rootfs.img from casync chunks"
    local -a extract_args=(
      --caibx "$caibx"
      --output "$img"
      --workers "${EXTRACT_WORKERS:-8}"
      --expected-sha256 "$expected_sha256"
    )
    if [[ -d "$chunks" ]]; then
      log "Using local chunk cache ${chunks}"
      extract_args+=(--chunks-dir "$chunks")
    else
      log "No ${chunks}/ — downloading chunks from Valve (slow)"
    fi
    python3 "${SCRIPTS}/extract_rootfs.py" "${extract_args[@]}"
  fi

  unpack_rootfs_img "$img" "$R"
  log "Official rootfs ready at ${R}"
}

apply_mods() {
  [[ "$SKIP_APPLY" -eq 1 ]] && { log "Skipping apply-odin-mods"; return 0; }
  [[ -x "${SCRIPTS}/apply-odin-mods.sh" ]] || die "missing scripts/apply-odin-mods.sh"
  if [[ "$SKIP_BUILD" -eq 1 ]]; then
    log "Skipping vendor recompiles (--skip-build)"
    export SKIP_GAMESCOPE_BUILD=1
    export SKIP_MANGOHUD_BUILD=1
  else
    log "Will compile gamescope + MangoHud from external-and-mods/ during apply-odin-mods"
  fi
  log "Applying test-preview userspace (gamescope / Mesa SM8550 / OOBE / Plasma)"
  log "SM8550 ABL kernel 7.2.8 is NOT installed here"
  sudo_run env SKIP_SM8550_KERNEL=1 "${SCRIPTS}/apply-odin-mods.sh"
}

apply_odin3_kernel() {
  [[ "${SKIP_ODIN3_KERNEL:-0}" == "1" ]] && { log "Skipping ODIN3 kernel overlay"; return 0; }
  [[ -x "${SCRIPTS}/apply-odin3-kernel.sh" ]] || die "missing scripts/apply-odin3-kernel.sh"
  [[ -x "${SCRIPTS}/verify-sm8750-prereqs.sh" ]] || die "missing scripts/verify-sm8750-prereqs.sh"
  KOUT="${KOUT}" "${SCRIPTS}/verify-sm8750-prereqs.sh"
  log "Installing SM8750 ABL kernel 7.1.4-edge-sm8750 + firmware + UCM (Odin 3)"
  sudo_run env KOUT="${KOUT}" ODIN3_KERNEL_RELEASE=7.1.4-edge-sm8750 \
    "${SCRIPTS}/apply-odin3-kernel.sh" "${R}"
  [[ -x "${SCRIPTS}/install-mesa-sm8750.sh" ]] || die "missing scripts/install-mesa-sm8750.sh"
  [[ -f "${MOD}/mesa-sm8750/turnip-working/libvulkan_freedreno.so" ]] \
    || die "missing mesa-sm8750 Turnip (A830). Build: ./scripts/build-mesa-sm8750.sh"
  log "Installing Mesa SM8750 (A830 chip-id Turnip — not SM8550)"
  sudo_run "${SCRIPTS}/install-mesa-sm8750.sh" "${R}"
}

prepare_runtime() {
  log "Installing runtime (fstab template, expand-home, growpart, pad)"
  install -D -m0755 "${OVL}/usr/lib/steamos/steamos-sm8550-expand-home" \
    "${R}/usr/lib/steamos/steamos-sm8550-expand-home"
  install -D -m0644 "${OVL}/usr/lib/systemd/system/steamos-sm8550-expand-home.service" \
    "${R}/usr/lib/systemd/system/steamos-sm8550-expand-home.service"
  mkdir -p "${R}/etc/systemd/system/multi-user.target.wants" \
    "${R}/etc/systemd/system/local-fs-pre.target.wants" \
    "${R}/usr/lib/systemd/system/local-fs-pre.target.wants" \
    "${R}/usr/lib/systemd/system/systemd-fsck@.service.d" \
    "${R}/usr/lib/systemd/system/systemd-growfs@.service.d"
  rm -f "${R}/etc/systemd/system/multi-user.target.wants/steamos-sm8550-expand-home.service" \
        "${R}/etc/systemd/system/local-fs.target.wants/steamos-sm8550-expand-home.service" \
        "${R}/usr/lib/systemd/system/multi-user.target.wants/steamos-sm8550-expand-home.service" \
        "${R}/usr/lib/systemd/system/local-fs.target.wants/steamos-sm8550-expand-home.service"
  ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
    "${R}/etc/systemd/system/local-fs-pre.target.wants/steamos-sm8550-expand-home.service"
  ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
    "${R}/usr/lib/systemd/system/local-fs-pre.target.wants/steamos-sm8550-expand-home.service"
  install -D -m0644 "${OVL}/usr/lib/systemd/system/systemd-fsck@.service.d/sm8550-after-expand-home.conf" \
    "${R}/usr/lib/systemd/system/systemd-fsck@.service.d/sm8550-after-expand-home.conf"
  install -D -m0644 "${OVL}/usr/lib/systemd/system/systemd-growfs@.service.d/sm8550-after-expand-home.conf" \
    "${R}/usr/lib/systemd/system/systemd-growfs@.service.d/sm8550-after-expand-home.conf"
  if [[ -x /usr/bin/growpart ]]; then
    install -D -m0755 /usr/bin/growpart "${R}/usr/bin/growpart"
  fi
  install -D -m0755 "${OVL}/usr/lib/steamos/sm8550-fixpad" \
    "${R}/usr/lib/steamos/sm8550-fixpad"
  install -D -m0644 "${OVL}/usr/lib/systemd/system/sm8550-fixpad.service" \
    "${R}/usr/lib/systemd/system/sm8550-fixpad.service"
  ln -sfn /usr/lib/systemd/system/sm8550-fixpad.service \
    "${R}/etc/systemd/system/multi-user.target.wants/sm8550-fixpad.service"
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
  # Production images use journald's volatile default. scripts/sd-debug-boot.sh
  # can explicitly enable persistent logs for diagnostics.
  rm -f "${R}/etc/systemd/journald.conf.d/99-sm8550-persist.conf"
  rm -rf "${R}/var/log/journal"
  mkdir -p "${R}/etc/systemd/system/graphical.target.wants"
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

# Keep the ABL pack's cmdline (DTB chain lives inside KERNEL). Only rewrite
# root=UUID= so this image's ext4 root matches.
repack_kernel_uuid() {
  local src="$1" dest="$2" uuid="$3"
  local cmdline
  cmdline="$(python3 - "${src}" "${dest}" "${uuid}" <<'PY'
import re
import sys
from pathlib import Path

src, dest, uuid = sys.argv[1], sys.argv[2], sys.argv[3]
data = bytearray(Path(src).read_bytes())
if data[:8] != b"ANDROID!":
    raise SystemExit("not an ANDROID bootimg")
cmd = bytes(data[0x40:0x40 + 512]).split(b"\x00", 1)[0].decode("ascii")
ncmd, n = re.subn(
    r"root=UUID=[0-9a-fA-F-]{36}", f"root=UUID={uuid}", cmd, count=1
)
if n != 1:
    raise SystemExit(f"could not patch root=UUID= in cmdline: {cmd}")
enc = ncmd.encode("ascii")
if len(enc) >= 512:
    raise SystemExit(f"cmdline too long ({len(enc)})")
data[0x40:0x40 + 512] = enc.ljust(512, b"\x00")
Path(dest).write_bytes(data)
print(ncmd)
PY
)"
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
    usr/bin/gpasswd usr/bin/unix_chkpwd usr/bin/mount usr/bin/umount \
    usr/bin/fusermount usr/bin/fusermount3
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
    # Reserved blocks (1%) + slack for first boot / pacman / Heroic updates.
    # Target ~3 GiB free at pack (was 1.5 GiB; root filled too fast on device).
    ROOT_MIB=$((used_mib + 3072 + used_mib / 100 + 128))
    log "root auto-size ${ROOT_MIB} MiB (rootfs ${used_mib} MiB, ~3 GiB free)"
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
  log "  p1 BOOT ${BOOT_MIB}M vfat (ABL KERNEL)"
  log "  p2 root ${ROOT_MIB}M ext4 UUID=${root_uuid}"
  log "  p3 home ${HOME_MIB}M ext4 UUID=${home_uuid} (grows on first boot)"

  detach_img_loops
  rm -f "${IMG}"
  truncate -s "${total_mib}M" "${IMG}"

  # Same MBR layout as SM8550: ABL reads KERNEL from the first FAT partition.
  # 1 MiB = 2048 x 512-byte sectors.
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

  # Do not ship the SM8550 UFS installer on this preview.
  log "Skipping SM8550 UFS installer (Odin 3 ABL preview)"

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
# SteamOS SM8750 Odin 3 preview — ABL KERNEL + ext4 root + ext4 home
UUID=${root_uuid}  /      ext4  defaults,noatime                         0 1
LABEL=BOOT         /boot  vfat  defaults,umask=0077,nofail               0 2
LABEL=home         /home  ext4  defaults,noatime                         0 0
EOF
  sudo_run mkdir -p "${MNT}/root/var/lib/overlays/etc/upper"
  sudo_run cp -a "${MNT}/root/etc/fstab" "${MNT}/root/var/lib/overlays/etc/upper/fstab"

  local ktmp
  ktmp="$(mktemp)"
  repack_kernel_uuid "${KOUT}/boot/KERNEL" "${ktmp}" "${root_uuid}"
  sudo_run install -m0644 "${ktmp}" "${MNT}/boot/KERNEL"
  sudo_run bash -c "cd '${MNT}/boot' && md5sum KERNEL > KERNEL.md5"
  rm -f "${ktmp}"

  sudo_run mkdir -p "${MNT}/root/opt/masi-kernel-odin3"
  sudo_run tee "${MNT}/root/opt/masi-kernel-odin3/IMAGE.txt" >/dev/null <<EOF
image=$(basename "${IMG}")
preview=odin3-sm8750
built=$(date -Iseconds)
root_uuid=${root_uuid}
home_uuid=${home_uuid}
boot_label=BOOT
layout=vfat-boot + ext4-root + ext4-home
bootloader=ABL KERNEL
kernel=7.1.4-edge-sm8750
audio=ucm2/AYN/Odin3
hdmi_dp=not working
expand=steamos-sm8550-expand-home.service
EOF

  sudo_run tee "${MNT}/boot/README.txt" >/dev/null <<EOF
AYN Odin 3 preview — ABL reads KERNEL from this FAT partition.
Do not rename KERNEL. Home grows on first boot.
root=UUID=${root_uuid}
HDMI/DP: not working in this kernel pack.
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
fi
apply_odin3_kernel
prepare_runtime
build_image
