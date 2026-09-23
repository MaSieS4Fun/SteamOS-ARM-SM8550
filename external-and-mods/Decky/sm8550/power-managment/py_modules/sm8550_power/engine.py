from __future__ import annotations

from typing import Any

from . import hardware
from .config import load_config, save_config
from .fans import fan_tick


def apply_profile(profile_id: str | None = None) -> None:
    config = load_config()
    pid = profile_id or config.get("active_profile", "balanced")
    profile = config["profiles"].get(pid)
    if not profile:
        return

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
