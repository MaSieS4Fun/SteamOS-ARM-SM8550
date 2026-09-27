#!/usr/bin/env bash
# Apply Odin 2 / SM8550 overlays onto the extracted SteamOS Frame rootfs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}"/lib/*.sh 2>/dev/null || true
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${ROOT}/rootfs"
MOD="${ROOT}/external-and-mods"
OVL="${ROOT}/odin-overlay"
KOUT="${MOD}/kernel/output/7.0.14-edge-sm8550"
STOCK="${R}/opt/stock-steamos"
GSBUILD="${MOD}/gamescope/build"
MESA_TURNIP="${MOD}/mesa-sm8550/turnip-working/libvulkan_freedreno.so"
MESA_OGL="${MOD}/mesa-sm8550/opengl-working/libEGL_mesa.so.0.0.0"
LOG="${ROOT}/odin-apply.log"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "$*" | tee -a "$LOG"; }

run_privileged() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif sudo -n true 2>/dev/null; then
    sudo "$@"
  else
    die "need root for: $* (run apply-odin-mods.sh via sudo make-steamos-sm8550.sh)"
  fi
}

: >"$LOG"
log "== $(date -Iseconds) apply Odin mods into $R"

# ---------------------------------------------------------------------------
# Compile project gamescope (SM8550) — never use stock rootfs gamescope.
# ---------------------------------------------------------------------------
log "========================================"
log "== COMPILE gamescope (external-and-mods/gamescope)"
log "========================================"
if [[ "${SKIP_GAMESCOPE_BUILD:-0}" == "1" ]]; then
  log "SKIP_GAMESCOPE_BUILD=1 — using existing ${GSBUILD}/src/gamescope"
else
  "${SCRIPT_DIR}/build-gamescope-sm8550.sh"
fi
[[ -x "$GSBUILD/src/gamescope" ]] || die "missing built gamescope at $GSBUILD/src/gamescope"

[[ -d "$R/usr/bin" ]] || die "missing rootfs at $R"
[[ -f "$KOUT/boot/KERNEL" ]] || die "missing kernel $KOUT"
[[ -f "$MESA_TURNIP" ]] || die "missing Mesa turnip $MESA_TURNIP"
[[ -f "$MESA_OGL" ]] || die "missing Mesa opengl $MESA_OGL"

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
# Always use external-and-mods/gamescope/build (SM8550 patches). Stock rootfs gamescope
# is NOT Adreno-740 adapted. HOST_GAMESCOPE is blocked unless ALLOW_HOST_GAMESCOPE=1.
if [[ -n "${HOST_GAMESCOPE:-}" && "${ALLOW_HOST_GAMESCOPE:-0}" != "1" ]]; then
  die "HOST_GAMESCOPE is set but ALLOW_HOST_GAMESCOPE=1 was not given — use project build in ${GSBUILD}/src/gamescope"
fi
PROJECT_GS="$GSBUILD/src/gamescope"
GS_MD5="$(md5sum "$PROJECT_GS" | awk '{print $1}')"
log "gamescope: project build $PROJECT_GS (md5=$GS_MD5)"
for b in gamescope gamescopectl gamescopereaper gamescopestream; do
  backup "$R/usr/bin/$b" "$STOCK/usr/bin/$b"
  src="$GSBUILD/src/$b"
  if [[ "$b" == "gamescope" && -n "${HOST_GAMESCOPE:-}" && -x "$HOST_GAMESCOPE" ]]; then
    src="$HOST_GAMESCOPE"
    log "gamescope: ALLOW_HOST_GAMESCOPE override $HOST_GAMESCOPE"
  fi
  install_file "$src" "$R/usr/bin/$b" 0755
  mkdir -p "$R/usr/local/bin"
  install_file "$src" "$R/usr/local/bin/$b" 0755
