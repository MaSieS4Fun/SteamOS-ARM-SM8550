#!/usr/bin/env bash
# Apply Odin 2 / SM8550 overlays onto the extracted SteamOS Frame rootfs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${ROOT}/rootfs"
MOD="${ROOT}/external-and-mods"
OVL="${ROOT}/odin-overlay"
KOUT="${MOD}/kernel/output/7.0.14-edge-sm8550"
STOCK="${R}/opt/stock-steamos"
GSBUILD="${MOD}/gamescope/build"
MESA_SO="/home/steam/MESA-Drivers/26.2.3/libvulkan_freedreno.so"
LOG="${ROOT}/odin-apply.log"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "$*" | tee -a "$LOG"; }

[[ -d "$R/usr/bin" ]] || die "missing rootfs at $R"
[[ -f "$KOUT/boot/KERNEL" ]] || die "missing kernel $KOUT"
[[ -x "$GSBUILD/src/gamescope" ]] || die "missing built gamescope"
[[ -f "$MESA_SO" ]] || die "missing Mesa $MESA_SO"

: >"$LOG"
log "== $(date -Iseconds) apply Odin mods into $R"

backup() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  if [[ ! -e "$dest" ]]; then
    cp -a "$src" "$dest"
  fi
}

install_file() {
  local src="$1" dest="$2" mode="${3:-}"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  [[ -n "$mode" ]] && chmod "$mode" "$dest"
}

# ---------------------------------------------------------------------------
# Kernel
# ---------------------------------------------------------------------------
log "== kernel 7.0.14-edge-sm8550"
mkdir -p "$R/boot" "$R/usr/lib/modules" "$R/usr/lib/firmware" "$R/opt/masi-kernel"
if [[ -e "$R/boot/KERNEL" && ! -e "$STOCK/boot/KERNEL" ]]; then
  mkdir -p "$STOCK/boot"
  cp -a "$R/boot/KERNEL" "$STOCK/boot/KERNEL" 2>/dev/null || true
fi
cp -a "$KOUT/boot/KERNEL" "$R/boot/KERNEL"
cp -a "$KOUT/boot/KERNEL.md5" "$R/boot/KERNEL.md5"
chmod 0644 "$R/boot/KERNEL" "$R/boot/KERNEL.md5"

rm -rf "$R/usr/lib/modules/7.0.14-edge-sm8550"
cp -a "$KOUT/modules/7.0.14-edge-sm8550" "$R/usr/lib/modules/7.0.14-edge-sm8550"
# Merge firmware without wiping Frame blobs.
cp -a "$KOUT/firmware/." "$R/usr/lib/firmware/"

# Kernel updater (UUID-repack on the real device)
rm -rf "$R/opt/masi-kernel"
mkdir -p "$R/opt/masi-kernel"
for item in update.sh make.sh gui.sh apt-install.sh config lib scripts packaging hooks docs README.md LICENSE CREDITS.md; do
  [[ -e "${MOD}/kernel/${item}" ]] && cp -a "${MOD}/kernel/${item}" "$R/opt/masi-kernel/"
done
mkdir -p "$R/opt/masi-kernel/output"
cp -a "$KOUT" "$R/opt/masi-kernel/output/7.0.14-edge-sm8550"
chmod 0755 "$R/opt/masi-kernel/update.sh" "$R/opt/masi-kernel/"*.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# gamescope
# ---------------------------------------------------------------------------
log "== gamescope (MSM + backlight)"
for b in gamescope gamescopectl gamescopereaper gamescopestream; do
  backup "$R/usr/bin/$b" "$STOCK/usr/bin/$b"
  install_file "$GSBUILD/src/$b" "$R/usr/bin/$b" 0755
  mkdir -p "$R/usr/local/bin"
  install_file "$GSBUILD/src/$b" "$R/usr/local/bin/$b" 0755
done
if [[ -f "$GSBUILD/layer/libVkLayer_FROG_gamescope_wsi_aarch64.so" ]]; then
  backup "$R/usr/lib/libVkLayer_FROG_gamescope_wsi_aarch64.so" \
    "$STOCK/usr/lib/libVkLayer_FROG_gamescope_wsi_aarch64.so"
  install_file "$GSBUILD/layer/libVkLayer_FROG_gamescope_wsi_aarch64.so" \
    "$R/usr/lib/libVkLayer_FROG_gamescope_wsi_aarch64.so" 0755
  mkdir -p "$R/usr/local/lib"
  install_file "$GSBUILD/layer/libVkLayer_FROG_gamescope_wsi_aarch64.so" \
    "$R/usr/local/lib/libVkLayer_FROG_gamescope_wsi_aarch64.so" 0755
fi
if [[ -d "${MOD}/gamescope/scripts" ]]; then
  mkdir -p "$R/usr/share/gamescope" "$R/usr/local/share/gamescope"
  rm -rf "$R/usr/share/gamescope/scripts" "$R/usr/local/share/gamescope/scripts"
  cp -a "${MOD}/gamescope/scripts" "$R/usr/share/gamescope/scripts"
  cp -a "${MOD}/gamescope/scripts" "$R/usr/local/share/gamescope/scripts"
  if [[ -d "${MOD}/gamescope/looks" ]]; then
    rm -rf "$R/usr/share/gamescope/looks" "$R/usr/local/share/gamescope/looks"
    cp -a "${MOD}/gamescope/looks" "$R/usr/share/gamescope/looks"
    cp -a "${MOD}/gamescope/looks" "$R/usr/local/share/gamescope/looks"
  fi
