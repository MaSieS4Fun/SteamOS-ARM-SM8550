# Build and SM8550 integration notes

This document describes the production image path. Older `QAM-*` documents
record investigations and are not build instructions.

## Production build

Build on an `aarch64` Linux host:

```bash
sudo ./make-steamos-sm8550.sh
```

Useful variants:

```bash
# Reuse an already assembled/extracted official rootfs.
sudo ./make-steamos-sm8550.sh --skip-download

# Reuse existing gamescope and MangoHud build products.
sudo ./make-steamos-sm8550.sh --skip-download --skip-build

# Pack the current rootfs without applying the overlay again.
sudo ./make-steamos-sm8550.sh --image-only

# Select the output file.
sudo ./make-steamos-sm8550.sh --img /path/to/steamos-sm8550.img
```

`--skip-build` runs `scripts/verify-sm8550-prereqs.sh`. Do not use it after
changing gamescope or MangoHud sources unless those components have already
been rebuilt.

Lutris and Heroic require network access while baking the image. They can be
omitted independently:

```bash
sudo SKIP_LUTRIS=1 ./make-steamos-sm8550.sh --skip-download
sudo SKIP_HEROIC=1 ./make-steamos-sm8550.sh --skip-download
```

The default pipeline is:

1. Reconstruct the official Frame/Deckard rootfs from the casync index.
2. Run `scripts/apply-odin-mods.sh`.
3. Install the first-boot runtime and InputPlumber integration.
4. Create an MBR image with `BOOT`, `root`, and `home`.
5. Repack `BOOT/KERNEL` with the generated root UUID.

The output is sparse and tightly sized. The `home` partition grows to the
remaining device capacity on first boot.

## Built and installed components

The following components are built from source during the normal image build:

- gamescope from `external-and-mods/gamescope/`, using
  `scripts/build-gamescope-sm8550.sh`;
- MangoHud and mangoapp from `external-and-mods/MangoHud/`, built inside the
  target rootfs by `scripts/build-vendor-mangohud.sh`;
- Heroic Games Launcher for Linux ARM64, using Node 22 and pnpm 10 through
  `scripts/install-heroic-into-rootfs.sh`;
- Box64 and, when absent, libiio;
- selected Plasma components only when the official rootfs does not provide a
  compatible version.

The following are installed rather than compiled:

- the prebuilt SM8550 kernel from
  `external-and-mods/kernel/output/7.0.14-edge-sm8550/`;
- the verified Turnip/OpenGL binaries from
  `external-and-mods/mesa-sm8550/`;
- InputPlumber from its ARM64 release plus the local SM8550 input overlay;
- Lutris as the Arch Linux ARM `noarch` package and its Python dependencies.

Lutris is not compiled. It is absent from the configured Holo repositories, so
`scripts/install-lutris-into-rootfs.sh` uses the shared package extractor in
`scripts/lib/holo-pkg-install.sh`. That extractor installs application
dependencies without running the target rootfs `pacman` on the host.

## Graphics platform contract

The working image depends on one coherent platform stack:

- the complete Wayland 1.26 runtime family;
- Vulkan loader 1.4.309;
- LLVM 19.1;
- the project Turnip and OpenGL libraries;
- stock Frame gallium (`libgallium-26.3.0-devel.so`).

`scripts/install-mesa-sm8550.sh` installs the verified Turnip, EGL, GLX, GBM,
DRI, and `libwayland-client.so.0.26.0` files. The remaining Wayland, Vulkan,
LLVM, systemd, and GLVND files must remain those from the official rootfs.

Installing generic Arch Linux ARM platform packages caused a mixed stack
(Wayland 0.26 client with 0.22 server/cursor/EGL, Vulkan 1.3, and LLVM 17).
The result was Plasma returning immediately to Game Mode and, in some builds,
black-screen or compositor failures.

Normal builds prevent this in `scripts/lib/holo-pkg-install.sh`. It treats the
existing `mesa`, `wayland`, `vulkan-icd-loader`, `llvm-libs`, `systemd`,
`systemd-libs`, and `libglvnd` as already satisfied.

> [!CAUTION]
> `HOLO_PKG_ALLOW_PLATFORM_REPLACE=1` is diagnostic-only. Never set it for a
> production build or while installing Lutris/Plasma applications.

Verified SM8550 library MD5 values:

- Turnip `libvulkan_freedreno.so`: `1bf0bdda5747eedac3649cae13cdcda0`
- EGL `libEGL_mesa.so.0.0.0`: `db5d5a6112625f37183f02cf8891d0f7`
- GLX `libGLX_mesa.so.0.0.0`: `e9fcbe0019a965ea82103ef50b19c611`

The authoritative file list is
`external-and-mods/mesa-sm8550/MANIFEST.sha256`.

## Final runtime fixes

### Game Mode, QAM, and MangoHud

