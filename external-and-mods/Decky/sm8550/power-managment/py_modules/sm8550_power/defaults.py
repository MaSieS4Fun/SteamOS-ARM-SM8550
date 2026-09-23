from __future__ import annotations

from copy import deepcopy
from typing import Any

SOC_CLASS = "SM8550"

FACTORY: dict[str, Any] = {
    "active_profile": "balanced",
    "general": {"default_profile": "balanced"},
    "profiles": {
        "eco": {
            "label": "Eco",
            "cpu_governor": "schedutil",
            "cpu_max": 0.65,
            "cpu_underclock": "large",
            "gpu_max": 0.80,
            "gpu_min": 0.0,
            "fan_curve": "relaxed",
            "ufs_keepalive": False,
        },
        "balanced": {
            "label": "Balanced",
            "cpu_governor": "schedutil",
            "cpu_max": 0.65,
            "cpu_underclock": "medium",
            "gpu_max": 1.0,
            "gpu_min": 0.0,
            "fan_curve": "moderate",
            "ufs_keepalive": False,
        },
        "performance": {
            "label": "Performance",
            "cpu_governor": "performance",
            "cpu_max": 1.0,
            "cpu_underclock": "none",
            "gpu_max": 1.0,
            "gpu_min": 1.0,
            "fan_curve": "aggressive",
            "ufs_keepalive": False,
        },
        "gaming": {
            "label": "Gaming",
            "cpu_governor": "performance",
            "cpu_max": 1.0,
            "cpu_underclock": "none",
            "gpu_max": 1.0,
            "gpu_min": 1.0,
            "fan_curve": "aggressive",
            "ufs_keepalive": True,
        },
    },
    "fan_curves": {
        "relaxed": {
            "label": "Relaxed",
            "curve": "98:255,94:204,88:153,82:102,76:77,65:51,0:51",
        },
        "moderate": {
            "label": "Moderate",
            "curve": "96:255,90:204,84:153,78:102,72:77,55:51,0:51",
        },
        "aggressive": {
            "label": "Aggressive",
            "curve": "90:255,85:204,80:153,74:102,66:77,45:51,0:51",
        },
    },
    "fan_settings": {
        "mode": "auto",
        "manual_level": 4,
        "ramp_up": 36,
        "ramp_down": 6,
        "smoothing": 0.50,
        "min_pwm": 51,
    },
    "underclocks": {
        "SM8550": {
            "small": {
                "policy0": 1785600,
                "policy3": 2323200,
                "policy7": 2476800,
            },
            "medium": {
                "policy0": 1555200,
                "policy3": 2054400,
                "policy7": 2092800,
            },
            "large": {
                "policy0": 1459200,
                "policy3": 1785600,
                "policy7": 1843200,
            },
        }
    },
}

PROFILE_IDS = tuple(FACTORY["profiles"].keys())
