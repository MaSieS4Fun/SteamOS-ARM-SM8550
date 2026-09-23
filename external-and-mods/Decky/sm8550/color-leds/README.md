# SM8550 LED — Decky plugin

Brought to this tree from **[SteamOS-Ubuntu](https://github.com/MaSieS4Fun/SteamOS-Ubuntu)**.

Based on **[Hooandee/decky-colores](https://github.com/Hooandee/decky-colores)** — adapted for AYN SM8550 `pwm-leds-multicolor` sysfs and Decky plugin id **`SM8550-LED`**. Full attribution: [`CREDITS.md`](../../../../CREDITS.md).

RGB LED control for **Qualcomm SM8550** handhelds (Odin 2, Thor, Portal, similar rsinput layouts).

## Hardware

Expected zones under `/sys/class/leds/`:

- `left-joystick`, `left-side`, `right-joystick`, `right-side`

Each zone: `multi_intensity` = `R G B`, `brightness` = 0–255.

## Build frontend

```bash
./build.sh
```

## Image bake

Staged to `/usr/share/steamos-odin/decky-plugins/color-leds/` during finalize. Synced to `~/homebrew/plugins/` when Decky is installed.
