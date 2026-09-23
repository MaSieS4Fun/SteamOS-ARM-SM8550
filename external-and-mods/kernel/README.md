# MaSi-OS Kernel Updater

SM8550 gaming kernel for AYN / Retroid / AYANEO handhelds, packaged as a
ROCKNIX-ABL **`boot/KERNEL`** bootimg — with **strict multi-device install**.

## Performance Kernel
Technical breakdown: **[GAMING-PERFORMANCE.md](https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater/blob/main/docs/GAMING-PERFORMANCE.md)**

Default target is Armbian **edge (7.0.x)**. By default MaSi skips Armbian GPU ACD +
SM8550 interconnect QoS, hardens A740 GMU HFI BW/perf votes (`patches/masi/1030-…`
+ `1031-…` forbid GMU runtime PM), and deep-suspend userspace — so
`GX_BW_PERF_VOTE` responds instead of timing out. Max clocks unchanged.

## Quick start

```bash
./make.sh
sudo ./update.sh                # on EACH device before reboot
./gui.sh                        # Easy Kernel Updater (GUI)
```

Output: `output/<version>-edge-sm8550-kbase/` (or the suffix set in `config/`)

## Why strict install

Install **fails closed** if it cannot embed **this SD’s** `root=UUID=`:

- Preflight checks SoC + ABL hints before install
- Post-install verifies KERNEL cmdline
- Docs: [`docs/ARRANQUE-SEGURO.md`](docs/ARRANQUE-SEGURO.md)

## ABL (mandatory)

Vol Down → **Set the Device** → exact model → Linux → START.

Wrong model (Odin 2 vs Mini) = black screen **before** Linux.  
Bootloader: [ROCKNIX-ABL](https://github.com/ROCKNIX/abl).

## UFS internal

```bash
sudo ./update.sh
sudo masi-install-to-ufs
# First UFS boot: remove microSD
```

See [`docs/INTERNAL-UFS-BOOT.md`](docs/INTERNAL-UFS-BOOT.md).

## Device extras (after `./update.sh` + reboot)

| Device | Extra |
|--------|--------|
| **AYN Thor** touch / dual panel | `output/.../fix-thor-screen/./fix-thor.sh` — [`docs/THOR-TOUCH.md`](docs/THOR-TOUCH.md) |
| **Odin 2 / Thor** gyro userspace | External project **`giroscopio`** → `./install.sh` (kernel already ships FastRPC/SensorsPD + Thor ADSP firmware + `CONFIG_UHID`) — [`docs/GYRO.md`](docs/GYRO.md) |

---

## Sources & credits

This kernel is assembled from public upstream work. **Full attribution and
“what we took from each”:** [`CREDITS.md`](CREDITS.md).

### Kernel, patches, firmware

| Project | Link | Role here |
|---------|------|-----------|
| Linux kernel | https://www.kernel.org · [CDN](https://cdn.kernel.org/pub/linux/kernel) | Vanilla sources compiled by `./make.sh` |
| Armbian build | https://github.com/armbian/build | SM8550 patch archive (`sm8550-7.0`, …) — AYN boards, SoC, rsinput, panels |
| Armbian firmware | https://github.com/armbian/firmware | Firmware tree staged into `output/.../firmware/` |

### Boot / multi-device / suspend

| Project | Link | Role here |
|---------|------|-----------|
| ROCKNIX | https://github.com/ROCKNIX/distribution | ABL KERNEL model, UFS install pattern, AYANEO DTS |
| ROCKNIX PR #2952 | https://github.com/ROCKNIX/distribution/pull/2952 | Deep-suspend UFS/wake patches → `patches/masi/1006`–`1013` |
| ROCKNIX-ABL | https://github.com/ROCKNIX/abl | Device index → DTB chain slot |
| Reference image | community SM8550 image | Reference 14-slot DTB chain (`reference/`, `device-tree/vendored/`) |

### Gyro (kernel) & Thor touch

| Project | Link | Role here |
|---------|------|-----------|
| Batocera.linux | https://github.com/batocera-linux/batocera.linux · [AYN wiki](https://wiki.batocera.org/hardware:ayn) | Sensor Core / FastRPC DT conventions (Odin 2 & Thor) |
| Batocera Custom ARM (suckbluefrog) | https://github.com/suckbluefrog/Batocera-Custom-Arm-Builds | FastRPC SensorsPD + Thor PD-type DT adapted in MaSi gyro patches |
| thorch-os / thorch | https://github.com/thorch-os/thorch | Thor touch udev + KWin map → `fix-thor-screen` |

### Boards / panels (overlays)

| Project / author | Link or note | Role here |
|------------------|--------------|-----------|
| LineageOS AYN `kernel-ack` | public `android_kernel_ayn_kernel-ack` | Retroid Pocket 6 DTS → `qcs8550-retroidpocket-rp6.dts` |
| Teguh Sobirin / ROCKNIX | https://github.com/ROCKNIX | AYANEO Pocket DTS under `patches/masi/ayaneo/` |
| Philippe Simons | panel patch authorship | Pocket DMG / DS panel drivers (`1020`, `1021`) |
| Qualcomm / Linux Foundation | HV haptics copyright in-driver | `qcom-hv-haptics` + AYN haptics DT fragment |

### Companion (userspace, not built by this repo)

| Project | Role |
|---------|------|
| **giroscopio** | Motion DSU + DualSense UHID + Steam Game Mode pad switch |

---

## Config

- `config/defaults.conf` — build defaults (`OUTPUT_SUFFIX=kbase`, `INSTALL_STRICT=1`)
- `config/local.conf` — optional overrides (copy from `config/local.conf.example`)

## Structure

```
.
  make.sh          compile kernel + boot/KERNEL
  update.sh        install on this device (strict UUID repack)
  CREDITS.md       full upstream attribution
  config/          dtb-chain, golden.config, defaults
  lib/             build + install logic
  patches/masi/    post-Armbian overlays (haptics, suspend, gyro, Thor, AYANEO…)
  payload/         fix-thor-screen (touch) — staged into output/
  reference/       reference DTB chain blobs
  hooks/           initramfs (dual-root SD/UFS)
  scripts/         preflight, verify, ufs-linux, ROCKNIX suspend fetch
  vendor/qcom-gyro firmware-thor-adsp (ADSP overlay for Thor gyro)
```

## Debug black screen

```bash
DEBUG_BOOTLOG=1 ./make.sh
sudo ./update.sh
```

See [`docs/DEBUG-BOOTLOG.md`](docs/DEBUG-BOOTLOG.md).

## License

Build/packaging scripts: MIT (`LICENSE`).  
Produced kernel/modules/firmware: GPL-2.0 and upstream licenses (kernel.org, Armbian, etc.).