done
mkdir -p "$R/usr/share/steamos-odin"
{
  date -Iseconds
  echo "source=external-and-mods/gamescope/build"
  echo "md5=$GS_MD5"
  file -b "$R/usr/bin/gamescope"
} > "$R/usr/share/steamos-odin/gamescope-sm8550.txt"
INSTALLED_MD5="$(md5sum "$R/usr/bin/gamescope" | awk '{print $1}')"
[[ "$INSTALLED_MD5" == "$GS_MD5" ]] || die "gamescope install mismatch: installed=$INSTALLED_MD5 expected=$GS_MD5"
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
# Frame ships holo-cursor-{32,64,128,256}.png; gamescope-session needs holo-cursor.png.
if [[ ! -e "$R/usr/share/holo/holo-cursor.png" && -f "$R/usr/share/holo/holo-cursor-256.png" ]]; then
  ln -sfn holo-cursor-256.png "$R/usr/share/holo/holo-cursor.png"
fi
install_file "$OVL/usr/lib/steamos/sm8550-launch-steam" \
  "$R/usr/lib/steamos/sm8550-launch-steam" 0755
install_file "$OVL/usr/lib/steamos/sm8550-ensure-steam-home" \
  "$R/usr/lib/steamos/sm8550-ensure-steam-home" 0755
backup "$R/usr/lib/steamos/gamescope-onready" "$STOCK/usr/lib/steamos/gamescope-onready"
install_file "$OVL/usr/lib/steamos/gamescope-onready" \
  "$R/usr/lib/steamos/gamescope-onready" 0755
backup "$R/usr/lib/systemd/user/gamescope-session.service" \
  "$STOCK/usr/lib/systemd/user/gamescope-session.service"
install_file "$OVL/usr/lib/systemd/user/gamescope-session.service" \
  "$R/usr/lib/systemd/user/gamescope-session.service" 0644
backup "$R/usr/lib/systemd/user/gamescope-session.target" \
  "$STOCK/usr/lib/systemd/user/gamescope-session.target"
install_file "$OVL/usr/lib/systemd/user/gamescope-session.target" \
  "$R/usr/lib/systemd/user/gamescope-session.target" 0644
install_file "$OVL/usr/lib/steamos/sm8550-steam-focus" \
  "$R/usr/lib/steamos/sm8550-steam-focus" 0755
# Steam-controlled mangoapp sibling. The wrapper uses the external-overlay
# plane without taking STEAM_OVERLAY and only displays while a game is active.
install_file "$OVL/usr/lib/steamos/sm8550-mango-config" \
  "$R/usr/lib/steamos/sm8550-mango-config" 0755
install_file "$OVL/usr/lib/steamos/sm8550-mangoapp" \
  "$R/usr/lib/steamos/sm8550-mangoapp" 0755
install_file "$OVL/usr/lib/steamos/sm8550-plugin-loader" \
  "$R/usr/lib/steamos/sm8550-plugin-loader" 0755
install_file "$OVL/usr/lib/steamos/sm8550-plugin-loader" \
  "$R/usr/share/steamos-odin/sm8550-plugin-loader" 0755
install_file "$OVL/usr/lib/steamos/sm8550-fex" \
  "$R/usr/lib/steamos/sm8550-fex" 0755
install_file "$OVL/usr/lib/steamos/sm8550-fex-binfmt" \
  "$R/usr/lib/steamos/sm8550-fex-binfmt" 0755
install_file "$OVL/usr/lib/steamos/sm8550-restore-decky-box64" \
  "$R/usr/lib/steamos/sm8550-restore-decky-box64" 0755
install_file "$OVL/usr/lib/systemd/user/sm8550-plugin-loader.service" \
  "$R/usr/lib/systemd/user/sm8550-plugin-loader.service" 0644
# Never run a second, system-wide PluginLoader. It survives Game Mode and its
# LSFG children delay session changes and shutdown.
rm -f "$R/usr/lib/systemd/system/plugin_loader.service" \
  "$R/etc/systemd/system/plugin_loader.service" \
  "$R/etc/systemd/system/multi-user.target.wants/plugin_loader.service"
install_file "$OVL/usr/lib/systemd/system/sm8550-fex-binfmt.service" \
  "$R/usr/lib/systemd/system/sm8550-fex-binfmt.service" 0644
# Never ship the FEX path watcher — Steam installing FEX-Emu must not hijack binfmt.
rm -f "$R/usr/lib/systemd/system/sm8550-fex-binfmt.path" \
  "$R/lib/systemd/system/sm8550-fex-binfmt.path" \
  "$R/etc/systemd/system/sm8550-fex-binfmt.path" \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-fex-binfmt.path" \
  "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/sm8550-fex-binfmt.path"
