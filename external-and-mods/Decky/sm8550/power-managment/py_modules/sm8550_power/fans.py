from __future__ import annotations

import re
from typing import Any

from . import hardware

CURVE_POINT_RE = re.compile(r"^-?\d{1,3}:\d{1,3}$")
_last_pwm = 0
_smoothed_temp: float | None = None


def parse_curve(value: str) -> list[tuple[int, int]]:
    points = []
    for item in str(value or "").split(","):
        item = item.strip()
        if not CURVE_POINT_RE.match(item):
            continue
        temp_s, pwm_s = item.split(":", 1)
        points.append((int(temp_s), int(pwm_s)))
    points.sort(key=lambda p: p[0])
    return points


def format_curve(points: list[tuple[int, int]]) -> str:
    return ",".join(f"{temp}:{pwm}" for temp, pwm in sorted(points, key=lambda p: p[0]))


def interpolate_pwm(temp: float, points: list[tuple[int, int]]) -> int:
    if not points:
        return 0
    if temp <= points[0][0]:
        return points[0][1]
    if temp >= points[-1][0]:
        return points[-1][1]
    for idx in range(len(points) - 1):
        t0, p0 = points[idx]
        t1, p1 = points[idx + 1]
        if t0 <= temp <= t1:
            if t1 == t0:
                return p0
            ratio = (temp - t0) / (t1 - t0)
            return int(round(p0 + ratio * (p1 - p0)))
    return points[-1][1]


def fan_tick(config: dict[str, Any]) -> None:
    global _last_pwm, _smoothed_temp
    settings = config.get("fan_settings", {})
    mode = settings.get("mode", "auto")
    if mode == "manual":
        level = int(settings.get("manual_level", 4))
        max_level = hardware.read_fan_state().get("max_level", 7) or 7
        pwm = int(round(level / max_level * 255)) if max_level else 0
        hardware.set_fan_pwm(max(pwm, int(settings.get("min_pwm", 0))))
        _last_pwm = pwm
        return

    active = config.get("active_profile", "balanced")
    profile = config.get("profiles", {}).get(active, {})
    curve_name = profile.get("fan_curve", "moderate")
    curve_def = config.get("fan_curves", {}).get(curve_name, {})
    points = parse_curve(curve_def.get("curve", ""))
    if not points:
        return

    temp = hardware.read_current_temp()
    if temp is None:
        return

    smoothing = float(settings.get("smoothing", 0.5))
    if _smoothed_temp is None:
        _smoothed_temp = temp
    else:
        _smoothed_temp = _smoothed_temp * smoothing + temp * (1.0 - smoothing)

    target = interpolate_pwm(_smoothed_temp, points)
    min_pwm = int(settings.get("min_pwm", 51))
    if any(p[1] == 0 for p in points[:1]):
        min_pwm = 0
    target = max(target, min_pwm)

    ramp_up = int(settings.get("ramp_up", 36))
    ramp_down = int(settings.get("ramp_down", 6))
    if target > _last_pwm:
        next_pwm = min(target, _last_pwm + ramp_up)
    elif target < _last_pwm:
        next_pwm = max(target, _last_pwm - ramp_down)
    else:
        next_pwm = target

    hardware.set_fan_pwm(next_pwm)
    _last_pwm = next_pwm