fi
install_file "${MOD}/gamescope/scripts/udev/60-gamescope-backlight.rules" \
  "$R/usr/lib/udev/rules.d/60-gamescope-backlight.rules" 0644
# Also land in /lib if SteamOS uses it
mkdir -p "$R/lib/udev/rules.d"
install_file "${MOD}/gamescope/scripts/udev/60-gamescope-backlight.rules" \
  "$R/lib/udev/rules.d/60-gamescope-backlight.rules" 0644

backup "$R/usr/lib/steamos/gamescope-session" "$STOCK/usr/lib/steamos/gamescope-session"
install_file "$OVL/usr/lib/steamos/gamescope-session" \
  "$R/usr/lib/steamos/gamescope-session" 0755
backup "$R/usr/lib/steamos/gamescope-onready" "$STOCK/usr/lib/steamos/gamescope-onready"
install_file "$OVL/usr/lib/steamos/gamescope-onready" \
  "$R/usr/lib/steamos/gamescope-onready" 0755
install_file "$OVL/usr/lib/steamos/sm8550-steam-focus" \
  "$R/usr/lib/steamos/sm8550-steam-focus" 0755
install_file "$OVL/usr/lib/steamos/odin-bin/steamvr" \
  "$R/usr/lib/steamos/odin-bin/steamvr" 0755
backup "$R/usr/bin/steamos-select-branch" "$STOCK/usr/bin/steamos-select-branch"
install_file "$OVL/usr/bin/steamos-select-branch" \
  "$R/usr/bin/steamos-select-branch" 0755
# Official Plasma is already in the image. Switch-to-desktop must clear
# Game Mode QT_QPA_PLATFORM=xcb or plasmashell dies and the screen stays black.
install_file "$OVL/usr/lib/steamos/sm8550-prepare-plasma" \
  "$R/usr/lib/steamos/sm8550-prepare-plasma" 0755
install_file "$OVL/usr/lib/steamos/sm8550-startplasma" \
  "$R/usr/lib/steamos/sm8550-startplasma" 0755
backup "$R/usr/bin/steamos-session-select" "$STOCK/usr/bin/steamos-session-select"
install_file "$OVL/usr/bin/steamos-session-select" \
  "$R/usr/bin/steamos-session-select" 0755
backup "$R/usr/share/wayland-sessions/plasma.desktop" \
  "$STOCK/usr/share/wayland-sessions/plasma.desktop"
install_file "$OVL/usr/share/wayland-sessions/plasma.desktop" \
  "$R/usr/share/wayland-sessions/plasma.desktop" 0644
install_file "$OVL/usr/lib/systemd/user/sm8550-plasma-env.service" \
  "$R/usr/lib/systemd/user/sm8550-plasma-env.service" 0644
for tgt in plasma-core.target plasma-workspace.target plasma-workspace-wayland.target; do
  mkdir -p "$R/usr/lib/systemd/user/${tgt}.d"
  install_file "$OVL/usr/lib/systemd/user/${tgt}.d/99-odin.conf" \
    "$R/usr/lib/systemd/user/${tgt}.d/99-odin.conf" 0644
done
WAYLAND_DROPIN="$OVL/usr/lib/systemd/user/plasma-plasmashell.service.d/99-odin-wayland.conf"
for svc in plasma-plasmashell plasma-ksplash plasma-ksmserver \
  plasma-kcminit plasma-kcminit-phase1 plasma-kded6 plasma-kwin_wayland \
  plasma-gmenudbusmenuproxy plasma-xembedsniproxy plasma-kaccess \
  plasma-powerdevil plasma-polkit-agent plasma-kglobalaccel plasma-kscreen \
  plasma-xdg-desktop-portal-kde plasma-krunner plasma-kactivitymanagerd \
  plasma-dolphin plasma-ksystemstats plasma-restoresession plasma-baloorunner
do
  mkdir -p "$R/usr/lib/systemd/user/${svc}.service.d"
  install_file "$WAYLAND_DROPIN" \
    "$R/usr/lib/systemd/user/${svc}.service.d/99-odin-wayland.conf" 0644
done
rm -f "$R/usr/lib/steamos/sm8550-desktop-session"
install_file "$OVL/usr/bin/jupiter-initial-firmware-update" \
  "$R/usr/bin/jupiter-initial-firmware-update" 0755
install_file "$OVL/usr/bin/steamos-mandatory-update" \
  "$R/usr/bin/steamos-mandatory-update" 0755
# Steam Software Updates toast: official steamos-update → pkexec/atomupd → 127.
backup "$R/usr/bin/steamos-update" "$STOCK/usr/bin/steamos-update"
install_file "$OVL/usr/bin/steamos-update" \
  "$R/usr/bin/steamos-update" 0755
install_file "$OVL/usr/bin/steamos-polkit-helpers/steamos-update" \
  "$R/usr/bin/steamos-polkit-helpers/steamos-update" 0755
install_file "$OVL/usr/lib/steamos/sm8550-oobe-restart-steam" \
  "$R/usr/lib/steamos/sm8550-oobe-restart-steam" 0755