- Steam runs on Gamescope's internal Xwayland contract
  (`GAMESCOPE_SM8550_STEAM_INTERNAL_X11=1`).
- `gamescope-session.target` must not depend on `steam.service`. Steam is
  launched exactly once by `gamescope-onready` through
  `sm8550-launch-steam`. Starting both paths creates two clients controlling
  the same UI and controller; after Decky enables CEF debugging this commonly
  appears as a black screen with a cursor in the top-left corner.
- Steam's display seed is `External: DSI-1 8"|||Windowed`. Automatic
  `config.vdf` display guards are deliberately not used.
- mangoapp is a Gamescope external overlay and never claims Steam's
  `STEAM_OVERLAY` plane. This keeps Home/QAM above the game.
- `sm8550-mangoapp --supervisor` keeps mangoapp available, while
  `--watch-config` mirrors the QAM preset. Preset `0` hides it; non-zero
  presets are shown only while a real game is focused.
- Game detection scans every Gamescope Xwayland display and uses the live
  `GAMESCOPE_FOCUSABLE_APPS` list. A stale focused-app atom must not keep the
  HUD visible after the game exits.
- MangoHud libraries live under `/usr/lib/mangohud/lib64`; stale global copies
  under `/usr/lib` are removed.

The final contract is checked by `scripts/verify-qam-image-contract.sh`.

### Switching to Plasma

`scripts/install-plasma-desktop-switch.sh` keeps the native `steamosctl`,
provides a Plasma Wayland session, preserves SteamOS Manager's one-shot SDDM
selection, and clears Game Mode's `QT_QPA_PLATFORM=xcb` before Plasma starts.
X11 Plasma entries and the experimental session-switch listener are removed.

Decky/LSFG runs through `sm8550-plugin-loader.service`, a user service tied to
`gamescope-session.target`. `install-decky` creates its target link only after
PluginLoader is installed. The service invokes the x86_64 loader explicitly
through the Box64 wrapper and its complete process tree is stopped before a
session change.

The legacy root-level `plugin_loader.service`, its drop-ins, and its
`multi-user.target` link must not exist. That service survived session changes,
could launch a second loader, and was often regenerated with a broken
`/usr/bin/box64` or `home.mount` dependency. `install-decky verify` now repairs
the user-service model rather than recreating the legacy service.

The Steam desktop keyboard is enabled through the stock Plasma Steam client
and IBus integration. Never export `QT_IM_MODULE=steam` globally: KWin is a Qt
process and the plugin can terminate the whole Plasma session.

### Applications and Flatpak

- Lutris is installed without replacing platform graphics packages.
- Heroic is compiled and installed in `/opt/Heroic`.
- Flatpak/Discover uses the SteamOS offload location and restores the required
  `fusermount` privileges.
- Phantom SteamOS updates in Discover are disabled because this image does not
  use atomupd/RAUC for OS updates.

### First boot, power, and input

- The OOBE update shim handles Steam's post-Wi-Fi update request and relaunches
  Steam instead of looping against the stub `steam.service`.
- `steamos-sm8550-expand-home.service` grows partition 3 and its ext4
  filesystem on first boot.
- logind maps a short power-key press to suspend and a long press to poweroff.
- InputPlumber exposes the Deck-compatible controller; `sm8550-fixpad`
  normalizes the native stick range. Its virtual `keyboard` target is removed
  while a real USB/Bluetooth keyboard or mouse is attached and restored after
  the last external HID is removed.
- Game Mode masks `ibus-gamescope.service` and uses the session-aware
  `sm8550-ibus-daemon` wrapper. The original IBus executable remains available
  as `ibus-daemon.real` for Plasma. Running Steam OSK and IBus XIM together in
  Game Mode duplicates physical and on-screen keyboard events and can leave a
  key apparently held.
- AYN Thor touch changes are staged but enabled only when device tree reports
  `ayn,thor`.

### Logging policy

Production images use journald's volatile default. QAM debug flags, persistent
journals, boot-marker services, test backups, and session log redirections are
not part of the image. Use `scripts/sd-debug-boot.sh` only for an explicit
diagnostic build.

## Do not reintroduce

- automatic Steam display guards that rewrite `config.vdf`;
- a permanent global MangoHud Vulkan layer for the whole session;
- mangoapp as `STEAM_OVERLAY`;
- `Wants=steam.service` or `Wants=ibus-gamescope.service` in
  `gamescope-session.target`;
- global Plasma `QT_QPA_PLATFORM=xcb` or `QT_IM_MODULE=steam`;
- a system-wide PluginLoader alongside the Game Mode user service;
- FEX as the global x86_64 binfmt handler in place of Box64;
- generic Arch Mesa, Wayland, Vulkan loader, LLVM, systemd, or GLVND packages;
- persistent diagnostic logging in release images.
