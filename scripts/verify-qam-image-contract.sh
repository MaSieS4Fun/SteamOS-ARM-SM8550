#!/usr/bin/env bash
# Fail image creation if the proven SM8550 Home/QAM stacking contract regresses.
set -euo pipefail

R="${1:?rootfs mount}"
H="${2:?home/steamos path}"
R="${R%/}"
H="${H%/}"
SESSION="$R/usr/lib/steamos/gamescope-session"
ONREADY="$R/usr/lib/steamos/gamescope-onready"
CONFIG="$H/.local/share/Steam/config/config.vdf"
MANGO="$R/usr/share/steamos-odin/MangoHud/steam/MangoHud.conf"

fail() { echo "FAIL [QAM contract]: $*" >&2; exit 1; }

[[ -x "$R/usr/bin/gamescope" ]] || fail "gamescope missing"
grep -qx 'export GAMESCOPE_SM8550_STEAM_INTERNAL_X11=1' "$SESSION" \
  || fail "INTERNAL_X11=1 missing from gamescope-session"
grep -Fq 'sm8550_keep_gamescope_wsi' "$SESSION" \
  || fail "Game Mode does not keep Gamescope WSI for LSFG launches"
if [[ -f "$H/.config/lsfg-vk/conf.toml" ]]; then
  grep -q '^enable_wsi = true$' "$H/.config/lsfg-vk/conf.toml" \
    || fail "lsfg enable_wsi is off; Game Mode stays on the Steam spinner"
fi

for pattern in \
  '/usr/lib/steamos/sm8550-ensure-steam-internal-display.sh' \
  '/usr/lib/steamos/sm8550-steam-display-guard'; do
  ! grep -Fq "$pattern" "$ONREADY" || fail "active onready hook: $pattern"
done
! grep -Fq '/usr/lib/steamos/sm8550-fix-steam-display' "$SESSION" \
  || fail "gamescope-session rewrites config.vdf"
! grep -Fq 'sm8550-fix-steam-display' "$R/usr/lib/steamos/sm8550-relaunch-steam" \
  || fail "OOBE relaunch rewrites config.vdf"

for helper in sm8550-fix-steam-display sm8550-ensure-steam-internal-display.sh \
  sm8550-steam-display-guard; do
  [[ ! -x "$R/usr/lib/steamos/$helper" ]] || fail "automatic helper is executable: $helper"
done

for helper in sm8550-mango-config sm8550-mangoapp; do
  [[ -x "$R/usr/lib/steamos/$helper" ]] || fail "MangoApp helper is not executable: $helper"
done
grep -Fq 'sm8550_xwayland_displays' "$R/usr/lib/steamos/sm8550-mangoapp" \
  || fail "MangoApp does not scan all Gamescope Xwayland displays"
grep -Fq 'GAMESCOPE_FOCUSABLE_APPS' "$R/usr/lib/steamos/sm8550-mangoapp" \
  || fail "MangoApp does not use Gamescope's live game-window list"
grep -Fq '/usr/lib/steamos/sm8550-mangoapp --supervisor' "$ONREADY" \
  || fail "game-only MangoApp supervisor is not started"
grep -Fq '/usr/lib/steamos/sm8550-mangoapp --watch-config' "$ONREADY" \
  || fail "MangoApp QAM preset watcher is not started"

! rg -q 'sm8550-steam-display-guard' \
  "$R/usr/lib/systemd/user/gamescope-session.target.d" \
  "$R/etc/systemd/user" 2>/dev/null \
  || fail "display guard is wanted by the user session"

grep -qx 'control=mangohud' "$MANGO" || fail "MangoHud is not Steam-controlled"
grep -qx 'control=mangohud' "$H/.local/share/Steam/config/mangohud.conf" \
  || fail "Steam MangoHud fallback is not control=mangohud"
grep -q '"IsExternalDisplay"[[:space:]]*"1"' "$CONFIG" \
  || fail "config.vdf does not identify an external nested display"
grep -q 'External: DSI-1 8\\"|||Windowed' "$CONFIG" \
  || fail "config.vdf is not External: DSI-1 Windowed"

resolved="$(readlink -f "$R/usr/lib/libwayland-client.so.0" 2>/dev/null || true)"
[[ "$resolved" == *libwayland-client.so.0.26.0 ]] \
  || fail "libwayland-client.so.0 does not resolve to 0.26.0"
for spec in \
  "libwayland-cursor.so.0:libwayland-cursor.so.0.26.0" \
  "libwayland-server.so.0:libwayland-server.so.0.26.0" \
  "libwayland-egl.so.1:libwayland-egl.so.1.26.0"; do
  link="${spec%%:*}"
  want="${spec##*:}"
  got="$(readlink "$R/usr/lib/$link" 2>/dev/null || true)"
  [[ "$got" == "$want" ]] \
    || fail "$link -> ${got:-missing} (need $want; Lutris left 0.22 and kwin dies)"
done

grep -q 'failed quickly' "$R/usr/lib/steamos/sm8550-startplasma" \
  || fail "sm8550-startplasma must fallback to kwin when startplasma-wayland dies immediately"
grep -q 'kwin_wayland --xwayland' "$R/usr/lib/steamos/sm8550-startplasma" \
  || fail "sm8550-startplasma missing kwin fallback"
[[ -x "$R/usr/lib/steamos/sm8550-plasma-session" ]] \
  || fail "sm8550-plasma-session missing"
[[ -x "$R/usr/lib/steamos/plasma-stubs/kdeinit5_shutdown" ]] \
  || fail "kdeinit5_shutdown stub missing"

