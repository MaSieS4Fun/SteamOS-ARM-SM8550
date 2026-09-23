# Standard vs performance — why SM8550 handhelds need tuning

Generic explanation for Qualcomm SM8550 handhelds (AYN Odin 2, Mini, Portal, Thor, Retroid Pocket 6, etc.) running Linux — **any** kernel, **any** distro.

This is not “distro A vs distro B”. The same gap appears whenever you compare a **default / stock build** with a **performance-tuned build** on the same hardware.

---

## What “standard” usually means

Typical upstream or vendor kernels for these devices are built and booted with goals like:

- Boot on many boards and form factors  
- Safe defaults for power and thermals  
- Compatibility with vendor boot chains (ABL, embedded DTBs, long cmdlines)  
- General-purpose scheduling and I/O  

That profile is fine for a desktop-like or console-like OS image. It is **not** optimized for low-latency gaming on a big.LITTLE phone SoC used as a handheld.

---

## What “performance” means here

A performance profile keeps full device support (USB, Wi‑Fi, audio, storage) but changes **how the system uses the CPU, GPU, interrupts, and I/O** under load:

| Layer | Standard tendency | Performance adjustment | Why it matters on SM8550 |
|-------|-------------------|------------------------|---------------------------|
| **Kernel build** | Generic scheduler / I/O options | Cluster-aware scheduling, tuned storage driver, no extra pressure metrics | Games and IRQs compete on little vs big cores; bad scheduler + I/O choices show up as FPS drops and stutter. |
| **Boot cmdline** | Long vendor line, often IRQ affinity on little cores | Short line; **no** pinning interrupts to CPUs 0–2 | Once Wi‑Fi/USB/audio run, IRQ traffic rises; pinning it to little cores while games use big cores costs a lot of FPS. |
| **Initramfs** | Large or wrong content for ABL size limits | Small initrd, minimal early load | Usually affects **boot reliability**, not sustained FPS — but a broken boot blocks everything. |
| **Userspace power** | Default governors (schedutil / ondemand) | CPU and GPU held in performance while gaming | GPU especially often stays on a conservative governor unless something sets it for play. |
| **Device tree / EAS** | Generic or mismatched CPU capacity values | Correct capacity numbers for A510 vs A715 cores | Scheduler sends work to the wrong cluster. |

None of this is unique to one project. You see the same pattern on **Armbian, ROCKNIX ports, custom builds, and reference LinuxLoader images** — whenever one side uses stock defaults and the other applies the table above.

---

## Why it looks like “devices kill performance”

On the **same kernel binary**, if firmware and drivers are missing:

- Fewer interrupts, less Wi‑Fi/audio/GPU activity  
- Less thermal throttling  
- GPU governor may not even be active  

FPS looks good. After enabling USB, Wi‑Fi, and audio, load increases and **weak defaults surface**. That is often misread as “drivers are slow” when the real issue is **cmdline + kernel config + governors** under real workload.

Standard and performance can coexist: peripherals working does not require accepting bad FPS.

---

## The changes, in plain terms

### 1. Kernel — compile-time

Some choices are **baked into the binary**. Boot parameters and initramfs cannot turn them on later.

Performance-oriented builds typically:

- Enable **cluster / SMT-aware scheduling** for big.LITTLE  
- Avoid or disable **pressure-based scheduling (PSI)** that pushes work when the system looks busy  
- Use the **platform storage driver** with vendor I/O tuning where available  
- Keep **early HDMI / dock drivers** out of the critical boot path when they cause hangs  

Stock builds often omit or disable these for portability.

### 2. Cmdline — boot-time

Vendor images often ship a long cmdline copied from Android or a fixed product image. For Linux gaming on Armbian-style setups, a **short cmdline** is enough, plus ABL-specific tokens if you use a `KERNEL` bootimg.

The most common gaming regression on this hardware: **`irqaffinity=0-2`** (interrupts on little cores). Remove it.

Useful additions: `psi=0` if PSI is compiled in; standard handoff tokens (`clk_ignore_unused`, `pd_ignore_unused`, etc.).

Do **not** add `devicetree=` when ABL selects the DTB from an embedded chain.

### 3. Initramfs — boot path

For ABL bootimg there is a **fixed size budget** (~78–82 MB total). Standard mistakes: stuffing all firmware and all modules into initrd. Performance-oriented setups use a **small initrd** and put modules + firmware on the root filesystem.

