from __future__ import annotations

import glob
import os
import re
from typing import Any

UFS_HOST = "/sys/devices/platform/soc@0/1d84000.ufshc"
GPU_DEVFREQ_GLOBS = (
    "/sys/class/devfreq/*gpu*",
    "/sys/class/devfreq/3d00000.gpu",
    "/sys/devices/platform/soc@0/3d00000.gpu/devfreq/*",
)
GPU_PM_GLOBS = (
    "/sys/devices/platform/soc@0/3d00000.gpu/power/control",
    "/sys/devices/platform/soc@0/3d00000.gmu/power/control",
    "/sys/bus/platform/devices/3d00000.gpu/power/control",
    "/sys/bus/platform/devices/3d00000.gmu/power/control",
)
FAN_PWM_PATH = "/sys/class/hwmon/hwmon40/pwm1"
FAN_PWM_ENABLE_PATH = "/sys/class/hwmon/hwmon40/pwm1_enable"
FAN_RPM_PATH = "/sys/class/hwmon/hwmon40/fan1_input"

CPU_GOV_FALLBACK = {
    "schedutil": ("ondemand", "interactive"),
    "simple_ondemand": ("ondemand", "userspace"),
    "powersave": ("ondemand",),
    "performance": ("ondemand",),
}
GPU_GOV_FALLBACK = {
    "simple_ondemand": ("ondemand", "userspace"),
    "powersave": ("simple_ondemand", "ondemand"),
    "performance": ("simple_ondemand", "ondemand"),
}

KNOWN_DEVICES = (
    ("ayn-odin", "AYN Odin 2"),
    ("odin2", "AYN Odin 2"),
    ("odin-2", "AYN Odin 2"),
    ("qcs8550-ayn", "AYN Handheld"),
    ("thor", "AYN Thor"),
    ("portal", "AYN Portal"),
    ("retroid", "Retroid Pocket 6"),
    ("rp6", "Retroid Pocket 6"),
    ("rp-6", "Retroid Pocket 6"),
    ("qcm8550", "SM8550 Handheld"),
    ("sm8550", "SM8550 Handheld"),
)


def read(path: str, default: str = "") -> str:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return default


def read_int(path: str, default: int = 0) -> int:
    raw = read(path)
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def write(path: str, value: str) -> bool:
    try:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(value)
        return True
    except OSError:
        return False


def dt_strings() -> str:
    parts = []
    for path in (
        "/sys/firmware/devicetree/base/model",
        "/sys/firmware/devicetree/base/compatible",
    ):
        raw = read(path)
        if raw:
            parts.append(raw.replace("\x00", " ").lower())
    return " ".join(parts)


def is_sm8550_platform() -> bool:
    blob = dt_strings()
    if "sm8550" in blob or "qcm8550" in blob or "qcs8550" in blob:
        return True
    return bool(gpu_base() and glob.glob("/sys/devices/system/cpu/cpufreq/policy*"))


def detect_device_name() -> str:
    env_name = os.environ.get("STEAMOS_DEVICE_NAME", "").strip()
    if env_name:
        return env_name
    blob = dt_strings()
    for needle, label in KNOWN_DEVICES:
        if needle in blob:
            return label
    model = read("/sys/firmware/devicetree/base/model").replace("\x00", " ").strip()
    if model:
        return model.split(" board")[0].strip()[:48]
    return "SM8550 Handheld"


def gpu_base() -> str | None:
    for pattern in GPU_DEVFREQ_GLOBS:
        for path in sorted(glob.glob(pattern)):
            if os.path.isdir(path) and os.path.isfile(f"{path}/governor"):
                return path
    return None


def gpu_pm_paths() -> list[str]:
    return [p for p in GPU_PM_GLOBS if os.path.isfile(p)]


def cpu_available_governors() -> list[str]:
    for pol in sorted(glob.glob("/sys/devices/system/cpu/cpufreq/policy*")):
        avail = read(f"{pol}/scaling_available_governors").split()
        if avail:
            return avail
    return read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors").split()


