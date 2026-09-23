#!/usr/bin/env python3
"""Decky backend — SM8550 power, fan curves, and hardware control."""

from __future__ import annotations

import asyncio
from typing import Any

import decky

from sm8550_power.args import coerce_power_patch, coerce_profile_id
from sm8550_power.config import (
    build_config,
    fans_state,
    load_config,
    save_config,
    save_fan_curves,
    update_active_profile,
    update_power,
)
from sm8550_power.engine import apply_profile
from sm8550_power.fans import fan_tick
from sm8550_power import hardware


class Plugin:
    def __init__(self) -> None:
        self._fan_task: asyncio.Task[None] | None = None
        self._fan_stop = asyncio.Event()

    async def _fan_loop(self) -> None:
        while not self._fan_stop.is_set():
            try:
                fan_tick(load_config())
            except Exception as exc:
                decky.logger.warning(f"fan loop: {exc}")
            try:
                await asyncio.wait_for(self._fan_stop.wait(), timeout=3.0)
            except asyncio.TimeoutError:
                continue

    async def _main(self) -> None:
        if not hardware.is_sm8550_platform():
            decky.logger.warning("SM8550 Power: unsupported platform")
            return
        decky.logger.info("SM8550 Power: backend ready")
        await asyncio.to_thread(apply_profile)
        self._fan_stop.clear()
        self._fan_task = asyncio.create_task(self._fan_loop())

    async def _unload(self) -> None:
        self._fan_stop.set()
        if self._fan_task:
            self._fan_task.cancel()
            try:
                await self._fan_task
            except asyncio.CancelledError:
                pass
        decky.logger.info("SM8550 Power: unloaded")

    async def get_config(self) -> dict[str, Any]:
        return await asyncio.to_thread(build_config)

    async def save_power_config(
        self,
        general: dict[str, Any] | None = None,
        profiles: dict[str, Any] | None = None,
        **extra: Any,
    ) -> dict[str, Any]:
        data = coerce_power_patch(general, profiles, extra)
        if not data:
            raise ValueError("invalid power config")
        config = await asyncio.to_thread(update_power, data)
        await asyncio.to_thread(apply_profile)
        return config

    async def set_active_profile(self, profile_id: str = "balanced", **kwargs: Any) -> dict[str, Any]:
        pid = coerce_profile_id(profile_id, **kwargs)
        config = await asyncio.to_thread(update_active_profile, pid)
        await asyncio.to_thread(apply_profile, pid)
        return config

    async def get_fans_state(self) -> dict[str, Any]:
        return await asyncio.to_thread(fans_state)

    async def save_fan_curves(
        self,
        fan_curves: dict[str, Any] | None = None,
        fan_settings: dict[str, Any] | None = None,
        **extra: Any,
    ) -> dict[str, Any]:
        curves = fan_curves
        settings = fan_settings
        if curves is None and isinstance(extra.get("fan_curves"), dict):
            curves = extra["fan_curves"]
        if settings is None and isinstance(extra.get("fan_settings"), dict):
            settings = extra["fan_settings"]
        if curves is None or settings is None:
            raise ValueError("fan_curves and fan_settings are required")
        state = await asyncio.to_thread(save_fan_curves, curves, settings)
        await asyncio.to_thread(apply_profile)
        return state

    async def get_current_temp(self) -> float | None:
        return await asyncio.to_thread(hardware.read_current_temp)

    # Legacy aliases kept for older frontend bundles during upgrade.
    async def get_snapshot(self) -> dict[str, Any]:
        config = await asyncio.to_thread(build_config)
        monitor = config.get("monitor", {})
        return {
            "supported": config.get("supported", False),
            "active_profile": config.get("active_profile", "balanced"),
            **monitor,
        }

    async def get_device_info(self) -> dict[str, Any]:
        config = await asyncio.to_thread(build_config)
        device = config.get("device", {})
        return {
            "name": device.get("name", "SM8550 Handheld"),
            "soc": device.get("soc", "Qualcomm SM8550"),
            "supported": config.get("supported", False),
        }

    async def list_profiles(self) -> list[dict[str, str]]:
        config = await asyncio.to_thread(load_config)
        return [
            {
                "id": pid,
                "label": spec["label"],
                "description": spec.get("cpu_underclock", ""),
            }
            for pid, spec in config["profiles"].items()
        ]

    async def apply_profile(self, profile_id: str = "balanced", gpu_max_mhz: int = 0, **kwargs: Any) -> dict[str, Any]:
        pid = coerce_profile_id(profile_id, **kwargs)
        await self.set_active_profile(pid)
        return {"ok": True, "profile": pid}

    async def set_gpu_cap(self, max_mhz: int = 0, **_: Any) -> dict[str, Any]:
        return {"ok": False, "error": "Use save_power_config GPU sliders"}

    async def set_fan_mode(self, mode: str = "auto", **_: Any) -> dict[str, Any]:
        data = await asyncio.to_thread(load_config)
        data["fan_settings"]["mode"] = mode
        await asyncio.to_thread(save_config, data)
        return {"ok": True, "mode": mode}

    async def set_fan_level(self, level: int = 0, **_: Any) -> dict[str, Any]:
        data = await asyncio.to_thread(load_config)
        data["fan_settings"]["mode"] = "manual"
        data["fan_settings"]["manual_level"] = int(level)
        await asyncio.to_thread(save_config, data)
        return {"ok": True, "level": level}
