from __future__ import annotations

import argparse
import sys

from . import __app_name__, __version__
from .versions import (
    list_github_releases,
    list_kernel_org_candidates,
    list_local_builds,
    merge_candidates,
    running_release,
    running_version,
)


def cmd_status(_: argparse.Namespace) -> int:
    print(f"Running: {running_release()} (base {running_version()})")
    return 0


def cmd_list(_: argparse.Namespace) -> int:
    rows = merge_candidates(list_local_builds(), list_github_releases(), list_kernel_org_candidates())
    print(f"Running: {running_release()}")
    if not rows:
        print("(no candidates)")
        return 0
    for row in rows:
        flags = []
        if row.current:
            flags.append("current")
        if row.newer:
            flags.append("newer")
        mark = f" [{', '.join(flags)}]" if flags else ""
        print(f"  {row.version:10}  {row.source:10}  {row.label}{mark}")
    return 0


def cmd_gui(_: argparse.Namespace) -> int:
    from .ui import run_gui

    run_gui()
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="easy-kernel-updater",
        description=f"{__app_name__} — SM8550 kernel status and updates",
    )
    parser.add_argument("--version", action="version", version=f"{__app_name__} {__version__}")
    sub = parser.add_subparsers(dest="command")

    p_gui = sub.add_parser("gui", help="Open the graphical manager (default)")
    p_gui.set_defaults(func=cmd_gui)

    p_status = sub.add_parser("status", help="Print the running kernel")
    p_status.set_defaults(func=cmd_status)

    p_list = sub.add_parser("list", help="List local/GitHub/kernel.org candidates")
    p_list.set_defaults(func=cmd_list)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        args.func = cmd_gui
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
