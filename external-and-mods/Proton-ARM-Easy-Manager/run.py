#!/usr/bin/env python3
"""Launcher for Proton ARM Easy Manager."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from proton_arm_easy_manager.__main__ import main

if __name__ == "__main__":
    raise SystemExit(main())
