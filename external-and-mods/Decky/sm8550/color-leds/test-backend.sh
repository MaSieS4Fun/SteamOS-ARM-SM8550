#!/usr/bin/env bash
# Quick backend smoke test (run on device, outside Decky).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="${ROOT}/py_modules:${PYTHONPATH:-}"

echo "==> Import controller (no decky/colorsys required)"
python3 -c "
from sm8550_led.controller import RGBController, hsv_to_rgb
assert hsv_to_rgb(0.0) == (255, 0, 0)
c = RGBController()
print('zones:', list(c.zones.keys()))
print('state:', c.get_public_state())
"

echo "OK — controller works. Decky main.py needs the plugin_loader runtime (decky module)."
