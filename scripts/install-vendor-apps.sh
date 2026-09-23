#!/usr/bin/env bash
# Install ARM-Manager / Games launchers into a SteamOS Frame rootfs.
# Reference: SteamOS-Ubuntu install-vendor-arm-manager.sh (no Ubuntu files copied).
#
# Usage: install-vendor-apps.sh [rootfs]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
R="$(cd "$R" && pwd)"
MOD="${ROOT}/external-and-mods"
OVL="${ROOT}/odin-overlay"
HOME_DST="${STEAMOS_HOME:-$R/home/steamos}"

log() { echo "== vendor-apps: $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "$R/usr" ]] || die "missing rootfs $R"

bin="$R/usr/bin"
apps="$R/usr/share/applications"
icons="$R/usr/share/icons/hicolor"
dirs="$R/usr/share/desktop-directories"
menus="$R/etc/xdg/menus/applications-merged"
mkdir -p "$bin" "$apps" "$icons/scalable/apps" "$dirs" "$menus" \
  "$R/usr/share/icons/hicolor/256x256/apps"

# ── ARM-Manager menu ────────────────────────────────────────────────────────
install -m 0644 "$OVL/usr/share/desktop-directories/arm-manager.directory" \
  "$dirs/arm-manager.directory"
install -m 0644 "$OVL/etc/xdg/menus/applications-merged/arm-manager.menu" \
  "$menus/arm-manager.menu"
# Live SteamOS /etc is an overlay; persist the menu in upper too.
if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
  mkdir -p "$R/var/lib/overlays/etc/upper/xdg/menus/applications-merged"
  install -m 0644 "$OVL/etc/xdg/menus/applications-merged/arm-manager.menu" \
    "$R/var/lib/overlays/etc/upper/xdg/menus/applications-merged/arm-manager.menu"
fi

# ── Easy UFS Installer (ARM-Manager, no desktop icon) ───────────────────────
log "Easy UFS Installer"
share_ufs="$R/usr/share/easy-ufs-install"
rm -rf "$share_ufs"
mkdir -p "$share_ufs"
cp -a "${MOD}/ufs-install/." "$share_ufs/"
chmod 0755 "$share_ufs/"*.sh "$share_ufs/"*.py 2>/dev/null || true
cat >"$bin/easy-ufs-installer" <<'EOF'
#!/bin/bash
export EASY_UFS_INSTALL_ROOT=/usr/share/easy-ufs-install
exec python3 "${EASY_UFS_INSTALL_ROOT}/easy-ufs-installer.py" "$@"
EOF
chmod 0755 "$bin/easy-ufs-installer"
for s in install-masios-to-internal ufs-bootimg ufs-diagnose ufs-fix-internal-boot ufs-probe-sizes; do
  if [[ -x "${MOD}/ufs-install/${s}.sh" ]]; then
    cat >"$bin/${s}.sh" <<EOF
#!/bin/bash
exec /usr/share/easy-ufs-install/${s}.sh "\$@"
EOF
    chmod 0755 "$bin/${s}.sh" || true
    ln -sfn "${s}.sh" "$bin/${s}" || true
  fi
done
[[ -f "${MOD}/ufs-install/easy-ufs-installer.svg" ]] && \
  install -m 0644 "${MOD}/ufs-install/easy-ufs-installer.svg" \
    "$icons/scalable/apps/easy-ufs-installer.svg"
install -m 0644 "${MOD}/ufs-install/easy-ufs-installer.desktop" \
  "$apps/easy-ufs-installer.desktop"
rm -f "$HOME_DST/Desktop/Easy UFS Installer.desktop" \
  "$R/etc/skel/Desktop/Easy UFS Installer.desktop"

# ── MESA Easy Manager (ARM-Manager, SteamOS password warning in app) ────────
log "MESA Easy Manager"
share_mesa="$R/usr/share/mesa-easy-manager"
rm -rf "$share_mesa"
mkdir -p "$share_mesa/scripts"
cp -a "${MOD}/MESA-Easy-Manager/mesa_easy_manager" "$share_mesa/"
cp -a "${MOD}/MESA-Easy-Manager/scripts/mesa_easy_privileged.py" "$share_mesa/scripts/"
chmod 0755 "$share_mesa/scripts/mesa_easy_privileged.py"
[[ -f "${MOD}/MESA-Easy-Manager/run.py" ]] && \
  cp -a "${MOD}/MESA-Easy-Manager/run.py" "$share_mesa/"
find "$share_mesa" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
cat >"$bin/mesa-easy-manager" <<'EOF'
#!/bin/bash
export MESA_EASY_MANAGER_ROOT=/usr/share/mesa-easy-manager
export PYTHONPATH="${MESA_EASY_MANAGER_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m mesa_easy_manager "$@"
EOF
chmod 0755 "$bin/mesa-easy-manager"
[[ -f "${MOD}/MESA-Easy-Manager/packaging/mesa-easy-manager.svg" ]] && \
  install -m 0644 "${MOD}/MESA-Easy-Manager/packaging/mesa-easy-manager.svg" \
    "$icons/scalable/apps/mesa-easy-manager.svg"
cat >"$apps/mesa-easy-manager.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=MESA Easy Manager
GenericName=Mesa Freedreno Vulkan Manager
Comment=Requires a user password (SteamOS has none until you set one). Compile/install libvulkan_freedreno.so
Exec=mesa-easy-manager
Icon=mesa-easy-manager
Terminal=false
Categories=System;Settings;X-ARM-Manager;
Keywords=mesa;vulkan;freedreno;adreno;turnip;driver;
StartupNotify=true
EOF

# ── Proton ARM Easy Manager (Games) ─────────────────────────────────────────
log "Proton ARM Easy Manager"
share_proton="$R/usr/share/proton-arm-easy-manager"
rm -rf "$share_proton"
mkdir -p "$share_proton"
cp -a "${MOD}/Proton-ARM-Easy-Manager/proton_arm_easy_manager" "$share_proton/"
[[ -d "${MOD}/Proton-ARM-Easy-Manager/data" ]] && \
  cp -a "${MOD}/Proton-ARM-Easy-Manager/data" "$share_proton/"
[[ -f "${MOD}/Proton-ARM-Easy-Manager/run.py" ]] && \
  cp -a "${MOD}/Proton-ARM-Easy-Manager/run.py" "$share_proton/"
find "$share_proton" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
cat >"$bin/proton-arm-easy-manager" <<'EOF'
#!/bin/bash
export PROTON_ARM_EASY_MANAGER_ROOT=/usr/share/proton-arm-easy-manager
export PYTHONPATH="${PROTON_ARM_EASY_MANAGER_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m proton_arm_easy_manager "$@"
EOF
chmod 0755 "$bin/proton-arm-easy-manager"
if [[ -f "${MOD}/Proton-ARM-Easy-Manager/data/icons/eparm.png" ]]; then
  for size in 16 24 32 48 64 128 256 512; do
    src="${MOD}/Proton-ARM-Easy-Manager/data/icons/eparm-${size}.png"
    [[ -f "$src" ]] || src="${MOD}/Proton-ARM-Easy-Manager/data/icons/eparm.png"
    mkdir -p "$icons/${size}x${size}/apps"
    install -m 0644 "$src" "$icons/${size}x${size}/apps/proton-arm-easy-manager.png"
  done
fi
cat >"$apps/proton-arm-easy-manager.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Proton ARM Easy Manager
Comment=Install and manage ARM64 Proton builds for Steam, Lutris and Heroic
Exec=proton-arm-easy-manager gui
Icon=proton-arm-easy-manager
Terminal=false
Categories=Game;Utility;
Keywords=Proton;Steam;ARM;Wine;Lutris;Heroic;
StartupNotify=true
EOF

# ── ARM Non-Steam Games (Games) ─────────────────────────────────────────────
log "ARM Non-Steam Games"
share_ns="$R/usr/share/no-steam-games"
rm -rf "$share_ns"
mkdir -p "$share_ns"
cp -a "${MOD}/NO_Steam/no_steam_games" "$share_ns/"
[[ -f "${MOD}/NO_Steam/run.py" ]] && cp -a "${MOD}/NO_Steam/run.py" "$share_ns/"
[[ -d "${MOD}/NO_Steam/data" ]] && cp -a "${MOD}/NO_Steam/data" "$share_ns/"
find "$share_ns" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
cat >"$bin/no-steam-games" <<'EOF'
#!/bin/bash
export NO_STEAM_GAMES_ROOT=/usr/share/no-steam-games
export PYTHONPATH="${NO_STEAM_GAMES_ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
exec python3 -m no_steam_games "$@"
EOF
chmod 0755 "$bin/no-steam-games"
if [[ -f "${MOD}/NO_Steam/data/icons/no-steam-games.png" ]]; then
  for size in 16 24 32 48 64 128 256 512; do
    mkdir -p "$icons/${size}x${size}/apps"
    install -m 0644 "${MOD}/NO_Steam/data/icons/no-steam-games.png" \
      "$icons/${size}x${size}/apps/no-steam-games.png"
  done
fi
cat >"$apps/no-steam-games.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=ARM Non-Steam Games
GenericName=Add DRM-free games to Steam
Comment=Add DRM-free games to Steam — assign Proton in Steam for .exe
Exec=no-steam-games gui
Icon=no-steam-games
Terminal=false
Categories=Game;Utility;
Keywords=Steam;Non-Steam;GOG;Proton;ARM;Shortcut;
StartupNotify=true
EOF

# ── Steam ROM Manager icon + menu only (no desktop shortcut) ────────────────
log "Steam ROM Manager icon"
if [[ -d /opt/SteamROMManager ]]; then
  rm -rf "$R/opt/SteamROMManager"
  mkdir -p "$R/opt"
  cp -a /opt/SteamROMManager "$R/opt/SteamROMManager"
  cat >"$bin/steam-rom-manager" <<'EOF'
#!/bin/sh
exec /opt/SteamROMManager/steam-rom-manager --no-sandbox "$@"
EOF
  chmod 0755 "$bin/steam-rom-manager"
fi
if [[ -f "${MOD}/SteamROMManager/steam-rom-manager.png" ]]; then
  for size in 16 24 32 48 64 128 256; do
    mkdir -p "$icons/${size}x${size}/apps"
    install -m 0644 "${MOD}/SteamROMManager/steam-rom-manager.png" \
      "$icons/${size}x${size}/apps/steam-rom-manager.png"
  done
fi
install -m 0644 "$OVL/usr/share/applications/steam-rom-manager.desktop" \
  "$apps/steam-rom-manager.desktop"
rm -f "$HOME_DST/Desktop/Steam ROM Manager.desktop"

# ── Decky in ARM-Manager (keep installer, drop forced desktop copy later) ───
if [[ -f "${MOD}/Decky/decky_installer.desktop" ]]; then
  install -m 0644 "${MOD}/Decky/decky_installer.desktop" "$apps/install-decky.desktop"
  if ! grep -q 'X-ARM-Manager' "$apps/install-decky.desktop"; then
    sed -i 's/^Categories=.*/Categories=System;Utility;X-ARM-Manager;/' \
      "$apps/install-decky.desktop" || true
  fi
fi
if [[ -x "$OVL/usr/bin/install-decky" ]]; then
  install -m 0755 "$OVL/usr/bin/install-decky" "$bin/install-decky"
elif [[ -x "$bin/install-decky" ]]; then
  true
fi

rm -f "$apps/sm8550-display-setup.desktop" \
      "$apps/sm8550-display-scale.desktop" \
      "$bin/sm8550-display-setup"
rm -f "$HOME_DST/Desktop/Decky Loader.desktop"
mkdir -p "$HOME_DST/Desktop"
install -m 0755 "$OVL/etc/skel/Desktop/Return.desktop" \
  "$HOME_DST/Desktop/Return.desktop"
if [[ -f "$OVL/usr/share/applications/install-decky.desktop" ]]; then
  install -m 0644 "$OVL/usr/share/applications/install-decky.desktop" \
    "$apps/install-decky.desktop"
fi

# ── Plasma scale 125% (DSI-1 1080x1920 rotated; 250–300% is unusable) ───────
log "Plasma scale 125%"
mkdir -p "$HOME_DST/.config" "$R/etc/xdg"
install -m 0644 "$OVL/etc/xdg/kwinoutputconfig.json" \
  "$HOME_DST/.config/kwinoutputconfig.json"
install -m 0644 "$OVL/etc/xdg/kwinoutputconfig.json" \
  "$R/etc/xdg/kwinoutputconfig.json"
# Merge scale into existing kwinrc / kdeglobals (do not replace Vapor).
if [[ -f "$R/etc/xdg/kwinrc" ]]; then
  if grep -q '^\[Xwayland\]' "$R/etc/xdg/kwinrc"; then
    if grep -q '^Scale=' "$R/etc/xdg/kwinrc"; then
      sed -i 's/^Scale=.*/Scale=1.25/' "$R/etc/xdg/kwinrc"
    else
      sed -i '/^\[Xwayland\]/a Scale=1.25' "$R/etc/xdg/kwinrc"
    fi
  else
    printf '\n[Xwayland]\nScale=1.25\n' >>"$R/etc/xdg/kwinrc"
  fi
fi
if [[ -f "$R/etc/xdg/kdeglobals" ]] && ! grep -q '^\[KScreen\]' "$R/etc/xdg/kdeglobals"; then
  printf '\n[KScreen]\nScaleFactor=1.25\nScreenScaleFactors=DSI-1=1.25\n' >>"$R/etc/xdg/kdeglobals"
fi
mkdir -p "$HOME_DST/.config"
cat >"$HOME_DST/.config/kwinrc" <<'EOF'
[Desktops]
Number=1
Rows=1

[Xwayland]
Scale=1.25
EOF
if [[ -f "$HOME_DST/.config/kdeglobals" ]]; then
  if grep -q '^\[KScreen\]' "$HOME_DST/.config/kdeglobals"; then
    sed -i 's/^ScaleFactor=.*/ScaleFactor=1.25/' "$HOME_DST/.config/kdeglobals" || true
  else
    printf '\n[KScreen]\nScaleFactor=1.25\nScreenScaleFactors=DSI-1=1.25\n' >>"$HOME_DST/.config/kdeglobals"
  fi
else
  printf '[KScreen]\nScaleFactor=1.25\nScreenScaleFactors=DSI-1=1.25\n' >"$HOME_DST/.config/kdeglobals"
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f "$icons" >/dev/null 2>&1 || true
fi

log "done"
