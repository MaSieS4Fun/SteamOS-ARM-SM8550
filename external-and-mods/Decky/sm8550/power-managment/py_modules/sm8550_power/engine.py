from __future__ import annotations

import shutil
import subprocess
from typing import Any

from . import hardware
from .config import load_config, save_config
from .fans import fan_tick

NATIVE_PROFILES = {
    "eco": "Basic",
    "balanced": "Balanced",
    "performance": "Performance",
    "gaming": "Performance",
}


def set_native_profile(profile_id: str) -> bool:
    busctl = shutil.which("busctl")
    native = NATIVE_PROFILES.get(profile_id)
    if not busctl or not native:
        return False
    for object_path in ("/com/steampowered/SteamOSManager1", "/"):
        result = subprocess.run(
            [
                busctl,
                "--system",
                "set-property",
                "com.steampowered.SteamOSManager1",
                object_path,
                "com.steampowered.SteamOSManager1.PerformanceProfile1",
                "PerformanceProfile",
                "s",
                native,
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return True
    return False


def apply_profile(profile_id: str | None = None) -> None:
    config = load_config()
    pid = profile_id or config.get("active_profile", "balanced")
    profile = config["profiles"].get(pid)
    if not profile:
        return

    # SteamOS Manager owns the native CPU/GPU profile and permits the active
    # session user to switch it. Keep direct sysfs writes as a compatibility
    # fallback for systems without that interface.
    set_native_profile(pid)
    hardware.set_cpu_governor(str(profile.get("cpu_governor", "schedutil")))
    hardware.set_cpu_limits(profile, config["underclocks"].get("SM8550", {}))
    gpu_pm = "on" if str(profile.get("cpu_governor")) == "performance" else "auto"
    hardware.set_gpu_governor(
        "performance" if str(profile.get("cpu_governor")) == "performance" else "simple_ondemand"
    )
    hardware.set_gpu_freq_range(float(profile.get("gpu_min", 0)), float(profile.get("gpu_max", 1)))
    hardware.set_gpu_pm(gpu_pm)
    hardware.set_ufs_keepalive(bool(profile.get("ufs_keepalive")))


def apply_and_persist(profile_id: str) -> None:
    config = load_config()
    config["active_profile"] = profile_id
    save_config(config)
    apply_profile(profile_id)
