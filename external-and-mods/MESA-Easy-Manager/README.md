# MESA Easy Manager

**Repository:** https://github.com/MaSieS4Fun/MESA-Easy-Manager

GTK application for **aarch64 Linux** (Adreno / Turnip) that switches **only**:

```text
/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so
```

It does **not** replace the rest of the system Mesa stack.

Designed for Qualcomm handhelds such as the **AYN Odin 2 (SM8550 / Adreno 740)** and **AYN Odin 3 (SM8750 / Adreno 830)**, where some games and emulators work better on specific Mesa releases.

---

## Features

- Lists official Mesa releases **≥ 25.0.0** from [mesa3d.org](https://mesa3d.org/) ([release notes](https://docs.mesa3d.org/relnotes.html))
- Always shows a top **devel** entry (Mesa git tip) with an instability warning
- Warns when a new release is not yet stored under `~/MESA-Drivers/`
- Compiles `libvulkan_freedreno.so` from the official Mesa archive (or git for devel) and stores it locally
- Before each **Compile** / **Recompile**, choose a profile:
  - **Generic** — stock Mesa, no device patches
  - **SM8550** — Odin 2 / Thor / R-Pocket 6 (bundled offline patches; then ask apply or not)
  - **SM8750** — Odin 3 (bundled offline patches; then ask apply or not)
- SM8550 / SM8750 bundles include **Batocera sync** + **ROCKNIX UBO** only
  (and A830 chip-id on SM8750). Local Wayland WSI / RPCS3 experiment patches
  are **not** shipped.
- **Install** replaces the system library (password via Polkit / `pkexec`)
- **Restore MESA system default** restores the original system library
- No password prompt when opening the app — only when replacing the system library

---

## Patch sources (attribution)

All device patches are **bundled offline** under `mesa_easy_manager/patches/`
(no GitHub download at compile time). Attribution links below are historical /
mirrors only. Full detail: [docs/PATCH_SOURCES.md](docs/PATCH_SOURCES.md).

| Profile | Bundled files |
| --- | --- |
| **SM8550** | Sync (Batocera) + UBO (ROCKNIX) + WSI `0004`–`0007` |
| **SM8750** | Same + A830 chip-id |

**Batocera mirror** (original repo deleted):  
[MaSieS4Fun/Batocera-Custom-Qualcomm-Builds](https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds)

**ROCKNIX:**  
[SM8550](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/graphics/mesa/patches/SM8550) ·
[SM8750](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/graphics/mesa/patches/SM8750)

Skipping patches may cause broken Vulkan (e.g. `vkcube` abort without the sync
fix) or Wayland glitches. Applying patches can also make some titles worse —
use **Recompile** to try the other choice.

**Note:** this app only replaces `libvulkan_freedreno.so`. For best Plasma Wayland
results, keep EGL/GBM on a matching Mesa series (full stack).

Related upstream issue: [mesa#14656](https://gitlab.freedesktop.org/mesa/mesa/-/issues/14656)

---

## Requirements

- Linux **aarch64**
- Python **3.10+**
- GTK 3 + PyGObject (`python3-gi`, `gir1.2-gtk-3.0`)
- PolicyKit (`pkexec`) for install/restore
- For compile: `meson`, `ninja`, `gcc`, and Mesa build dependencies
- For **devel** builds: `git` (shallow clone of Mesa upstream)

### Debian / Armbian

```bash
sudo apt install python3-gi gir1.2-gtk-3.0 policykit-1 git \
  meson ninja-build build-essential python3-mako python3-yaml \
  libdrm-dev libexpat1-dev libwayland-dev wayland-protocols \
  libx11-dev libxext-dev libxdamage-dev libx11-xcb-dev \
  libxcb-glx0-dev libxcb-shm0-dev libxcb-dri2-0-dev \
  libxcb-dri3-dev libxcb-present-dev libxcb-sync-dev \
  libxshmfence-dev zlib1g-dev libzstd-dev
```

Exact `-dev` packages can vary by Mesa version; install whatever Meson reports as missing.

---

## Quick start

```bash
git clone https://github.com/MaSieS4Fun/MESA-Easy-Manager.git
cd MESA-Easy-Manager
python3 run.py
```

Or:

```bash
python3 -m mesa_easy_manager
```

### AppImage (recommended)

Download the latest **`MESA_Easy_Manager-*-aarch64.AppImage`** from
[GitHub Releases](https://github.com/MaSieS4Fun/MESA-Easy-Manager/releases), or build locally:

```bash
./packaging/build-appimage.sh
chmod +x dist/MESA_Easy_Manager-*-aarch64.AppImage
./dist/MESA_Easy_Manager-*-aarch64.AppImage
```

The AppImage bundles application code. Host packages still required:

```bash
sudo apt install python3-gi gir1.2-gtk-3.0 policykit-1
```

For **devel** compiles from the AppImage, `git` must also be installed on the host.

---

## Local driver store

```text
~/MESA-Drivers/
  original-system-lib/
    libvulkan_freedreno.so   # backup of the system library (first change only)
  devel/
    libvulkan_freedreno.so   # rolling Mesa git tip (unstable)
  25.3.6/
    libvulkan_freedreno.so
  26.0.8/
    libvulkan_freedreno.so
  26.1.5/
    libvulkan_freedreno.so
```

---

## How it works

### Install

1. On the first change, the current system library is copied to `~/MESA-Drivers/original-system-lib/` (read-only; no root).
2. `pkexec` runs `scripts/mesa_easy_privileged.py` to replace `/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so`.
3. Later installs overwrite the system file with another stored build; the original backup is kept.

### Restore

**Restore MESA system default** copies the backup back with `pkexec`.

Restart Vulkan apps (or the session) after switching.

### Compile

1. Choose a **compile profile**:
   - **Generic** — stock Mesa, no device patches
   - **SM8550** — Odin 2 / Thor / R-Pocket 6
   - **SM8750** — Odin 3
2. For **SM8550** / **SM8750**, the app loads **bundled offline patches** and asks whether to apply them.
3. Downloads the official Mesa archive (`https://archive.mesa3d.org/mesa-<version>.tar.xz`), or shallow-clones Mesa git for **devel**
4. Optionally applies the selected bundled patches (user choice)
5. Configures a minimal Meson build (`-Dvulkan-drivers=freedreno`, `-Dfreedreno-kmds=msm`)
6. Builds and stores `libvulkan_freedreno.so` under `~/MESA-Drivers/<version>/` (or `~/MESA-Drivers/devel/`)
7. Deletes the temporary build directory under `~/.cache/mesa-easy-manager/build/`

---

## Safety

- Only `libvulkan_freedreno.so` is modified on the system
- The privileged helper refuses any destination other than that path
- Authentication is required for install and restore only

---

## Project layout

```text
mesa_easy_manager/     # Python application (GTK UI + core logic)
scripts/               # pkexec helper for install/restore
packaging/             # AppImage build (AppRun, desktop, icon, script)
docs/                  # Extra documentation (patches, releases)
```

---

## Releases

| Version | Highlights |
| --- | --- |
| **1.8.0** | WSI `0006`/`0007` (no explicit sync; no modifiers / scanout like X11) |
| **1.7.0** | All SoC patches bundled offline (no GitHub fetch); Batocera mirror attribution |
| **1.6.0** | Bundled Wayland WSI patches (LINEAR + ordered submits) for SM8550/SM8750 |
| **1.5.0** | Compile profiles (Generic / SM8550 / SM8750), rolling **devel** tip, SM8750 patch support |
| **1.0.0** | Initial release — SM8550 Batocera + ROCKNIX patches, AppImage |

See [CHANGELOG.md](CHANGELOG.md) for full notes. AppImages are attached to each
[GitHub Release](https://github.com/MaSieS4Fun/MESA-Easy-Manager/releases).

---

## Disclaimer

Use at your own risk. Replacing GPU driver libraries can break rendering or Vulkan applications. Keep the **Restore MESA system default** backup available. Bundled third-party-origin patches remain under their upstream licenses.

---

## License

This project is licensed under the [MIT License](LICENSE).

Third-party patches remain under their respective upstream licenses and copyrights (see [docs/PATCH_SOURCES.md](docs/PATCH_SOURCES.md)).

## Credits

- [Mesa 3D](https://mesa3d.org/) — Freedreno / Turnip Vulkan driver
- [ROCKNIX](https://github.com/ROCKNIX/distribution) — SM8550 / SM8750 Mesa patches
- [Batocera Custom Qualcomm Builds (fork)](https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds) — Freedreno Vulkan sync and SM8750 chip-id patches (original upstream deleted)
