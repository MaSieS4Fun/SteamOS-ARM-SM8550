import { ButtonItem, PanelSection, PanelSectionRow } from "@decky/ui";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Dispatch, SetStateAction } from "react";
import { getFansState, saveFanCurves } from "../backend";
import { FanCurveGraph } from "../components/FanCurveGraph";
import { SelectEdit, SliderEdit, ToggleRow } from "../components/widgets";
import { useCurrentTemp } from "../hooks/useCurrentTemp";
import { useFanCurvesSave } from "../hooks/useFanCurvesSave";
import {
  CURVE_TEMP_MAX,
  CURVE_TEMP_MIN,
  DEFAULT_POINT,
  formatCurve,
  parseCurve,
  percentToPwm,
  pwmToPercent,
} from "../lib/fanCurve";
import type { CurvePoint } from "../lib/fanCurve";
import { clamp, clone, titleCase, update } from "../lib/util";
import type { Config, CurvesState } from "../types";

const DEFAULT_FAN_STOP_TEMP = 60;
const FAN_STOP_SPAN = 20;

function PointRow({
  index,
  point,
  isExpanded,
  onToggle,
  onCommitTemp,
  onCommitPwm,
  onRemove,
  canRemove,
}: {
  index: number;
  point: CurvePoint;
  isExpanded: boolean;
  onToggle: () => void;
  onCommitTemp: (value: number) => void;
  onCommitPwm: (value: number) => void;
  onRemove: () => void;
  canRemove: boolean;
}) {
  return (
    <div className="sfc-point-row">
      <div className="sfc-point-row-header">
        <ButtonItem layout="below" onClick={onToggle}>
          {`${isExpanded ? "▾" : "▸"} P${index + 1}: ${point.temp}°C / ${pwmToPercent(point.pwm)}%`}
        </ButtonItem>
        <ButtonItem layout="below" disabled={!canRemove} onClick={onRemove}>
          ×
        </ButtonItem>
      </div>
      <div
        className="sfc-collapse"
        style={{ maxHeight: isExpanded ? 120 : 0 }}
      >
        <div className="sfc-point-details-inner">
          <SliderEdit
            label="Temperature (°C)"
            value={point.temp}
            min={CURVE_TEMP_MIN}
            max={CURVE_TEMP_MAX}
            step={1}
            wrapperClassName="sfc-slider-field"
            onChange={onCommitTemp}
          />
          <SliderEdit
            label="Fan speed (%)"
            value={pwmToPercent(point.pwm)}
            min={0}
            max={100}
            step={1}
            wrapperClassName="sfc-slider-field"
            onChange={(v) => onCommitPwm(percentToPwm(v))}
          />
        </div>
      </div>
    </div>
  );
}

