from __future__ import annotations

import glob
import json
import math
import os
import random
import threading
import time
from typing import Any

LEDS_BASE_DIR = "/sys/class/leds"

EXCLUDE_KEYWORDS = (
    "power",
    "batt",
    "charge",
    "charging",
    "disk",
    "mmc",
    "caps",
    "num",
    "scroll",
    "backlight",
    "input",
    "default",
)

DEFAULT_STATE: dict[str, Any] = {
    "enabled": True,
    "brightness": 220,
    "effect": "static",
    "speed": 5,
    "color": [0, 200, 255],
    "secondary_color": [255, 0, 200],
    "sync_zones": True,
    "sticks_color": [0, 200, 255],
    "sides_color": [255, 0, 200],
    "include_power_led": False,
    "sleep_off": True,
}


def settings_file() -> str:
    settings_dir = os.environ.get("DECKY_PLUGIN_SETTINGS_DIR", "/var/lib/steamos-ubuntu")
    return os.path.join(settings_dir, "led-config.json")


def hsv_to_rgb(hue: float, saturation: float = 1.0, value: float = 1.0) -> tuple[int, int, int]:
    """HSV to RGB without colorsys (Decky Python may omit that module)."""
    hue = hue % 1.0
    saturation = max(0.0, min(1.0, saturation))
    value = max(0.0, min(1.0, value))
    h = hue * 6.0
    i = int(h)
    f = h - i
    p = int(255 * value * (1.0 - saturation))
    q = int(255 * value * (1.0 - f * saturation))
    t = int(255 * value * (1.0 - (1.0 - f) * saturation))
    v = int(255 * value)
    if i == 0:
        return v, t, p
    if i == 1:
        return q, v, p
    if i == 2:
        return p, v, t
    if i == 3:
        return p, q, v
    if i == 4:
        return t, p, v
    return v, p, q


class LEDZone:
    def __init__(self, name: str, zone_type: str, data: dict[str, Any]) -> None:
        self.name = name
        self.zone_type = zone_type
        self.data = data

    def write(self, rgb: tuple[int, int, int], brightness: int) -> None:
        if self.zone_type == "multicolor":
            base_path = self.data["path"]
            try:
                with open(os.path.join(base_path, "multi_intensity"), "w", encoding="utf-8") as fh:
                    fh.write(f"{int(rgb[0])} {int(rgb[1])} {int(rgb[2])}")
                with open(os.path.join(base_path, "brightness"), "w", encoding="utf-8") as fh:
                    fh.write(str(int(brightness)))
            except OSError:
                pass
        elif self.zone_type == "discrete":
            factor = brightness / 255.0
            r_val = str(int(max(0, min(255, rgb[0] * factor))))
            g_val = str(int(max(0, min(255, rgb[1] * factor))))
            b_val = str(int(max(0, min(255, rgb[2] * factor))))
            for key, val in (("r", r_val), ("g", g_val), ("b", b_val)):
                for path in self.data.get(key, []):
                    try:
                        with open(os.path.join(path, "brightness"), "w", encoding="utf-8") as fh:
                            fh.write(val)
                    except OSError:
                        pass


