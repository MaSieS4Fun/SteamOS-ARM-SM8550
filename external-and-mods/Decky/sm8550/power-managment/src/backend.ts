import { callable } from "@decky/api";
import type { Config, CurvesState, FanCurve, FanSettings, PowerConfigPatch } from "./types";

export const getConfig = callable<[], Config>("get_config");
export const savePowerConfig = callable<[PowerConfigPatch], Config>("save_power_config");
export const setActiveProfile = callable<[string], Config>("set_active_profile");
export const getFansState = callable<[], CurvesState>("get_fans_state");
export const saveFanCurves = callable<
  [Record<string, FanCurve>, FanSettings],
  CurvesState
>("save_fan_curves");
export const getCurrentTemp = callable<[], number | null>("get_current_temp");
