from __future__ import annotations

import os
from pathlib import Path

APP_NAME = "Easy Kernel Updater"
APP_ID = "org.easy.kernel-updater"
VERSION = "1.0.0"

PACKAGE_ROOT = Path(
    os.environ.get("EASY_KERNEL_UPDATER_ROOT")
    or os.environ.get("MASI_KERNEL_MANAGER_ROOT")  # back-compat
    or Path(__file__).resolve().parent.parent
).resolve()


def _detect_kernel_tree() -> Path:
    env = (
        os.environ.get("EASY_KERNEL_TREE", "").strip()
        or os.environ.get("MASI_KERNEL_TREE", "").strip()
    )
    if env:
        return Path(env).resolve()
    packaged = Path("/usr/share/easy-kernel-updater-runtime")
    # Legacy path from earlier builds
    legacy = Path("/usr/share/masi-kernel-updater")
    if (packaged / "update.sh").is_file():
        return packaged
    if (legacy / "update.sh").is_file():
        return legacy
    parent = PACKAGE_ROOT.parent
    if (parent / "update.sh").is_file():
        return parent
    if (PACKAGE_ROOT / "update.sh").is_file():
        return PACKAGE_ROOT
    return packaged if packaged.is_dir() else parent


KERNEL_TREE = _detect_kernel_tree()
OUTPUT_DIR = Path(os.environ.get("EASY_KERNEL_OUTPUT", str(KERNEL_TREE / "output")))
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "easy-kernel-updater"
DOWNLOAD_DIR = CACHE_DIR / "downloads"
BUILDS_DIR = CACHE_DIR / "builds"

GITHUB_REPO = os.environ.get(
    "EASY_KERNEL_GITHUB_REPO",
    "MaSieS4Fun/MaSi-OS-Kernel-Updater",
)
GITHUB_API = f"https://api.github.com/repos/{GITHUB_REPO}/releases"
KERNEL_ORG_RELEASES = "https://www.kernel.org/releases.json"

SUPPORTED_SERIES = tuple(
    s.strip()
    for s in os.environ.get("EASY_KERNEL_SERIES", "7.0,6.18").split(",")
    if s.strip()
)

USER_AGENT = f"Easy-Kernel-Updater/{VERSION}"
ICON_NAME = "easy-kernel-updater"