install_file "$OVL/usr/lib/systemd/system/sm8550-oobe-restart-steam.service" \
  "$R/usr/lib/systemd/system/sm8550-oobe-restart-steam.service" 0644
mkdir -p "$R/usr/lib/systemd/user/steam.service.d"
install_file "$OVL/usr/lib/systemd/user/steam.service.d/99-sm8550-bootstrap.conf" \
  "$R/usr/lib/systemd/user/steam.service.d/99-sm8550-bootstrap.conf" 0644
backup "$R/usr/bin/start-gamescope-session" "$STOCK/usr/bin/start-gamescope-session"
install_file "$OVL/usr/bin/start-gamescope-session" \
  "$R/usr/bin/start-gamescope-session" 0755
backup "$R/usr/share/deckard/RUNSTEAM.sh" "$STOCK/usr/share/deckard/RUNSTEAM.sh"
install_file "$OVL/usr/share/deckard/RUNSTEAM.sh" \
  "$R/usr/share/deckard/RUNSTEAM.sh" 0755
install_file "$OVL/usr/share/deckard/steam-health-check" \
  "$R/usr/share/deckard/steam-health-check" 0755
# Odin 2 has no dock. Missing /usr/bin/jupiter-dock-updater is exit 127
# and Steam shows "Error de actualización". --check must exit 7 (up to date).
log "== dock stub"
mkdir -p "$R/usr/bin/steamos-polkit-helpers"
install_file "$OVL/usr/bin/jupiter-dock-updater" \
  "$R/usr/bin/jupiter-dock-updater" 0755
install_file "$OVL/usr/bin/steamos-polkit-helpers/jupiter-dock-updater" \
  "$R/usr/bin/steamos-polkit-helpers/jupiter-dock-updater" 0755
# steam.service copies this into the user home on each start.
if [[ -d "$R/home/steamos/.local/share/Steam" ]]; then
  install_file "$OVL/usr/share/deckard/RUNSTEAM.sh" \
    "$R/home/steamos/.local/share/Steam/RUNSTEAM.sh" 0755
fi

mkdir -p "$R/usr/lib/systemd/user/gamescope-session.service.d"
mkdir -p "$R/usr/lib/systemd/user/gamescope-session.target.d"
mkdir -p "$R/usr/lib/systemd/user/steam.service.d"
install_file "$OVL/usr/lib/systemd/user/gamescope-session.service.d/99-odin.conf" \
  "$R/usr/lib/systemd/user/gamescope-session.service.d/99-odin.conf" 0644
install_file "$OVL/usr/lib/systemd/user/gamescope-session.target.d/99-odin.conf" \
  "$R/usr/lib/systemd/user/gamescope-session.target.d/99-odin.conf" 0644
install_file "$OVL/usr/lib/systemd/user/steam.service.d/99-odin.conf" \
  "$R/usr/lib/systemd/user/steam.service.d/99-odin.conf" 0644
# Frame leftover: SteamVR must not start on a handheld (Wants= is additive).
mkdir -p "$R/etc/systemd/user" "$R/etc/systemd/system"
for u in steamvr.service steamvr-logs.service steamvr-proxmicmute.service \
         steamvr-v4l2cam.service steamvr-nested-desktop.service; do
  ln -sfn /dev/null "$R/etc/systemd/user/${u}"
done
for u in steamvr-program-ble.service steamvr-v4l2loopback.service \
         steamvr-set-kernel-thread-priorities.service \
         deckard-audio-setup.service \
         deckard-fan-control.service deckard-fpga.service \
         deckard-led-control.service deckard-typec-logger.service \
         set-wifi-mac-address.service iwd.service deckard-charger.service; do
  ln -sfn /dev/null "$R/etc/systemd/system/${u}"
done

# ---------------------------------------------------------------------------
# Audio UCM + Wi-Fi (wpa, not iwd) + BT power + gamescope Wayland session
# ---------------------------------------------------------------------------
log "== alsa UCM AYN-Odin2 + wifi/wpa + bluetooth + wayland session"
if [[ -d "$OVL/usr/share/alsa/ucm2" ]]; then
  mkdir -p "$R/usr/share/alsa/ucm2"
  cp -r --no-preserve=mode,ownership "$OVL/usr/share/alsa/ucm2/." "$R/usr/share/alsa/ucm2/"
  # root alsaucm cannot read 600 steam:steam UCM (speakers stay silent).
  chown -R root:root "$R/usr/share/alsa/ucm2/AYN" \
    "$R/usr/share/alsa/ucm2/codecs" "$R/usr/share/alsa/ucm2/lib" \
    "$R/usr/share/alsa/ucm2/conf.d/sm8550" 2>/dev/null || true
  find "$R/usr/share/alsa/ucm2/AYN" "$R/usr/share/alsa/ucm2/codecs" \
    "$R/usr/share/alsa/ucm2/lib" "$R/usr/share/alsa/ucm2/conf.d/sm8550" \
    -type d -exec chmod 0755 {} + 2>/dev/null || true
  find "$R/usr/share/alsa/ucm2/AYN" "$R/usr/share/alsa/ucm2/codecs" \
    "$R/usr/share/alsa/ucm2/lib" "$R/usr/share/alsa/ucm2/conf.d/sm8550" \
    -type f -exec chmod 0644 {} + 2>/dev/null || true
