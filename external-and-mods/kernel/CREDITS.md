# CREDITS — Upstream sources

> **SteamOS-ARM-SM8550** ships this kernel tree from
> **[SteamOS-Ubuntu](https://github.com/MaSieS4Fun/SteamOS-Ubuntu)** /
> [MaSi-OS Kernel Updater](https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater).
> Project-wide attribution: [`../../CREDITS.md`](../../CREDITS.md).
> This file details the kernel tree only.

**MaSi-OS Kernel Updater** —
[github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater](https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater)

This tree builds the SM8550 gaming kernel with **strict multi-device install**
(`INSTALL_STRICT=1`), Thor touch packaging, and ADSP Sensor Core (gyro)
**kernel** support. Gyro **userspace** lives in the separate `giroscopio` project.

This file lists **what we took from each upstream**. Licenses remain those of the
respective projects (kernel = GPL-2.0; build scripts here = MIT — see `LICENSE`).

---

## Kernel tree & base patches

| Source | URL | What we use |
|--------|-----|-------------|
| **Linux kernel (kernel.org)** | https://cdn.kernel.org/pub/linux/kernel · https://www.kernel.org | Vanilla `linux-<ver>` tarball compiled by `./make.sh`. |
| **Armbian build** | https://github.com/armbian/build | Full SM8550 patch set under `patch/kernel/archive/sm8550-<series>/` (board DTS for AYN Odin 2 / Mini / Portal / Thor, Qualcomm SoC bring-up, rsinput gamepad, panels, audio, etc.). Fetched via `lib/armbian-patch-sync.sh` / manifests in `config/armbian-manifests/`. |
| **Armbian firmware** | https://github.com/armbian/firmware | Device firmware staged into `output/.../firmware/` (`FIRMWARE_SOURCE=download`). |

---

## Bootloader, DTB chain & dual-boot layout

| Source | URL | What we use |
|--------|-----|-------------|
| **ROCKNIX distribution** | https://github.com/ROCKNIX/distribution | Multi-device ABL `KERNEL` concept; UFS/`ROCKNIX` partition install pattern; deep-suspend kernel patches (see below); AYANEO Pocket DTS copyrights / board ids. |
| **ROCKNIX PR #2952 (deep suspend)** | https://github.com/ROCKNIX/distribution/pull/2952 | Vendored as `patches/masi/1006`–`1013` (UFS hibern8/relink, QMP RX LineCfg, IPCC wake, Thor tsens). Authors include **jaewun**. Re-fetch: `scripts/fetch-rocknix-suspend-patches.py`. |
| **ROCKNIX-ABL** | https://github.com/ROCKNIX/abl | Boot model selection (“Set the Device”) that picks DTB chain index; dual Linux/Android boot. We do **not** ship the ABL binary; we document and package for it. |
| **Reference SM8550 image** | (community SM8550 image; local extract) | Reference DTB chain layout / slot sizes in `reference/dtb-chain` and `device-tree/vendored/` (14-slot order matching ABL indices). |

---

## Device trees & panels (MaSi overlays)

| Source | URL / author | What we use |
|--------|--------------|-------------|
| **LineageOS AYN kernel-ack** | Public tree cited as `android_kernel_ayn_kernel-ack` | Retroid Pocket 6 board DTS → `patches/masi/qcs8550-retroidpocket-rp6.dts` (adapted onto Armbian `qcs8550-ayn-common.dtsi`). |
| **ROCKNIX + Teguh Sobirin** | https://github.com/ROCKNIX · copyright in DTS | AYANEO Pocket ACE / DMG / DS / EVO / S1 DTS under `patches/masi/ayaneo/`. |
| **Philippe Simons** | `simons.philippe@gmail.com` (panel patches) | Pocket DMG panel driver (`1020-drm-panel-ar02-pocket-dmg.patch`); related DS secondary panel work (`1021`). |
| **Armbian sm8550 (historical)** | https://github.com/armbian/build | Base for AYANEO common dtsi port notes (`docs/DEVICE-MATRIX.md`: Armbian `sm8550-6.18` + MaSi Pocket S 2K). |
| **Qualcomm / Linux Foundation** | Downstream PMIC haptics (Copyright Linaro / QuIC in driver) | `qcom-hv-haptics` driver landed via `1000`–`1004` (+ Steam FF deadlock fix); DT fragment `qcs8550-ayn-haptics.dtsi.frag` (Batocera-derived wiring on AYN boards). |
| **Armbian `rsinput`** | Via Armbian SM8550 patches | Native AYN gamepad driver; MaSi adds FF/rumble bridge to HV haptics (`1003` + `apply_masi_rsinput_ff_bridge`). |

---

## Gyro / Qualcomm Sensor Core (kernel only)

| Source | URL | What we use |
|--------|-----|-------------|
| **Batocera.linux** | https://github.com/batocera-linux/batocera.linux · [wiki AYN](https://wiki.batocera.org/hardware:ayn) | Validated AYN Odin 2 / Thor Sensor Core behaviour; DT conventions (SensorsPD attach; Thor-only `qcom,pd-type`). |
| **Batocera Custom ARM builds (suckbluefrog)** | https://github.com/suckbluefrog/Batocera-Custom-Arm-Builds | FastRPC SensorsPD + legacy ioctl port adapted in `1025` / `1026`; Thor FastRPC PD banks in `qcs8550-ayn-thor-gyro-fastrpc-pd.dtsi.frag` (“Matches Batocera suckbluefrog gyro DT”). |
| **Thor ADSP firmware (SH5001)** | Vendored under `vendor/qcom-gyro/firmware-thor-adsp/` | Overlay into `firmware/qcom/sm8550/ayn/thor/` so Thor does not reuse Odin 2 `adsp.mbn` incorrectly (`lib/gyro-firmware.sh`). |

Userspace (hexagonrpcd, libssc, `qcom-motion`, DualSense UHID, Steam Game Mode wrapper) is **not** built here — see **`giroscopio`**.

---

## Thor dual-screen / touch (userspace bundle)

| Source | URL | What we use |
|--------|-----|-------------|
| **thorch-os/thorch** | https://github.com/thorch-os/thorch | udev calibration, systemd touch setup, KWin DBus touch map, display layout scripts packaged as `payload/fix-thor-screen/` → `fix-thor.sh`. Kernel side: CH13726A reset polarity (`1005`), FT5452 retain-power-in-suspend (`1024`), Thor touch DTS hooks. |

---

## MaSi-original / in-tree fixes (not copied wholesale)

These are authored or heavily reworked in this project; still listed so the map is complete:

| Area | Patches / paths | Notes |
|------|-----------------|-------|
| HDMI/DP audio race | `1014`, `1015` | `drm_hdmi_audio` hw_params + q6apm graph start on trigger |
| Haptics Steam FF | `1004` | Deadlock / brake poll hardening for Steam rumble |
| Thor panel reset | `1005` | CH13726A GPIO polarity |
| Gyro FastRPC port | `1025`, `1026` + DT frags | Batocera-inspired, ported to linux 7.0 `dma_addr` |
| Strict install | `lib/install.sh`, `scripts/preflight-device.sh`, `lib/verify-build.sh` | UUID repack required; ship-gate on bootimg/cmdline/initrd |
| Dual-root SD/UFS | `hooks/masi-dual-root*` | Same KERNEL for microSD and UFS ROCKNIX partition |

---

## External companion (not in this repo’s `./make.sh` output)

| Project | Role |
|---------|------|
| **giroscopio** | Full gyro userspace install for Odin 2 / Thor after this kernel is installed |

---

## Acknowledgements

Thanks to the maintainers and contributors of **kernel.org**, **Armbian**, **ROCKNIX**, **Batocera**, **suckbluefrog**, **thorch-os**, **LineageOS** AYN kernel work, **Teguh Sobirin**, **Philippe Simons**, **jaewun** (UFS/suspend), and everyone who documented ABL/DTB slot behaviour for SM8550 handhelds.

If a credit is missing or mis-attributed, open an issue or PR against this repository.
