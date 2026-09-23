# Credits and upstream sources

**SteamOS-ARM-SM8550** adapts official SteamOS ARM to Qualcomm SM8550
handhelds. This file lists the sources this repository is built from.

Original licenses remain with their authors. Project glue (scripts,
overlays) is **GPL-2.0** — see [`LICENSE`](LICENSE).

If a credit is missing or incorrect, please open an issue or pull request.

---

## Previous project (required credit)

This work is based on **[SteamOS-Ubuntu](https://github.com/MaSieS4Fun/SteamOS-Ubuntu)**
by the same author.

| From SteamOS-Ubuntu | Path here | Notes |
|---------------------|-----------|--------|
| **SM8550 gaming kernel** | `external-and-mods/kernel/` | Same tree as [MaSi-OS Kernel Updater](https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater). Kernel-only detail: [`external-and-mods/kernel/CREDITS.md`](external-and-mods/kernel/CREDITS.md). |
| **Decky SM8550-Power** | `external-and-mods/Decky/sm8550/power-managment/` | Energy / power-control plugin (CPU/GPU profiles, fan, thermals). |
| **Decky SM8550-LED** | `external-and-mods/Decky/sm8550/color-leds/` | Controller RGB LED panel. |

Those two Decky plugins were adapted in SteamOS-Ubuntu from
**Hooandee**:

- Power UI: [Hooandee/panel-de-control](https://github.com/Hooandee/panel-de-control)
- LED UI: [Hooandee/decky-colores](https://github.com/Hooandee/decky-colores)

---

## Base system

| Source | URL | What we use |
|--------|-----|-------------|
| **Valve SteamOS ARM** (Frame / Deckard) | Valve | Official aarch64 userspace, Plasma, gamescope session, Steam Gamepad UI. Reconstructed at build time; **not** stored in git. |
| **Valve Steam (ARM64)** | Steam client | Game Mode client. Downloaded at image-build time; **not** stored in git. |
| **KDE Plasma / Frameworks** | https://kde.org | Official SteamOS desktop; kscreen and plasma-nm rebuilt to match SteamOS Qt/Plasma. |
| **Arch Linux ARM (Gear extras)** | https://archlinuxarm.org | Selected Plasma extras (Ark, Kate, …) built against SteamOS libraries. |

---

## Kernel and firmware

Inherited from **SteamOS-Ubuntu**. See
[`external-and-mods/kernel/CREDITS.md`](external-and-mods/kernel/CREDITS.md).

| Source | URL | What we use |
|--------|-----|-------------|
| **SteamOS-Ubuntu** | https://github.com/MaSieS4Fun/SteamOS-Ubuntu | Kernel tree, ABL `KERNEL` packaging, firmware staging |
| **MaSi-OS Kernel Updater** | https://github.com/MaSieS4Fun/MaSi-OS-Kernel-Updater | Same SM8550 kernel project |
| **Linux kernel** | https://www.kernel.org | GPL-2.0 vanilla tree |
| **Armbian** | https://github.com/armbian/build | SM8550 patch set and firmware |
| **ROCKNIX** | https://github.com/ROCKNIX/distribution · https://github.com/ROCKNIX/abl | ABL boot model, UFS `ROCKNIX`+`STORAGE`(+`HOME`), suspend patches |
| **Batocera / community DT** | Batocera, LineageOS AYN, Teguh Sobirin, Philippe Simons, thorch-os | Device trees, Thor touch, gyro firmware notes |

---

## Decky Loader and bundled plugins

| Source | URL | What we use |
|--------|-----|-------------|
| **SteamOS-Ubuntu** | https://github.com/MaSieS4Fun/SteamOS-Ubuntu | SM8550-Power and SM8550-LED as shipped here |
| **SteamDeckHomebrew / decky-loader** | https://github.com/SteamDeckHomebrew/decky-loader | PluginLoader (x86_64 via Box64) |
| **Hooandee / panel-de-control** | https://github.com/Hooandee/panel-de-control | Power-plugin design reference |
| **Hooandee / decky-colores** | https://github.com/Hooandee/decky-colores | LED-plugin design reference |
| **xXJSONDeruloXx / decky-lsfg-vk** | https://github.com/xXJSONDeruloXx/decky-lsfg-vk | LSFG Decky UI (when bundled) |

---

## Input, session, and graphics extras

| Source | URL | What we use |
|--------|-----|-------------|
| **ShadowBlip / InputPlumber** | https://github.com/ShadowBlip/InputPlumber | `deck-uhid` + keyboard target (OSK haptics) |
| **gamescope (Valve)** | https://github.com/ValveSoftware/gamescope | Gaming Mode compositor (MSM / backlight patches in-tree) |
| **Mesa / Freedreno Turnip** | https://gitlab.freedesktop.org/mesa/mesa | Adreno 740 Vulkan (host-provided `.so` at image apply) |
| **MangoHud** | https://github.com/flightlessmango/MangoHud | Performance overlay |
| **lsfg-vk** | https://github.com/PancakeTAS/lsfg-vk | Vulkan frame generation |
| **ptitSeb / box64** | https://github.com/ptitSeb/box64 | x86_64 for Decky PluginLoader |
| **thorch-os/thorch** | https://github.com/thorch-os/thorch | AYN Thor dual-screen / touch extras |

---

## Applications bundled by this overlay

| Source | URL | What we use |
|--------|-----|-------------|
| **MESA Easy Manager** | https://github.com/MaSieS4Fun/MESA-Easy-Manager | Turnip / Mesa helper |
| **Proton ARM Easy Manager** | In-tree / inspired by ProtonPlus | ARM Proton helper |
| **Steam ROM Manager** | https://github.com/SteamGridDB/steam-rom-manager | Desktop launcher |
| **Easy UFS Install** | `external-and-mods/ufs-install/` (MaSi-OS UFS lineage) | Internal UFS install: ROCKNIX + STORAGE + HOME |

---

## Design inspiration

| Project | Relationship |
|---------|--------------|
| **SteamOS / Jupiter (Valve)** | Game Mode, Gamepad UI, official Plasma desktop |
| **SteamOS-Ubuntu** | Kernel, Decky SM8550 plugins, SM8550 handheld bring-up |
| **ROCKNIX** | ABL, UFS partition names, kernel patches |
| **Hooandee** | Decky power and LED plugin design |

---

## Acknowledgements

Thanks to **Valve**, the **SteamOS-Ubuntu** testers, **Hooandee**, and
maintainers of **kernel.org**, **Armbian**, **ROCKNIX**, **Batocera**,
**SteamDeckHomebrew**, **ShadowBlip**, **PancakeTAS**, **Flightless Mango**,
**ptitSeb**, **thorch-os**, and everyone who documented ABL / DTB slots
on SM8550 handhelds.