fi
# Frame steamclient reads VARIANT_ID=vr and Gamepad UI then throws.
for _osr in "$R/etc/os-release" "$R/usr/lib/os-release" \
  "$R/var/lib/overlays/etc/upper/os-release"; do
  [[ -f "$_osr" ]] || continue
  sed -i 's/^VARIANT_ID=.*/VARIANT_ID="steamdeck"/' "$_osr" || true
  grep -q '^VARIANT_ID=' "$_osr" || echo 'VARIANT_ID="steamdeck"' >> "$_osr"
done
unset _osr
# Dangling Frame VR audio plugins break Chromium/Steam streams.
for _so in \
  "$R/usr/lib/ladspa/vraudiocompositor.so" \
  "$R/usr/lib/ladspa/audiofilter.so" \
  "$R/usr/lib/ladspa/libphonon.so"
do
  if [[ -L "$_so" && ! -e "$_so" ]]; then
    rm -f "$_so"
  fi
done
unset _so
install_file "$OVL/usr/lib/NetworkManager/conf.d/40-sm8550-wifi.conf" \
  "$R/usr/lib/NetworkManager/conf.d/40-sm8550-wifi.conf" 0644
install_file "$OVL/usr/lib/modprobe.d/ath12k.conf" \
  "$R/usr/lib/modprobe.d/ath12k.conf" 0644
install_file "$OVL/usr/lib/systemd/network/99-sm8550-wlan0.link" \
  "$R/usr/lib/systemd/network/99-sm8550-wlan0.link" 0644
install_file "$OVL/usr/lib/steamos/sm8550-wifi-backend" \
  "$R/usr/lib/steamos/sm8550-wifi-backend" 0755
install_file "$OVL/usr/lib/systemd/system/sm8550-wifi-backend.service" \
  "$R/usr/lib/systemd/system/sm8550-wifi-backend.service" 0644
install_file "$OVL/usr/lib/systemd/system/sm8550-wifi-backend.path" \
  "$R/usr/lib/systemd/system/sm8550-wifi-backend.path" 0644
mkdir -p "$R/usr/lib/systemd/system/NetworkManager.service.d"
install_file "$OVL/usr/lib/systemd/system/NetworkManager.service.d/99-sm8550-wpa.conf" \
  "$R/usr/lib/systemd/system/NetworkManager.service.d/99-sm8550-wpa.conf" 0644
install_file "$OVL/usr/lib/steamos/sm8550-audio-setup" \
  "$R/usr/lib/steamos/sm8550-audio-setup" 0755
install_file "$OVL/usr/lib/steamos/sm8550-audio-pipewire" \
  "$R/usr/lib/steamos/sm8550-audio-pipewire" 0755
install_file "$OVL/usr/lib/steamos/sm8550-volume-keys" \
  "$R/usr/lib/steamos/sm8550-volume-keys" 0755
install_file "$OVL/usr/lib/systemd/system/sm8550-audio-setup.service" \
  "$R/usr/lib/systemd/system/sm8550-audio-setup.service" 0644
install_file "$OVL/usr/lib/systemd/user/sm8550-audio-pipewire.service" \
  "$R/usr/lib/systemd/user/sm8550-audio-pipewire.service" 0644
install_file "$OVL/usr/lib/systemd/user/sm8550-volume-keys.service" \
  "$R/usr/lib/systemd/user/sm8550-volume-keys.service" 0644
install_file "$OVL/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" \
  "$R/usr/share/wireplumber/wireplumber.conf.d/51-sm8550-hifi-priority.conf" 0644
install_file "$OVL/usr/share/wireplumber/wireplumber.conf.d/52-sm8550-alsa.conf" \
  "$R/usr/share/wireplumber/wireplumber.conf.d/52-sm8550-alsa.conf" 0644
install_file "$OVL/etc/wireplumber/wireplumber.conf.d/52-sm8550-alsa.conf" \
  "$R/etc/wireplumber/wireplumber.conf.d/52-sm8550-alsa.conf" 0644
install_file "$OVL/usr/share/pipewire/pipewire.conf.d/99-sm8550-buffers.conf" \
  "$R/usr/share/pipewire/pipewire.conf.d/99-sm8550-buffers.conf" 0644
install_file "$OVL/usr/share/pipewire/pipewire-pulse.conf.d/99-sm8550-buffers.conf" \
  "$R/usr/share/pipewire/pipewire-pulse.conf.d/99-sm8550-buffers.conf" 0644
install_file "$OVL/usr/lib/udev/rules.d/90-sm8550-audio.rules" \
  "$R/usr/lib/udev/rules.d/90-sm8550-audio.rules" 0644
install_file "$OVL/etc/wireplumber/wireplumber.conf.d/99-sm8550-no-vr-spatial.conf" \
  "$R/etc/wireplumber/wireplumber.conf.d/99-sm8550-no-vr-spatial.conf" 0644
if [[ -f "$R/etc/wireplumber/wireplumber.conf.d/50-alsa-config.conf" ]]; then
  sed -i 's/api.acp.disable-pro-audio = true/api.acp.disable-pro-audio = false/' \
    "$R/etc/wireplumber/wireplumber.conf.d/50-alsa-config.conf" || true
  sed -i 's/node.force-quantum    = 480/node.force-quantum    = 512/' \
    "$R/etc/wireplumber/wireplumber.conf.d/50-alsa-config.conf" || true
  sed -i 's/api.alsa.period-size  = 256/api.alsa.period-size  = 1024/' \
    "$R/etc/wireplumber/wireplumber.conf.d/50-alsa-config.conf" || true
