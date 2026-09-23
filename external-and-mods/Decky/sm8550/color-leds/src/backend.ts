import { callable } from "@decky/api";
import type { LedState, LedZone, LedZoneInfo } from "./types";
import { DEFAULT_LED_STATE } from "./types";

export const getState = callable<[], LedState>("get_state");
export const setEnabled = callable<[boolean], boolean>("set_enabled");
export const setBrightness = callable<[number], number>("set_brightness");
export const setColor = callable<
  [color: [number, number, number], zone: LedZone],
  [number, number, number]
>("set_color");
export const setSecondaryColor = callable<
  [color: [number, number, number]],
  [number, number, number]
>("set_secondary_color");
export const setEffect = callable<
  [effect: string, speed?: number],
  { effect: string; speed: number }
>("set_effect");
export const setSyncZones = callable<[boolean], boolean>("set_sync_zones");
export const setIncludePowerLed = callable<[boolean], boolean>("set_include_power_led");
export const setSleepOff = callable<[boolean], boolean>("set_sleep_off");
export const rediscoverZones = callable<[], LedState>("rediscover_zones");

function normalizeZones(zones: unknown): LedZoneInfo[] {
  if (!Array.isArray(zones)) return [];
  return zones.map((zone) => {
    if (typeof zone === "string") {
      return { id: zone, name: zone, type: "" };
    }
    if (zone && typeof zone === "object") {
      const item = zone as Partial<LedZoneInfo>;
      const id = String(item.id ?? item.name ?? "zone");
      return {
        id,
        name: String(item.name ?? id),
        type: item.type ? String(item.type) : "",
      };
    }
    return { id: "zone", name: "zone", type: "" };
  });
}

function normalizeState(raw: Partial<LedState> | null | undefined): LedState {
  const base = { ...DEFAULT_LED_STATE, ...(raw ?? {}) };
  return {
    ...base,
    enabled: Boolean(base.enabled),
    brightness: Number(base.brightness ?? DEFAULT_LED_STATE.brightness),
    speed: Number(base.speed ?? DEFAULT_LED_STATE.speed),
    effect: String(base.effect ?? DEFAULT_LED_STATE.effect),
    color: normalizeRgb(base.color, DEFAULT_LED_STATE.color),
    secondary_color: normalizeRgb(base.secondary_color, DEFAULT_LED_STATE.secondary_color),
    sticks_color: normalizeRgb(base.sticks_color, DEFAULT_LED_STATE.sticks_color),
    sides_color: normalizeRgb(base.sides_color, DEFAULT_LED_STATE.sides_color),
    sync_zones: Boolean(base.sync_zones),
    include_power_led: Boolean(base.include_power_led),
    has_power_led: Boolean(base.has_power_led),
    sleep_off: Boolean(base.sleep_off),
    device_name: String(base.device_name ?? DEFAULT_LED_STATE.device_name),
    zones: normalizeZones(base.zones),
  };
}

function normalizeRgb(
  value: unknown,
  fallback: [number, number, number],
): [number, number, number] {
  if (!Array.isArray(value) || value.length < 3) return fallback;
  return [
    Math.max(0, Math.min(255, Number(value[0]) || 0)),
    Math.max(0, Math.min(255, Number(value[1]) || 0)),
    Math.max(0, Math.min(255, Number(value[2]) || 0)),
  ];
}

function withTimeout<T>(promise: Promise<T>, ms: number, message: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = window.setTimeout(() => reject(new Error(message)), ms);
    promise
      .then((value) => {
        window.clearTimeout(timer);
        resolve(value);
      })
      .catch((error) => {
        window.clearTimeout(timer);
        reject(error);
      });
  });
}

export async function refreshState(): Promise<LedState> {
  try {
    const raw = await withTimeout(getState(), 15000, "LED backend timed out");
    return normalizeState(raw);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`get_state failed: ${message}`);
  }
}