### 4. Userspace — after boot

Stock desktop/server distros do not ship handheld “game mode” scripts. Without setting **CPU and GPU governors** (and optionally GPU frequency caps), the system stays on power-saving behavior even when the kernel default governor is `performance`.

Handheld OS images (e.g. emulation-focused distros) often do this in platform quirks; generic Linux installs need an equivalent service or manual tuning.

---

## Why this applies to all kernels on these devices

SM8550 handhelds share the same constraints:

1. **big.LITTLE** — games, IRQs, and background tasks fight over core selection.  
2. **High IRQ load when “complete”** — Wi‑Fi, USB, audio, Type‑C all use the same little-core pool if cmdline says so.  
3. **ABL bootimg** — size limits and embedded DTBs; vendor cmdlines carry over easily.  
4. **Adreno devfreq** — GPU behavior is runtime policy, not only kernel `.config`.  
5. **Vendor kernels target their own OS** — scheduler, cmdline, and initrd match their power model, not necessarily yours.

So every “standard” 7.0.x or 6.18.x build for Odin / RP6 can show the same gap until the performance column in the table is applied — regardless of who compiled it.

---

## How to tell which side you are on

Quick checks on a running system:

```bash
# Bad for gaming if present:
cat /proc/cmdline | tr ' ' '\n' | grep irqaffinity

# GPU often stuck on conservative governor:
cat /sys/devices/platform/soc@0/3d00000.gpu/devfreq/3d00000.gpu/governor 2>/dev/null

# PSI active (optional to disable at boot with psi=0):
ls /proc/pressure/ 2>/dev/null
```

Extract and compare kernel config (IKCFG from bootimg) against a known-good performance profile if FPS is still low after fixing cmdline and governors.

---

## Summary

| | Standard | Performance |
|---|----------|-------------|
| **Intent** | Boot everywhere, safe power | Full devices + low latency gaming |
| **Kernel** | Generic options | Scheduler, I/O, PSI tuned for load |
| **Cmdline** | Vendor copy, often bad IRQ affinity | Minimal, no little-core IRQ pin |
| **Initramfs** | Often too large or wrong | Small; firmware/modules on rootfs |
| **Userspace** | Default governors | CPU/GPU performance while gaming |

**MaSi-OS Kernel Updater** applies this performance column by default (`golden.config`, gaming cmdline, gold initrd). The **principles** are the same for any SM8550 kernel you compile yourself.

Further kernel option checklist: [KCONFIG-REQUIREMENTS.md](KCONFIG-REQUIREMENTS.md).

---

## Reference — performance profile (this project)

Concrete targets used in this project. Same ideas apply if you build elsewhere; paths and scripts may differ.

### Golden `.config` — options that must differ from a standard build

Full file in the repo: `config/golden.config` (based on verified Armbian SM8550 / 6.18.8 gaming profile).  
At build time, `GAMING_TUNING=1` also forces these via `scripts/config`:

```kconfig
# Scheduler / big.LITTLE
CONFIG_SCHED_SMT=y
CONFIG_SCHED_MC=y
CONFIG_SCHED_CLUSTER=y
# CONFIG_PSI is not set

# CPU default at boot
CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
CONFIG_ENERGY_MODEL=y

# Storage (Qualcomm downstream SDHCI)
CONFIG_MMC_SDHCI_MSM=y
CONFIG_MMC_SDHCI_MSM_DOWNSTREAM=y

# Compiler
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y
# CONFIG_CC_OPTIMIZE_FOR_SIZE is not set

# HDMI dock — module or disabled (not built-in =y)
# CONFIG_DRM_LONTIUM_LT8912B is not set
# (or CONFIG_DRM_LONTIUM_LT8912B=m)
```

Also required from **Armbian SM8550 patches** (not kconfig alone): correct `capacity-dmips-mhz` in `sm8550.dtsi` — little cores **326**, mid **693**, prime **1024**.

Release string baked into modules:

```kconfig
CONFIG_LOCALVERSION="-edge-sm8550"
```

(`KERNEL_LOCALVERSION` in build defaults.)

---

### `initrd.img` — how it should look (ABL bootimg)