fi
# Frame spatializer is required= and its .so is a /run dangling symlink.
for _sp in 60-spatial-audio.conf 70-spatial-node-config.conf; do
  if [[ -f "$R/etc/wireplumber/wireplumber.conf.d/${_sp}" ]]; then
    mv -f "$R/etc/wireplumber/wireplumber.conf.d/${_sp}" \
      "$R/etc/wireplumber/wireplumber.conf.d/${_sp}.disabled" || true
  fi
done
unset _sp
install_file "$OVL/usr/lib/steamos/sm8550-patch-steamui" \
  "$R/usr/lib/steamos/sm8550-patch-steamui" 0755
install_file "$OVL/usr/lib/steamos/sm8550-bluetooth-setup" \
  "$R/usr/lib/steamos/sm8550-bluetooth-setup" 0755
install_file "$OVL/usr/lib/systemd/system/sm8550-bluetooth-setup.service" \
  "$R/usr/lib/systemd/system/sm8550-bluetooth-setup.service" 0644
# Steam writes this fragment to force iwd; pin wpa in /etc and the overlay upper.
for dest in \
  "$R/etc/NetworkManager/conf.d/99-valve-wifi-backend.conf" \
  "$R/var/lib/overlays/etc/upper/NetworkManager/conf.d/99-valve-wifi-backend.conf"
do
  install_file "$OVL/etc/NetworkManager/conf.d/99-valve-wifi-backend.conf" "$dest" 0644
done
mkdir -p "$R/etc/systemd/system/multi-user.target.wants" \
  "$R/etc/systemd/system/NetworkManager.service.wants" \
  "$R/etc/systemd/system/bluetooth.target.wants" \
  "$R/etc/systemd/system/sound.target.wants" \
  "$R/etc/systemd/user/default.target.wants"
ln -sfn /usr/lib/systemd/system/sm8550-wifi-backend.service \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-wifi-backend.service"
ln -sfn /usr/lib/systemd/system/sm8550-wifi-backend.service \
  "$R/etc/systemd/system/NetworkManager.service.wants/sm8550-wifi-backend.service"
ln -sfn /usr/lib/systemd/system/sm8550-wifi-backend.path \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-wifi-backend.path"
ln -sfn /usr/lib/systemd/system/sm8550-audio-setup.service \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-audio-setup.service"
ln -sfn /usr/lib/systemd/system/sm8550-audio-setup.service \
  "$R/etc/systemd/system/sound.target.wants/sm8550-audio-setup.service"
mkdir -p "$R/usr/lib/systemd/system/multi-user.target.wants" \
  "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/sm8550-audio-setup.service \
  "$R/usr/lib/systemd/system/multi-user.target.wants/sm8550-audio-setup.service"
ln -sfn /usr/lib/systemd/system/sm8550-audio-setup.service \
  "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/sm8550-audio-setup.service"
mkdir -p "$R/usr/lib/systemd/user/default.target.wants"
ln -sfn /usr/lib/systemd/user/sm8550-audio-pipewire.service \
  "$R/usr/lib/systemd/user/default.target.wants/sm8550-audio-pipewire.service"
ln -sfn /usr/lib/systemd/user/sm8550-volume-keys.service \
  "$R/usr/lib/systemd/user/default.target.wants/sm8550-volume-keys.service"
ln -sfn /usr/lib/systemd/user/sm8550-volume-keys.service \
  "$R/etc/systemd/user/default.target.wants/sm8550-volume-keys.service"
ln -sfn /usr/lib/systemd/system/sm8550-bluetooth-setup.service \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-bluetooth-setup.service"
ln -sfn /usr/lib/systemd/system/sm8550-bluetooth-setup.service \
  "$R/etc/systemd/system/bluetooth.target.wants/sm8550-bluetooth-setup.service"
install_file "$OVL/etc/systemd/journald.conf.d/99-sm8550-persist.conf" \
  "$R/etc/systemd/journald.conf.d/99-sm8550-persist.conf" 0644
# Leave the initramfs/fsck console text (modprobe + "root: clean").
# Do not unbind fbcon: on MSM the last console frame looks hung.
rm -f "$R/usr/lib/steamos/sm8550-hide-console" \
  "$R/usr/lib/systemd/system/sm8550-hide-console.service" \
  "$R/lib/systemd/system/sm8550-hide-console.service" \
  "$R/etc/systemd/system/graphical.target.wants/sm8550-hide-console.service" \
  "$R/etc/systemd/system/sysinit.target.wants/sm8550-hide-console.service" \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-hide-console.service" \
  "$R/usr/lib/systemd/system/graphical.target.wants/sm8550-hide-console.service" \
  "$R/usr/lib/systemd/system/sysinit.target.wants/sm8550-hide-console.service" \
  "$R/usr/lib/systemd/system/multi-user.target.wants/sm8550-hide-console.service"
# Debug dumps must not paint the panel.
rm -f "$R/etc/systemd/system/multi-user.target.wants/sm8550-boot-debug.service" \
      "$R/etc/systemd/system/graphical.target.wants/sm8550-boot-debug-late.service"
ln -sfn /usr/lib/systemd/user/sm8550-audio-pipewire.service \
  "$R/etc/systemd/user/default.target.wants/sm8550-audio-pipewire.service"