def pick_governor(preferred: str, available: list[str], fallbacks: dict[str, tuple[str, ...]]) -> str:
    if preferred in available:
        return preferred
    for alt in fallbacks.get(preferred, ()):
        if alt in available:
            return alt
    return available[0] if available else preferred


def set_cpu_governor(governor: str) -> None:
    avail = cpu_available_governors()
    chosen = pick_governor(governor, avail, CPU_GOV_FALLBACK)
    for gov in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"):
        write(gov, chosen)


def set_gpu_governor(governor: str) -> None:
    base = gpu_base()
    if not base:
        return
    avail = read(f"{base}/available_governors").split()
    chosen = pick_governor(governor, avail, GPU_GOV_FALLBACK)
    write(f"{base}/governor", chosen)


def set_gpu_freq_range(gpu_min_ratio: float, gpu_max_ratio: float) -> None:
    base = gpu_base()
    if not base:
        return
    avail = read(f"{base}/available_frequencies").split()
    freqs = sorted(int(x) for x in avail if x.isdigit())
    if not freqs:
        return
    min_hz = freqs[0]
    max_hz = freqs[-1]
    span = max_hz - min_hz
    cap_min = min_hz + int(span * max(0.0, min(1.0, gpu_min_ratio)))
    cap_max = min_hz + int(span * max(0.0, min(1.0, gpu_max_ratio)))
    if cap_min > cap_max:
        cap_min = cap_max
    write(f"{base}/min_freq", str(cap_min))
    write(f"{base}/max_freq", str(cap_max))


def set_gpu_pm(mode: str) -> None:
    for path in gpu_pm_paths():
        write(path, mode)


def set_ufs_keepalive(enabled: bool) -> None:
    if not os.path.isdir(UFS_HOST):
        return
    if enabled:
        write(f"{UFS_HOST}/power/control", "on")
        for name in ("clkgate_enable", "clkscale_enable"):
            p = f"{UFS_HOST}/{name}"
            if os.path.isfile(p):
                write(p, "0")
        for host in glob.glob("/sys/class/scsi_host/host*/power/control"):
            write(host, "on")
        for power in glob.glob("/sys/block/sd*/device/power/control"):
            write(power, "on")
    else:
        for name in ("clkgate_enable", "clkscale_enable"):
            p = f"{UFS_HOST}/{name}"
            if os.path.isfile(p):
                write(p, "1")
        if os.path.isfile(f"{UFS_HOST}/power/control"):
            write(f"{UFS_HOST}/power/control", "auto")


def set_cpu_limits(profile: dict[str, Any], underclocks: dict[str, Any]) -> None:
    underclock = str(profile.get("cpu_underclock") or "none")
    cpu_max = float(profile.get("cpu_max") or 1.0)
    caps = underclocks.get(underclock) if underclock != "none" else None
    for pol in sorted(glob.glob("/sys/devices/system/cpu/cpufreq/policy*")):
        pol_id = os.path.basename(pol)
        max_hz = read_int(f"{pol}/cpuinfo_max_freq")
        if max_hz <= 0:
            continue
        if caps and pol_id in caps:
            target = int(caps[pol_id])
        else:
            target = int(max_hz * cpu_max)
        write(f"{pol}/scaling_max_freq", str(min(target, max_hz)))
        write(f"{pol}/scaling_min_freq", str(read_int(f"{pol}/cpuinfo_min_freq", 0)))


def find_fan_cdev() -> str | None:
    for idx in range(16):
        cdev = f"/sys/class/thermal/cooling_device{idx}"
        if "fan" in read(f"{cdev}/type").lower():
            return cdev
    return None


def set_fan_pwm(pwm: int) -> None:
    pwm = max(0, min(255, int(pwm)))
    cdev = find_fan_cdev()
    if cdev:
        max_level = read_int(f"{cdev}/max_state", 7)
        if max_level > 0 and os.path.isfile(FAN_PWM_ENABLE_PATH):
            write(FAN_PWM_ENABLE_PATH, "1")
            level = int(round(pwm / 255 * max_level))
            write(f"{cdev}/cur_state", str(level))
    if os.path.isfile(FAN_PWM_PATH):
        if os.path.isfile(FAN_PWM_ENABLE_PATH):
            write(FAN_PWM_ENABLE_PATH, "1")
        write(FAN_PWM_PATH, str(pwm))


