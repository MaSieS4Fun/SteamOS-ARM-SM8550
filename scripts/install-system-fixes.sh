#!/usr/bin/env bash
# LSFG-VK shutdown, AYN Thor touch, Decky SM8550 plugins, Return icon.
# Usage: install-system-fixes.sh [rootfs]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
R="$(cd "$R" && pwd)"
MOD="${ROOT}/external-and-mods"
OVL="${ROOT}/odin-overlay"
HOME_DST="${STEAMOS_HOME:-$R/home/steamos}"

log() { echo "== system-fixes: $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "$R/usr" ]] || die "missing rootfs $R"

persist_etc() {
  local rel="$1" src="$2" mode="${3:-0644}"
  local dest="$R/etc/${rel}"
  mkdir -p "$(dirname "$dest")"
  install -m "$mode" "$src" "$dest"
  if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
    mkdir -p "$R/var/lib/overlays/etc/upper/$(dirname "$rel")" 2>/dev/null \
      && install -m "$mode" "$src" "$R/var/lib/overlays/etc/upper/${rel}" \
      || log "WARN: etc overlay upper not writable for ${rel}"
  fi
}

# ── pkexec/sudo setuid (dropped when /usr is copied as a normal user) ──
log "restore pkexec/sudo setuid on next boot"
install -m 0755 "$OVL/usr/lib/steamos/sm8550-restore-privs" \
  "$R/usr/lib/steamos/sm8550-restore-privs"
install -m 0644 "$OVL/usr/lib/systemd/system/sm8550-restore-privs.service" \
  "$R/usr/lib/systemd/system/sm8550-restore-privs.service"
install -m 0755 "$OVL/usr/bin/steamos-set-root-password" \
  "$R/usr/bin/steamos-set-root-password"
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/sm8550-restore-privs.service \
  "$R/etc/systemd/system/multi-user.target.wants/sm8550-restore-privs.service"
if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
  mkdir -p "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants" 2>/dev/null \
    && ln -sfn /usr/lib/systemd/system/sm8550-restore-privs.service \
      "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/sm8550-restore-privs.service" \
    || true
fi

# ── Home partition: grow on first boot (static enable, survives /etc overlay) ──
log "expand-home first-boot (LABEL=home / p3)"
install -m 0755 "$OVL/usr/lib/steamos/steamos-sm8550-expand-home" \
  "$R/usr/lib/steamos/steamos-sm8550-expand-home"
install -m 0644 "$OVL/usr/lib/systemd/system/steamos-sm8550-expand-home.service" \
  "$R/usr/lib/systemd/system/steamos-sm8550-expand-home.service"
mkdir -p "$R/usr/lib/systemd/system/local-fs.target.wants" \
  "$R/usr/lib/systemd/system/multi-user.target.wants" \
  "$R/etc/systemd/system/local-fs.target.wants" \
  "$R/etc/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
  "$R/usr/lib/systemd/system/local-fs.target.wants/steamos-sm8550-expand-home.service"
ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
  "$R/usr/lib/systemd/system/multi-user.target.wants/steamos-sm8550-expand-home.service"
ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
  "$R/etc/systemd/system/local-fs.target.wants/steamos-sm8550-expand-home.service"
ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
  "$R/etc/systemd/system/multi-user.target.wants/steamos-sm8550-expand-home.service"
if [[ -x /usr/bin/growpart ]]; then
  install -D -m 0755 /usr/bin/growpart "$R/usr/bin/growpart"
fi
if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
  mkdir -p "$R/var/lib/overlays/etc/upper/systemd/system/local-fs.target.wants" \
    "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants" 2>/dev/null \
    && ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
      "$R/var/lib/overlays/etc/upper/systemd/system/local-fs.target.wants/steamos-sm8550-expand-home.service" \
    && ln -sfn /usr/lib/systemd/system/steamos-sm8550-expand-home.service \
      "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/steamos-sm8550-expand-home.service" \
    || log "WARN: etc overlay upper not writable for expand-home"
fi

# ── LSFG-VK: from external-and-mods/system-fixes/LSFG-VK ──
log "LSFG-VK plugin_loader drop-ins"
LSFG="${MOD}/system-fixes/LSFG-VK/plugin_loader.service.d"
mkdir -p "$R/usr/share/steamos-odin/plugin_loader.service.d" \
  "$R/etc/systemd/system/plugin_loader.service.d" \
  "$R/usr/lib/systemd/system/plugin_loader.service.d"
rewrite_home() {
  local src="$1" dest="$2"
  python3 - "$src" "$dest" <<'PY'
import re, sys
src, dest = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
# Never match /home/steamos (would become /home/steamosos).
text = re.sub(r"(?<![A-Za-z0-9_])/home/steam(?![A-Za-z0-9_])", "/home/steamos", text)
open(dest, "w", encoding="utf-8").write(text)
PY
  chmod 0644 "$dest"
}
for drop in fast-stop.conf fex-steam-rootfs.conf; do
  if [[ -f "${LSFG}/${drop}" ]]; then
    src="${LSFG}/${drop}"
  else
    src="$OVL/usr/share/steamos-odin/plugin_loader.service.d/${drop}"
  fi
  [[ -f "$src" ]] || continue
  rewrite_home "$src" "$R/usr/share/steamos-odin/plugin_loader.service.d/${drop}"
  rewrite_home "$src" "$R/etc/systemd/system/plugin_loader.service.d/${drop}"
  rewrite_home "$src" "$R/usr/lib/systemd/system/plugin_loader.service.d/${drop}"
done
if [[ -f "$OVL/usr/share/steamos-odin/plugin_loader.service.d/sm8550.conf" ]]; then
  install -m 0644 "$OVL/usr/share/steamos-odin/plugin_loader.service.d/sm8550.conf" \
    "$R/usr/share/steamos-odin/plugin_loader.service.d/sm8550.conf"
  install -m 0644 "$OVL/usr/share/steamos-odin/plugin_loader.service.d/sm8550.conf" \
    "$R/etc/systemd/system/plugin_loader.service.d/sm8550.conf"
  install -m 0644 "$OVL/usr/share/steamos-odin/plugin_loader.service.d/sm8550.conf" \
    "$R/usr/lib/systemd/system/plugin_loader.service.d/sm8550.conf"
fi
if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
  mkdir -p "$R/var/lib/overlays/etc/upper/systemd/system/plugin_loader.service.d" 2>/dev/null \
    && cp -a "$R/etc/systemd/system/plugin_loader.service.d/." \
      "$R/var/lib/overlays/etc/upper/systemd/system/plugin_loader.service.d/" \
    || log "WARN: etc overlay upper not writable for plugin_loader drop-ins"
fi

# ── Thor: stage detector + binaries. Apply the touch fix only on AYN Thor.
# Previous images enabled thorch-* on every SM8550 and broke other panels.
log "AYN Thor touch (detect at boot; ignore unless ayn,thor)"
THOR="${MOD}/system-fixes/Thor"
if [[ -x "${THOR}/install-auto.sh" ]]; then
  "${THOR}/install-auto.sh" --root "$R" || log "WARN: Thor autoinstall staging failed"
  # SteamOS /usr is often read-only. Keep binaries so Thor can run them.
  # Scripts and the unit no-op unless device-tree compatible contains ayn,thor.
  if [[ -d "${THOR}/payload/usr/bin" ]]; then
    install -D -m 0755 "${THOR}/payload/usr/bin/thorch-kwin-touch-map" \
      "$R/usr/bin/thorch-kwin-touch-map"
    install -D -m 0755 "${THOR}/payload/usr/bin/thorch-touchscreen-setup" \
      "$R/usr/bin/thorch-touchscreen-setup"
    install -D -m 0755 "${THOR}/payload/usr/bin/thorch-display-setup" \
      "$R/usr/bin/thorch-display-setup"
  fi
  if [[ -f "${THOR}/payload/usr/lib/systemd/system/thorch-touchscreen-setup.service" ]]; then
    install -D -m 0644 \
      "${THOR}/payload/usr/lib/systemd/system/thorch-touchscreen-setup.service" \
      "$R/usr/lib/systemd/system/thorch-touchscreen-setup.service"
  fi
  # Never enable the Thor touch stack or KDE autostart on the shared image.
  rm -f \
    "$R/etc/xdg/autostart/thorch-kwin-touch-map.desktop" \
    "$R/etc/xdg/autostart/thorch-display-setup.desktop" \
    "$R/etc/udev/rules.d/99-thorch-touchscreen-calibration.rules" \
    "$R/usr/lib/systemd/system/multi-user.target.wants/thorch-touchscreen-setup.service" \
    "$R/etc/systemd/system/multi-user.target.wants/thorch-touchscreen-setup.service"
  mkdir -p "$R/usr/lib/systemd/system/multi-user.target.wants"
  ln -sfn /usr/lib/systemd/system/odin3-thor-autoinstall.service \
    "$R/usr/lib/systemd/system/multi-user.target.wants/odin3-thor-autoinstall.service"
  if [[ -d "$R/var/lib/overlays/etc/upper" ]]; then
    rm -f \
      "$R/var/lib/overlays/etc/upper/xdg/autostart/thorch-kwin-touch-map.desktop" \
      "$R/var/lib/overlays/etc/upper/xdg/autostart/thorch-display-setup.desktop" \
      "$R/var/lib/overlays/etc/upper/udev/rules.d/99-thorch-touchscreen-calibration.rules" \
      "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/thorch-touchscreen-setup.service"
    mkdir -p "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants" \
      2>/dev/null || true
    ln -sfn /usr/lib/systemd/system/odin3-thor-autoinstall.service \
      "$R/var/lib/overlays/etc/upper/systemd/system/multi-user.target.wants/odin3-thor-autoinstall.service" \
      2>/dev/null || true
  fi
else
  log "WARN: Thor install-auto.sh missing"
fi

# ── Decky SM8550 plugins (built dist, no node_modules) ──
log "Stage SM8550 Decky plugins"
BUNDLE="$R/usr/share/steamos-odin/decky-plugins"
mkdir -p "$BUNDLE"
for src in "${MOD}/Decky/sm8550/power-managment" "${MOD}/Decky/sm8550/color-leds"; do
  [[ -f "${src}/plugin.json" && -f "${src}/dist/index.js" ]] || {
    log "WARN: skip $(basename "$src") (not built)"
    continue
  }
  name="$(basename "$src")"
  dest="${BUNDLE}/${name}"
  rm -rf "$dest"
  mkdir -p "$dest"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude node_modules \
      --exclude src \
      --exclude .pnpm-store \
      --exclude __pycache__ \
      --exclude pnpm-lock.yaml \
      "${src}/" "$dest/"
  else
    cp -a "${src}/plugin.json" "${src}/main.py" "${src}/package.json" "$dest/"
    cp -a "${src}/dist" "$dest/"
    [[ -d "${src}/py_modules" ]] && cp -a "${src}/py_modules" "$dest/"
  fi
done
install -m 0755 "$OVL/usr/lib/steamos/sync-decky-bundled-plugins.sh" \
  "$R/usr/lib/steamos/sync-decky-bundled-plugins.sh"
install -m 0755 "$OVL/usr/bin/install-decky" "$R/usr/bin/install-decky"
if [[ -f "$OVL/usr/share/applications/install-decky.desktop" ]]; then
  install -m 0644 "$OVL/usr/share/applications/install-decky.desktop" \
    "$R/usr/share/applications/install-decky.desktop"
fi
if [[ -f "$OVL/usr/share/polkit-1/actions/org.steamos.install-decky.policy" ]]; then
  install -D -m 0644 "$OVL/usr/share/polkit-1/actions/org.steamos.install-decky.policy" \
    "$R/usr/share/polkit-1/actions/org.steamos.install-decky.policy"
fi
mkdir -p "$R/usr/bin/steamos-polkit-helpers"
cat >"$R/usr/bin/steamos-polkit-helpers/install-decky" <<'EOF'
#!/bin/bash
set -eu
if [[ $EUID -ne 0 ]]; then
    exec pkexec --disable-internal-agent "$0" "$@"
fi
exec /usr/bin/install-decky "$@"
EOF
chmod 0755 "$R/usr/bin/steamos-polkit-helpers/install-decky"

# Pre-seed ~/homebrew/plugins even before Decky is installed.
if [[ -d "$HOME_DST" ]]; then
  STEAM_USER=steamos STEAM_HOME="$HOME_DST" BUNDLE_ROOT="$BUNDLE" \
    "$R/usr/lib/steamos/sync-decky-bundled-plugins.sh" || true
fi

# ── Return to Gaming Mode ──
log "Return to Gaming Mode desktop icon"
mkdir -p "$R/etc/skel/Desktop" \
  "$R/etc/xdg/plasma-workspace/env" \
  "$R/usr/share/icons/hicolor/scalable/apps"
install -m 0644 "$OVL/etc/skel/Desktop/Return.desktop" \
  "$R/etc/skel/Desktop/Return.desktop"
install -m 0755 "$OVL/etc/xdg/plasma-workspace/env/set-return-icon.sh" \
  "$R/etc/xdg/plasma-workspace/env/set-return-icon.sh"
persist_etc "skel/Desktop/Return.desktop" "$OVL/etc/skel/Desktop/Return.desktop" 0644
persist_etc "xdg/plasma-workspace/env/set-return-icon.sh" \
  "$OVL/etc/xdg/plasma-workspace/env/set-return-icon.sh" 0755
install -m 0644 "$OVL/usr/share/icons/hicolor/scalable/apps/steamos-gamemode.svg" \
  "$R/usr/share/icons/hicolor/scalable/apps/steamos-gamemode.svg"
install -m 0644 "$OVL/etc/skel/Desktop/Return.desktop" \
  "$R/usr/share/applications/steamos-gamemode.desktop"
mkdir -p "$HOME_DST/Desktop"
install -m 0755 "$OVL/etc/skel/Desktop/Return.desktop" \
  "$HOME_DST/Desktop/Return.desktop"
rm -f "$HOME_DST/Desktop/Decky Loader.desktop" \
      "$HOME_DST/Desktop/install-decky.desktop"

# Handheld: never lock the Plasma session (empty password cannot unlock).
log "Plasma screen lock never"
persist_etc "xdg/kscreenlockerrc" "$OVL/etc/xdg/kscreenlockerrc" 0644
if [[ -f "$OVL/etc/xdg/powerdevilrc" ]]; then
  persist_etc "xdg/powerdevilrc" "$OVL/etc/xdg/powerdevilrc" 0644
fi
mkdir -p "$HOME_DST/.config" "$R/etc/skel/.config"
install -m 0644 "$OVL/etc/xdg/kscreenlockerrc" "$HOME_DST/.config/kscreenlockerrc"
install -m 0644 "$OVL/etc/xdg/kscreenlockerrc" "$R/etc/skel/.config/kscreenlockerrc"
if [[ -f "$OVL/etc/xdg/powerdevilrc" ]]; then
  install -m 0644 "$OVL/etc/xdg/powerdevilrc" "$HOME_DST/.config/powerdevilrc"
  install -m 0644 "$OVL/etc/xdg/powerdevilrc" "$R/etc/skel/.config/powerdevilrc"
fi

# Official Plasma kscreen KCM is installed by build-kscreen-6.2.5.sh
# Do not ship a fake Display Configuration menu.

# Branch selector (rel + beta + preview, no atomupd)
install -m 0755 "$OVL/usr/bin/steamos-select-branch" \
  "$R/usr/bin/steamos-select-branch"

log "done"
