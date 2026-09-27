# SteamOS-ARM-SM8550

Official **SteamOS ARM** userspace (Valve Frame / Deckard) adapted for
Qualcomm **SM8550** / Adreno 740 handhelds.

This is **not** an Ubuntu remix. Game Mode is gamescope + Steam Gamepad UI.
Desktop Mode is the official SteamOS **KDE Plasma** session.

The SM8550 kernel and the bundled Decky power / LED plugins come from the
previous project **[SteamOS-Ubuntu](https://github.com/MaSieS4Fun/SteamOS-Ubuntu)**.
Full attribution: [`CREDITS.md`](CREDITS.md).

---

### Join the community on [Discord](https://discord.gg/Mqegm7PvV9).

---

> [!WARNING]
> - Before a public image is released, it is tested on hardware.
> - Functionality tests have been carried out on the **AYN Odin 2**.
> - Other devices below share the same SoC and ABL; some features may be
>   incomplete or untested on those models.
> - The first boot can take **2–3 minutes**. Please be patient.

SteamOS-ARM-SM8550 boots with **ROCKNIX ABL** (not EFI). If ABL is already
installed and the device model is selected, flash the image to a microSD
card and boot Linux.

# Supported devices

| Device | Status |
|--------|--------|
| AYN Odin 2 | Supported - Tested |
| AYN Odin 2 Portal | Supported - Untested |
| AYN Odin 2 Mini | Supported - Untested |
| AYN Thor | Supported - Untested |
| Retroid Pocket 6 | Supported - Partial issues |
| AYANEO Pocket EVO | Supported - Untested |
| AYANEO Pocket ACE | Supported - Untested |
| AYANEO Pocket DS | Supported - Untested |
| AYANEO Pocket DMG | Supported - Untested |
| AYANEO Pocket S 2K | Supported - Untested |
---

### System user

| | |
|--------|--------|
| user | `steamos` |
| password | Set during first-boot Steam setup (empty until then) |

First boot is a clean Steam Deck-style OOBE: language, timezone, Wi-Fi,
then Steam login. The `home` partition grows to the rest of the card.

# What this image includes

- Official SteamOS ARM Game Mode (gamescope DRM + Steam Gamepad UI)
- Official SteamOS Plasma desktop (kscreen + NetworkManager applets)
- Kernel **7.0.14-edge-sm8550** from [SteamOS-Ubuntu](https://github.com/MaSieS4Fun/SteamOS-Ubuntu) / [MaSi-OS Kernel Updater](https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater)
- InputPlumber `deck-uhid` (Valve Steam Deck controller) + OSK haptics
- USB / Bluetooth keyboard and mouse: virtual OSK keyboard is disabled
  while they are connected, then restored on unplug; Game Mode IBus is isolated
  to prevent duplicate or stuck keys
- Decky plugins **SM8550-Power** and **SM8550-LED** (from SteamOS-Ubuntu;
  design based on [Hooandee](https://github.com/Hooandee))
- Easy UFS Installer: internal install as `ROCKNIX` + `STORAGE` + `HOME`
- Box64 (for Decky / x86_64 helpers), MangoHud, lsfg-vk, ARM-Manager apps
- **Lutris** (open gaming platform) and **Heroic Games Launcher** (Epic/GOG/Amazon;
  built for linux arm64 at image bake — no official ARM AppImage)

# Decky Loader

- Decky PluginLoader is x86_64. This image ships **Box64** (system binfmt) so
  the loader can run on aarch64.
- Decky runs as a user service tied to Game Mode. The installer removes the
  legacy system-wide PluginLoader, so Decky survives reboot without leaving
  LSFG processes behind during session changes.
- **Valve FEX-Emu** (from Steam when forcing Proton x86_64) is for games only —
  it must not replace Box64 globally. See [docs/DECKY-BOX64-FEX.md](docs/DECKY-BOX64-FEX.md).
- Install Decky from ARM-Manager. If Decky stops after a Steam update:
  `pkexec /usr/lib/steamos/sm8550-restore-decky-box64`
- **Discover / Flathub:** if installs fail with `revokefs-fuse`, see
  [docs/DISCOVER-FLATPAK.md](docs/DISCOVER-FLATPAK.md). Ghost “SteamOS”
  updates in Discover are disabled (no atomupd on this image).
- **SM8550-Power** (CPU/GPU profiles, fan, thermals) and **SM8550-LED**
  (controller RGB) are bundled from
  [SteamOS-Ubuntu](https://github.com/MaSieS4Fun/SteamOS-Ubuntu).
  Those plugins are based on [Hooandee's plugins](https://github.com/Hooandee).

# Installation

- Install [ROCKNIX ABL](https://github.com/ROCKNIX/abl) first.
- You can use the ABL installation [scripts from Android](https://github.com/user-attachments/files/31857066/rocknix_abl.zip).
  Place the `abl_signed-SM8550.elf` ABL file inside that folder.
- After ABL is installed: **Set the Device** → your exact model → Linux → START.
  The wrong model (for example Odin 2 vs Mini) is a black screen before Linux.
- Flash a release image with [balenaEtcher](https://etcher.balena.io/) or
  [Rufus](https://rufus.ie/) onto a microSD card.
- Insert the card and boot.

Images will be attached to [Releases](https://github.com/MaSieS4Fun/SteamOS-ARM-SM8550/releases)
when a build is published. This repository stays **private** while the first
release and this README are adjusted.

## Image layout

| Partition | Filesystem | Role |
|-----------|------------|------|
| p1 `BOOT` | FAT32 | ABL `KERNEL` (not a Steam Deck ESP) |
| p2 `root` | ext4 | Official SteamOS userspace + SM8550 overlay |
| p3 `home` | ext4 | `/home/steamos`, grown on first boot |

This matches SteamOS PC/handheld (root + home), not Steam Deck A/B.

## Internal UFS

From SteamOS on microSD, open **Easy UFS Installer** (ARM-Manager) or run
the scripts in `external-and-mods/ufs-install/`. That installer writes
three Linux partitions next to Android: **ROCKNIX** + **STORAGE** + **HOME**.
See that folder's README. It **repartitions UFS** and can wipe Android
userdata.

# This repository

This tree is the **build sources and SM8550 overlay**. It does **not**
contain the official SteamOS rootfs, RAUC chunks, Steam client zips, or
packed `.img` files (Valve terms; also too large for Git).

| Path | Contents |
|------|----------|
| `make-steamos-sm8550.sh` | Download / apply / pack the flashable image |
| `odin-overlay/` | SM8550 SteamOS overlay (systemd, InputPlumber, sessions) |
| `scripts/` | Apply overlay, Steam client, Plasma extras, vendor apps |
| `external-and-mods/kernel/` | SM8550 kernel from SteamOS-Ubuntu |
| `external-and-mods/Decky/` | SM8550-Power and SM8550-LED (from SteamOS-Ubuntu) |
| `external-and-mods/ufs-install/` | Easy UFS Installer |
| `external-and-mods/system-fixes/` | LSFG-VK and AYN Thor touch extras |
| `external-and-mods/mesa-sm8550/` | Turnip + OpenGL + wayland verified on Odin 2 |

## Building an image

On an **aarch64** Linux host. The image always uses **project** binaries, not
stock rootfs gamescope/Mesa:

Detailed build architecture and the final fixes are documented in
[`docs/BUILD-AND-FIXES.md`](docs/BUILD-AND-FIXES.md). Before publishing an
image, follow [`docs/RELEASE-CHECKLIST.md`](docs/RELEASE-CHECKLIST.md).

| Component | Source | Notes |
|-----------|--------|-------|
| gamescope | `external-and-mods/gamescope/build/` | SM8550 patches (backlight, rotation, QAM) |
| MangoHud | `external-and-mods/MangoHud/` | Built in chroot during apply (kgsl temp/MHz) |
| Mesa | `external-and-mods/mesa-sm8550/` | Turnip + OpenGL + wayland only; gallium stays stock |

**Build the flashable image** (compiles gamescope + MangoHud automatically):

```bash
sudo ./make-steamos-sm8550.sh
# or, if the official rootfs was already extracted:
sudo ./make-steamos-sm8550.sh --skip-download
```

During `apply-odin-mods.sh` you should see:

1. `COMPILE gamescope` — `external-and-mods/gamescope` (meson + ninja)
2. `COMPILE MangoHud` — `external-and-mods/MangoHud` (meson + ninja in rootfs chroot)
3. Mesa SM8550 install + overlay copy

To skip recompiles when binaries are already fresh:

```bash
sudo ./make-steamos-sm8550.sh --skip-download --skip-build
```

Manual preflight (optional, used with `--skip-build`):

```bash
./scripts/verify-sm8550-prereqs.sh
```

Checksums are stamped under `/usr/share/steamos-odin/gamescope-sm8550.txt` and
`mesa-sm8550.txt`.

**Display policy:** Game Mode defaults to the internal DSI panel
(`GAMESCOPE_FORCE_INTERNAL=1`). To paint on a dock monitor (DP/HDMI) for
debugging, enable `SM8550_DOCK_DISPLAY=1` (see
`odin-overlay/usr/lib/systemd/user/gamescope-session.service.d/50-sm8550-dock-display.conf.example`).

Mesa overrides replace only `libvulkan_freedreno.so`, the OpenGL stack
(EGL/GLX/GBM/DRI), and the verified Wayland client; gallium stays stock.
The rest of the official platform must remain coherent: Wayland 1.26,
Vulkan loader 1.4.309, and LLVM 19.1. Do **not** use full chroot gallium,
fex-mesa OpenGL, or generic Arch platform packages.

> [!CAUTION]
> Never set `HOLO_PKG_ALLOW_PLATFORM_REPLACE=1` for a production image.
> Replacing Mesa, Wayland, Vulkan, LLVM, systemd, or GLVND while installing
> Lutris breaks Gamescope and can make Plasma return directly to Game Mode.

The official Frame/Deckard rootfs is reconstructed with
`scripts/extract_rootfs.py` (casync). Do not copy random host Ubuntu
binaries into that rootfs (SteamOS glibc is older).

Packed `home` is sized tightly; it expands to the card on first boot.

**Lutris** and **Heroic** install during `install-vendor-apps.sh` (needs
network). Lutris is installed from the Arch Linux ARM `noarch` package with
the platform stack protected; it is not compiled. Heroic is compiled on the
build host (aarch64, Node 22 + pnpm 10; can take 10–20 minutes). To skip
either step:

```bash
sudo SKIP_HEROIC=1 ./make-steamos-sm8550.sh --skip-download
sudo SKIP_LUTRIS=1 SKIP_HEROIC=1 ./make-steamos-sm8550.sh --skip-download
```

# Relationship to SteamOS-Ubuntu

**[SteamOS-Ubuntu](https://github.com/MaSieS4Fun/SteamOS-Ubuntu)** is the
earlier SM8550 handheld project (Ubuntu Resolute userspace + gaming session).

This repository reuses from that project:

- the **SM8550 gaming kernel** (patches, ABL `KERNEL` packaging, firmware)
- the Decky plugins **SM8550-Power** (energy / power control) and
  **SM8550-LED** (controller LED panel)

Userspace here is official SteamOS ARM, not Ubuntu. Do not mix the two
root filesystems.

# Support the project

If this helps you and you want to support development, testing, and hosting:

**[Donate via PayPal](https://paypal.me/masies4fun)**

Thank you to everyone who uses, tests, reports issues, and contributes.

---

## License

Project glue: GPL-2.0. Vendor trees keep their own licenses.
See [`CREDITS.md`](CREDITS.md) and [`LICENSE`](LICENSE).