def set_fan_auto() -> None:
    if os.path.isfile(FAN_PWM_ENABLE_PATH):
        write(FAN_PWM_ENABLE_PATH, "2")


def read_fan_state() -> dict[str, Any]:
    cdev = find_fan_cdev()
    if not cdev:
        return {"present": False}
    return {
        "present": True,
        "level": read_int(f"{cdev}/cur_state"),
        "max_level": read_int(f"{cdev}/max_state", 7),
        "rpm": read_int(FAN_RPM_PATH),
        "pwm": read_int(FAN_PWM_PATH),
    }


def read_current_temp() -> float | None:
    temps = []
    for path in sorted(glob.glob("/sys/class/thermal/thermal_zone*")):
        name = read(f"{path}/type")
        if not name:
            continue
        if not re.search(r"cpu|gpu|gpuss|video|mem|soc|pm8550", name, re.I):
            continue
        temp = read_int(f"{path}/temp")
        if temp <= 0:
            continue
        temp_c = temp / 1000.0 if temp > 1000 else float(temp)
        temps.append(temp_c)
    if not temps:
        return None
    temps.sort(reverse=True)
    top = temps[:3]
    return round(sum(top) / len(top), 1)


def monitor_snapshot() -> dict[str, Any]:
    base = gpu_base()
    gpu: dict[str, Any] = {}
    if base:
        freqs_mhz = []
        for x in read(f"{base}/available_frequencies").split():
            if x.isdigit():
                mhz = int(x) // 1_000_000
                if mhz > 0:
                    freqs_mhz.append(mhz)
        gpu = {
            "governor": read(f"{base}/governor"),
            "cur_mhz": read_int(f"{base}/cur_freq") // 1000,
            "min_mhz": read_int(f"{base}/min_freq") // 1000,
            "max_mhz": read_int(f"{base}/max_freq") // 1000,
            "available_mhz": sorted(set(freqs_mhz)),
            "runtime_pm": read(gpu_pm_paths()[0]) if gpu_pm_paths() else "",
        }

    cpus = []
    for pol in sorted(glob.glob("/sys/devices/system/cpu/cpufreq/policy*")):
        max_hz = read_int(f"{pol}/cpuinfo_max_freq")
        label = "Prime"
        if max_hz <= 2_100_000_000:
            label = "Little"
        elif max_hz <= 2_900_000_000:
            label = "Mid"
        cpus.append(
            {
                "id": os.path.basename(pol),
                "label": label,
                "governor": read(f"{pol}/scaling_governor"),
                "cur_mhz": read_int(f"{pol}/scaling_cur_freq") // 1000,
                "max_mhz": max_hz // 1000,
            }
        )

    battery: dict[str, Any] = {"present": False}
    bat = "/sys/class/power_supply/battery"
    if os.path.isdir(bat):
        power_uw = read_int(f"{bat}/power_now")
        battery = {
            "present": True,
            "capacity": read_int(f"{bat}/capacity"),
            "status": read(f"{bat}/status"),
            "power_w": round(power_uw / 1_000_000, 2) if power_uw else 0.0,
        }

    thermals = []
    for path in sorted(glob.glob("/sys/class/thermal/thermal_zone*")):
        name = read(f"{path}/type")
        if not name:
            continue
        if not re.search(r"cpu|gpu|gpuss|soc|battery|pm8550|video|mem", name, re.I):
            continue
        temp = read_int(f"{path}/temp")
        temp_c = temp / 1000.0 if temp > 1000 else float(temp)
        thermals.append({"name": name, "temp_c": round(temp_c, 1)})
    thermals.sort(key=lambda t: t["temp_c"], reverse=True)

    return {
        "gpu": gpu,
        "cpus": cpus,
        "battery": battery,
        "thermals": thermals[:8],
        "fan": read_fan_state(),
        "ufs_keepalive": read(f"{UFS_HOST}/clkgate_enable", "1") == "0"
        if os.path.isdir(UFS_HOST)
        else False,
    }