# Host enables these explicitly; socket-only leaves gamescope without a sink.
mkdir -p "$R/etc/systemd/user/default.target.wants" \
  "$R/etc/xdg/systemd/user/default.target.wants"
for u in pipewire.service pipewire-pulse.service; do
  if [[ -f "$R/usr/lib/systemd/user/${u}" ]]; then
    ln -sfn "/usr/lib/systemd/user/${u}" \
      "$R/etc/systemd/user/default.target.wants/${u}"
    ln -sfn "/usr/lib/systemd/user/${u}" \
      "$R/etc/xdg/systemd/user/default.target.wants/${u}"
  fi
done
if [[ -f "$R/usr/lib/systemd/system/wpa_supplicant.service" ]]; then
  ln -sfn /usr/lib/systemd/system/wpa_supplicant.service \
    "$R/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service"
  ln -sfn /usr/lib/systemd/system/wpa_supplicant.service \
    "$R/etc/systemd/system/NetworkManager.service.wants/wpa_supplicant.service"
fi
rm -f "$R/etc/systemd/system/multi-user.target.wants/iwd.service"
# Official Wayland Plasma, started via sm8550-startplasma (clears Game Mode xcb).
install_file "$OVL/usr/share/wayland-sessions/plasma.desktop" \
  "$R/usr/share/wayland-sessions/plasma.desktop" 0644
rm -f "$R/usr/lib/steamos/sm8550-desktop-session"
if [[ -d "$R/usr/share/steamos-manager/devices" ]]; then
  install_file "$OVL/usr/share/steamos-manager/devices/ayn-odin2.toml" \
    "$R/usr/share/steamos-manager/devices/ayn-odin2.toml" 0644
fi
# Steam "Switch to Desktop" listed only plasmax11. Hide Frame X11 sessions.
mkdir -p "$R/usr/share/steamos/hidden-xsessions"
for s in plasmax11.desktop openbox.desktop openbox-kde.desktop; do
  if [[ -f "$R/usr/share/xsessions/$s" ]]; then
    mv -f "$R/usr/share/xsessions/$s" "$R/usr/share/steamos/hidden-xsessions/$s"
  fi
done

# ---------------------------------------------------------------------------
# Native rsinput ±740, then InputPlumber deck-uhid + keyboard (OSK haptic).
# USB/Bluetooth HID is ignored in the composite so it is not grabbed.
# ---------------------------------------------------------------------------
log "== gamepad (rsinput ±740 + InputPlumber deck-uhid)"
install_file "$OVL/usr/lib/steamos/sm8550-fixpad" \
  "$R/usr/lib/steamos/sm8550-fixpad" 0755
install_file "$OVL/usr/lib/systemd/system/sm8550-fixpad.service" \
  "$R/usr/lib/systemd/system/sm8550-fixpad.service" 0644
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/sm8550-fixpad.service \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-fixpad.service"
install_file "$OVL/usr/lib/udev/rules.d/70-sm8550-gamepad.rules" \
  "$R/usr/lib/udev/rules.d/70-sm8550-gamepad.rules" 0644
mkdir -p "$R/lib/udev/rules.d"
install_file "$OVL/usr/lib/udev/rules.d/70-sm8550-gamepad.rules" \
  "$R/lib/udev/rules.d/70-sm8550-gamepad.rules" 0644
install_file "$OVL/etc/sdl2/qcom-gamecontrollerdb.txt" \
  "$R/etc/sdl2/qcom-gamecontrollerdb.txt" 0644
install_file "$OVL/usr/lib/environment.d/60-sm8550-gamepad.conf" \
  "$R/usr/lib/environment.d/60-sm8550-gamepad.conf" 0644
install_file "$OVL/etc/profile.d/sm8550-gamepad.sh" \
  "$R/etc/profile.d/sm8550-gamepad.sh" 0644
"${SCRIPT_DIR}/install-inputplumber-sm8550.sh" "$R"

# ---------------------------------------------------------------------------
# MangoHud: keep SteamOS stock binaries. Host Ubuntu mangoapp needs GLIBC_2.43
# (SteamOS is 2.39) and crash-loops gamescopereaper / the session.
# Build from external-and-mods/MangoHud against SteamOS glibc before replacing.
# ---------------------------------------------------------------------------
log "== MangoHud (stock SteamOS — host Ubuntu mango needs GLIBC_2.43)"
for b in mangohud mangoapp mangohudctl; do
  if [[ -f "$STOCK/usr/bin/$b" ]]; then
    install_file "$STOCK/usr/bin/$b" "$R/usr/bin/$b" 0755
  fi
done
for lib in libMangoHud.so libMangoHud_opengl.so libMangoHud_shim.so libMangoHud-next.so; do
  if [[ -f "$STOCK/usr/lib/$lib" ]]; then
    install_file "$STOCK/usr/lib/$lib" "$R/usr/lib/$lib" 0755
  fi
done

# ---------------------------------------------------------------------------
# lsfg-vk
# ---------------------------------------------------------------------------
log "== lsfg-vk"
mkdir -p "$R/usr/local/lib" "$R/usr/lib" "$R/usr/share/vulkan/implicit_layer.d" \
  "$R/usr/local/share/vulkan/implicit_layer.d"
