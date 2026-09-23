"""Local ~/MESA-Drivers store and active-driver detection."""

from __future__ import annotations

import hashlib
import os
import shutil
from dataclasses import dataclass
from pathlib import Path

from .constants import (
    DRIVERS_DIR,
    LIBRARY_NAME,
    ORIGINAL_DIR,
    SYSTEM_LIBRARY,
    ensure_drivers_dir,
    original_library,
    version_library,
)
from .versions import is_devel, parse_version, version_sort_key


def file_sha256(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


@dataclass(frozen=True)
class LocalVersion:
    version: str
    path: Path

    @property
    def library(self) -> Path:
        return self.path / LIBRARY_NAME

    @property
    def available(self) -> bool:
        return self.library.is_file()


def list_local_versions() -> list[LocalVersion]:
    ensure_drivers_dir()
    versions: list[LocalVersion] = []
    if not DRIVERS_DIR.is_dir():
        return versions

    for entry in DRIVERS_DIR.iterdir():
        if not entry.is_dir():
            continue
        if entry.name == ORIGINAL_DIR.name:
            continue
        if is_devel(entry.name):
            pass
        else:
            try:
                parse_version(entry.name)
            except ValueError:
                continue
        candidate = LocalVersion(version=entry.name, path=entry)
        if candidate.available:
            versions.append(candidate)

    versions.sort(key=lambda item: version_sort_key(item.version), reverse=True)
    return versions


def local_version_set() -> set[str]:
    return {item.version for item in list_local_versions()}


def has_original_backup() -> bool:
    return original_library().is_file()


def ensure_original_backup() -> Path:
    """
    Backup the current system library the first time a change is applied.

    Reading the system library does not require elevated privileges.
    """
    ensure_drivers_dir()
    ORIGINAL_DIR.mkdir(parents=True, exist_ok=True)
    destination = original_library()
    if destination.is_file():
        return destination

    if not SYSTEM_LIBRARY.is_file():
        raise FileNotFoundError(f"System library not found: {SYSTEM_LIBRARY}")

    shutil.copy2(SYSTEM_LIBRARY, destination)
    return destination


def detect_active_source() -> str | None:
    """
    Return a label describing which stored library matches the system file.

    Possible values:
      - "original-system-lib"
      - "<version>"
      - None if unknown / missing system library
    """
    if not SYSTEM_LIBRARY.is_file():
        return None

    try:
        system_hash = file_sha256(SYSTEM_LIBRARY)
    except OSError:
        return None

    if has_original_backup():
        try:
            if file_sha256(original_library()) == system_hash:
                return "original-system-lib"
        except OSError:
            pass

    for local in list_local_versions():
        try:
            if file_sha256(local.library) == system_hash:
                return local.version
        except OSError:
            continue

    return None


def store_compiled_library(version: str, source_library: Path) -> Path:
    ensure_drivers_dir()
    target_dir = DRIVERS_DIR / version
    target_dir.mkdir(parents=True, exist_ok=True)
    destination = target_dir / LIBRARY_NAME
    shutil.copy2(source_library, destination)
    os.chmod(destination, 0o755)
    return destination


def library_for_version(version: str) -> Path:
    path = version_library(version)
    if not path.is_file():
        raise FileNotFoundError(f"Local library not found for {version}: {path}")
    return path
