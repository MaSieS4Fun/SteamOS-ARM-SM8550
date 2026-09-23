from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable, Optional

from .constants import CACHE_DIR, SOURCES_FILE, USER_AGENT
from .models import Release, Source, pick_arm_asset


ProgressCallback = Callable[[int, Optional[int]], None]


def _request_json(url: str, timeout: int = 60) -> Any:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def load_source_definitions(path: Path | None = None) -> list[Source]:
    path = path or SOURCES_FILE
    data = json.loads(path.read_text(encoding="utf-8"))
    sources: list[Source] = []
    for item in data.get("sources", []):
        sources.append(
            Source(
                id=item["id"],
                title=item["title"],
                description=item.get("description", ""),
                endpoint=item["endpoint"],
                type=item.get("type", "github"),
                homepage=item.get("homepage", ""),
            )
        )
    return sources


def _normalize_forgejo_releases(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in ("data", "releases", "items"):
            if isinstance(payload.get(key), list):
                return payload[key]
    return []


def _asset_download_url(asset: dict[str, Any], fallback_html: str = "") -> str:
    return (
        asset.get("browser_download_url")
        or asset.get("browser_url")
        or asset.get("download_url")
        or asset.get("url")
        or fallback_html
    )


def fetch_arm_releases_for_source(source: Source, per_page: int = 30, pages: int = 2) -> list[Release]:
    """Fetch releases and keep only those with an ARM archive asset.

    Sources with zero ARM releases are considered unsupported for this app.
    """
    releases: list[Release] = []

    if source.type == "github":
        for page in range(1, pages + 1):
            sep = "&" if "?" in source.endpoint else "?"
            url = f"{source.endpoint}{sep}per_page={per_page}&page={page}"
            payload = _request_json(url)
            if not isinstance(payload, list) or not payload:
                break
            for item in payload:
                arm = pick_arm_asset(item.get("assets") or [])
                if not arm:
                    continue
                tag = item.get("tag_name") or item.get("name") or "unknown"
                asset_name = arm.get("name") or ""
                releases.append(
                    Release(
                        source_id=source.id,
                        source_title=source.title,
                        tag=tag,
                        title=tag,
                        description=(item.get("body") or "").strip(),
                        published_at=item.get("published_at") or item.get("created_at") or "",
                        html_url=item.get("html_url") or source.homepage,
                        asset_name=asset_name,
                        download_url=_asset_download_url(arm),
                        size=int(arm.get("size") or 0),
                    )
                )
            if len(payload) < per_page:
                break

    elif source.type == "forgejo":
        # Forgejo API: /repos/{owner}/{repo}/releases
        url = source.endpoint
        if "limit=" not in url:
            sep = "&" if "?" in url else "?"
            url = f"{url}{sep}limit={per_page}"
        payload = _request_json(url)
        for item in _normalize_forgejo_releases(payload):
            assets = item.get("assets") or item.get("attachments") or []
            arm = pick_arm_asset(assets)
            if not arm:
                continue
            tag = item.get("tag_name") or item.get("name") or "unknown"
            asset_name = arm.get("name") or arm.get("filename") or ""
            releases.append(
                Release(
                    source_id=source.id,
                    source_title=source.title,
                    tag=tag,
                    title=tag,
                    description=(item.get("body") or item.get("content") or "").strip(),
                    published_at=item.get("published_at") or item.get("created_at") or "",
                    html_url=item.get("html_url") or item.get("url") or source.homepage,
                    asset_name=asset_name,
                    download_url=_asset_download_url(arm, source.homepage),
                    size=int(arm.get("size") or 0),
                )
            )
    else:
        raise ValueError(f"Unsupported source type: {source.type}")

    return releases


def probe_sources(definitions: list[Source] | None = None) -> list[Source]:
    """Return only sources that currently publish at least one ARM Proton build."""
    definitions = definitions or load_source_definitions()
    available: list[Source] = []
    for source in definitions:
        try:
            source.releases = fetch_arm_releases_for_source(source)
            source.loaded = True
            source.error = ""
        except Exception as exc:  # noqa: BLE001 — surface per-source errors in UI
            source.releases = []
            source.loaded = True
            source.error = str(exc)
        if source.has_arm:
            available.append(source)
    return available


def download_file(
    url: str,
    destination: Path,
    progress: ProgressCallback | None = None,
    cancel_check: Callable[[], bool] | None = None,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".partial")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp, partial.open("wb") as out:
            total = resp.headers.get("Content-Length")
            total_i = int(total) if total and total.isdigit() else None
            done = 0
            while True:
                if cancel_check and cancel_check():
                    raise RuntimeError("Download canceled")
                chunk = resp.read(1024 * 256)
                if not chunk:
                    break
                out.write(chunk)
                done += len(chunk)
                if progress:
                    progress(done, total_i)
        partial.replace(destination)
    except Exception:
        if partial.exists():
            partial.unlink(missing_ok=True)
        raise


def ensure_cache_dir() -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    return CACHE_DIR
