#!/usr/bin/env bash
# "Switch to Desktop" → Plasma Wayland (not SDDM relogin back to Game Mode).
#
# Steam calls steamosctl switch-to-desktop-mode; wrapper runs sm8550-prepare-plasma
# and sets plasma.desktop before the real steamosctl. Plasma starts via startplasma-wayland
# after clearing Game Mode QT_QPA_PLATFORM=xcb.
#
# Usage: sudo ./scripts/install-plasma-desktop-switch.sh [/run/media/steam/root]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-/run/media/steam/root}"
R="$(cd "$R" && pwd)"
OVL="${ROOT}/odin-overlay"

log() { printf '==> [plasma-switch] %s\n' "$*"; }
die() { printf 'ERROR: [plasma-switch] %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "run as root: sudo $0 $R"
[[ -d "$R/usr" ]] || die "missing root at $R"

install_file() {
  local src="$1" dest="$2" mode="${3:-}"
  [[ -e "$src" ]] || die "missing $src"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  [[ -n "$mode" ]] && chmod "$mode" "$dest"
}

log "restore native steamosctl (same contract as working nofix image)"
steamosctl_elf=""
for cand in \
  "$R/usr/lib/steamos/steamosctl.real.bin" \
  "$R/usr/lib/steamos/steamosctl.real" \
  "$R/usr/bin/steamosctl"
do
  [[ -x "$cand" ]] || continue
  [[ "$(head -c 4 "$cand" | od -An -tx1 | tr -d ' \n')" == 7f454c46 ]] || continue
  steamosctl_elf="$cand"
  break
done
[[ -n "$steamosctl_elf" ]] || die "native steamosctl ELF missing (looked for steamosctl.real.bin)"
if [[ "$steamosctl_elf" != "$R/usr/bin/steamosctl" ]]; then
  install -m 0755 "$steamosctl_elf" "$R/usr/bin/steamosctl"
fi
rm -f "$R/usr/lib/steamos/steamosctl.real"
[[ "$(head -c 4 "$R/usr/bin/steamosctl" | od -An -tx1 | tr -d ' \n')" == 7f454c46 ]] \
  || die "steamosctl is not the native ELF binary"

for f in sm8550-prepare-plasma sm8550-startplasma sm8550-plasma-session; do
  install_file "$OVL/usr/lib/steamos/$f" "$R/usr/lib/steamos/$f" 0755
done
install_file "$OVL/usr/lib/steamos/plasma-stubs/kdeinit5_shutdown" \
  "$R/usr/lib/steamos/plasma-stubs/kdeinit5_shutdown" 0755
install_file "$OVL/usr/lib/steamos/plasma-stubs/qdbus" \
  "$R/usr/lib/steamos/plasma-stubs/qdbus" 0755
install_file "$OVL/usr/lib/steamos/plasma-stubs/kdeinit5_shutdown" \
  "$R/usr/bin/kdeinit5_shutdown" 0755
install_file "$OVL/usr/lib/steamos/sm8550-preserve-sddm-session" \
  "$R/usr/lib/steamos/sm8550-preserve-sddm-session" 0755
install_file "$OVL/usr/lib/steamos/sm8550-reset-sddm-session" \
  "$R/usr/lib/steamos/sm8550-reset-sddm-session" 0755
for unit in \
  sm8550-preserve-sddm-session.path \
  sm8550-preserve-sddm-session.service \
  sm8550-reset-sddm-session.service
do
  install_file "$OVL/usr/lib/systemd/system/$unit" \
    "$R/usr/lib/systemd/system/$unit" 0644
done
install_file "$OVL/usr/bin/steamos-session-select" "$R/usr/bin/steamos-session-select" 0755

install_file "$OVL/usr/share/wayland-sessions/plasma.desktop" \
  "$R/usr/share/wayland-sessions/plasma.desktop" 0644

# Preserve SteamOS Manager's one-shot Plasma selection if SDDM restarts.
install_file "$OVL/usr/lib/systemd/system/sddm.service.d/reset-oneshot-boot.conf" \
  "$R/usr/lib/systemd/system/sddm.service.d/reset-oneshot-boot.conf" 0644

rm -f \
  "$R/etc/systemd/system/graphical.target.wants/sm8550-session-switch-listener.service" \
  "$R/usr/lib/systemd/system/sm8550-session-switch-listener.service" \
  "$R/usr/lib/steamos/sm8550-session-switch-listener" \
  "$R/etc/sddm.conf.d/zzz-sm8550-session-override.conf" \
  "$R/var/lib/overlays/etc/upper/sddm.conf.d/zzz-sm8550-session-override.conf"

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
  plasma-dolphin plasma-ksystemstats plasma-restoresession plasma-baloorunner; do
  mkdir -p "$R/usr/lib/systemd/user/${svc}.service.d"
  install_file "$WAYLAND_DROPIN" \
    "$R/usr/lib/systemd/user/${svc}.service.d/99-odin-wayland.conf" 0644
done

log "hide Frame X11 sessions (Steam was picking plasmax11 → relogin loop)"
mkdir -p "$R/usr/share/steamos/hidden-xsessions"
for s in plasmax11.desktop openbox.desktop openbox-kde.desktop; do
  if [[ -f "$R/usr/share/xsessions/$s" ]]; then
    mv -f "$R/usr/share/xsessions/$s" "$R/usr/share/steamos/hidden-xsessions/$s"
  fi
done

# Plasma desktop helpers. Do not export QT_IM_MODULE=steam globally: KWin is a
# Qt process and the Steam input plugin terminates the whole Plasma session.
rm -f \
  "$R/etc/xdg/plasma-workspace/env/sm8550-plasma-im.sh" \
  "$R/etc/xdg/plasma-workspace/env/sm8550-plasma-portal-perms.sh" \
  "$R/var/lib/overlays/etc/upper/xdg/plasma-workspace/env/sm8550-plasma-im.sh" \
  "$R/var/lib/overlays/etc/upper/xdg/plasma-workspace/env/sm8550-plasma-portal-perms.sh" \
  "$R/usr/lib/systemd/user/plasma-workspace.target.wants/sm8550-plasma-steam.service" \
  "$R/usr/lib/systemd/user/sm8550-plasma-steam.service"
if [[ -f "$OVL/etc/xdg/plasma-workspace/env/set-return-icon.sh" ]]; then
  install_file "$OVL/etc/xdg/plasma-workspace/env/set-return-icon.sh" \
    "$R/etc/xdg/plasma-workspace/env/set-return-icon.sh" 0755
fi

if [[ -f "$OVL/etc/xdg/kwinrc" ]]; then
  install_file "$OVL/etc/xdg/kwinrc" "$R/etc/xdg/kwinrc" 0644
fi

log "verify"
[[ -x "$R/usr/bin/steamosctl" ]] || die "steamosctl missing"
[[ "$(head -c 4 "$R/usr/bin/steamosctl" | od -An -tx1 | tr -d ' \n')" == 7f454c46 ]] \
  || die "steamosctl wrapper still installed"
grep -q sm8550-startplasma "$R/usr/share/wayland-sessions/plasma.desktop" || die "plasma.desktop wrong"
! grep -q '^ExecStartPre=.*zzt-.*temp-login\.conf' \
  "$R/usr/lib/systemd/system/sddm.service.d/reset-oneshot-boot.conf" \
  || die "SDDM still removes SteamOS Manager one-shot session"
grep -q 'sm8550-preserve-sddm-session.path' \
  "$R/usr/lib/systemd/system/sddm.service.d/reset-oneshot-boot.conf" \
  || die "SDDM session preservation path is not enabled"
grep -q 'sm8550-reset-sddm-session.service' \
  "$R/usr/lib/systemd/system/sddm.service.d/reset-oneshot-boot.conf" \
  || die "SDDM boot reset of one-shot Plasma is not enabled"
[[ -x "$R/usr/lib/steamos/sm8550-reset-sddm-session" ]] \
  || die "sm8550-reset-sddm-session missing"
[[ ! -e "$R/var/lib/overlays/etc/upper/sddm.conf.d/zzz-sm8550-session-override.conf" ]] \
  || die "baked image still pins Plasma via overlay SDDM override"
[[ ! -e "$R/usr/lib/systemd/system/sm8550-session-switch-listener.service" ]] \
  || die "experimental SDDM listener still installed"
[[ ! -f "$R/usr/share/xsessions/plasmax11.desktop" ]] || die "plasmax11 still visible"
grep -q 'failed quickly' "$R/usr/lib/steamos/sm8550-startplasma" \
  || die "sm8550-startplasma must fallback to kwin when startplasma-wayland dies immediately"
grep -q 'kwin_wayland --xwayland' "$R/usr/lib/steamos/sm8550-startplasma" \
  || die "sm8550-startplasma missing kwin fallback"
[[ -x "$R/usr/lib/steamos/sm8550-plasma-session" ]] \
  || die "sm8550-plasma-session missing"
log "OK — Switch to Desktop → Plasma Wayland; reboot returns to Game Mode"
