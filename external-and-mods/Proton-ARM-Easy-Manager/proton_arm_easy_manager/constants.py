from __future__ import annotations

import os
from pathlib import Path

APP_NAME = "Proton ARM Easy Manager"
APP_ID = "io.github.protonarm.EasyManager"
VERSION = "1.0.0"

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
SOURCES_FILE = DATA_DIR / "sources.json"
ICON_PATH = DATA_DIR / "icons" / "eparm.png"
# Fallback to project-root copy if data/icons is missing.
if not ICON_PATH.is_file():
    ICON_PATH = PROJECT_ROOT / "eparm.png"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "proton-arm-easy-manager"
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "proton-arm-easy-manager"

DEFAULT_INSTALL_DIR = Path.home() / ".local" / "share" / "Steam" / "compatibilitytools.d"

USER_AGENT = f"Proton-ARM-Easy-Manager/{VERSION} (+https://github.com/)"

# Asset names must match one of these (case-insensitive) to count as ARM.
ARM_MARKERS = ("aarch64", "arm64", "-arm.", "_arm.", ".arm.")

# Never treat checksum / metadata files as installable archives.
NON_ARCHIVE_SUFFIXES = (
    ".sha512sum",
    ".sha256sum",
    ".sha1sum",
    ".md5",
    ".sum",
    ".torrent",
    ".txt",
    ".json",
    ".asc",
    ".sig",
)

ARCHIVE_SUFFIXES = (".tar.gz", ".tar.xz", ".tar.zst", ".tgz", ".tar", ".zip")
