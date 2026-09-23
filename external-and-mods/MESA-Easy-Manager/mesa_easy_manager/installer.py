"""Install / restore system libvulkan_freedreno.so via pkexec."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from .constants import LIBRARY_NAME, SYSTEM_LIBRARY
from .local_store import ensure_original_backup, has_original_backup, library_for_version, original_library


class InstallError(RuntimeError):
    pass


def privileged_helper_path() -> Path:
    return Path(__file__).resolve().parent.parent / "scripts" / "mesa_easy_privileged.py"


def _stage_helper_for_pkexec(helper: Path) -> Path:
    """
    Copy the helper to a world-readable temp path.

    AppImage FUSE mounts are often inaccessible to root, so pkexec cannot read
    files from inside the mounted AppImage directly.
    """
    staged = Path(tempfile.gettempdir()) / "mesa-easy-privileged.py"
    shutil.copy2(helper, staged)
    os.chmod(staged, 0o644)
    return staged


def _run_pkexec(action: str, source: Path) -> None:
    helper = privileged_helper_path()
    if not helper.is_file():
        raise InstallError(f"Privileged helper not found: {helper}")

    staged = _stage_helper_for_pkexec(helper)
    cmd = [
        "pkexec",
        sys.executable,
        str(staged),
        action,
        str(source),
        str(SYSTEM_LIBRARY),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        if result.returncode == 126 or "dismissed" in detail.lower():
            raise InstallError("Authentication cancelled.")
        raise InstallError(detail or f"pkexec failed with code {result.returncode}")


def install_version(version: str) -> None:
    """Replace the system Freedreno Vulkan library with a locally stored build."""
    source = library_for_version(version)
    if not source.is_file():
        raise InstallError(f"Missing local library for {version}")

    # Backup once, before the first privileged replace.
    ensure_original_backup()
    _run_pkexec("install", source)


def restore_system_default() -> None:
    """Restore the original system library saved on first change."""
    if not has_original_backup():
        raise InstallError(
            "No original system backup found. "
            f"Expected {original_library()}"
        )
    _run_pkexec("restore", original_library())


def dry_copy_check(source: Path) -> None:
    if not source.is_file():
        raise InstallError(f"Source library missing: {source}")
    if source.name != LIBRARY_NAME:
        raise InstallError(f"Unexpected library name: {source.name}")
