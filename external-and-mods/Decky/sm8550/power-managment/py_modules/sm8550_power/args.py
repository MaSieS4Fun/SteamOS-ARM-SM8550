from __future__ import annotations

from typing import Any


def coerce_profile_id(value: Any, **kwargs: Any) -> str:
    """Decky callables may pass profile_id as a kwarg or as a single dict arg."""
    if isinstance(value, str) and value:
        return value
    if isinstance(value, dict):
        for key in ("profile_id", "id", "profile"):
            item = value.get(key)
            if isinstance(item, str) and item:
                return item
    for key in ("profile_id", "id", "profile"):
        item = kwargs.get(key)
        if isinstance(item, str) and item:
            return item
    return "balanced"


def coerce_power_patch(
    general: dict[str, Any] | None,
    profiles: dict[str, Any] | None,
    extra: dict[str, Any],
) -> dict[str, Any]:
    data: dict[str, Any] = {}
    if isinstance(extra.get("data"), dict):
        data.update(extra["data"])

    if isinstance(general, dict) and profiles is None and (
        "profiles" in general or "general" in general
    ):
        patch = general
        if isinstance(patch.get("general"), dict):
            data["general"] = patch["general"]
        if isinstance(patch.get("profiles"), dict):
            data["profiles"] = patch["profiles"]
        return data

    if general is not None:
        data["general"] = general
    if profiles is not None:
        data["profiles"] = profiles
    return data