rm -f "$R/usr/lib/systemd/user/sm8550-mangoapp.service"
mkdir -p "$R/usr/share/steamos-odin/MangoHud/steam"
install_file "$OVL/usr/share/steamos-odin/MangoHud/steam/MangoHud.conf" \
  "$R/usr/share/steamos-odin/MangoHud/steam/MangoHud.conf" 0644
install_file "$OVL/usr/share/steamos-odin/MangoHud/steam/presets.conf" \
  "$R/usr/share/steamos-odin/MangoHud/steam/presets.conf" 0644
install_file "$OVL/usr/lib/steamos/odin-bin/steamvr" \
  "$R/usr/lib/steamos/odin-bin/steamvr" 0755
install_file "$OVL/usr/lib/steamos/odin-bin/mangoapp" \
  "$R/usr/lib/steamos/odin-bin/mangoapp" 0755
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
# Display rewriting is recovery-only. The verified Game Mode contract is
# External: DSI-1 + INTERNAL_X11=1, with no automatic fix/guard helpers.
rm -f "$R/usr/lib/steamos/sm8550-fix-steam-display" \
  "$R/usr/lib/steamos/sm8550-ensure-steam-internal-display.sh" \
  "$R/usr/lib/steamos/sm8550-steam-display-guard" \
  "$R/usr/lib/systemd/user/sm8550-steam-display-guard.service"
install_file "$OVL/usr/lib/steamos/sm8550-disable-external-x11" \
  "$R/usr/lib/steamos/sm8550-disable-external-x11" 0755
install_file "$OVL/usr/lib/steamos/sm8550-dock-hotplug" \
  "$R/usr/lib/steamos/sm8550-dock-hotplug" 0755
install_file "$OVL/usr/lib/steamos/sm8550-oobe-restart-steam" \
  "$R/usr/lib/steamos/sm8550-oobe-restart-steam" 0755
install_file "$OVL/usr/lib/steamos/sm8550-relaunch-steam" \
  "$R/usr/lib/steamos/sm8550-relaunch-steam" 0755
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
rm -f "$R/etc/systemd/user/gamescope-session.target.wants/sm8550-steam-display-guard.service" \
  "$R/usr/lib/systemd/user/gamescope-session.target.wants/sm8550-steam-display-guard.service" \
  "$R/etc/sm8550-steam-display-mode"
install_file "$OVL/usr/lib/systemd/user/steam.service.d/99-odin.conf" \
  "$R/usr/lib/systemd/user/steam.service.d/99-odin.conf" 0644
rm -f "$R/usr/lib/systemd/user/steam.service.d/99-sm8550-handheld.conf"
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
# Keep production logging volatile. Enable persistence only with
# scripts/sd-debug-boot.sh while diagnosing a specific problem.
rm -f "$R/etc/systemd/journald.conf.d/99-sm8550-persist.conf"
rm -rf "$R/var/log/journal"
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
# Native rsinput ±740, InputPlumber deck-uhid + keyboard, udev touch dedupe (image bake).
# USB/Bluetooth HID is ignored in the composite so it is not grabbed.
# ---------------------------------------------------------------------------
log "== gamepad (rsinput ±740 + InputPlumber + udev touch dedupe)"
install_file "$OVL/usr/lib/steamos/sm8550-fixpad" \
  "$R/usr/lib/steamos/sm8550-fixpad" 0755
install_file "$OVL/usr/lib/systemd/system/sm8550-fixpad.service" \
  "$R/usr/lib/systemd/system/sm8550-fixpad.service" 0644
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/sm8550-fixpad.service \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-fixpad.service"
install_file "$OVL/etc/sdl2/qcom-gamecontrollerdb.txt" \
  "$R/etc/sdl2/qcom-gamecontrollerdb.txt" 0644
install_file "$OVL/usr/lib/environment.d/60-sm8550-gamepad.conf" \
  "$R/usr/lib/environment.d/60-sm8550-gamepad.conf" 0644
