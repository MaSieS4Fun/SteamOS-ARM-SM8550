from __future__ import annotations

import os
from pathlib import Path

APP_NAME = "ARM Non-Steam Games"
APP_ID = "io.steamosubuntu.nosteamgames"
APP_VERSION = "1.0.0"

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
ICON_PATH = DATA_DIR / "icons" / "no-steam-games.png"

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "no-steam-games"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "no-steam-games"

LUTRIS_API = "https://lutris.net/api/games"
USER_AGENT = f"{APP_NAME}/{APP_VERSION}"

DISCLAIMER = (
    "For DRM-free games only (GOG, itch.io, manual installs). "
    "Do not use for games that require online license validation. "
    "After adding: restart Steam. Windows .exe → choose Proton in Steam like any other game. "
    "Native Linux ARM binaries launch directly (no Proton)."
)