for link in steam root sdk32 sdk64 sdkarm64 bin32 bin64 binarm64; do
  [[ -L "$H/.steam/$link" ]] || fail "missing ~/.steam/$link"
done

grep -q 'Retroid Pocket 6' "$R/etc/inputplumber/devices.d/02-ayn-odin.yaml" \
  || fail "InputPlumber composite missing Retroid Pocket 6"
grep -q 'ayn,odin2portal' "$SESSION" \
  || fail "gamescope-session missing Portal/RP6 orientation pin"
[[ -x "$R/usr/lib/steamos/sm8550-thor-gamescope-touch" ]] \
  || fail "sm8550-thor-gamescope-touch missing"
[[ -f "$R/usr/lib/systemd/system/sm8550-thor-gamescope-touch.path" ]] \
  || fail "sm8550-thor-gamescope-touch.path missing"
[[ ! -e "$R/etc/systemd/system/multi-user.target.wants/sm8550-thor-gamescope-touch.path" ]] \
  || fail "Thor Game Mode touch path must not be enabled on the shared image"
[[ "$(readlink -f "$R/etc/systemd/system/adbd-post.service" 2>/dev/null || true)" == /dev/null ]] \
  || fail "Frame adbd-post.service must be masked (infinite ffs.adb/ready wait)"
[[ "$(readlink -f "$R/etc/systemd/system/usb-gadget.target" 2>/dev/null || true)" == /dev/null ]] \
  || fail "Frame usb-gadget.target must be masked"
[[ -x "$R/usr/bin/sm8550-fix-sshd" ]] \
  || fail "sm8550-fix-sshd missing"
[[ "$(tr -d '[:space:]' < "$R/etc/X11/default-display-manager" 2>/dev/null || true)" == /usr/bin/sddm ]] \
  || fail "default-display-manager is not /usr/bin/sddm"
[[ -x "$R/usr/lib/steamos/sm8550-plasma-display" ]] \
  || fail "sm8550-plasma-display missing"
[[ -x "$R/usr/lib/steamos/sm8550-device-profile" ]] \
  || fail "sm8550-device-profile missing"
[[ -f "$R/usr/share/steamos-odin/devices/sm8550-display.conf" ]] \
  || fail "sm8550-display.conf missing"
grep -q 'POWERDEVIL_NO_DDCUTIL=1' \
  "$R/usr/lib/systemd/user/plasma-powerdevil.service.d/99-sm8550-no-ddcutil.conf" \
  || fail "powerdevil still probes dock DDC"
grep -q 'sm8550-plasma-display.service' \
  "$R/usr/lib/systemd/user/plasma-workspace-wayland.target.d/99-odin.conf" \
  || fail "Plasma Wayland session does not start display recovery"
grep -q 'drm_kms_helper.poll=0' "$R/etc/modprobe.d/sm8550-drm-poll.conf" \
  || fail "drm connector poll is not disabled at boot"
[[ -x "$R/usr/lib/steamos/sm8550-drm-poll" ]] \
  || fail "sm8550-drm-poll missing"
grep -Fq 'sm8550-drm-poll on' "$R/usr/lib/steamos/sm8550-prepare-plasma" \
  || fail "Plasma does not enable connector poll for a dock monitor"
[[ -f "$R/usr/lib/systemd/system/sm8550-drm-probe.service" ]] \
  || fail "dock HDMI/DP probe service missing"
grep -Fq 'sm8550-drm-probe.service' \
  "$R/usr/lib/udev/rules.d/99-sm8550-dock-display.rules" \
  || fail "USB-C dock does not probe HDMI/DP"
[[ "$(stat -c '%U:%G' "$R/etc/sudoers.d/sm8550-drm-poll")" == root:root ]] \
  || fail "dock probe sudoers is not owned by root"
grep -Fq 'sm8550-drm-poll off' "$R/usr/bin/steamos-session-select" \
  || fail "return to Game Mode does not stop connector poll"
grep -Fq 'sm8550-force-speaker' "$R/usr/bin/steamos-session-select" \
  || fail "return to Game Mode does not pin speakers before the dock drops"
# Do not pipe strings into grep -q: grep exits at the first match, strings
# gets SIGPIPE, and pipefail reports failure even when the text is present.
grep -a -Fq 'ignoring external connector' "$R/usr/bin/gamescope" \
  || fail "gamescope still probes DP/HDMI in force-internal mode"
! grep -q 'xrandr' "$R/usr/lib/steamos/sm8550-dock-hotplug" \
  || fail "dock hotplug must not probe via xrandr"

POWER_DEVICE="$R/usr/share/steamos-manager/devices/ayn-odin2.toml"
for profile in Performance Balanced Basic; do
  grep -q "name = \"$profile\"" "$POWER_DEVICE" \
    || fail "SteamOS Manager native power profile missing: $profile"
done
grep -Fq '/usr/lib/steamos/sm8550-plugin-loader' \
  "$R/usr/lib/systemd/user/sm8550-plugin-loader.service" \
  || fail "Decky user service does not start PluginLoader through Box64"
[[ -f "$H/homebrew/plugins/power-managment/plugin.json" ]] \
  || fail "SM8550 Power Decky plugin missing"
grep -Fq '.config", "sm8550-power"' \
  "$H/homebrew/plugins/power-managment/py_modules/sm8550_power/config.py" \
  || fail "SM8550 Power still requires the root-owned /var/lib state directory"

echo "OK [QAM contract]: native power profiles + Decky; INTERNAL_X11 + DSI-1 + game-only MangoApp; Plasma kwin fallback + Wayland 0.26"
