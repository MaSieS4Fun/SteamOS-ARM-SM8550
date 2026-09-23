from __future__ import annotations

import json
import ssl
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from .constants import CACHE_DIR, LUTRIS_API, USER_AGENT


@dataclass
class CoverCandidate:
    title: str
    slug: str
    banner_url: str
    icon_url: str


def _fetch_json(url: str, timeout: float = 15.0) -> object:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
        return json.loads(resp.read().decode("utf-8"))


def search_covers(query: str, limit: int = 12) -> list[CoverCandidate]:
    """Search Lutris public API for game artwork (same source Lutris uses)."""
    query = query.strip()
    if not query:
        return []
    url = f"{LUTRIS_API}?{urllib.parse.urlencode({'search': query})}"
    try:
        payload = _fetch_json(url)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return []

    results: list[CoverCandidate] = []
    if not isinstance(payload, list):
        return results

    for item in payload[:limit]:
        if not isinstance(item, dict):
            continue
        title = str(item.get("name") or "").strip()
        slug = str(item.get("slug") or "").strip()
        if not title:
            continue
        banner = str(item.get("banner") or item.get("poster") or "").strip()
        icon = str(item.get("icon") or banner).strip()
        if not banner and not icon:
            continue
        results.append(CoverCandidate(title=title, slug=slug, banner_url=banner, icon_url=icon))
    return results


def download_cover(url: str, dest: Path) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=20.0, context=ctx) as resp:
        data = resp.read()
    suffix = ".jpg"
    ctype = resp.headers.get("Content-Type", "")
    if "png" in ctype:
        suffix = ".png"
    elif dest.suffix:
        suffix = dest.suffix
    if not dest.suffix:
        dest = dest.with_suffix(suffix)
    dest.write_bytes(data)
    return dest