if [[ -f /usr/local/lib/liblsfg-vk.so ]]; then
  install_file /usr/local/lib/liblsfg-vk.so "$R/usr/local/lib/liblsfg-vk.so" 0755
  install_file /usr/local/lib/liblsfg-vk.so "$R/usr/lib/liblsfg-vk.so" 0755
fi
install_file "$OVL/usr/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json" \
  "$R/usr/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json" 0644
install_file "$OVL/usr/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json" \
  "$R/usr/local/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json" 0644

# ---------------------------------------------------------------------------
# Mesa Turnip
# ---------------------------------------------------------------------------
log "== Mesa libvulkan_freedreno.so 26.2.3"
backup "$R/usr/lib/libvulkan_freedreno.so" "$STOCK/usr/lib/libvulkan_freedreno.so"
install_file "$MESA_SO" "$R/usr/lib/libvulkan_freedreno.so" 0755
# Patched .so needs libdisplay-info.so.3 (SteamOS only ships .so.1)
if [[ -f /usr/lib/aarch64-linux-gnu/libdisplay-info.so.3 ]]; then
  real="$(readlink -f /usr/lib/aarch64-linux-gnu/libdisplay-info.so.3)"
  install_file "$real" "$R/usr/lib/$(basename "$real")" 0755
  ln -sfn "$(basename "$real")" "$R/usr/lib/libdisplay-info.so.3"
fi

# ---------------------------------------------------------------------------
# User home (steamos uid 1000)
# ---------------------------------------------------------------------------
log "== home/steamos (Decky plugin + configs)"
if [[ -n "${STEAMOS_HOME:-}" ]]; then
  HOME_DST="$STEAMOS_HOME"
elif [[ -d /run/media/steam/home/steamos && "$R" == /run/media/steam/root ]]; then
  HOME_DST=/run/media/steam/home/steamos
else
  HOME_DST="$R/home/steamos"
fi
mkdir -p "$HOME_DST"
# Copy plugin tree (resolve lsfg .so symlink into a real file if needed)
rsync -a --copy-links "${MOD}/Decky/Plug-ins/" "$HOME_DST/"
# Fix lsfg-vk home paths
if [[ -f "$HOME_DST/.config/lsfg-vk/conf.toml" ]]; then
  sed -i 's|/home/steam/|/home/steamos/|g' "$HOME_DST/.config/lsfg-vk/conf.toml"
fi
if [[ -f "$HOME_DST/.local/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json" ]]; then
  python3 - "$HOME_DST" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]) / ".local/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json"
txt = p.read_text()
txt = txt.replace("/home/steam/", "/home/steamos/")
p.write_text(txt)
PY
fi
# Ensure the layer .so exists in the home tree even if the symlink was dangling
if [[ -f "$R/usr/local/lib/liblsfg-vk.so" ]]; then
  mkdir -p "$HOME_DST/.local/lib"
  install_file "$R/usr/local/lib/liblsfg-vk.so" "$HOME_DST/.local/lib/liblsfg-vk.so" 0755
fi
install_file "$OVL/home-steamos/LEEME-ODIN.txt" "$HOME_DST/LEEME-ODIN.txt" 0644
install_file "$OVL/home-steamos/README-ODIN.txt" "$HOME_DST/README-ODIN.txt" 0644

# Frame steam.tar.zst is an incomplete client (spinner, no package zips).
# Bake a complete ARM client (seed binaries from host if present), then
# strip login/account data so first boot is a clean Steam Deck login.
STEAM_HOME="$HOME_DST/.local/share/Steam"
log "== complete Steam ARM client"
mkdir -p "$STEAM_HOME"
if [[ -x "${SCRIPT_DIR}/install-complete-steam-client.sh" ]]; then
  "${SCRIPT_DIR}/install-complete-steam-client.sh" "$STEAM_HOME" \
    || log "WARN: complete Steam install failed — Game Mode will stay on the spinner"
fi
if [[ -x "$R/usr/lib/steamos/sm8550-patch-steamui" && -d "$STEAM_HOME/steamui" ]]; then
  "$R/usr/lib/steamos/sm8550-patch-steamui" "$STEAM_HOME/steamui" || true
fi
touch "$STEAM_HOME/.install-complete"
install_file "$OVL/usr/share/deckard/RUNSTEAM.sh" \
  "$STEAM_HOME/RUNSTEAM.sh" 0755
if [[ -d "$STEAM_HOME/linuxarm64" && -d "$STEAM_HOME/steamrtarm64" ]]; then
  for _lib in steamclient.so crashhandler.so steam-launch-wrapper; do
    if [[ -s "$STEAM_HOME/steamrtarm64/${_lib}" && ! -s "$STEAM_HOME/linuxarm64/${_lib}" ]]; then
      cp -f "$STEAM_HOME/steamrtarm64/${_lib}" "$STEAM_HOME/linuxarm64/${_lib}"
    fi
  done
  unset _lib
fi

# Desktop: only Return to Gaming Mode. Decky lives in ARM-Manager.
mkdir -p "$HOME_DST/Desktop" "$R/usr/share/applications" "$R/usr/share/icons/hicolor/scalable/apps"
rm -f "$HOME_DST/Desktop/Decky Loader.desktop" "$HOME_DST/Desktop/install-decky.desktop"

