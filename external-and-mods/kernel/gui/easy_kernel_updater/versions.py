"""Discover running kernel + local/remote update candidates."""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .constants import (
    BUILDS_DIR,
    GITHUB_API,
    KERNEL_ORG_RELEASES,
    OUTPUT_DIR,
    SUPPORTED_SERIES,
    USER_AGENT,
)


@dataclass(frozen=True)
class KernelCandidate:
    version: str  # e.g. 7.0.14
    label: str
    source: str  # local | github | kernel.org
    path: Path | None = None
    download_url: str | None = None
    asset_name: str | None = None
    newer: bool = False
    current: bool = False

    @property
    def key(self) -> tuple[int, ...]:
        return parse_version_key(self.version)


def parse_version_key(text: str) -> tuple[int, ...]:
    base = text.split("-", 1)[0].strip()
    parts: list[int] = []
    for chunk in base.split("."):
        if chunk.isdigit():
            parts.append(int(chunk))
        else:
            m = re.match(r"(\d+)", chunk)
            parts.append(int(m.group(1)) if m else 0)
    return tuple(parts) if parts else (0,)


def running_release() -> str:
    try:
        return Path("/proc/sys/kernel/osrelease").read_text(encoding="utf-8").strip()
    except OSError:
        return os.uname().release


def running_version() -> str:
    """Numeric version prefix from uname -r (7.0.14-edge-sm8550 → 7.0.14)."""
    return running_release().split("-", 1)[0]


def version_in_supported_series(version: str) -> bool:
    key = parse_version_key(version)
    if len(key) < 2:
        return False
    series = f"{key[0]}.{key[1]}"
    return series in SUPPORTED_SERIES


def is_newer_than_running(version: str) -> bool:
    return parse_version_key(version) > parse_version_key(running_version())


def _http_json(url: str, timeout: float = 45.0) -> object:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/vnd.github+json, application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def list_local_builds(output_dir: Path | None = None) -> list[KernelCandidate]:
    root = output_dir or OUTPUT_DIR
    out: list[KernelCandidate] = []
    if not root.is_dir():
        return out
    for child in sorted(root.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True):
        if not child.is_dir():
            continue
        name = child.name
        if name in {"old_kernel", "meta", ".build", ".install-staging"}:
            continue
        if not (child / "boot" / "KERNEL").is_file():
            continue
        ver = name.split("-", 1)[0]
        out.append(
            KernelCandidate(
                version=ver,
                label=name,
                source="local",
                path=child,
                newer=is_newer_than_running(ver),
                current=parse_version_key(ver) == parse_version_key(running_version()),
            )
        )
    # Also scan cache builds extracted from GitHub
    if BUILDS_DIR.is_dir():
        for child in sorted(BUILDS_DIR.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True):
            if not child.is_dir() or not (child / "boot" / "KERNEL").is_file():
                continue
            ver = child.name.split("-", 1)[0]
            out.append(
                KernelCandidate(
                    version=ver,
                    label=child.name,
                    source="local",
                    path=child,
                    newer=is_newer_than_running(ver),
                    current=parse_version_key(ver) == parse_version_key(running_version()),
                )
            )
    return out


_ASSET_RE = re.compile(
    r"(?P<ver>\d+\.\d+(?:\.\d+)?)[^/]*sm8550[^/]*kbase.*\.(?:tar\.(?:xz|gz|zst)|tgz|zip)$",
    re.IGNORECASE,
)


