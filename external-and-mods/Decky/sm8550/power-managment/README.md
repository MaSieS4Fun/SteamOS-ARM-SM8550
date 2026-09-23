# SM8550 Power — Decky plugin

Brought to this tree from **[SteamOS-Ubuntu](https://github.com/MaSieS4Fun/SteamOS-Ubuntu)**.

Based on **[Hooandee/panel-de-control](https://github.com/Hooandee/panel-de-control)** — adapted for Qualcomm SM8550 sysfs and Decky plugin id **`SM8550-Power`**. Full attribution: [`CREDITS.md`](../../../../CREDITS.md).

Power control panel for **Qualcomm SM8550** ARM64 handhelds:

- AYN Odin 2, Thor, Portal
- Retroid Pocket 6
- Other SM8550 / QCM8550 / QCS8550 devices with the same sysfs layout

**Not** for x86_64 PC handhelds (Steam Deck, ROG Ally, Legion Go, etc.). No TDP slider — SM8550 uses CPU/GPU governors, runtime PM, and UFS keepalive instead.

## Features

| Profile | CPU | GPU | UFS keepalive |
|---------|-----|-----|---------------|
| Power Saver | powersave | powersave | off |
| Balanced | schedutil/ondemand | simple_ondemand | off |
| Performance | performance | performance | off |
| Gaming | performance | performance + GMU on | on |

Also: battery stats, thermal zones, fan level, GPU max clock cap (when devfreq exposes steps).

## Build frontend (optional)

```bash
chmod +x build.sh install-local.sh
./build.sh
```

## Install (Decky required)

```bash
./install-local.sh
```

Or fix `~/homebrew` ownership if PluginLoader created it as root:

```bash
sudo chown -R steamos:steamos ~/homebrew
./install-local.sh
```

Then enable **SM8550 Power** in Decky → Plugins and restart `plugin_loader` if needed.

## Decky beta / stable

This plugin ships a **legacy frontend bundle** (no `import` lines). Decky loads it via `frontend_bundle` + globals `SP_REACT` and `DFL`, which works on beta and stable without a Node build on the device.

The plugin id in Decky is **`SM8550-Power`** (from `plugin.json`, no spaces).

```bash
grep '^import' ~/homebrew/plugins/power-managment/dist/index.js && echo BAD || echo OK
```

Must print **OK** (zero import lines).

If you previously installed as «Energía SM8550», remove the old entry in Decky → Plugins before enabling **SM8550-Power**.

## Image bake

Staged to `/usr/share/steamos-odin/decky-plugins/power-managment/` during image finalize. Synced to `~/homebrew/plugins/` when Decky is installed.

Upstream credits: [`CREDITS.md`](../../../../CREDITS.md) (repository root).
