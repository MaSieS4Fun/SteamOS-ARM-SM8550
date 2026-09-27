# Mesa SM8550 — verified libraries (AYN Odin 2)

Minimal set extracted from the verified working SD. It replaces only the
required files on top of the stock SteamOS Frame rootfs
(`20260921.6090922`); it does **not** replace gallium or the complete Mesa
stack.

## Replaced files

| File | Source | Reason |
|---------|--------|--------|
| `usr/lib/libvulkan_freedreno.so` | `turnip-working/` | Gamescope presents to the panel through Vulkan/Turnip |
| `usr/lib/libEGL_mesa.so.0.0.0` | `opengl-working/` | Xwayland/Steam UI on Adreno 740 (a7xx) |
| `usr/lib/libGLX_mesa.so.0.0.0` | `opengl-working/` | Same as above |
| `usr/lib/libgbm.so.1.0.0` | `opengl-working/` | GBM for the compositor |
| `usr/lib/gbm/dri_gbm.so` | `opengl-working/` | Same as above |
| `usr/lib/dri/libdril_dri.so` | `opengl-working/` | DRI loader for Adreno 740 |
| `usr/lib/libwayland-client.so.0.26.0` | `wayland/` | `wl_fixes_interface` required by Turnip |

Symlinks such as `libEGL_mesa.so.0`, `libgbm.so.1`, and the `*_dri.so` links
to `libdril_dri.so` are created by
`scripts/install-opengl-mesa-sm8550.sh`.

## Files deliberately kept from Frame

- `libgallium-26.3.0-devel.so` (stock Frame)
- `libdisplay-info.so.*` (stock Frame)
- every other Mesa/EGL/Vulkan library from the rootfs

## Platform contract

This bundle is not a complete platform replacement. It is installed on the
official rootfs while preserving:

- the complete Wayland 1.26 runtime family;
- Vulkan loader 1.4.309;
- LLVM 19.1;
- systemd, GLVND, and gallium from the Frame rootfs.

The installer pins `libwayland-client.so.0` to `0.26.0`, but every other
Wayland component must also remain in the rootfs 1.26 family. Do not mix a
0.26 client with 0.22 server, cursor, or EGL libraries.

`scripts/lib/holo-pkg-install.sh` treats platform dependencies as already
satisfied when adding Lutris or other applications. Never use
`HOLO_PKG_ALLOW_PLATFORM_REPLACE=1` in a production image: it allows generic
Arch Linux ARM packages to replace Mesa/Wayland/Vulkan/LLVM and breaks
Gamescope or the transition to Plasma.

## Installation

```bash
# Install only SM8550 Mesa into an extracted or mounted rootfs.
sudo ./scripts/install-mesa-sm8550.sh [path/to/rootfs]

# Apply the complete Odin integration (includes this installer).
sudo ./scripts/apply-odin-mods.sh
```

For a release image, prefer the complete build:

```bash
sudo ./make-steamos-sm8550.sh
```

## Checksums (SHA256)

See `MANIFEST.sha256`. Regenerate it after changing binaries:

```bash
( cd external-and-mods/mesa-sm8550 && sha256sum \
  turnip-working/libvulkan_freedreno.so \
  opengl-working/libEGL_mesa.so.0.0.0 \
  opengl-working/libGLX_mesa.so.0.0.0 \
  opengl-working/libgbm.so.1.0.0 \
  opengl-working/gbm/dri_gbm.so \
  opengl-working/dri/libdril_dri.so \
  wayland/libwayland-client.so.0.26.0 ) > external-and-mods/mesa-sm8550/MANIFEST.sha256
```

## Notes

- `26.2.3/libvulkan_freedreno.so` is the MESA-Drivers Turnip build for
  Adreno 740. It does **not** present correctly through Gamescope on this
  hardware; use `turnip-working/`.
- Do **not** use `opengl/` (fex-mesa); it breaks Frame's `libgbm`.
