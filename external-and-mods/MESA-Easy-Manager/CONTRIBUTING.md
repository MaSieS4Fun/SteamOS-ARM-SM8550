# Contributing

Thanks for your interest in improving MESA Easy Manager.

## Scope

This project targets **aarch64** Linux devices with Qualcomm Adreno GPUs
(especially SM8550 / Adreno 740 and SM8750 / Adreno 830), and intentionally
replaces **only** `libvulkan_freedreno.so`.

## Development

```bash
python3 run.py
```

Runtime deps: `python3-gi`, `gir1.2-gtk-3.0`, `policykit-1`.

For **devel** compile tests, also install `git` and Mesa build dependencies
(see README **Requirements**).

## Patches

**All SoC patches are vendored** under `mesa_easy_manager/patches/` and applied
offline. Do not reintroduce GitHub downloads for Batocera/ROCKNIX at compile
time — the original Batocera tree was deleted; keep the
[MaSieS4Fun fork](https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds)
as attribution only.

When adding or updating a patch:

- Place the `.patch` file under `mesa_easy_manager/patches/SM8550/` or
  `SM8750/` and register it in `PLATFORM_PATCH_FILES` in
  `mesa_easy_manager/rocknix.py`
- Update [docs/PATCH_SOURCES.md](docs/PATCH_SOURCES.md) and the README
  **Patch sources** section
- Keep clear attribution (Batocera fork, ROCKNIX, or local WSI)

Compile profiles (`Generic`, `SM8550`, `SM8750`) are defined in
`mesa_easy_manager/rocknix.py` (`CompileProfile`) and the GTK flow in
`mesa_easy_manager/ui.py`.

## AppImage

```bash
./packaging/build-appimage.sh
```

See [docs/RELEASING.md](docs/RELEASING.md) for the full GitHub release checklist.

## Language

- Application UI and documentation: **English**
- Commit messages: concise, imperative English preferred
