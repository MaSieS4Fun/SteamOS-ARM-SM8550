#!/usr/bin/env bash
# Bake SM8550 input stack into a rootfs at image-build time (not at user boot).
# - udev: ghost touchpad ignore, gamepad, external HID
# - InputPlumber: deck-uhid + keyboard (OSK haptics)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:?rootfs path required}"
OVL="${ROOT}/odin-overlay"

log() { printf '==> [sm8550-input] %s\n' "$*"; }
die() { printf 'ERROR: [sm8550-input] %s\n' "$*" >&2; exit 1; }

[[ -d "${R}/usr" ]] || die "not a rootfs: ${R}"

install_file() {
  local src="$1" dest="$2" mode="${3:-}"
  [[ -e "$src" ]] || die "missing $src"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  [[ -n "$mode" ]] && chmod "$mode" "$dest"
}

log "udev rules (70 gamepad, 71 ext-hid hotplug)"
mkdir -p "${R}/usr/lib/udev/rules.d" "${R}/lib/udev/rules.d"
for rule in 70-sm8550-gamepad.rules 71-sm8550-ext-hid.rules; do
  install_file "${OVL}/usr/lib/udev/rules.d/${rule}" \
    "${R}/usr/lib/udev/rules.d/${rule}" 0644
  install_file "${OVL}/usr/lib/udev/rules.d/${rule}" \
    "${R}/lib/udev/rules.d/${rule}" 0644
done
rm -f "${R}/usr/lib/udev/rules.d/72-sm8550-touch-dedupe.rules" \
  "${R}/lib/udev/rules.d/72-sm8550-touch-dedupe.rules"

log "InputPlumber composite (deck-uhid + keyboard)"
install -d "${R}/etc/inputplumber/devices.d" \
  "${R}/etc/inputplumber/capability_maps.d" \
  "${R}/usr/share/inputplumber/capability_maps" \
  "${R}/usr/lib/systemd/system/inputplumber.service.d"
install_file "${OVL}/etc/inputplumber/devices.d/02-ayn-odin.yaml" \
  "${R}/etc/inputplumber/devices.d/02-ayn-odin.yaml" 0644
install_file "${OVL}/etc/inputplumber/capability_maps.d/ayn_mcu.yaml" \
  "${R}/etc/inputplumber/capability_maps.d/ayn_mcu.yaml" 0644
install_file "${OVL}/etc/inputplumber/capability_maps.d/ayn_mcu.yaml" \
  "${R}/usr/share/inputplumber/capability_maps/ayn_mcu.yaml" 0644
install_file "${OVL}/usr/lib/systemd/system/inputplumber.service.d/99-sm8550.conf" \
  "${R}/usr/lib/systemd/system/inputplumber.service.d/99-sm8550.conf" 0644

log "InputPlumber ext-hid helper (udev 71 only — no boot race with yaml keyboard target)"
install_file "${OVL}/usr/lib/steamos/sm8550-inputplumber-ext-hid" \
  "${R}/usr/lib/steamos/sm8550-inputplumber-ext-hid" 0755
install_file "${OVL}/usr/lib/systemd/system/sm8550-inputplumber-ext-hid.service" \
  "${R}/usr/lib/systemd/system/sm8550-inputplumber-ext-hid.service" 0644
rm -f "${R}/usr/lib/steamos/sm8550-inputplumber-osk" \
  "${R}/usr/lib/steamos/sm8550-inputplumber-common.sh"
rm -f "${R}/etc/systemd/system/multi-user.target.wants/sm8550-inputplumber-ext-hid.service"

# Drop Ubuntu-named composites if a tarball left them behind.
rm -f "${R}/etc/inputplumber/devices.d/"*mouse* \
  "${R}/etc/inputplumber/devices.d/02-ayn-controller.yaml" \
  "${R}/etc/inputplumber/devices.d/01-ayn-controller.yaml"

# No runtime udev installers — rules must already be in the image.
rm -f "${R}/usr/lib/steamos/sm8550-touch-dedupe" \
  "${R}/usr/lib/systemd/system/sm8550-touch-dedupe.service" \
  "${R}/etc/systemd/system/multi-user.target.wants/sm8550-touch-dedupe.service"

log "steamosctl wrapper (prepare-plasma before desktop switch)"
if [[ -x "${R}/usr/bin/steamosctl" && ! -x "${R}/usr/lib/steamos/steamosctl.real" ]]; then
  if ! head -1 "${R}/usr/bin/steamosctl" | grep -q bash; then
    mv "${R}/usr/bin/steamosctl" "${R}/usr/lib/steamos/steamosctl.real"
  fi
fi
install_file "${OVL}/usr/bin/steamosctl" "${R}/usr/bin/steamosctl" 0755

log "IBus disabled in Game Mode (USB/OSK key duplication)"
install_file "${OVL}/usr/lib/steamos/sm8550-ibus-daemon" \
  "${R}/usr/lib/steamos/sm8550-ibus-daemon" 0755
if [[ -x "${R}/usr/bin/ibus-daemon" && ! -e "${R}/usr/bin/ibus-daemon.real" ]]; then
  if ! grep -q sm8550-ibus-daemon "${R}/usr/bin/ibus-daemon" 2>/dev/null; then
    mv "${R}/usr/bin/ibus-daemon" "${R}/usr/bin/ibus-daemon.real"
  fi
fi
if [[ -x "${R}/usr/bin/ibus-daemon.real" ]]; then
  install_file "${OVL}/usr/lib/steamos/sm8550-ibus-daemon" \
    "${R}/usr/bin/ibus-daemon" 0755
fi
install_file "${OVL}/usr/share/dbus-1/services/org.freedesktop.IBus.service" \
  "${R}/usr/share/dbus-1/services/org.freedesktop.IBus.service" 0644
install_file "${OVL}/usr/lib/systemd/user/ibus-gamescope.service" \
  "${R}/usr/lib/systemd/user/ibus-gamescope.service" 0644
install_file "${OVL}/usr/lib/systemd/user/ibus-gamescope.service.d/99-sm8550-disable.conf" \
  "${R}/usr/lib/systemd/user/ibus-gamescope.service.d/99-sm8550-disable.conf" 0644
mkdir -p "${R}/etc/systemd/user"
ln -sfn /dev/null "${R}/etc/systemd/user/ibus-gamescope.service"
if [[ -d "${R}/var/lib/overlays/etc/upper" ]]; then
  mkdir -p "${R}/var/lib/overlays/etc/upper/systemd/user"
  ln -sfn /dev/null \
    "${R}/var/lib/overlays/etc/upper/systemd/user/ibus-gamescope.service"
fi
install_file "${OVL}/usr/lib/systemd/user/gamescope-session.service.d/99-odin.conf" \
  "${R}/usr/lib/systemd/user/gamescope-session.service.d/99-odin.conf" 0644

log "OK — input stack baked into ${R}"
