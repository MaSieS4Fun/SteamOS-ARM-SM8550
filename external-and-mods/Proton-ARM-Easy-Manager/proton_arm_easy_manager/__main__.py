from __future__ import annotations

import argparse
import json
import sys

from . import __app_name__, __version__
from .constants import DEFAULT_INSTALL_DIR
from .github_api import load_source_definitions, probe_sources
from .installer import (
    find_install_path,
    get_install_dir,
    install_release,
    list_installed,
    remove_install,
    repair_installed,
)


def cmd_list_sources(_: argparse.Namespace) -> int:
    available = probe_sources()
    all_defs = load_source_definitions()
    discarded = [s for s in all_defs if s.id not in {a.id for a in available}]
    print(f"ARM sources ({len(available)}):")
    for source in available:
        print(f"  • {source.title}: {len(source.releases)} ARM release(s)")
        for rel in source.releases[:5]:
            print(f"      - {rel.tag}  [{rel.asset_name}]")
        if len(source.releases) > 5:
            print(f"      … {len(source.releases) - 5} more")
    print(f"\nDiscarded (no ARM builds): {', '.join(s.title for s in discarded) or 'none'}")
    return 0


def cmd_list_installed(_: argparse.Namespace) -> int:
    root = get_install_dir()
    print(f"Install dir: {root}")
    installed = list_installed()
    if not installed:
        print("(none)")
        return 0
    for path in installed:
        print(f"  • {path.name} -> {path}")
    return 0


def cmd_install(args: argparse.Namespace) -> int:
    available = probe_sources()
    match = None
    for source in available:
        if args.source and source.id != args.source and source.title.lower() != args.source.lower():
            continue
        for release in source.releases:
            if release.tag == args.tag or release.title == args.tag:
                match = release
                break
        if match:
            break
    if not match:
        print(f"No ARM release found for tag={args.tag!r} source={args.source!r}", file=sys.stderr)
        return 1

    def progress(stage: str, fraction: float) -> None:
        if fraction < 0:
            print(f"\r{stage}…", end="", flush=True)
        else:
            print(f"\r{stage}: {fraction * 100:5.1f}%", end="", flush=True)

    path = install_release(match, progress=progress)
    print(f"\nInstalled to {path}")
    return 0


def cmd_remove(args: argparse.Namespace) -> int:
    available = probe_sources()
    for source in available:
        for release in source.releases:
            if release.tag == args.tag or release.title == args.tag:
                path = find_install_path(release)
                if not path:
                    print("Not installed", file=sys.stderr)
                    return 1
                remove_install(path)
                print(f"Removed {path}")
                return 0
    # Fallback: remove by directory name
    path = get_install_dir() / args.tag
    if path.exists():
        remove_install(path)
        print(f"Removed {path}")
        return 0
    print("Not found", file=sys.stderr)
    return 1


def cmd_repair(_: argparse.Namespace) -> int:
    results = repair_installed()
    if not results:
        print("No installed tools")
        return 0
    for name, flags in results:
        print(f"{name}: {json.dumps(flags)}")
    return 0


def cmd_gui(_: argparse.Namespace) -> int:
    from .ui.window import run_gui

    run_gui()
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="proton-arm-easy-manager",
        description=f"{__app_name__} — install ARM-only Proton builds for Steam/Lutris/Heroic",
    )
    parser.add_argument("--version", action="version", version=f"{__app_name__} {__version__}")
    sub = parser.add_subparsers(dest="command")

    p_gui = sub.add_parser("gui", help="Open the graphical manager (default)")
    p_gui.set_defaults(func=cmd_gui)

    p_sources = sub.add_parser("sources", help="Probe download sources and list ARM releases only")
    p_sources.set_defaults(func=cmd_list_sources)

    p_installed = sub.add_parser("installed", help="List tools in compatibilitytools.d")
    p_installed.set_defaults(func=cmd_list_installed)

    p_install = sub.add_parser("install", help="Install an ARM release by tag")
    p_install.add_argument("tag", help="Release tag, e.g. GE-Proton11-3 or cachyos-11.0-20260703-slr")
    p_install.add_argument("--source", help="Optional source id/title filter")
    p_install.set_defaults(func=cmd_install)

    p_remove = sub.add_parser("remove", help="Remove an installed release by tag or folder name")
    p_remove.add_argument("tag")
    p_remove.set_defaults(func=cmd_remove)

    p_repair = sub.add_parser(
        "repair",
        help="Re-apply ARM fixes (strip require_tool_appid, bin→bin-arm64) on installed tools",
    )
    p_repair.set_defaults(func=cmd_repair)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        args.func = cmd_gui
    print(f"{__app_name__} {__version__}")
    print(f"Target: {get_install_dir()} (default {DEFAULT_INSTALL_DIR})")
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
