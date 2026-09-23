# AYN Thor — pantalla dual y táctil

El Thor es el único handheld SM8550 de este árbol que necesita **tres capas** para el táctil (kernel + udev + KWin). Solo cambiar la rotación en KDE **no basta** si faltan udev y el mapeo DBus de KWin.

Basado en [thorch-os/thorch](https://github.com/thorch-os/thorch) (ROCKNIX + KDE).

## Problema

- **Pantalla principal (DSI-2):** montada físicamente girada (`rotation = <90>` en el DT). Las coordenadas del FT5426 salen ~90° desalineadas respecto a la imagen.
- **Pantalla inferior (DSI-1):** FT5452 en otro bus I2C; en suspend profundo puede fallar si el driver apaga el regulador.

En KDE Plasma (Wayland), la rotación **“Derecha” (270°)** en Configuración de pantalla actúa como perilla de orientación del **touch** en el panel grande (la imagen puede quedar derecha). Eso se persiste en `~/.config/kwinoutputconfig.json` (`"transform": "Rotated270"`).

## Qué va en el kernel vs. el sistema

| Capa | Dónde | Qué |
|------|-------|-----|
| **Kernel/DTB** | `boot/KERNEL` ( `./make.sh` ) | Eje remapeado FT5426, `edt,retain-power-in-suspend` FT5452, labels |
| **Userspace** | `fix-thor-screen/fix-thor.sh` (manual) | udev, systemd, KWin DBus mapper, autostart KDE |

`update.sh` **solo instala kernel** (boot/firmware/modules). El fix userspace es **manual**:

```bash
sudo ./update.sh
sudo reboot
cd output/7.0.14-edge-sm8550-kbase/fix-thor-screen
./fix-thor.sh              # pide contraseña root; solo /usr y /etc
```

Instala en el sistema (nada en `$HOME`):

| Ruta | Función |
|------|---------|
| `/etc/udev/rules.d/99-thorch-touchscreen-calibration.rules` | `WL_OUTPUT=DSI-2` / `DSI-1` |
| `/usr/lib/systemd/system/thorch-touchscreen-setup.service` | udev antes del display manager |
| `/etc/xdg/autostart/thorch-kwin-touch-map.desktop` | KWin DBus mapper al iniciar KDE |
| `/etc/xdg/autostart/thorch-display-setup.desktop` | layout/rotación vía kscreen-doctor |
| `/usr/bin/thorch-*` | scripts de soporte |

Opciones: `--check-only`, `--force`.

## Tras instalar kernel + fix-thor.sh

1. Reboot o cerrar sesión e iniciar **KDE Plasma** (Wayland).
2. Autostart global aplica touch + display; no hace falta tocar `~/.config`.

## Limitaciones conocidas

- El touch de la pantalla grande **aún necesita más testeo** (comportamiento intermitente reportado en thorch).
- Bluetooth y sincronía brillo/resolución dual van aparte.
- Solo KDE; GNOME u otros compositors no tienen `thorch-kwin-touch-map`.

## Referencias en el árbol

- `payload/fix-thor-screen/` — bundle que se copia al output en cada build
- `lib/fix-thor-screen.sh` — staging + verify en build
- `lib/kbuild/patches.sh` — `apply_masi_thor_touch_dts`
- `patches/masi/1024-input-edt-ft5x06-retain-power-in-suspend.patch`
