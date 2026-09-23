from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Iterable, Optional

from .constants import ARCHIVE_SUFFIXES, ARM_MARKERS, NON_ARCHIVE_SUFFIXES


def is_archive_name(name: str) -> bool:
    lower = name.lower()
    if any(lower.endswith(s) for s in NON_ARCHIVE_SUFFIXES):
        return False
    return any(lower.endswith(s) for s in ARCHIVE_SUFFIXES)


def is_arm_asset_name(name: str) -> bool:
    """Return True only for installable archives that look like ARM builds."""
    if not is_archive_name(name):
        return False
    lower = name.lower()
    # Explicit x86-only names are never ARM, even if somehow tagged oddly.
    if re.search(r"(x86_64|amd64|x64)(?!.*arm)", lower) and not any(m in lower for m in ARM_MARKERS):
        return False
    return any(marker in lower for marker in ARM_MARKERS)


def pick_arm_asset(assets: Iterable[dict[str, Any]]) -> Optional[dict[str, Any]]:
    """Pick the best ARM archive asset from a release asset list."""
    candidates: list[dict[str, Any]] = []
    for asset in assets:
        name = asset.get("name") or asset.get("filename") or ""
        if is_arm_asset_name(name):
            candidates.append(asset)
    if not candidates:
        return None

    def score(asset: dict[str, Any]) -> tuple[int, int]:
        name = (asset.get("name") or asset.get("filename") or "").lower()
        # Prefer tar.xz/tar.gz over zip; prefer aarch64/arm64 wording.
        pref_ext = 0
        if name.endswith(".tar.xz"):
            pref_ext = 3
        elif name.endswith(".tar.gz") or name.endswith(".tgz"):
            pref_ext = 2
        elif name.endswith(".tar.zst"):
            pref_ext = 1
        marker = 2 if ("aarch64" in name or "arm64" in name) else 1
        return (marker, pref_ext)

    candidates.sort(key=score, reverse=True)
    return candidates[0]


def archive_extension(name: str) -> str:
    lower = name.lower()
    for suffix in ARCHIVE_SUFFIXES:
        if lower.endswith(suffix):
            return suffix
    return ""


@dataclass
class Release:
    source_id: str
    source_title: str
    tag: str
    title: str
    description: str
    published_at: str
    html_url: str
    asset_name: str
    download_url: str
    size: int
    install_dir_name: str = ""

    def __post_init__(self) -> None:
        if not self.install_dir_name:
            # Default guess: strip archive suffix from asset name.
            ext = archive_extension(self.asset_name)
            self.install_dir_name = self.asset_name[: -len(ext)] if ext else self.asset_name


@dataclass
class Source:
    id: str
    title: str
    description: str
    endpoint: str
    type: str
    homepage: str = ""
    releases: list[Release] = field(default_factory=list)
    error: str = ""
    loaded: bool = False

    @property
    def has_arm(self) -> bool:
        return bool(self.releases)