export function Fans({
  setConfig,
}: {
  setConfig: Dispatch<SetStateAction<Config | null>>;
}) {
  const [saved, setSaved] = useState<CurvesState | null>(null);
  const [draft, setDraft] = useState<CurvesState | null>(null);
  const [message, setMessage] = useState("Loading");
  const [selectedCurve, setSelectedCurve] = useState("");
  const [showPoints, setShowPoints] = useState(false);
  const [expanded, setExpanded] = useState<Set<number>>(new Set());
  const minPwmBeforeFanStop = useRef<number | null>(null);
  const preFanStopPoints = useRef<{ name: string; points: CurvePoint[] } | null>(null);
  const currentTemp = useCurrentTemp();

  const load = useCallback(async () => {
    try {
      const next = await getFansState();
      setSaved(next);
      setDraft(clone(next));
      const names = Object.keys(next.fan_curves).sort();
      const activeCurve = next.profiles?.[next.active_profile]?.fan_curve;
      setSelectedCurve(activeCurve && names.includes(activeCurve) ? activeCurve : names[0] || "");
      setMessage("");
    } catch (error) {
      setMessage(String(error));
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const syncSharedFanCurves = (next: CurvesState) => {
    setConfig((current) =>
      current
        ? { ...current, power: { ...current.power, fan_curves: next.fan_curves }, fan_settings: next.fan_settings }
        : current,
    );
  };

  const { dirty, saving, saveError, handleSave, handleRevert } = useFanCurvesSave({
    working: draft,
    saved,
    setSaved,
    setWorking: setDraft,
    save: saveFanCurves,
    onSaved: syncSharedFanCurves,
  });

  const curveName = selectedCurve;
  const curve = draft?.fan_curves[curveName];
  const points = useMemo(() => parseCurve(curve?.curve), [curve?.curve]);
  const names = useMemo(() => Object.keys(draft?.fan_curves ?? {}).sort(), [draft?.fan_curves]);

  const commitPoints = (nextPoints: CurvePoint[]) => {
    if (!curveName) return;
    setDraft((current) =>
      current
        ? update(current, ["fan_curves", curveName, "curve"], formatCurve(nextPoints))
        : current,
    );
  };

  const setFanSetting = (key: "ramp_up" | "ramp_down" | "smoothing" | "min_pwm", value: number) => {
    setDraft((current) => (current ? update(current, ["fan_settings", key], value) : current));
  };

  const setFanMode = (manual: boolean) => {
    setDraft((current) => {
      if (!current) return current;
      const next = clone(current);
      next.fan_settings.mode = manual ? "manual" : "auto";
      return next;
    });
  };

  const setManualLevel = (level: number) => {
    setDraft((current) => {
      if (!current) return current;
      const next = clone(current);
      next.fan_settings.manual_level = level;
      return next;
    });
  };

  let zeroRunEnd = 0;
  while (zeroRunEnd < points.length && points[zeroRunEnd].pwm === 0) zeroRunEnd += 1;
  const fanStopEnabled = zeroRunEnd > 0;
  const anyFanStop = Object.values(draft?.fan_curves ?? {}).some((fc) => {
    const pts = parseCurve(fc.curve);
    return pts.length > 0 && pts[0].pwm === 0;
  });

  const restoreFanStopPoints = (allPoints: CurvePoint[], runEnd: number): CurvePoint[] => {
    if (runEnd <= 0) return allPoints;
    const zeroRun = allPoints.slice(0, runEnd);
    const rest = allPoints.slice(runEnd);
    const restorePwm = rest.length ? rest[0].pwm : DEFAULT_POINT.pwm;
    const restored = zeroRun.map((point) => ({ ...point, pwm: restorePwm || DEFAULT_POINT.pwm }));
    if (rest.length) return [...restored, ...rest];
    const lastTemp = restored[restored.length - 1].temp;
    return [
      ...restored,
      { temp: clamp(lastTemp + FAN_STOP_SPAN, lastTemp + 1, CURVE_TEMP_MAX), pwm: DEFAULT_POINT.pwm },
    ];
  };

  const buildFanStopPoints = (temp: number, allPoints: CurvePoint[]): CurvePoint[] => {
    const zeroed = allPoints.filter((p) => p.temp <= temp).map((p) => ({ ...p, pwm: 0 }));
    const above = allPoints.filter((p) => p.temp > temp);
    const hasBoundary = zeroed.some((p) => p.temp === temp);
    const zone = hasBoundary ? zeroed : [...zeroed, { temp, pwm: 0 }];
    if (above.length) return [...zone, ...above];
    const fallbackPwm = allPoints.length ? allPoints[allPoints.length - 1].pwm : DEFAULT_POINT.pwm;
    return [
      ...zone,
      { temp: clamp(temp + FAN_STOP_SPAN, temp + 1, CURVE_TEMP_MAX), pwm: fallbackPwm || DEFAULT_POINT.pwm },
    ];
  };

  const toggleFanStop = (checked: boolean) => {
    if (!curveName || !draft) return;
    let nextPoints: CurvePoint[];
    if (checked) {
      preFanStopPoints.current = { name: curveName, points };
      nextPoints = buildFanStopPoints(clamp(DEFAULT_FAN_STOP_TEMP, CURVE_TEMP_MIN, CURVE_TEMP_MAX), points);
    } else {
      const cached = preFanStopPoints.current;
      nextPoints =
        cached && cached.name === curveName ? cached.points : restoreFanStopPoints(points, zeroRunEnd);
      preFanStopPoints.current = null;
    }
    setDraft((current) => {
      if (!current) return current;
      const next = update(current, ["fan_curves", curveName, "curve"], formatCurve(nextPoints));
      if (checked) {
        minPwmBeforeFanStop.current = current.fan_settings.min_pwm;
        next.fan_settings.min_pwm = 0;
      } else {
        const anotherStops = Object.entries(next.fan_curves).some(([name, fc]) => {
          if (name === curveName) return false;
          const pts = parseCurve(fc.curve);
          return pts.length > 0 && pts[0].pwm === 0;
        });
        if (!anotherStops) {
          next.fan_settings.min_pwm =
            minPwmBeforeFanStop.current ?? next.factory_fan_settings.min_pwm;
          minPwmBeforeFanStop.current = null;
        }
      }
      return next;
    });
  };

  const usedBy = Object.values(draft?.profiles ?? {}).filter((p) => p.fan_curve === curveName);

  if (!draft) {
    return (
      <PanelSection title="Fan Curves">
        <PanelSectionRow>{message || "Loading…"}</PanelSectionRow>
      </PanelSection>
    );
  }

  const manualMode = draft.fan_settings.mode === "manual";
  const maxLevel = 7;

  return (
    <div className="sfc-scope">
      {saveError ? <div className="sfc-error">{saveError}</div> : null}

      <PanelSection title="Fan Curve">
        {names.length ? (
          <SelectEdit
            label="Curve"
            value={curveName}
            options={names.map((name) => ({
              data: name,
              label: draft.fan_curves[name]?.label || titleCase(name),
            }))}
            onChange={setSelectedCurve}
          />
        ) : (
          <PanelSectionRow>No fan curves configured.</PanelSectionRow>
        )}
        {curveName ? (
          <PanelSectionRow>
            <div className="sfc-field-note sfc-used-by-note">
              {usedBy.length
                ? `Used by: ${usedBy.map((p) => p.label).join(", ")}`
                : "Not assigned to any profile"}
            </div>
          </PanelSectionRow>
        ) : null}

        {curve ? (
          <>
            <PanelSectionRow>
              <div className="sfc-graph-focusable">
                <FanCurveGraph
                  points={points}
                  onChange={commitPoints}
                  currentTemp={currentTemp ?? draft.current_temp}
                />
              </div>
            </PanelSectionRow>
            <ToggleRow label="Fan stop (0% below threshold)" value={fanStopEnabled} onChange={toggleFanStop} />
          </>
        ) : null}
      </PanelSection>

      <PanelSection title="Curve Points">
        <PanelSectionRow>
          <ButtonItem layout="below" onClick={() => setShowPoints((v) => !v)}>
            {showPoints ? "Hide Points" : "Edit Curve Points"}
          </ButtonItem>
        </PanelSectionRow>
        {showPoints && curve ? (
          <div className="sfc-points-drawer">
            {points.map((point, index) => (
              <PointRow
                key={index}
                index={index}
                point={point}
                isExpanded={expanded.has(index)}
                onToggle={() =>
                  setExpanded((cur) => {
                    const next = new Set(cur);
                    if (next.has(index)) next.delete(index);
                    else next.add(index);
                    return next;
                  })
                }
                onCommitTemp={(v) => {
                  const next = points.map((p, i) => (i === index ? { ...p, temp: v } : p));
                  commitPoints(next);
                }}
                onCommitPwm={(v) => {
                  const next = points.map((p, i) => (i === index ? { ...p, pwm: v } : p));
                  commitPoints(next);
                }}
                onRemove={() => {
                  if (points.length <= 1) return;
                  commitPoints(points.filter((_, i) => i !== index));
                }}
                canRemove={points.length > 1}
              />
            ))}
            <PanelSectionRow>
              <ButtonItem
                layout="below"
                onClick={() =>
                  commitPoints([
                    ...points,
                    { temp: clamp((points[points.length - 1]?.temp ?? 50) + 5, 0, CURVE_TEMP_MAX), pwm: DEFAULT_POINT.pwm },
                  ])
                }
              >
                Add Point
              </ButtonItem>
            </PanelSectionRow>
          </div>
        ) : null}
      </PanelSection>

      <PanelSection title="Fan Behavior">
        <SliderEdit
          label="Ramp up"
          value={draft.fan_settings.ramp_up}
          min={1}
          max={255}
          step={1}
          wrapperClassName="sfc-slider-field"
          onChange={(v) => setFanSetting("ramp_up", v)}
        />
        <div className="sfc-field-note">How fast the fan speeds up per tick as the target rises.</div>
        <SliderEdit
          label="Ramp down"
          value={draft.fan_settings.ramp_down}
          min={1}
          max={255}
          step={1}
          wrapperClassName="sfc-slider-field"
          onChange={(v) => setFanSetting("ramp_down", v)}
        />
        <div className="sfc-field-note">How fast the fan slows down once the target drops.</div>
        <SliderEdit
          label="Smoothing"
          value={Math.round(Number(draft.fan_settings.smoothing) * 100)}
          min={0}
          max={99}
          step={1}
          wrapperClassName="sfc-slider-field"
          onChange={(v) => setFanSetting("smoothing", Number((v / 100).toFixed(2)))}
        />
        <div className="sfc-field-note">Evens out temperature readings before they reach the curve.</div>
        <SliderEdit
          label="Minimum fan speed"
          value={pwmToPercent(draft.fan_settings.min_pwm)}
          min={0}
          max={100}
          step={1}
          disabled={anyFanStop}
          wrapperClassName="sfc-slider-field"
          onChange={(v) => setFanSetting("min_pwm", percentToPwm(v))}
        />
      </PanelSection>

      <PanelSection title="Manual Mode">
        <ToggleRow
          label="Manual fan control"
          value={manualMode}
          onChange={(v) => setFanMode(v)}
        />
        {manualMode ? (
          <SliderEdit
            label="Fan level"
            value={draft.fan_settings.manual_level}
            min={0}
            max={maxLevel}
            step={1}
            wrapperClassName="sfc-slider-field"
            onChange={setManualLevel}
          />
        ) : null}
      </PanelSection>

      <PanelSection title="Save">
        <PanelSectionRow>
          <ButtonItem layout="below" disabled={!dirty || saving} onClick={handleSave}>
            {saving ? "Saving…" : "Save Changes"}
          </ButtonItem>
        </PanelSectionRow>
        <PanelSectionRow>
          <ButtonItem layout="below" disabled={!dirty || saving} onClick={handleRevert}>
            Revert Changes
          </ButtonItem>
        </PanelSectionRow>
        {dirty ? (
          <PanelSectionRow>
            <div className="sfc-note">You have unsaved changes.</div>
          </PanelSectionRow>
        ) : null}
      </PanelSection>
    </div>
  );
}