install_file "$OVL/etc/profile.d/sm8550-gamepad.sh" \
  "$R/etc/profile.d/sm8550-gamepad.sh" 0644
"${SCRIPT_DIR}/install-inputplumber-sm8550.sh" "$R"

# ---------------------------------------------------------------------------
# MangoHud + mangoapp: compile vendor tree in chroot (GLIBC 2.39) with Holo layout
#   /usr/lib/mangohud/lib64/  +  Vulkan layer JSON  +  mangohud wrapper.
# Source: external-and-mods/MangoHud (kgsl temp/MHz for Adreno 740).
# Do NOT copy loose .so into /usr/lib/ — layer path would break (no FPS overlay).
# Game Mode: mangoapp sibling via gamescope-onready (not gamescope --mangoapp).
# ---------------------------------------------------------------------------
log "========================================"
log "== COMPILE MangoHud (external-and-mods/MangoHud, chroot in rootfs)"
log "========================================"
if [[ "${SKIP_MANGOHUD_BUILD:-0}" == "1" ]]; then
  [[ -f "$R/usr/lib/mangohud/lib64/libMangoHud.so" ]] \
    || die "SKIP_MANGOHUD_BUILD=1 but $R/usr/lib/mangohud/lib64/libMangoHud.so missing"
  log "SKIP_MANGOHUD_BUILD=1 — using existing vendor MangoHud in rootfs"
else
  run_privileged "${SCRIPT_DIR}/build-vendor-mangohud.sh" "$R" \
    || die "vendor MangoHud build failed (need glfw3/dbus/x11 + meson>=1.7 in rootfs)"
fi

# ---------------------------------------------------------------------------
# lsfg-vk
# ---------------------------------------------------------------------------
log "== lsfg-vk"
mkdir -p "$R/usr/local/lib" "$R/usr/lib" "$R/usr/share/vulkan/implicit_layer.d" \
  "$R/usr/local/share/vulkan/implicit_layer.d"
lsfg_src=""
for _c in /usr/local/lib/liblsfg-vk.so \
  "${MOD}/lsfg-vk/liblsfg-vk.so" \
  "${ROOT}/gold-config/binaries/liblsfg-vk.so"; do
  if [[ -f "$_c" ]]; then
    lsfg_src="$_c"
    break
  fi
done
if [[ -z "$lsfg_src" && -e "${MOD}/Decky/Plug-ins/.local/lib/liblsfg-vk.so" ]]; then
  lsfg_src="$(readlink -f "${MOD}/Decky/Plug-ins/.local/lib/liblsfg-vk.so" 2>/dev/null || true)"
  [[ -f "$lsfg_src" ]] || lsfg_src=""
fi
if [[ -n "$lsfg_src" ]]; then
  log "liblsfg-vk.so from ${lsfg_src}"
  install_file "$lsfg_src" "$R/usr/local/lib/liblsfg-vk.so" 0755
  install_file "$lsfg_src" "$R/usr/lib/liblsfg-vk.so" 0755
else
  log "WARN: liblsfg-vk.so not found (install on build host: /usr/local/lib/liblsfg-vk.so)"
fi
install_file "$OVL/usr/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json" \
  "$R/usr/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json" 0644
install_file "$OVL/usr/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json" \
  "$R/usr/local/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json" 0644

# ---------------------------------------------------------------------------
# Mesa SM8550 — Turnip + OpenGL + wayland (see external-and-mods/mesa-sm8550/)
# ---------------------------------------------------------------------------
log "== Mesa SM8550 (turnip-working + opengl-working + wayland)"
"${SCRIPT_DIR}/install-mesa-sm8550.sh" "$R"
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
mkdir -p "$HOME_DST/.config/MangoHud/steam" "$R/etc/skel/.config/MangoHud/steam"
install_file "$OVL/usr/share/steamos-odin/MangoHud/steam/MangoHud.conf" \
  "$HOME_DST/.config/MangoHud/steam/MangoHud.conf" 0644
install_file "$OVL/usr/share/steamos-odin/MangoHud/steam/presets.conf" \
  "$HOME_DST/.config/MangoHud/steam/presets.conf" 0644