| Property | Performance target |
|----------|-------------------|
| **Size** | ~45–62 MB (must leave room in bootimg; total **≤ ~78 MB** with zImage + DTBs) |
| **Kernel modules (`.ko`)** | **0** inside initrd cpio |
| **MODULES=** | `list` empty or reference image with `most` but no `.ko` shipped |
| **Firmware in initrd** | Minimal early-boot subset only (not full `lib/firmware`) |
| **Early DRM/GPU** | Stripped from initrd (avoid HDMI dock hang at boot) |

**Default:** `INITRAMFS_PROFILE=gold` — use a known-good reference initrd (~47 MB, 0 `.ko`), or set `GOLD_INITRD_REF=/path/to/initrd.img-*`.

If building with `mkinitramfs` (`efi-clean` profile):

- `MODULES=list` with empty module list  
- Hook: no early `drm` / `msm` / `kgsl` / `lt8912` modules  
- Optional minimal firmware paths only:

  ```
  qcom/sm8550
  qcom/a740_sqe.fw
  qcom/gmu_gen70200.bin
  qcom/vpu/vpu30_p4.mbn
  ath12k/WCN7850/hw2.0
  qcom/sm8550/ayn
  ```

**On rootfs (not initrd):** full `output/firmware/` → `/usr/lib/firmware/` and `output/modules/<release>/` → `/usr/lib/modules/`.

Verify after build:

```bash
lsinitramfs output/.build/*-masi/initrd.img-* | grep -c '\.ko$'   # expect 0
du -h output/.build/*-masi/initrd.img-*
```

---

### Boot cmdline (embedded in `boot/KERNEL`)

```
clk_ignore_unused pd_ignore_unused quiet rw rootwait root=UUID=<your-ext4-uuid>
```

Optional (legacy ABL only): `ABL_CMDLINE_EXTRAS=1` adds `psi=0 arm64.nopauth efi=noruntime video=efifb:off`.

Must **not** include: `irqaffinity=0-2`, `devicetree=`, `dtb=`.

---

### Kernel build parameters

Environment / defaults (`config/defaults.conf`):

| Variable | Performance value | Notes |
|----------|-------------------|--------|
| `GAMING_TUNING` | `1` | Applies golden overrides + AYN panel/touch drivers |
| `KERNEL_CONFIG` | `config/golden.config` | Or auto-resolved from repo |
| `KERNEL_LOCALVERSION` | `-edge-sm8550` | Module path: `7.0.14-edge-sm8550` |
| `INITRAMFS_PROFILE` | `gold` | Small initrd for ABL |
| `FIRMWARE_IN_INITRD` | `minimal` | Only if using `efi-clean` mkinitramfs |
| `INITRD_MAX_MB` | `62` | Hard limit check |
| `BOOTIMG_MAX_BYTES` | `82536448` | ABL partition budget |
| `BUILD_COMPILE` | `1` | `0` = repack only (keeps existing Image) |
| `PATCH_POLICY` | `strict` | Armbian sm8550 patch set |
| `DEVICE_TARGET` | `all` | All AYN DTBs in zImage chain |
| `AYN_FAMILY_DRIVERS` | `1` | Handheld panels / touch in kernel |

Compile invocation (inside MaSi-OS pipeline):

```bash
make -C <linux-src> ARCH=arm64 -j$(nproc) Image modules
make -C <linux-src> ARCH=arm64 -j$(nproc) qcom/qcs8550-ayn-*.dtb
make -C <linux-src> ARCH=arm64 modules_install INSTALL_MOD_STRIP=1
```

One-liner build:

```bash
./make.sh
# or non-interactive:
KERNEL_VER=7.0.14 GAMING_TUNING=1 INITRAMFS_PROFILE=gold ./make.sh
```

Repack initrd/cmdline only (same kernel binary):

```bash
KERNEL_VER=7.0.14 BUILD_COMPILE=0 ./make.sh
```

Install to system:

```bash
sudo ./update.sh
```

---

### Bootimg layout (ABL)

```
boot/KERNEL  =  Android bootimg {
                 kernel: gzip(Image) + 11 embedded DTBs (zImage)
                 ramdisk: initrd.img-<release>
                 cmdline: (performance line above)
               }
```

Typical sizes: zImage ~18–25 MB + initrd ~47 MB → fits ABL limit.

Output reference config after build: `output/meta/config-<release>`.

