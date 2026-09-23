from __future__ import annotations

import os
from pathlib import Path

from .shortcuts_vdf import emit_binary_vdf, parse_binary_vdf


def steam_home() -> Path:
    for candidate in (
        Path(os.environ.get("STEAM_HOME", "")),
        Path.home() / ".local" / "share" / "Steam",
        Path.home() / ".steam" / "steam",
    ):
        if candidate.is_dir() and (candidate / "steam.sh").exists():
            return candidate
        if candidate.is_dir() and (candidate / "config").exists():
            return candidate
    return Path.home() / ".local" / "share" / "Steam"


def find_userdata_dir() -> Path | None:
    for base in (
        steam_home() / "userdata",
        Path.home() / ".steam" / "steam" / "userdata",
    ):
        if not base.is_dir():
            continue
        candidates = sorted(
            (p for p in base.iterdir() if p.name.isdigit() and p.name != "0"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        for user_dir in candidates:
            if (user_dir / "config").is_dir():
                return user_dir
    return None


def shortcuts_path() -> Path | None:
    userdata = find_userdata_dir()
    if not userdata:
        return None
    return userdata / "config" / "shortcuts.vdf"


def compatibilitytools_dir() -> Path:
    return steam_home() / "compatibilitytools.d"


def list_proton_tools() -> list[tuple[str, str]]:
    """Return (folder_name, label) for Proton installs usable on ARM."""
    tools: list[tuple[str, str]] = []
    compat = compatibilitytools_dir()
    if compat.is_dir():
        for entry in sorted(compat.iterdir(), key=lambda p: p.name.lower()):
            target = entry.resolve() if entry.is_symlink() else entry
            if target.is_dir() and (target / "proton").exists():
                tools.append((entry.name, f"{entry.name} (compatibilitytools.d)"))

    common = steam_home() / "steamapps" / "common"
    if common.is_dir():
        for entry in sorted(common.iterdir(), key=lambda p: p.name.lower()):
            if entry.name.lower().startswith("proton") and (entry / "proton").exists():
                tools.append((entry.name, f"{entry.name} (Steam built-in)"))

    # Prefer Proton 11 / GE-Proton11 names first
    def sort_key(item: tuple[str, str]) -> tuple[int, str]:
        name = item[0].lower()
        if "proton11" in name or "proton_11" in name or name.startswith("proton 11"):
            return (0, name)
        if "ge-proton" in name:
            return (1, name)
        if "proton" in name:
            return (2, name)
        return (9, name)

    tools.sort(key=sort_key)
    seen: set[str] = set()
    unique: list[tuple[str, str]] = []
    for folder, label in tools:
        if folder in seen:
            continue
        seen.add(folder)
        unique.append((folder, label))
    return unique


def localconfig_path() -> Path | None:
    userdata = find_userdata_dir()
    if not userdata:
        return None
    return userdata / "config" / "localconfig.vdf"


def set_compat_tool(app_id: int, tool_name: str) -> bool:
    """Set Proton compat tool for a non-Steam appid in localconfig.vdf."""
    path = localconfig_path()
    if not path or not tool_name:
        return False

    if path.is_file():
        data = path.read_bytes()
        try:
            tree, _ = parse_binary_vdf(data)
        except ValueError:
            return False
    else:
        tree = {}

    software = tree.setdefault("Software", {})
    valve = software.setdefault("Valve", {})
    steam = valve.setdefault("Steam", {})
    mapping = steam.setdefault("CompatToolMapping", {})
    mapping[str(app_id)] = {
        "name": tool_name,
        "config": "",
        "priority": "250",
    }

    path.parent.mkdir(parents=True, exist_ok=True)
    backup = path.with_suffix(".vdf.bak")
    if path.is_file():
        backup.write_bytes(path.read_bytes())
    path.write_bytes(emit_binary_vdf(tree))
    os.chmod(path, 0o644)
    return True