install_file "$OVL/usr/share/steamos-odin/MangoHud/steam/MangoHud.conf" \
  "$R/etc/skel/.config/MangoHud/steam/MangoHud.conf" 0644
install_file "$OVL/usr/share/steamos-odin/MangoHud/steam/presets.conf" \
  "$R/etc/skel/.config/MangoHud/steam/presets.conf" 0644
# Copy plugin tree. Decky ships liblsfg-vk.so as symlink; on a fresh clone it may
# dangle and rsync --copy-links aborts. Materialize a real .so (never delete LSFG).
_decky_lsfg="${MOD}/Decky/Plug-ins/.local/lib/liblsfg-vk.so"
_lsfg_for_decky=""
if [[ -f "$R/usr/local/lib/liblsfg-vk.so" ]]; then
  _lsfg_for_decky="$R/usr/local/lib/liblsfg-vk.so"
elif [[ -f /usr/local/lib/liblsfg-vk.so ]]; then
  _lsfg_for_decky=/usr/local/lib/liblsfg-vk.so
fi
if [[ -n "$_lsfg_for_decky" ]]; then
  mkdir -p "$(dirname "$_decky_lsfg")"
  install -m0755 "$_lsfg_for_decky" "$_decky_lsfg"
elif [[ -L "$_decky_lsfg" ]] && [[ ! -e "$_decky_lsfg" ]]; then
  die "liblsfg-vk.so missing for Lossless Scaling: copy liblsfg-vk.so to /usr/local/lib/ on this PC, or restore external-and-mods/Decky/Plug-ins/.local/lib/liblsfg-vk.so from the old build machine"
fi
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
# steamrt expects ~/.steam/steam even when launched via sm8550-launch-steam
if [[ -n "${HOME_DST:-}" && -d "$STEAM_HOME" ]]; then
  bash "${SCRIPT_DIR}/ensure-steam-home-for-image.sh" "$R" "$HOME_DST"
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
"${SCRIPT_DIR}/lib/ensure-ecm-rootfs.sh" "$R" \
  || die "extra-cmake-modules >= 6.5 required for Plasma KCM builds"
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
log "== vendor apps (UFS, MESA, Proton-ARM, Non-Steam, SRM, Lutris, Heroic)"
STEAMOS_HOME="$HOME_DST" "${SCRIPT_DIR}/install-vendor-apps.sh" "$R" \
  || die "vendor apps incomplete"
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

# SSH (enabled; user must set a password before login works).
log "== SSH + power key + Plasma virtual keyboard"
install_file "$OVL/etc/ssh/sshd_config.d/99-sm8550.conf" \
  "$R/etc/ssh/sshd_config.d/99-sm8550.conf" 0644
install_file "$OVL/etc/systemd/logind.conf.d/20-sm8550-power-key.conf" \
  "$R/etc/systemd/logind.conf.d/20-sm8550-power-key.conf" 0644
if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
  install_file "$OVL/etc/systemd/logind.conf.d/20-sm8550-power-key.conf" \
    "$R/var/lib/overlays/etc/upper/systemd/logind.conf.d/20-sm8550-power-key.conf" 0644
  install_file "$OVL/etc/ssh/sshd_config.d/99-sm8550.conf" \
    "$R/var/lib/overlays/etc/upper/ssh/sshd_config.d/99-sm8550.conf" 0644
fi
install_file "$OVL/usr/lib/systemd/system/sm8550-sshd.service" \
  "$R/usr/lib/systemd/system/sm8550-sshd.service" 0644
mkdir -p "$R/etc/systemd/system/multi-user.target.wants" \
  "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/sm8550-sshd.service \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-sshd.service"
ln -sfn /usr/lib/systemd/system/sshd.service \
  "$R/etc/systemd/system/multi-user.target.wants/sshd.service"
ln -sfn /usr/lib/systemd/system/sm8550-sshd.service \
  "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/sm8550-sshd.service"
ln -sfn /usr/lib/systemd/system/sshd.service \
  "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/sshd.service"
if [[ -f "$OVL/etc/xdg/kwinrc" ]]; then
  install_file "$OVL/etc/xdg/kwinrc" "$R/etc/xdg/kwinrc" 0644
  if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
    install_file "$OVL/etc/xdg/kwinrc" \
      "$R/var/lib/overlays/etc/upper/xdg/kwinrc" 0644
  fi
