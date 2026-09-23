#!/usr/bin/env python3
"""Privileged helper for MESA Easy Manager.

Invoked only via pkexec when replacing / restoring
libvulkan_freedreno.so on SteamOS (/usr/lib) or Debian multiarch.

Usage:
  mesa_easy_privileged.py install|restore <source> <destination>
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path


ALLOWED_DESTS = {
    Path("/usr/lib/libvulkan_freedreno.so"),
    Path("/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so"),
    Path("/usr/lib64/libvulkan_freedreno.so"),
}
ALLOWED_NAME = "libvulkan_freedreno.so"


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def main(argv: list[str]) -> int:
    if os.geteuid() != 0:
        fail("This helper must run as root (via pkexec).", 2)

    if len(argv) != 4:
        fail("Usage: mesa_easy_privileged.py install|restore <source> <destination>")

    action, source_s, dest_s = argv[1], argv[2], argv[3]
    source = Path(source_s).resolve()
    destination = Path(dest_s).resolve()

    if action not in {"install", "restore"}:
        fail(f"Unknown action: {action}")

    if destination not in ALLOWED_DESTS:
        fail(f"Refusing destination outside allowed path: {destination}")

    if source.name != ALLOWED_NAME:
        fail(f"Refusing unexpected source name: {source.name}")

    if not source.is_file():
        fail(f"Source library not found: {source}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    tmp = destination.with_suffix(destination.suffix + ".tmp")
    shutil.copy2(source, tmp)
    os.chmod(tmp, 0o755)
    os.replace(tmp, destination)
    print(f"{action}: installed {source} -> {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
