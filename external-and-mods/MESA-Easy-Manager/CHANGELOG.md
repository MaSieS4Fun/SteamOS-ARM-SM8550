# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.8.1] - 2026-08-10

### Removed

- Local Wayland WSI / RPCS3 experiment patches `0004`–`0007` (they did not help).
  SM8550/SM8750 profiles keep only Batocera sync + ROCKNIX UBO (+ A830 on SM8750).

## [1.8.0] - 2026-08-07

### Added

- Wayland WSI patches **0006** (disable explicit sync) and **0007** (no
  modifiers → scanout/LINEAR like X11) for SM8550 and SM8750 profiles

### Changed

- SM8550 / SM8750 apply order: sync → UBO → WSI `0004`–`0007`

## [1.7.0] - 2026-08-05

### Changed

- **All SoC patches are bundled offline** under `mesa_easy_manager/patches/` —
  compile no longer downloads Batocera/ROCKNIX from GitHub (original Batocera
  tree was deleted; attribution points to
  [MaSieS4Fun/Batocera-Custom-Qualcomm-Builds](https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds))
- SM8550: sync + UBO + WSI `0004`/`0005` from the local tree
- SM8750: same plus bundled `0001-add-a830-chip-id.patch`
- UI / docs updated for offline-only patch loading

## [1.6.0] - 2026-08-05

### Added

- Bundled **Wayland WSI** patches for SM8550 and SM8750 profiles:
  - `0004-turnip-prefer-linear-for-wsi-modifiers.patch` — prefer LINEAR over UBWC for swapchain/WSI images (Plasma Wayland / RPCS3 glitch fix)
  - `0005-turnip-drirc-disable-unordered-wsi-submits.patch` — ordered WSI presents by default
- Local patches live under `mesa_easy_manager/patches/SM8550/` and ship inside the AppImage

### Changed

- SM8550 / SM8750 compile with patches now applies Batocera + ROCKNIX **plus** local WSI patches
- Patch dialog and docs mention Plasma Wayland WSI fixes and the Vulkan-only install limitation

## [1.5.0] - 2026-07-27

### Added

- **Compile profiles** when building:
  - **Generic** — stock Mesa, no device patches
  - **SM8550** — Odin 2 / Thor / R-Pocket 6 (Batocera + ROCKNIX SM8550)
  - **SM8750** — Odin 3 (Batocera + ROCKNIX SM8750)
- **devel** entry at the top of the version list (rolling Mesa git tip)
- Instability warnings before compiling or installing **devel**
- SM8750 patch fetching from Batocera and ROCKNIX upstream trees
- Patch deduplication by content hash; same filename from both mirrors keeps the Batocera copy (SM8750 a830 patch)

### Changed

- SM8550 patch flow unchanged in behaviour, but now selected explicitly via profile
- Documentation expanded for profiles, devel, and SM8750 attribution

### Requirements

- **devel** builds need `git` on the host (shallow clone of Mesa upstream)

## [1.0.0] - 2026-07-26

### Added

- GTK app to list, compile, install, and restore `libvulkan_freedreno.so`
- Mesa releases ≥ 25.0.0 from official release notes
- Optional Batocera + ROCKNIX SM8550 patches at compile time
- Local store under `~/MESA-Drivers/` with original-system-lib backup
- Privileged install/restore via `pkexec`
- AppImage packaging for aarch64

[1.7.0]: https://github.com/MaSieS4Fun/MESA-Easy-Manager/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/MaSieS4Fun/MESA-Easy-Manager/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/MaSieS4Fun/MESA-Easy-Manager/compare/v1.0.0...v1.5.0
[1.0.0]: https://github.com/MaSieS4Fun/MESA-Easy-Manager/releases/tag/v1.0.0