def list_github_releases() -> list[KernelCandidate]:
    try:
        data = _http_json(GITHUB_API)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError, ValueError):
        return []
    if not isinstance(data, list):
        return []
    out: list[KernelCandidate] = []
    for release in data:
        if not isinstance(release, dict) or release.get("draft"):
            continue
        tag = str(release.get("tag_name") or release.get("name") or "")
        assets = release.get("assets") or []
        if not isinstance(assets, list):
            continue
        for asset in assets:
            if not isinstance(asset, dict):
                continue
            name = str(asset.get("name") or "")
            url = str(asset.get("browser_download_url") or "")
            if not name or not url:
                continue
            m = _ASSET_RE.search(name)
            if not m:
                m2 = re.search(r"(?P<ver>\d+\.\d+\.\d+).*kbase", name, re.I)
                if not m2:
                    continue
                ver = m2.group("ver")
            else:
                ver = m.group("ver")
            if not version_in_supported_series(ver):
                continue
            out.append(
                KernelCandidate(
                    version=ver,
                    label=f"{tag} · {name}" if tag else name,
                    source="github",
                    download_url=url,
                    asset_name=name,
                    newer=is_newer_than_running(ver),
                    current=parse_version_key(ver) == parse_version_key(running_version()),
                )
            )
    seen: set[str] = set()
    uniq: list[KernelCandidate] = []
    for item in sorted(out, key=lambda c: c.key, reverse=True):
        key = f"{item.version}|{item.download_url}"
        if key in seen:
            continue
        seen.add(key)
        uniq.append(item)
    return uniq


def list_armbian_sm8550_series() -> list[str]:
    """Discover Armbian archive patch sets named sm8550-<series>."""
    url = "https://api.github.com/repos/armbian/build/contents/patch/kernel/archive"
    try:
        data = _http_json(url)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError, ValueError):
        return list(SUPPORTED_SERIES)
    if not isinstance(data, list):
        return list(SUPPORTED_SERIES)
    found: list[str] = []
    for item in data:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "")
        m = re.fullmatch(r"sm8550-(\d+\.\d+)", name)
        if m:
            found.append(m.group(1))
    return found or list(SUPPORTED_SERIES)


def list_kernel_org_candidates(limit: int = 16) -> list[KernelCandidate]:
    """Stable/longterm kernel.org versions that match Armbian sm8550-* series."""
    series_list = list_armbian_sm8550_series()
    try:
        data = _http_json(KERNEL_ORG_RELEASES)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError, ValueError):
        data = {}
    versions: list[str] = []
    if isinstance(data, dict):
        latest = data.get("latest_stable")
        if isinstance(latest, dict) and latest.get("version"):
            versions.append(str(latest["version"]))
        for item in data.get("releases") or []:
            if not isinstance(item, dict):
                continue
            if item.get("moniker") not in (None, "stable", "longterm", ""):
                continue
            ver = str(item.get("version") or "")
            if ver:
                versions.append(ver)

    versions.extend(
        [
            "7.0.14",
            "7.0.13",
            "7.0.12",
            "6.18.44",
            "6.18.37",
            "6.18.36",
            "6.18.35",
        ]
    )

    out: list[KernelCandidate] = []
    seen: set[str] = set()
    for ver in versions:
        if ver in seen:
            continue
        key = parse_version_key(ver)
        if len(key) < 2:
            continue
        series = f"{key[0]}.{key[1]}"
        if series not in series_list:
            continue
        seen.add(ver)
        out.append(
            KernelCandidate(
                version=ver,
                label=f"linux-{ver} (build from source · Armbian sm8550-{series})",
                source="kernel.org",
                newer=is_newer_than_running(ver),
                current=parse_version_key(ver) == parse_version_key(running_version()),
            )
        )
        if len(out) >= limit:
            break
    out.sort(key=lambda c: c.key, reverse=True)
    return out


def merge_candidates(
    local: Iterable[KernelCandidate],
    remote: Iterable[KernelCandidate],
    org: Iterable[KernelCandidate],
) -> list[KernelCandidate]:
    """Prefer installable local/github over build-only kernel.org for same version."""
    by_ver: dict[str, KernelCandidate] = {}
    priority = {"local": 3, "github": 2, "kernel.org": 1}
    for item in list(local) + list(remote) + list(org):
        prev = by_ver.get(item.version)
        if prev is None or priority.get(item.source, 0) > priority.get(prev.source, 0):
            by_ver[item.version] = item
    return sorted(by_ver.values(), key=lambda c: c.key, reverse=True)
