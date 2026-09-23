#!/usr/bin/env python3
"""Decky backend — SM8550 handheld RGB LED control."""

from __future__ import annotations

import asyncio
from typing import Any

import decky

from sm8550_led.controller import RGBController


class Plugin:
    def __init__(self) -> None:
        self._controller: RGBController | None = None

    def _ctrl(self) -> RGBController:
        if self._controller is None:
            self._controller = RGBController()
        return self._controller

    async def _main(self) -> None:
        ctrl = self._ctrl()
        decky.logger.info(
            "SM8550 LED: ready (%d zones, settings=%s)",
            len(ctrl.zones),
            ctrl.get_public_state().get("device_name", "?"),
        )
        ctrl.start_animation()
        asyncio.create_task(asyncio.to_thread(ctrl.apply_to_hardware))

    async def _unload(self) -> None:
        if self._controller is None:
            return
        self._controller.stop_animation()
        await asyncio.to_thread(self._controller.apply_to_hardware, None, 0)
        decky.logger.info("SM8550 LED: unloaded")

    async def ping(self, **_: Any) -> dict[str, Any]:
        return {"ok": True}

    async def get_state(self, **_: Any) -> dict[str, Any]:
        return self._ctrl().get_public_state()

    async def set_enabled(self, enabled: bool = True, **_: Any) -> bool:
        ctrl = self._ctrl()
        with ctrl.lock:
            ctrl.state["enabled"] = bool(enabled)
        ctrl.save_settings()
        await asyncio.to_thread(ctrl.apply_to_hardware)
        with ctrl.lock:
            return bool(ctrl.state["enabled"])

    async def set_brightness(self, brightness: int = 0, **_: Any) -> int:
        ctrl = self._ctrl()
        with ctrl.lock:
            ctrl.state["brightness"] = max(0, min(255, int(brightness)))
        ctrl.save_settings()
        await asyncio.to_thread(ctrl.apply_to_hardware)
        with ctrl.lock:
            return int(ctrl.state["brightness"])

    async def set_color(
        self,
        color: list[int] | None = None,
        zone: str = "all",
        **_: Any,
    ) -> list[int]:
        rgb = [max(0, min(255, int(c))) for c in (color or [])[:3]]
        ctrl = self._ctrl()
        with ctrl.lock:
            if zone == "sticks":
                ctrl.state["sticks_color"] = rgb
            elif zone == "sides":
                ctrl.state["sides_color"] = rgb
            else:
                ctrl.state["color"] = rgb
                ctrl.state["sticks_color"] = rgb
                ctrl.state["sides_color"] = rgb
        ctrl.save_settings()
        await asyncio.to_thread(ctrl.apply_to_hardware)
        return rgb

    async def set_secondary_color(self, color: list[int] | None = None, **_: Any) -> list[int]:
        rgb = [max(0, min(255, int(c))) for c in (color or [])[:3]]
        ctrl = self._ctrl()
        with ctrl.lock:
            ctrl.state["secondary_color"] = rgb
        ctrl.save_settings()
        await asyncio.to_thread(ctrl.apply_to_hardware)
        return rgb

    async def set_effect(
        self,
        effect: str = "static",
        speed: int | None = None,
        **_: Any,
    ) -> dict[str, Any]:
        ctrl = self._ctrl()
        with ctrl.lock:
            ctrl.state["effect"] = str(effect)
            if speed is not None:
                ctrl.state["speed"] = max(1, min(10, int(speed)))
            result = {
                "effect": ctrl.state["effect"],
                "speed": ctrl.state["speed"],
            }
        ctrl.save_settings()
        return result

    async def set_sync_zones(self, sync: bool = True, **_: Any) -> bool:
        ctrl = self._ctrl()
        with ctrl.lock:
            ctrl.state["sync_zones"] = bool(sync)
        ctrl.save_settings()
        await asyncio.to_thread(ctrl.apply_to_hardware)
        with ctrl.lock:
            return bool(ctrl.state["sync_zones"])

    async def set_include_power_led(self, include: bool = False, **_: Any) -> bool:
        ctrl = self._ctrl()
        with ctrl.lock:
            ctrl.state["include_power_led"] = bool(include)
        ctrl.save_settings()
        await asyncio.to_thread(ctrl.apply_to_hardware)
        with ctrl.lock:
            return bool(ctrl.state["include_power_led"])

    async def set_sleep_off(self, sleep_off: bool = True, **_: Any) -> bool:
        ctrl = self._ctrl()
        with ctrl.lock:
            ctrl.state["sleep_off"] = bool(sleep_off)
        ctrl.save_settings()
        with ctrl.lock:
            return bool(ctrl.state["sleep_off"])

    async def rediscover_zones(self, **_: Any) -> dict[str, Any]:
        ctrl = self._ctrl()
        with ctrl.lock:
            ctrl.discover_all_zones()
        await asyncio.to_thread(ctrl.apply_to_hardware)
        return ctrl.get_public_state()