fi
# Do not inject the Steam input context into KWin/startplasma. It causes the
# Plasma session to terminate and SDDM Relogin returns immediately to Game Mode.
rm -f "$R/etc/xdg/plasma-workspace/env/sm8550-plasma-im.sh" \
  "$R/etc/xdg/plasma-workspace/env/sm8550-plasma-portal-perms.sh" \
  "$R/var/lib/overlays/etc/upper/xdg/plasma-workspace/env/sm8550-plasma-im.sh" \
  "$R/var/lib/overlays/etc/upper/xdg/plasma-workspace/env/sm8550-plasma-portal-perms.sh"
if [[ -f "$OVL/etc/xdg/kwinoutputconfig.json" ]]; then
  install_file "$OVL/etc/xdg/kwinoutputconfig.json" \
    "$R/etc/xdg/kwinoutputconfig.json" 0644
fi
for _plasma_steam in sm8550-open-steam-keyboard sm8550-plasma-steam-pre \
  sm8550-plasma-steam-start; do
  install_file "$OVL/usr/lib/steamos/${_plasma_steam}" \
    "$R/usr/lib/steamos/${_plasma_steam}" 0755
done
rm -f "$R/usr/lib/systemd/user/sm8550-plasma-steam.service" \
  "$R/usr/lib/systemd/user/plasma-workspace.target.wants/sm8550-plasma-steam.service"
install_file "$OVL/etc/xdg/autostart/ibus.desktop" \
  "$R/etc/xdg/autostart/ibus.desktop" 0644

# Discover / Flatpak: fusermount setuid + wrappers + offload; no ghost atomupd OTA.
log "== Discover / Flatpak (revokefs fusermount + wrappers)"
install -D -m0755 "$OVL/usr/lib/steamos/sm8550-flatpak-env" \
  "$R/usr/lib/steamos/sm8550-flatpak-env"
install -D -m0644 "$OVL/usr/lib/environment.d/99-sm8550-flatpak.conf" \
  "$R/usr/lib/environment.d/99-sm8550-flatpak.conf"
if [[ -x "$R/usr/bin/flatpak" && ! -f "$R/usr/lib/steamos/flatpak.bin" ]]; then
  cp -a "$R/usr/bin/flatpak" "$R/usr/lib/steamos/flatpak.bin"
fi
install -D -m0755 "$OVL/usr/bin/flatpak" "$R/usr/bin/flatpak"
for _fp in flatpak-system-helper flatpak-session-helper; do
  if [[ -x "$R/usr/lib/${_fp}" && ! -f "$R/usr/lib/steamos/${_fp}.bin" ]]; then
    cp -a "$R/usr/lib/${_fp}" "$R/usr/lib/steamos/${_fp}.bin"
  fi
  install -D -m0755 "$OVL/usr/lib/${_fp}" "$R/usr/lib/${_fp}"
done
chmod 4755 "$R/usr/bin/fusermount" "$R/usr/bin/fusermount3" 2>/dev/null || true
install -D -m0644 \
  "$OVL/usr/lib/systemd/system/flatpak-system-helper.service.d/50-sm8550-path.conf" \
  "$R/usr/lib/systemd/system/flatpak-system-helper.service.d/50-sm8550-path.conf"
install -D -m0644 \
  "$OVL/usr/lib/systemd/user/flatpak-session-helper.service.d/50-sm8550-path.conf" \
  "$R/usr/lib/systemd/user/flatpak-session-helper.service.d/50-sm8550-path.conf"
install -D -m0755 "$OVL/etc/xdg/plasma-workspace/env/sm8550-flatpak-path.sh" \
  "$R/etc/xdg/plasma-workspace/env/sm8550-flatpak-path.sh"
install -D -m0644 "$OVL/etc/xdg/discoverrc" "$R/etc/xdg/discoverrc"
if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
  install -D -m0644 "$OVL/etc/xdg/discoverrc" \
    "$R/var/lib/overlays/etc/upper/xdg/discoverrc"
fi
install -D -m0755 "$OVL/usr/lib/steamos/sm8550-setup-steamos-offload" \
  "$R/usr/lib/steamos/sm8550-setup-steamos-offload"