# ---------------------------------------------------------------------------
# Plasma extras + ARM-Manager + LSFG/Thor/Decky plugins
# ---------------------------------------------------------------------------
log "== plasma extras (holo kate/ark/networkmanager-qt/…)"
STEAMOS_HOME="$HOME_DST" "${SCRIPT_DIR}/install-plasma-extras.sh" "$R" \
  || log "WARN: plasma extras incomplete"
if [[ ! -f "$R/usr/lib/qt6/plugins/plasma/kcms/systemsettings/kcm_kscreen.so" ]]; then
  log "== official Plasma kscreen 6.2.5 KCM"
  "${SCRIPT_DIR}/build-kscreen-6.2.5.sh" "$R" \
    || die "kscreen 6.2.5 is required (Display Configuration)"
fi
if [[ ! -f "$R/usr/lib/qt6/plugins/plasma/kcms/systemsettings_qwidgets/kcm_networkmanagement.so" ]]; then
  log "== KF6 NetworkManagerQt 6.14 (plasma-nm needs >= 6.5)"
  "${SCRIPT_DIR}/build-kf6-nm-qt-6.14.sh" "$R" \
    || die "networkmanager-qt 6.14 is required"
  log "== official Plasma plasma-nm 6.2.5 (Network Manager)"
  "${SCRIPT_DIR}/build-plasma-nm-6.2.5.sh" "$R" \
    || die "plasma-nm 6.2.5 is required (Network Manager)"
fi
# extras skip ALARM Gear (Qt_6.11). Build official 26.04.2 for Qt 6.8.
needs_gear_qt68() {
  local bin="$R/usr/bin/$1"
  [[ ! -x "$bin" ]] && return 0
  strings "$bin" 2>/dev/null | grep -q 'Qt_6\.11'
}
for _gear in ark kcalc filelight gwenview okular; do
  if needs_gear_qt68 "$_gear"; then
    log "== official ${_gear} 26.04.2 for Qt 6.8"
    "${SCRIPT_DIR}/build-kde-gear-26.04.2.sh" "$R" "$_gear" \
      || log "WARN: ${_gear} 26.04.2 build failed"
  fi
done
log "== vendor apps (UFS, MESA, Proton-ARM, Non-Steam, SRM)"
STEAMOS_HOME="$HOME_DST" "${SCRIPT_DIR}/install-vendor-apps.sh" "$R" \
  || log "WARN: vendor apps incomplete"
log "== system fixes (LSFG-VK, Thor, Decky plugins, Return icon)"
STEAMOS_HOME="$HOME_DST" "${SCRIPT_DIR}/install-system-fixes.sh" "$R" \
  || log "WARN: system fixes incomplete"

# ---------------------------------------------------------------------------
# Ownership / extras
# ---------------------------------------------------------------------------
log "== permissions"
chown -R 1000:1000 "$HOME_DST"
chmod 0755 "$HOME_DST"
# NetworkManager refuses plugins/scripts not owned by root (wifi/bt stay dead).
if [[ -d "$R/usr/lib/NetworkManager" ]]; then
  chown -R root:root "$R/usr/lib/NetworkManager" || true
  find "$R/usr/lib/NetworkManager" -type f -name '*.so' -exec chmod 0755 {} + || true
fi
if [[ -d "$R/etc/NetworkManager" ]]; then
  chown -R root:root "$R/etc/NetworkManager" || true
fi
if [[ -d "$R/var/lib/overlays/etc/upper/NetworkManager" ]]; then
  chown -R root:root "$R/var/lib/overlays/etc/upper/NetworkManager" || true
fi
# User session PipeWire.
if [[ -d "$HOME_DST" ]]; then
  mkdir -p "$HOME_DST/.config/systemd/user/default.target.wants"
  for u in pipewire.service pipewire-pulse.service sm8550-audio-pipewire.service sm8550-volume-keys.service; do
    src="/usr/lib/systemd/user/${u}"
    [[ -f "$R${src}" ]] || continue
    ln -sfn "$src" "$HOME_DST/.config/systemd/user/default.target.wants/${u}"
  done
fi
# SteamOS empty-password user stays as extracted (steamos:: in shadow)

# ldconfig cache is arch-specific; skip. Dynamic linker will still find /usr/lib.

log "== summary"
{
  echo "gamescope: $(file -b "$R/usr/bin/gamescope")"
  echo "KERNEL:    $(file -b "$R/boot/KERNEL")"
  echo "modules:   $R/usr/lib/modules/7.0.14-edge-sm8550"
  echo "mesa:      $(ls -l "$R/usr/lib/libvulkan_freedreno.so")"
  echo "display-info.so.3: $(ls -l "$R/usr/lib/libdisplay-info.so.3" 2>/dev/null || echo missing)"
  echo "lsfg:      $(ls -l "$R/usr/local/lib/liblsfg-vk.so" 2>/dev/null || echo missing)"
  echo "fixpad:    $(ls -l "$R/usr/lib/steamos/sm8550-fixpad" 2>/dev/null || echo missing)"
  echo "inputplumber: $(ls -l "$R/usr/bin/inputplumber" 2>/dev/null || echo missing)"
  echo "deck-uhid: $(grep -A2 target_devices "$R/etc/inputplumber/devices.d/02-ayn-odin.yaml" 2>/dev/null || echo missing)"
  echo "home:      $(find "$HOME_DST" -maxdepth 3 -printf '%p\n' | head -40)"
} | tee -a "$LOG"

log "OK"
