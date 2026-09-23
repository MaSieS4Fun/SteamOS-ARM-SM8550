"""Shared paths and constants."""

from __future__ import annotations

from pathlib import Path

APP_NAME = "MESA Easy Manager"
APP_ID = "org.mesa.easy-manager"
APP_VERSION = "1.8.0"

MIN_VERSION = (25, 0, 0)

# Rolling Mesa git tip (stored as ~/MESA-Drivers/devel/).
DEVEL_VERSION = "devel"
MESA_GIT_URL = "https://gitlab.freedesktop.org/mesa/mesa.git"

HOME = Path.home()
DRIVERS_DIR = HOME / "MESA-Drivers"
ORIGINAL_DIR_NAME = "original-system-lib"
ORIGINAL_DIR = DRIVERS_DIR / ORIGINAL_DIR_NAME
LIBRARY_NAME = "libvulkan_freedreno.so"


def _detect_system_library() -> Path:
    """Debian/Ubuntu uses multiarch; SteamOS/Arch uses /usr/lib."""
    candidates = (
        Path("/usr/lib") / LIBRARY_NAME,
        Path("/usr/lib/aarch64-linux-gnu") / LIBRARY_NAME,
        Path("/usr/lib64") / LIBRARY_NAME,
    )
    for path in candidates:
        if path.is_file():
            return path
    return Path("/usr/lib") / LIBRARY_NAME


SYSTEM_LIBRARY = _detect_system_library()


def is_steamos() -> bool:
    try:
        text = Path("/etc/os-release").read_text(encoding="utf-8")
    except OSError:
        return False
    return "steamos" in text.lower() or "VARIANT_ID=steamdeck" in text or 'VARIANT_ID="steamdeck"' in text

RELNOTES_URL = "https://docs.mesa3d.org/relnotes.html"
MESA_NEWS_URL = "https://mesa3d.org/"
ARCHIVE_BASE_URL = "https://archive.mesa3d.org"

# Temporary compile root under the user's home (removed after success/failure cleanup).
BUILD_ROOT = HOME / ".cache" / "mesa-easy-manager" / "build"

USER_AGENT = f"MESA-Easy-Manager/{APP_VERSION}"


def ensure_drivers_dir() -> None:
    DRIVERS_DIR.mkdir(parents=True, exist_ok=True)


def version_dir(version: str) -> Path:
    return DRIVERS_DIR / version


def version_library(version: str) -> Path:
    return version_dir(version) / LIBRARY_NAME


def original_library() -> Path:
    return ORIGINAL_DIR / LIBRARY_NAME
