# Patch sources and attribution

MESA Easy Manager optionally applies Mesa patches when compiling
`libvulkan_freedreno.so`. **All patches are bundled offline** under
`mesa_easy_manager/patches/` — nothing is downloaded from GitHub at compile
time (the original Batocera tree was removed upstream).

| Profile | Devices | Bundled patches |
| --- | --- | --- |
| **Generic** | Any | None (stock Mesa) |
| **SM8550** | Odin 2, Thor, R-Pocket 6 | Batocera sync + ROCKNIX UBO |
| **SM8750** | Odin 3 | Sync + UBO + A830 chip-id |

---

## Bundled layout

```text
mesa_easy_manager/patches/
  SM8550/
    001-fix-freedreno-vulkan.patch
    0001-freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering.patch
  SM8750/
    0001-add-a830-chip-id.patch
```

Apply order is fixed in `mesa_easy_manager/rocknix.py` (`PLATFORM_PATCH_FILES`).

---

## SM8550 (Odin 2 / Thor / R-Pocket 6)

### Sync fix (originally Batocera)

**Local:** `patches/SM8550/001-fix-freedreno-vulkan.patch`

**Attribution / mirror:**  
[MaSieS4Fun/Batocera-Custom-Qualcomm-Builds](https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds)
(`board/batocera/patches/mesa3d/`) — fork of the deleted upstream tree.

Soft Vulkan submit/sync fix for Adreno 7XX (`tu_knl_drm_msm.cc`).

### UBO fix (originally ROCKNIX)

**Local:** `patches/SM8550/0001-freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering.patch`

**Attribution:**  
[ROCKNIX SM8550 patches](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/graphics/mesa/patches/SM8550)

IR3 bindless UBO const-lowering fix for SM8550 / Adreno 740.

---

## SM8750 (Odin 3)

Uses the same sync + UBO files from `patches/SM8550/`, plus:

**Local:** `patches/SM8750/0001-add-a830-chip-id.patch`

Adds Adreno **a830** chip id support.

---

## Not shipped

Local Turnip Wayland WSI / RPCS3 experiment patches (`0004`–`0007`) were removed.
They did not fix the issues and are not part of Rocknix/Batocera.