class RGBController:
    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.running = False
        self.zones: dict[str, LEDZone] = {}
        self.power_zones: list[LEDZone] = []
        self.state = json.loads(json.dumps(DEFAULT_STATE))
        self.anim_thread: threading.Thread | None = None
        self.discover_all_zones()
        self.load_settings()

    def start_animation(self) -> None:
        if self.anim_thread and self.anim_thread.is_alive():
            self.running = True
            return
        self.running = True
        self.anim_thread = threading.Thread(target=self._animation_loop, daemon=True)
        self.anim_thread.start()

    def stop_animation(self) -> None:
        self.running = False

    def discover_all_zones(self) -> None:
        self.zones = {}
        self.power_zones = []
        if not os.path.isdir(LEDS_BASE_DIR):
            return

        entries = os.listdir(LEDS_BASE_DIR)

        for entry in entries:
            led_path = os.path.join(LEDS_BASE_DIR, entry)
            if not os.path.isfile(os.path.join(led_path, "multi_intensity")):
                continue
            lower = entry.lower()
            if any(k in lower for k in EXCLUDE_KEYWORDS):
                self.power_zones.append(LEDZone(entry, "multicolor", {"path": led_path}))
            else:
                self.zones[entry] = LEDZone(entry, "multicolor", {"path": led_path})

        left_channels: dict[str, list[str]] = {"r": [], "g": [], "b": []}
        right_channels: dict[str, list[str]] = {"r": [], "g": [], "b": []}

        for entry in entries:
            led_path = os.path.join(LEDS_BASE_DIR, entry)
            if os.path.isfile(os.path.join(led_path, "multi_intensity")):
                continue
            lower = entry.lower()
            if any(k in lower for k in EXCLUDE_KEYWORDS):
                continue

            side = None
            if lower.startswith("l:") or lower.startswith("l_") or "left" in lower:
                side = "left"
            elif lower.startswith("r:") or lower.startswith("r_") or "right" in lower:
                side = "right"
            if not side:
                continue

            target = left_channels if side == "left" else right_channels
            if ":r" in lower or "_r" in lower or "red" in lower:
                target["r"].append(led_path)
            elif ":g" in lower or "_g" in lower or "green" in lower:
                target["g"].append(led_path)
            elif ":b" in lower or "_b" in lower or "blue" in lower:
                target["b"].append(led_path)

        if left_channels["r"] or left_channels["g"] or left_channels["b"]:
            self.zones["left-joystick"] = LEDZone("left-joystick", "discrete", left_channels)
        if right_channels["r"] or right_channels["g"] or right_channels["b"]:
            self.zones["right-joystick"] = LEDZone("right-joystick", "discrete", right_channels)

    def load_settings(self) -> None:
        path = settings_file()
        try:
            if os.path.isfile(path):
                with open(path, encoding="utf-8") as fh:
                    data = json.load(fh)
                if isinstance(data, dict):
                    with self.lock:
                        self.state.update(data)
        except (OSError, json.JSONDecodeError):
            pass

    def save_settings(self) -> None:
        path = settings_file()
        try:
            os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
            with self.lock:
                snapshot = dict(self.state)
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(snapshot, fh, indent=2)
        except OSError:
            pass

    def get_public_state(self) -> dict[str, Any]:
        with self.lock:
            out = dict(self.state)
            zones = [
                {
                    "id": name,
                    "name": name.replace("-", " ").title(),
                    "type": zone.zone_type,
                }
                for name, zone in self.zones.items()
            ]
            has_power_led = bool(self.power_zones)
        out["zones"] = zones
        out["has_power_led"] = has_power_led
        out["device_name"] = self._detect_device_name()
        return out

    def _detect_device_name(self) -> str:
        try:
            with open("/sys/firmware/devicetree/base/model", encoding="utf-8") as fh:
                model = fh.read().replace("\x00", " ").strip()
                if model:
                    return model.split(" board")[0].strip()[:48]
        except OSError:
            pass
        return "SM8550 Handheld"

    def apply_to_hardware(
        self,
        per_zone_colors: dict[str, tuple[int, int, int]] | None = None,
        brightness_override: int | None = None,
    ) -> None:
        with self.lock:
            enabled = self.state["enabled"]
            brightness = self.state["brightness"] if brightness_override is None else brightness_override
            include_power = bool(self.state.get("include_power_led", False))
            base_color = tuple(self.state["color"])
            sync = self.state["sync_zones"]
            sticks_color = tuple(self.state["sticks_color"])
            sides_color = tuple(self.state["sides_color"])
            zones = list(self.zones.items())
            power_zones = list(self.power_zones)
            zone_overrides = dict(per_zone_colors) if per_zone_colors else None

        writes: list[tuple[LEDZone, tuple[int, int, int], int]] = []

        if not include_power:
            for pz in power_zones:
                writes.append((pz, (0, 0, 0), 0))
        elif enabled and brightness > 0:
            for pz in power_zones:
                writes.append((pz, base_color, brightness))

        if not enabled or brightness <= 0:
            for _, zone_obj in zones:
                writes.append((zone_obj, (0, 0, 0), 0))
        else:
            for zone_name, zone_obj in zones:
                if zone_overrides and zone_name in zone_overrides:
                    col = zone_overrides[zone_name]
                elif sync:
                    col = base_color
                elif "joystick" in zone_name or "stick" in zone_name:
                    col = sticks_color
                else:
                    col = sides_color
                writes.append((zone_obj, col, brightness))

        for zone_obj, rgb, level in writes:
            zone_obj.write(rgb, level)

    def _battery_level(self) -> int:
        for path in glob.glob("/sys/class/power_supply/*/capacity"):
            try:
                with open(path, encoding="utf-8") as fh:
                    return int(fh.read().strip())
            except (OSError, ValueError):
                pass
        return 100

    def _cpu_temp(self) -> float:
        for path in glob.glob("/sys/class/thermal/thermal_zone*/temp"):
            try:
                with open(path, encoding="utf-8") as fh:
                    value = float(fh.read().strip())
                if value > 1000:
                    value /= 1000.0
                if 20.0 <= value <= 110.0:
                    return value
            except (OSError, ValueError):
                pass
        return 45.0

    def _lerp_rgb(
        self,
        a: tuple[int, int, int],
        b: tuple[int, int, int],
        t: float,
    ) -> tuple[int, int, int]:
        t = max(0.0, min(1.0, t))
        return (
            int(a[0] + (b[0] - a[0]) * t),
            int(a[1] + (b[1] - a[1]) * t),
            int(a[2] + (b[2] - a[2]) * t),
        )

    def _animation_loop(self) -> None:
        step = 0.0
        while self.running:
            try:
                with self.lock:
                    enabled = self.state["enabled"]
                    effect = self.state["effect"]
                    speed = max(1, min(10, int(self.state.get("speed", 5))))
                    brightness = int(self.state["brightness"])
                    zones = list(self.zones.keys())
                    base = tuple(self.state["color"])
                    secondary = tuple(self.state["secondary_color"])

                if not enabled or brightness <= 0 or not zones:
                    time.sleep(0.2)
                    continue

                if effect == "static":
                    self.apply_to_hardware()
                    time.sleep(0.1)
                    continue

                if effect == "breathing":
                    step += 0.02 * (speed / 5.0)
                    factor = 0.15 + 0.85 * ((math.cos(step) + 1.0) / 2.0)
                    self.apply_to_hardware(brightness_override=int(brightness * factor))
                    time.sleep(0.03)
                    continue

                if effect == "rainbow":
                    step = (step + 0.005 * (speed / 5.0)) % 1.0
                    per_zone: dict[str, tuple[int, int, int]] = {}
                    for i, zone in enumerate(zones):
                        hue = (step + i * 0.15) % 1.0
                        per_zone[zone] = hsv_to_rgb(hue)
                    self.apply_to_hardware(per_zone_colors=per_zone)
                    time.sleep(0.03)
                    continue

                if effect == "wave":
                    step += 0.04 * (speed / 5.0)
                    per_zone = {}
                    for i, zone in enumerate(zones):
                        hue = (step + i / max(len(zones), 1)) % 1.0
                        per_zone[zone] = hsv_to_rgb(hue)
                    self.apply_to_hardware(per_zone_colors=per_zone)
                    time.sleep(0.03)
                    continue

                if effect == "gradient":
                    per_zone = {}
                    for i, zone in enumerate(zones):
                        t = i / max(len(zones) - 1, 1)
                        per_zone[zone] = self._lerp_rgb(base, secondary, t)
                    self.apply_to_hardware(per_zone_colors=per_zone)
                    time.sleep(0.1)
                    continue

                if effect == "cycle":
                    step = (step + 0.003 * (speed / 5.0)) % 1.0
                    col = hsv_to_rgb(step)
                    self.apply_to_hardware(per_zone_colors={z: col for z in zones})
                    time.sleep(0.03)
                    continue

                if effect == "sparkle":
                    col = base
                    if random.random() < 0.08 * (speed / 5.0):
                        col = (255, 255, 255)
                    self.apply_to_hardware(per_zone_colors={z: col for z in zones})
                    time.sleep(0.05)
                    continue

                if effect == "comet":
                    step = (step + 0.06 * (speed / 5.0)) % max(len(zones), 1)
                    per_zone = {}
                    for i, zone in enumerate(zones):
                        dist = abs(i - step)
                        fade = max(0.0, 1.0 - dist)
                        per_zone[zone] = (
                            int(base[0] * fade),
                            int(base[1] * fade),
                            int(base[2] * fade),
                        )
                    self.apply_to_hardware(per_zone_colors=per_zone)
                    time.sleep(0.04)
                    continue

                if effect == "battery":
                    cap = self._battery_level()
                    if cap >= 60:
                        col = (0, 255, 60)
                    elif cap >= 25:
                        col = (255, 180, 0)
                    else:
                        step += 0.08
                        pulse = 0.3 + 0.7 * ((math.sin(step * 4) + 1.0) / 2.0)
                        col = (int(255 * pulse), 0, 0)
                    self.apply_to_hardware(per_zone_colors={z: col for z in zones})
                    time.sleep(0.1)
                    continue

                if effect == "temp":
                    temp = self._cpu_temp()
                    if temp < 45.0:
                        col = (0, 200, 255)
                    elif temp < 65.0:
                        ratio = (temp - 45.0) / 20.0
                        col = (int(ratio * 255), int(200 - ratio * 40), int(255 - ratio * 255))
                    else:
                        col = (255, 30, 0)
                    self.apply_to_hardware(per_zone_colors={z: col for z in zones})
                    time.sleep(0.2)
                    continue

                self.apply_to_hardware()
                time.sleep(0.1)
            except Exception:
                time.sleep(0.2)
