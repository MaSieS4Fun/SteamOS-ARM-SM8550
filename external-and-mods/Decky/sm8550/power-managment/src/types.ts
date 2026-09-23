export interface PowerProfile {
  label: string;
  cpu_governor: string;
  cpu_max: number;
  cpu_underclock: string;
  gpu_max: number;
  gpu_min: number;
  fan_curve: string;
  ufs_keepalive?: boolean;
}

export interface FanCurve {
  label: string;
  curve: string;
}

export interface FanSettings {
  mode: "auto" | "manual";
  manual_level: number;
  ramp_up: number;
  ramp_down: number;
  smoothing: number;
  min_pwm: number;
}

export interface PowerSection {
  general: { default_profile: string };
  profiles: Record<string, PowerProfile>;
  fan_curves: Record<string, FanCurve>;
  underclocks: Record<string, Record<string, Record<string, number>>>;
}

export interface MonitorGpu {
  governor?: string;
  cur_mhz?: number;
  min_mhz?: number;
  max_mhz?: number;
  available_mhz?: number[];
  runtime_pm?: string;
}

export interface MonitorCpu {
  id: string;
  label: string;
  governor: string;
  cur_mhz: number;
  max_mhz: number;
}

export interface MonitorBattery {
  present: boolean;
  capacity?: number;
  status?: string;
  power_w?: number;
}

export interface MonitorThermal {
  name: string;
  temp_c: number;
}

export interface MonitorFan {
  present: boolean;
  mode?: "auto" | "manual";
  level?: number;
  max_level?: number;
  rpm?: number;
  pwm?: number;
}

export interface MonitorSnapshot {
  gpu: MonitorGpu;
  cpus: MonitorCpu[];
  battery: MonitorBattery;
  thermals: MonitorThermal[];
  fan: MonitorFan;
  ufs_keepalive: boolean;
}

export interface Config {
  supported: boolean;
  device: { name: string; soc: string };
  active_profile: string;
  power: PowerSection;
  power_defaults: Record<string, PowerProfile>;
  fan_settings: FanSettings;
  fan_defaults: FanSettings;
  perf: {
    governors: string[];
    cpu_device_class: string;
  };
  monitor: MonitorSnapshot;
  current_temp: number | null;
}

export interface ProfileSummary {
  label: string;
  fan_curve: string;
}

export interface CurvesState {
  fan_curves: Record<string, FanCurve>;
  factory_fan_curves: Record<string, FanCurve>;
  fan_settings: FanSettings;
  factory_fan_settings: FanSettings;
  profiles: Record<string, ProfileSummary>;
  active_profile: string;
  current_temp: number | null;
}

export interface DropdownChoice {
  data: string;
  label: string;
}

export type PowerConfigPatch = {
  general?: PowerSection["general"];
  profiles?: Record<string, Partial<PowerProfile>>;
};

export const PROFILE_ORDER = ["eco", "balanced", "performance", "gaming"] as const;