install -D -m0644 "$OVL/usr/lib/systemd/system/sm8550-setup-steamos-offload.service" \
  "$R/usr/lib/systemd/system/sm8550-setup-steamos-offload.service"
mkdir -p "$R/etc/systemd/system/local-fs.target.wants" \
  "$R/var/lib/overlays/etc/upper/systemd/system/local-fs.target.wants"
ln -sfn /usr/lib/systemd/system/sm8550-setup-steamos-offload.service \
  "$R/etc/systemd/system/local-fs.target.wants/sm8550-setup-steamos-offload.service"
ln -sfn /usr/lib/systemd/system/sm8550-setup-steamos-offload.service \
  "$R/var/lib/overlays/etc/upper/systemd/system/local-fs.target.wants/sm8550-setup-steamos-offload.service"
ln -sfn /usr/lib/systemd/system/steamos-offload.target \
  "$R/etc/systemd/system/local-fs.target.wants/steamos-offload.target" 2>/dev/null || true
# SM8550 has no RAUC image — Discover must not offer atomupd SteamOS OTA.
rm -f "$R/usr/lib/qt6/plugins/discover/steamos-backend.so"
mkdir -p "$R/etc/systemd/system"
ln -sfn /dev/null "$R/etc/systemd/system/atomupd.service"
if [[ -d "$R/var/lib/overlays/etc/upper/systemd/system" ]]; then
  ln -sfn /dev/null \
    "$R/var/lib/overlays/etc/upper/systemd/system/atomupd.service" 2>/dev/null || true
fi
OFFLOAD_ROOT="$(dirname "$HOME_DST")/.steamos/offload"
mkdir -p \
  "${OFFLOAD_ROOT}/var/lib/flatpak" \
  "${OFFLOAD_ROOT}/var/tmp" \
  "${OFFLOAD_ROOT}/var/log"
install -D -m0755 "$OVL/usr/bin/sm8550-fix-discover" "$R/usr/bin/sm8550-fix-discover"
# Box64 = system x86_64 (Decky). Valve FEX stays Steam/Proton-only (RUNSTEAM.sh).
log "== Box64 (Decky PluginLoader; FEX is not global)"
install -D -m0755 "${MOD}/BOX64/update-box64" "$R/usr/bin/update-box64"
if [[ -f "${MOD}/BOX64/install_manifest.txt" ]]; then
  mkdir -p "$R/usr/local/share/box64"
  grep -v 'box64-configurator\.desktop' "${MOD}/BOX64/install_manifest.txt" \
    >"$R/usr/local/share/box64/install_manifest.txt"
fi
if [[ -f "${MOD}/BOX64/update-box64.desktop" ]]; then
  install -D -m0644 "${MOD}/BOX64/update-box64.desktop" \
    "$R/usr/share/applications/update-box64.desktop"
fi
if [[ -x "${SCRIPT_DIR}/build-box64-sm8550.sh" ]]; then
  "${SCRIPT_DIR}/build-box64-sm8550.sh" "$R" \
    || log "WARN: box64 build failed — run update-box64 on the device"
fi
mkdir -p "$R/etc/systemd/system/multi-user.target.wants" \
  "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants"
rm -f "$R/etc/systemd/system/multi-user.target.wants/plugin_loader.service" \
  "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/plugin_loader.service" \
  "$R/var/lib/overlays/etc/upper/systemd/system/plugin_loader.service"
# One-shot cleanup if an older image registered FEX globally. Do not watch for FEX.
ln -sfn /usr/lib/systemd/system/sm8550-fex-binfmt.service \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-fex-binfmt.service"
ln -sfn /usr/lib/systemd/system/sm8550-fex-binfmt.service \
  "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/sm8550-fex-binfmt.service"
rm -f "$R/etc/systemd/system/multi-user.target.wants/sm8550-fex-binfmt.path" \
  "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/sm8550-fex-binfmt.path"
# ldconfig cache is arch-specific; skip. Dynamic linker will still find /usr/lib.

