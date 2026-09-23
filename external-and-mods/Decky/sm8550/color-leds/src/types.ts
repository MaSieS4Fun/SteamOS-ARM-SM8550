export type LedZone = "all" | "sticks" | "sides";

export type LedEffect =
  | "static"
  | "breathing"
  | "rainbow"
  | "wave"
  | "gradient"
  | "cycle"
  | "sparkle"
  | "comet"
  | "battery"
  | "temp";

export interface LedZoneInfo {
  id: string;
  name: string;
  type?: string;
}

export interface LedState {
  enabled: boolean;
  brightness: number;
  effect: LedEffect | string;
  speed: number;
  color: [number, number, number];
  secondary_color: [number, number, number];
  sync_zones: boolean;
  sticks_color: [number, number, number];
  sides_color: [number, number, number];
  include_power_led: boolean;
  has_power_led: boolean;
  sleep_off: boolean;
  zones: LedZoneInfo[];
  device_name: string;
}

export interface PresetColor {
  name: string;
  rgb: [number, number, number];
}

export const PRESET_COLORS: PresetColor[] = [
  { name: "White", rgb: [255, 255, 255] },
  { name: "Warm White", rgb: [255, 220, 180] },
  { name: "Red", rgb: [255, 40, 40] },
  { name: "Orange", rgb: [255, 120, 0] },
  { name: "Amber", rgb: [255, 180, 0] },
  { name: "Yellow", rgb: [255, 255, 0] },
  { name: "Lime", rgb: [120, 255, 0] },
  { name: "Green", rgb: [0, 255, 80] },
  { name: "Cyan", rgb: [0, 220, 255] },
  { name: "Blue", rgb: [40, 80, 255] },
  { name: "Purple", rgb: [160, 40, 255] },
  { name: "Magenta", rgb: [255, 0, 200] },
  { name: "Pink", rgb: [255, 100, 180] },
  { name: "Steam Blue", rgb: [26, 159, 255] },
];

export const LED_EFFECTS: LedEffect[] = [
  "static",
  "breathing",
  "rainbow",
  "wave",
  "gradient",
  "cycle",
  "sparkle",
  "comet",
  "battery",
  "temp",
];

export interface EffectInfo {
  label: string;
  description: string;
}

export const EFFECT_INFO: Record<LedEffect, EffectInfo> = {
  static: {
    label: "Static",
    description: "Solid color with no animation.",
  },
  breathing: {
    label: "Breathing",
    description: "Smooth pulse fade between dim and bright.",
  },
  rainbow: {
    label: "Rainbow",
    description: "Cycles through the full color spectrum.",
  },
  wave: {
    label: "Wave",
    description: "Traveling wave across LED zones.",
  },
  gradient: {
    label: "Gradient",
    description: "Blends primary and secondary colors over time.",
  },
  cycle: {
    label: "Cycle",
    description: "Steps through preset hues at a fixed pace.",
  },
  sparkle: {
    label: "Sparkle",
    description: "Random twinkling highlights on a base color.",
  },
  comet: {
    label: "Comet",
    description: "Bright streak that sweeps across the device.",
  },
  battery: {
    label: "Battery",
    description: "Color reflects current battery charge level.",
  },
  temp: {
    label: "Temperature",
    description: "Color shifts with system temperature.",
  },
};

export function rgbToHex(rgb: [number, number, number]): string {
  return `#${rgb
    .map((c) => Math.max(0, Math.min(255, Math.round(c))).toString(16).padStart(2, "0"))
    .join("")}`;
}

export function hexToRgb(hex: string): [number, number, number] | null {
  const match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex.trim());
  if (!match) return null;
  return [parseInt(match[1], 16), parseInt(match[2], 16), parseInt(match[3], 16)];
}

export function colorForZone(state: LedState, zone: LedZone): [number, number, number] {
  if (zone === "sticks") return [...state.sticks_color] as [number, number, number];
  if (zone === "sides") return [...state.sides_color] as [number, number, number];
  return [...state.color] as [number, number, number];
}

export const DEFAULT_LED_STATE: LedState = {
  enabled: true,
  brightness: 128,
  effect: "static",
  speed: 5,
  color: [26, 159, 255],
  secondary_color: [255, 40, 120],
  sync_zones: true,
  sticks_color: [26, 159, 255],
  sides_color: [26, 159, 255],
  include_power_led: false,
  has_power_led: false,
  sleep_off: true,
  zones: [],
  device_name: "SM8550 Handheld",
};
