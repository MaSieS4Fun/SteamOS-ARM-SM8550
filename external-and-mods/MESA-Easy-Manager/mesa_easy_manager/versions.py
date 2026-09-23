"""Version helpers and remote release discovery."""

from __future__ import annotations

import re
import urllib.request
from dataclasses import dataclass
from typing import Iterable

from .constants import DEVEL_VERSION, MIN_VERSION, RELNOTES_URL, USER_AGENT


def is_devel(version: str) -> bool:
    return version.strip().lower() == DEVEL_VERSION


def parse_version(text: str) -> tuple[int, int, int]:
    if is_devel(text):
        raise ValueError("devel is not a numeric Mesa version")
    parts = text.strip().split(".")
    if len(parts) != 3:
        raise ValueError(f"Invalid version: {text}")
    return int(parts[0]), int(parts[1]), int(parts[2])


def format_version(version: tuple[int, int, int]) -> str:
    return f"{version[0]}.{version[1]}.{version[2]}"


def version_sort_key(version: str) -> tuple[int, int, int, int]:
    """
    Sort key for UI lists (use with reverse=True).

    devel always sorts above every numeric release.
    """
    if is_devel(version):
        return (1, 0, 0, 0)
    major, minor, patch = parse_version(version)
    return (0, major, minor, patch)


@dataclass(frozen=True)
class RemoteVersion:
    version: str

    @property
    def key(self) -> tuple[int, int, int]:
        return parse_version(self.version)

    @property
    def is_devel(self) -> bool:
        return is_devel(self.version)


def _fetch_text(url: str, timeout: float = 30.0) -> str:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "text/html,application/xhtml+xml"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace")


def fetch_remote_versions(min_version: tuple[int, int, int] = MIN_VERSION) -> list[RemoteVersion]:
    """
    Discover stable Mesa releases from the official release notes index,
    plus a synthetic top entry for the rolling devel git tip.
    """
    html = _fetch_text(RELNOTES_URL)
    found: set[str] = set()

    for match in re.finditer(r"relnotes/(\d+\.\d+\.\d+)\.html", html):
        found.add(match.group(1))

    for match in re.finditer(r"(\d+\.\d+\.\d+)\s+release notes", html, flags=re.IGNORECASE):
        found.add(match.group(1))

    versions: list[RemoteVersion] = [RemoteVersion(version=DEVEL_VERSION)]
    for raw in found:
        try:
            key = parse_version(raw)
        except ValueError:
            continue
        if key >= min_version:
            versions.append(RemoteVersion(version=raw))

    versions.sort(key=lambda item: version_sort_key(item.version), reverse=True)
    return versions


def filter_missing(remote: Iterable[RemoteVersion], local_versions: set[str]) -> list[RemoteVersion]:
    return [item for item in remote if item.version not in local_versions]