log "== publish boot fixes (OOBE relaunch + Plasma switch + ~/.steam verify)"
export STEAMOS_HOME="$HOME_DST"
# Never publish a login-mode preference captured from the build/test device.
# SDDM already boots gamescope; SteamOSManager must remain free to apply its
# one-shot plasma.desktop selection.
rm -f "$HOME_DST/.config/steamos-manager/state.toml"
bash "${SCRIPT_DIR}/install-oobe-update-fix.sh" "$R"
bash "${SCRIPT_DIR}/install-plasma-desktop-switch.sh" "$R"
bash "${SCRIPT_DIR}/ensure-steam-home-for-image.sh" "$R" "$HOME_DST"
rm -f "$R/usr/share/vulkan/implicit_layer.d/MangoHud-next.aarch64.json" 2>/dev/null || true
bash "${SCRIPT_DIR}/verify-qam-image-contract.sh" "$R" "$HOME_DST"

log "== summary"
{
  echo "gamescope: $(file -b "$R/usr/bin/gamescope")"
  echo "gamescope-md5: $(md5sum "$R/usr/bin/gamescope" | awk '{print $1}')"
  echo "KERNEL:    $(file -b "$R/boot/KERNEL")"
  echo "modules:   $R/usr/lib/modules/7.0.14-edge-sm8550"
  echo "mesa:      $(ls -l "$R/usr/lib/libvulkan_freedreno.so")"
  echo "turnip-md5: $(md5sum "$R/usr/lib/libvulkan_freedreno.so" | awk '{print $1}')"
  echo "mangohud:  $(ls -l "$R/usr/lib/mangohud/lib64/libMangoHud.so" 2>/dev/null || echo missing)"
  echo "display-info.so.3: $(ls -l "$R/usr/lib/libdisplay-info.so.3" 2>/dev/null || echo missing)"
  echo "lsfg:      $(ls -l "$R/usr/local/lib/liblsfg-vk.so" 2>/dev/null || echo missing)"
  echo "fixpad:    $(ls -l "$R/usr/lib/steamos/sm8550-fixpad" 2>/dev/null || echo missing)"
  echo "inputplumber: $(ls -l "$R/usr/bin/inputplumber" 2>/dev/null || echo missing)"
  echo "deck-uhid: $(grep -A2 target_devices "$R/etc/inputplumber/devices.d/02-ayn-odin.yaml" 2>/dev/null || echo missing)"
  echo "touch-dedupe: $(grep -c LIBINPUT_IGNORE_DEVICE "$R/usr/lib/udev/rules.d/72-sm8550-touch-dedupe.rules" 2>/dev/null || echo 0) rules"
  echo "box64:     $(ls -l "$R/usr/local/bin/box64" 2>/dev/null || echo missing)"
  echo "box64fmt:  $(ls -l "$R/etc/binfmt.d/box64.conf" 2>/dev/null || echo missing)"
  echo "discover:  $(ls -l "$R/usr/lib/qt6/plugins/discover/steamos-backend.so" 2>/dev/null || echo removed)"
  echo "offload:   $(ls -ld "$R/home/.steamos/offload/var/lib/flatpak" 2>/dev/null || echo missing)"
  echo "gamescope-touch: $(grep -o 'default-touch-mode [0-9]' "$R/usr/lib/steamos/gamescope-session" 2>/dev/null || echo missing)"
  echo "gamescope-im: $(grep -E 'QT_IM_MODULE|GTK_IM_MODULE' "$R/usr/lib/steamos/gamescope-session" 2>/dev/null | head -2 || echo missing)"
  echo "steamosctl: $(head -1 "$R/usr/bin/steamosctl" 2>/dev/null || echo missing)"
  echo "plasma.desktop: $(grep ^Exec= "$R/usr/share/wayland-sessions/plasma.desktop" 2>/dev/null || echo missing)"
  echo "wayland-client: $(readlink -f "$R/usr/lib/libwayland-client.so.0" 2>/dev/null || echo missing)"
  echo "dot-steam: $(find "$HOME_DST/.steam" -maxdepth 1 -type l 2>/dev/null | wc -l) symlinks"
  echo "home:      $(find "$HOME_DST" -maxdepth 3 -printf '%p\n' | head -40)"
} | tee -a "$LOG"

log "OK"
