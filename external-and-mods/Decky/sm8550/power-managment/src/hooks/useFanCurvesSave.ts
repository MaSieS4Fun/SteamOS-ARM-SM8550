import { useState } from "react";
import { clone } from "../lib/util";
import type { CurvesState, FanCurve, FanSettings } from "../types";

interface UseFanCurvesSaveOptions {
  working: CurvesState | null;
  saved: CurvesState | null;
  setSaved: (next: CurvesState) => void;
  setWorking: (next: CurvesState) => void;
  save: (fanCurves: Record<string, FanCurve>, fanSettings: FanSettings) => Promise<CurvesState>;
  onSaved?: (next: CurvesState) => void;
}

export function useFanCurvesSave({
  working,
  saved,
  setSaved,
  setWorking,
  save,
  onSaved,
}: UseFanCurvesSaveOptions) {
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState("");

  const dirty =
    !!saved &&
    !!working &&
    JSON.stringify(saved.fan_curves) + JSON.stringify(saved.fan_settings) !==
      JSON.stringify(working.fan_curves) + JSON.stringify(working.fan_settings);

  const handleSave = async () => {
    if (!working || saving) return;
    setSaving(true);
    try {
      const next = await save(working.fan_curves, working.fan_settings);
      setSaveError("");
      setWorking(clone(next));
      setSaved(next);
      onSaved?.(next);
    } catch (error) {
      setSaveError(String(error));
    } finally {
      setSaving(false);
    }
  };

  const handleRevert = () => {
    if (!saved) return;
    setSaveError("");
    setWorking(clone(saved));
  };

  return { dirty, saving, saveError, handleSave, handleRevert };
}
