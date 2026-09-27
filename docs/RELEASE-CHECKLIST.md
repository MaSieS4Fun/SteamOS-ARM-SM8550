# Release checklist

Use this checklist for a clean image intended for distribution. Passing the
build scripts alone does not replace the hardware tests.

## 1. Build inputs

- Build on `aarch64`.
- Confirm the official casync bundle/index is present.
- Confirm kernel, gamescope, MangoHud, and Mesa project inputs:

```bash
./scripts/verify-sm8550-prereqs.sh
```

- Confirm `external-and-mods/mesa-sm8550/MANIFEST.sha256` passes:

```bash
(cd external-and-mods/mesa-sm8550 && sha256sum -c MANIFEST.sha256)
```

- Do not export `HOLO_PKG_ALLOW_PLATFORM_REPLACE=1`.
- Use a clean official rootfs when validating a release. Avoid carrying an
  old experimentally modified `rootfs/` into the final image.

## 2. Build

```bash
sudo ./make-steamos-sm8550.sh --img ./steamos-sm8550.img
```

Review `odin-apply.log` and require all of the following:

- project gamescope compiled and installed;
- vendor MangoHud/mangoapp compiled in the target rootfs;
- SM8550 Mesa manifest installed;
- Lutris installed without platform replacement;
- Heroic ARM64 compiled and installed;
- QAM image contract reports `OK`;
- Plasma desktop switch verification reports `OK`;
- no final `ERROR`, failed checksum, or missing required component.

The normal builder creates a tightly sized sparse image with three MBR
partitions. No post-build shrink should be necessary.

## 3. Offline image checks

Attach the image without mounting filesystems:

```bash
loop="$(sudo losetup --find --show --partscan ./steamos-sm8550.img)"
sudo e2fsck -fn "${loop}p2"
sudo e2fsck -fn "${loop}p3"
sudo losetup -d "$loop"
```

Both ext4 checks must complete without filesystem errors.

When inspecting a mounted image, verify:

```bash
readlink -f ROOT/usr/lib/libwayland-client.so.0
md5sum \
  ROOT/usr/lib/libvulkan_freedreno.so \
  ROOT/usr/lib/libEGL_mesa.so.0.0.0 \
  ROOT/usr/lib/libGLX_mesa.so.0.0.0
```

Expected library contract:

- Wayland client resolves to `libwayland-client.so.0.26.0`;
- Turnip MD5 is `1bf0bdda5747eedac3649cae13cdcda0`;
- EGL MD5 is `db5d5a6112625f37183f02cf8891d0f7`;
- GLX MD5 is `e9fcbe0019a965ea82103ef50b19c611`;
- the rest of the Wayland runtime remains the official 1.26 family;
- Vulkan loader remains 1.4.309 and LLVM remains 19.1.

Also verify that the release root does not contain QAM debug flags, persistent
journald configuration, `sm8550-session-switch-listener`, or an enabled
system-wide `plugin_loader.service`.

Verify the session and input contracts:

```bash
! grep -R 'Wants=\(steam\.service\|ibus-gamescope\.service\)' \
  ROOT/usr/lib/systemd/user/gamescope-session.target \
  ROOT/usr/lib/systemd/user/gamescope-session.target.d/

test "$(readlink ROOT/etc/systemd/user/ibus-gamescope.service)" = /dev/null
test -x ROOT/usr/bin/ibus-daemon.real
test -x ROOT/usr/lib/steamos/sm8550-plugin-loader
test -f ROOT/usr/lib/systemd/user/sm8550-plugin-loader.service
test ! -e ROOT/usr/lib/systemd/system/plugin_loader.service
```

A clean image may ship the Decky user unit, but it must not enable that unit
until `~/homebrew/services/PluginLoader` is installed.

## 4. Flash and first boot

Flash only after checking the destination device:

```bash
sudo dd if=./steamos-sm8550.img of=/dev/sdX bs=4M status=progress conv=fsync
```

On hardware:

- allow 2–3 minutes for the first boot;
- complete language, timezone, Wi-Fi, and Steam login;
- confirm the post-Wi-Fi update page completes without a retry loop;
- confirm partition 3 and `/home` grow to the remaining device capacity;
- reboot once and confirm Game Mode starts normally.

## 5. Game Mode tests

- Launch at least one native/Vulkan game.
- Open Home and QAM over the running game.
- Confirm both menus remain above the game and remain interactive.
- Change the performance-overlay level in QAM:
  - level `0` hides mangoapp;
  - non-zero levels show it only over the game;
  - opening Home/QAM does not shrink the game.
- Exit the game and confirm the overlay is not visible over the Steam UI.
- Verify controller, touch, audio, brightness, Wi-Fi, and Bluetooth.
- Connect a USB/Bluetooth keyboard and mouse. Confirm that keys are neither
  duplicated nor left held, then disconnect them and confirm controller/OSK
  input still works.
- Press power briefly and confirm suspend/resume; long press remains poweroff.

## 6. Desktop Mode tests

- Select **Switch to Desktop** and confirm Plasma Wayland starts instead of
  returning to Game Mode.
- Confirm only one Steam client is active and no phantom controller presses
  appear after the transition.
- Open Steam's on-screen keyboard in Plasma.
- Repeat the external keyboard test in Plasma and return to Game Mode without
  phantom controller or keyboard input.
- Install and launch a small Flatpak from Discover.
- Launch Lutris and Heroic.
- Return to Game Mode using the desktop shortcut, then repeat the transition.
- Install Decky from ARM-Manager, enable the bundled LED/Power plugins, and
  reboot. Decky must remain available and Game Mode must not become a black
  screen with a top-left cursor.
- Confirm only one Steam client and one PluginLoader are running in Game Mode.
- Shut down after using LSFG/Decky and confirm no multi-minute service stop
  delay.

## 7. Captured-SD image trimming

This is only for an image captured from a larger card when all unused space is
after the final partition. It does not shrink a partition or filesystem.

Calculate the byte immediately after the last partition:

```bash
img=./captured.img
end_bytes="$(
  sfdisk --json "$img" | python3 -c '
import json, sys
t = json.load(sys.stdin)["partitiontable"]
sector = int(t.get("sectorsize", 512))
print(max((int(p["start"]) + int(p["size"])) * sector
          for p in t["partitions"]))
'
)"
printf 'new image size: %s bytes\n' "$end_bytes"
truncate -s "$end_bytes" "$img"
```

Then run the offline `e2fsck -fn` checks above. Do not use this procedure if
the free space is inside partition 3; shrink ext4 and the partition first, or
prefer rebuilding with `make-steamos-sm8550.sh`.

## 8. Publish

- Remove `.img`, rootfs, chunk caches, build caches, credentials, and logs from
  the Git commit.
- Review `git status` and the complete diff.
- Update release notes and `CREDITS.md` when third-party revisions change.
- Record the image SHA256:

```bash
sha256sum ./steamos-sm8550.img
```
