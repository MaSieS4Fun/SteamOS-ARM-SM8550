# Bundled Mesa patches (SM8550 tree)

All files here are applied **offline** for **SM8550** (and shared sync/UBO
pieces for **SM8750**). Nothing is fetched from GitHub at compile time.

| File | Origin | Effect |
| --- | --- | --- |
| `001-fix-freedreno-vulkan.patch` | Batocera (fork) | Adreno 7XX submit/sync — prevents vkcube-style coredumps |
| `0001-freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering.patch` | ROCKNIX | IR3 bindless UBO const-lowering |

Batocera upstream was deleted; mirror (attribution only):
https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds

Local Wayland WSI / RPCS3 experiment patches were removed — they did not help.

See [docs/PATCH_SOURCES.md](../../docs/PATCH_SOURCES.md).
