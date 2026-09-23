#!/usr/bin/env python3
"""Root helper: install a prepared kernel build via update.sh."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def resolve_tree() -> Path:
    env = (
        os.environ.get("EASY_KERNEL_TREE", "").strip()
        or os.environ.get("MASI_KERNEL_TREE", "").strip()
    )
    candidates: list[Path] = []
    if env:
        candidates.append(Path(env))
    candidates.append(Path("/usr/share/easy-kernel-updater-runtime"))
    candidates.append(Path("/usr/share/masi-kernel-updater"))  # legacy
    here = Path(__file__).resolve()
    candidates.append(here.parents[2])  # gui/
    candidates.append(here.parents[2].parent)  # kernel root when under gui/

    for path in candidates:
        try:
            resolved = path.resolve()
        except OSError:
            continue
        if (resolved / "update.sh").is_file():
            return resolved
    raise SystemExit(
        "ERROR: kernel tree with update.sh not found. "
        "Set EASY_KERNEL_TREE or install /usr/share/easy-kernel-updater-runtime."
    )


def cmd_install(build: Path) -> int:
    if os.geteuid() != 0:
        print("ERROR: privileged_install must run as root (pkexec/sudo)", file=sys.stderr)
        return 1
    build = build.resolve()
    if not (build / "boot" / "KERNEL").is_file():
        print(f"ERROR: missing {build}/boot/KERNEL", file=sys.stderr)
        return 1

    tree = resolve_tree()
    env = os.environ.copy()
    env["UPDATE_BUILD"] = str(build)
    env["UPDATE_YES"] = "1"
    env["SKIP_REBOOT"] = "1"
    env["OUTPUT_DIR"] = str(tree / "output")
    (tree / "output").mkdir(parents=True, exist_ok=True)

    print(f"==> Installing {build} via {tree}/update.sh", flush=True)
    proc = subprocess.run(
        [str(tree / "update.sh")],
        cwd=str(tree),
        env=env,
        check=False,
    )
    return int(proc.returncode)


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] in {"-h", "--help"}:
        print("Usage: privileged_install.py install <build-dir>")
        return 0
    if args[0] != "install" or len(args) < 2:
        print("Usage: privileged_install.py install <build-dir>", file=sys.stderr)
        return 2
    return cmd_install(Path(args[1]))


if __name__ == "__main__":
    raise SystemExit(main())
