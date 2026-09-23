# Proton ARM Easy Manager

Gestor de herramientas de compatibilidad **solo para Proton ARM (aarch64/arm64)**, inspirado en [ProtonPlus](https://github.com/Vysp3r/ProtonPlus).

Descarta cualquier build x86_64. Si una fuente no publica assets ARM, **no aparece en la lista**.

## Qué hace

1. Consulta las mismas familias de Proton que ProtonPlus (GE, CachyOS, EM, RTSP, DW-Proton, …).
2. Filtra releases: solo se listan si el release tiene un archivo `*aarch64*` / `*arm64*`.
3. Instala en:

   `~/.local/share/Steam/compatibilitytools.d/`

4. Tras instalar, aplica dos ajustes obligatorios para Proton ARM:

   - En `toolmanifest.vdf` elimina la línea `"require_tool_appid" "…"`.
   - En `files/` crea el enlace simbólico `bin` → `bin-arm64` (Lutris / Heroic buscan `bin`, no `bin-arm64`).

## Requisitos

- Linux aarch64
- Python 3.10+
- PyGObject + GTK 3 (`python3-gi`, `gir1.2-gtk-3.0`)

En Debian/Ubuntu/SteamOS-like:

```bash
sudo apt install python3-gi gir1.2-gtk-3.0
```

## Uso

```bash
cd Proton-ARM-Easy-Manager
python3 run.py              # GUI
python3 run.py sources      # Ver qué fuentes tienen ARM
python3 run.py installed    # Instalados
python3 run.py install GE-Proton11-3
python3 run.py repair       # Reaplicar fixes ARM a lo ya instalado
```

También:

```bash
python3 -m proton_arm_easy_manager gui
```

## Fuentes

Definidas en `data/sources.json`. Al arrancar se comprueba cada endpoint:

| Fuente         | ARM hoy (ejemplo)                          |
|----------------|--------------------------------------------|
| Proton-GE      | `GE-Proton*-aarch64.tar.gz` (solo algunos) |
| Proton-CachyOS | `proton-cachyos-*-arm64.tar.xz`            |
| Proton-GE RTSP | sin ARM → descartado                       |
| Proton-EM      | sin ARM → descartado                       |
| DW-Proton      | sin ARM → descartado                       |

## Variable de entorno

- `PROTON_ARM_INSTALL_DIR` — sobrescribe el directorio de instalación.

## Licencia

Inspirado en ProtonPlus (GPL-3.0). Este proyecto se distribuye bajo GPL-3.0.
