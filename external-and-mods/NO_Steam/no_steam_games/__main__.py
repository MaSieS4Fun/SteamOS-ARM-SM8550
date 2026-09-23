from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __app_name__, __version__
from .steam_paths import shortcuts_path


def cmd_gui(_: argparse.Namespace) -> int:
    from .ui.window import run_gui

    run_gui()
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    from .shortcuts_vdf import add_shortcut, install_grid_art
    from .steam_paths import find_userdata_dir

    sc = shortcuts_path()
    if not sc:
        print("Steam userdata not found", file=sys.stderr)
        return 1
    app_id = add_shortcut(sc, args.name, args.exe)
    if args.cover:
        userdata = find_userdata_dir()
        if userdata:
            install_grid_art(userdata, app_id, args.cover)
    print(f"Added {args.name} appid={app_id}")
    print("Restart Steam. Assign Proton in Steam for .exe games; native ARM binaries launch direct.")
    return 0


def cmd_repair(_: argparse.Namespace) -> int:
    from .shortcuts_vdf import load_shortcuts, repair_shortcut_paths, save_shortcuts

    sc = shortcuts_path()
    if not sc:
        print("Steam userdata not found", file=sys.stderr)
        return 1
    tree = load_shortcuts(sc)
    n = repair_shortcut_paths(tree)
    save_shortcuts(sc, tree)
    print(f"Repaired {n} path field(s) in {sc}")
    print("Restart Steam, then try launching again.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="no-steam-games", description=__app_name__)
    parser.add_argument("--version", action="version", version=f"{__app_name__} {__version__}")
    sub = parser.add_subparsers(dest="command")

    gui = sub.add_parser("gui", help="Open graphical interface (default)")
    gui.set_defaults(func=cmd_gui)

    add = sub.add_parser("add", help="Add shortcut from CLI")
    add.add_argument("name")
    add.add_argument("exe")
    add.add_argument("--cover", type=Path)
    add.set_defaults(func=cmd_add)

    repair = sub.add_parser("repair", help="Fix malformed Exe/StartDir quotes in shortcuts.vdf")
    repair.set_defaults(func=cmd_repair)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        args.func = cmd_gui
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
