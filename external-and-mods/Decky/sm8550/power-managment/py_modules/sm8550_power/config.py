from __future__ import annotations

import json
import os
from copy import deepcopy
from typing import Any

from .defaults import FACTORY, PROFILE_IDS, SOC_CLASS

STATE_DIR = "/var/lib/steamos-ubuntu"
CONFIG_FILE = f"{STATE_DIR}/power-config.json"
LEGACY_PROFILE_FILE = f"{STATE_DIR}/power-profile"

_LEGACY_MAP = {
    "power": "eco",
    "balanced": "balanced",
    "performance": "performance",
    "gaming": "gaming",
}


def _deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    out = deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _deep_merge(out[key], value)
        else:
            out[key] = deepcopy(value)
    return out


def _migrate_legacy(data: dict[str, Any]) -> dict[str, Any]:
    if os.path.isfile(LEGACY_PROFILE_FILE):
        legacy = open(LEGACY_PROFILE_FILE, encoding="utf-8").read().strip()
        mapped = _LEGACY_MAP.get(legacy)
        if mapped:
            data["active_profile"] = mapped
    return data


def load_config() -> dict[str, Any]:
    data = deepcopy(FACTORY)
    if os.path.isfile(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, encoding="utf-8") as fh:
                stored = json.load(fh)
            if isinstance(stored, dict):
                data = _deep_merge(data, stored)
        except (OSError, json.JSONDecodeError):
            pass
    data = _migrate_legacy(data)
    if data.get("active_profile") not in PROFILE_IDS:
        data["active_profile"] = "balanced"
    return data


def save_config(data: dict[str, Any]) -> dict[str, Any]:
    os.makedirs(STATE_DIR, mode=0o755, exist_ok=True)
    with open(CONFIG_FILE, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return load_config()


def factory_config() -> dict[str, Any]:
    return deepcopy(FACTORY)


def build_config() -> dict[str, Any]:
    from . import hardware

    data = load_config()
    governors = [g for g in hardware.cpu_available_governors() if g != "userspace"]
    return {
        "supported": hardware.is_sm8550_platform(),
        "device": {
            "name": hardware.detect_device_name(),
            "soc": "Qualcomm SM8550 · Snapdragon 8 Gen 2",
        },
        "active_profile": data["active_profile"],
        "power": {
            "general": data["general"],
            "profiles": data["profiles"],
            "fan_curves": data["fan_curves"],
            "underclocks": data["underclocks"],
        },
        "power_defaults": factory_config()["profiles"],
        "fan_settings": data["fan_settings"],
        "fan_defaults": factory_config()["fan_settings"],
        "perf": {
            "governors": governors,
            "cpu_device_class": SOC_CLASS,
        },
        "monitor": hardware.monitor_snapshot(),
        "current_temp": hardware.read_current_temp(),
    }


def update_power(power_patch: dict[str, Any]) -> dict[str, Any]:
    data = load_config()
    if "general" in power_patch:
        data["general"].update(power_patch["general"])
    if "profiles" in power_patch:
        for pid, profile in power_patch["profiles"].items():
            if pid in data["profiles"] and isinstance(profile, dict):
                data["profiles"][pid].update(profile)
    save_config(data)
    return build_config()


def update_active_profile(profile_id: str) -> dict[str, Any]:
    if profile_id not in PROFILE_IDS:
        raise ValueError(f"unknown profile: {profile_id}")
    data = load_config()
    data["active_profile"] = profile_id
    save_config(data)
    return build_config()


def fans_state() -> dict[str, Any]:
    from . import hardware

    data = load_config()
    profiles = {
        pid: {
            "label": spec["label"],
            "fan_curve": spec.get("fan_curve", ""),
        }
        for pid, spec in data["profiles"].items()
    }
    return {
        "fan_curves": data["fan_curves"],
        "factory_fan_curves": factory_config()["fan_curves"],
        "fan_settings": data["fan_settings"],
        "factory_fan_settings": factory_config()["fan_settings"],
        "profiles": profiles,
        "active_profile": data["active_profile"],
        "current_temp": hardware.read_current_temp(),
    }


def save_fan_curves(fan_curves: dict[str, Any], fan_settings: dict[str, Any]) -> dict[str, Any]:
    data = load_config()
    if not isinstance(fan_curves, dict) or not fan_curves:
        raise ValueError("at least one fan curve is required")
    data["fan_curves"] = fan_curves
    if isinstance(fan_settings, dict):
        data["fan_settings"].update(fan_settings)
    save_config(data)
    return fans_state()
