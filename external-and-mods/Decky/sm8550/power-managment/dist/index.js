const manifest = {"name":"SM8550-Power"};
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader as as the loader API was not initialized. This is likely a bug in Decky Loader.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
}
catch {
    api = internalAPIConnection.connect(1, manifest.name);
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version 1. Some features may not work.`);
}
if (api._version != API_VERSION) {
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version ${api._version}. Some features may not work.`);
}
const callable = api.callable;
const toaster = api.toaster;
const definePlugin = (fn) => {
    return (...args) => {
        return fn(...args);
    };
};

const getConfig = callable("get_config");
const savePowerConfig = callable("save_power_config");
const setActiveProfile = callable("set_active_profile");
const getFansState = callable("get_fans_state");
const saveFanCurves = callable("save_fan_curves");
const getCurrentTemp = callable("get_current_temp");

function useDebouncedSave(options) {
    const { config, snapshot, save, setConfig, onError, delay = 900 } = options;
    const power = config?.power;
    SP_REACT.useEffect(() => {
        if (!config || !snapshot.current || !power)
            return;
        const patch = {
            general: power.general,
            profiles: power.profiles,
        };
        const current = JSON.stringify(patch);
        if (current === snapshot.current)
            return;
        const timer = window.setTimeout(async () => {
            try {
                const saved = current;
                const next = await save(patch);
                const nextPatch = {
                    general: next.power.general,
                    profiles: next.power.profiles,
                };
                snapshot.current = JSON.stringify(nextPatch);
                setConfig((stored) => {
                    if (!stored)
                        return next;
                    const storedPatch = {
                        general: stored.power.general,
                        profiles: stored.power.profiles,
                    };
                    if (JSON.stringify(storedPatch) !== saved)
                        return stored;
                    return { ...stored, power: next.power, active_profile: next.active_profile };
                });
            }
            catch (error) {
                onError?.(error);
            }
        }, delay);
        return () => window.clearTimeout(timer);
    }, [power, config, snapshot, save, setConfig, onError, delay]);
}

const styles = `
  .sm8550-power-tabs {
    height: 95%;
    width: 316px;
    position: fixed;
    margin-top: -12px;
    margin-left: -8px;
    overflow: hidden;
  }
  .sm8550-power-tabs > div > div:first-child::before {
    background: #0D141C;
    box-shadow: none;
    backdrop-filter: none;
  }
  .sm8550-power-tabs [role="tabpanel"] {
    padding-left: 0 !important;
    padding-right: 0 !important;
  }
  .sm8550-power-tabs [role="tablist"] {
    display: flex;
    flex-wrap: nowrap;
    justify-content: center;
  }
  .sm8550-power-tabs [role="tab"] {
    flex: 0 1 auto;
    min-width: 0;
    box-sizing: border-box;
    padding-left: 6px !important;
    padding-right: 6px !important;
    display: flex !important;
    align-items: center;
    justify-content: center;
  }
  .sm8550-power-tabs .sm8550-power-tab-content {
    padding-bottom: 24px;
  }
  .sm8550-power-tabs .sm8550-power-slider-field {
    width: 100%;
    max-width: none;
    overflow: hidden;
  }
  .sm8550-power-tabs .sm8550-power-slider-field * {
    min-width: 0 !important;
    max-width: 100% !important;
  }
  .sm8550-power-tabs .sm8550-power-subheader {
    text-transform: uppercase;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.5px;
    opacity: 0.7;
    margin: 0;
    padding: 10px 0 2px;
  }
  .sm8550-power-tabs .sm8550-power-field-note {
    box-sizing: border-box;
    width: 100%;
    margin-top: -12px;
    padding: 0 0 6px;
    font-size: 12px;
    line-height: 16px;
    opacity: 0.62;
  }
  .sm8550-power-tabs .sm8550-power-reset-row {
    padding: 0 14px 8px;
  }
  .sm8550-power-tabs .sm8550-power-profile-row {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    padding: 8px 14px 4px;
  }
  .sm8550-power-tabs .sm8550-power-profile-btn {
    flex: 1 1 45%;
    min-width: 0;
  }
  .sm8550-power-tabs .sm8550-power-status-row {
    display: flex;
    justify-content: space-between;
    padding: 4px 16px 8px;
    font-size: 13px;
    opacity: 0.85;
  }

  .sfc-scope .sfc-field-note {
    box-sizing: border-box;
    width: 100%;
    margin-top: 4px;
    padding: 0 0 6px;
    font-size: 12px;
    line-height: 16px;
    opacity: 0.62;
  }
  .sfc-scope .sfc-used-by-note {
    padding-bottom: 0;
  }
  .sfc-scope .sfc-note {
    box-sizing: border-box;
    width: 100%;
    margin-top: 6px;
    padding: 0 0 6px;
    font-size: 12px;
    line-height: 16px;
    opacity: 0.62;
  }
  .sfc-scope .sfc-reset-row {
    padding: 0 14px 8px;
  }
  .sfc-scope .sfc-control-inset {
    box-sizing: border-box;
    width: 100%;
    padding: 0 8px;
  }
  .sfc-scope .sfc-control-inset > * {
    min-width: 0;
    max-width: 100%;
  }
  .sfc-scope .sfc-error {
    box-sizing: border-box;
    width: 100%;
    padding: 8px 16px;
    font-size: 12px;
    line-height: 16px;
    color: #ff6b6b;
  }
  .sfc-scope .sfc-slider-field {
    width: 100%;
    max-width: none;
    overflow: hidden;
  }
  .sfc-scope .sfc-slider-field * {
    min-width: 0 !important;
    max-width: 100% !important;
  }
  .sfc-scope .sfc-graph-focusable {
    display: block;
    width: 100%;
    box-sizing: border-box;
    border-radius: 6px;
    border: 2px solid transparent;
  }
  .sfc-scope .sfc-graph-focusable.sfc-graph-focused {
    border-color: #5cc8ff;
    box-shadow: 0 0 0 2px rgba(92, 200, 255, 0.35);
  }
  .sfc-scope .sfc-points-drawer {
    margin: 4px 0 4px 12px;
    padding: 6px 0 6px 10px;
    background: rgba(92, 200, 255, 0.06);
    border-left: 2px solid rgba(92, 200, 255, 0.45);
  }
  .sfc-scope .sfc-point-row {
    padding: 0 14px 0;
  }
  .sfc-scope .sfc-point-row + .sfc-point-row {
    margin-top: -8px;
  }
  .sfc-scope .sfc-point-row-header {
    display: flex;
    align-items: stretch;
    gap: 6px;
  }
  .sfc-scope .sfc-point-row-header > *:first-child {
    flex: 1;
    min-width: 0;
  }
  .sfc-scope .sfc-point-row-header > *:last-child {
    flex: 0 0 40px;
    width: 40px;
  }
  .sfc-scope .sfc-collapse {
    overflow: hidden;
    transition: max-height 200ms ease;
  }
  .sfc-scope .sfc-point-details-inner {
    margin: 4px 0 8px 8px;
    padding: 4px 4px 4px 6px;
  }
  .sfc-scope button:disabled,
  .sfc-scope button[disabled] {
    opacity: 0.35 !important;
    filter: grayscale(70%) !important;
    cursor: not-allowed !important;
  }
  .sfc-scope .${DFL.gamepadSliderClasses.SliderTrack} {
    --left-track-color: #1a9fff;
  }
`;

const CURVE_TEMP_MIN = 0;
const CURVE_TEMP_MAX = 120;
const CURVE_PWM_MIN = 0;
const CURVE_PWM_MAX = 255;
const DEFAULT_POINT = { pwm: 128 };
function pwmToPercent(pwm) {
    return Math.round((Math.min(CURVE_PWM_MAX, Math.max(CURVE_PWM_MIN, pwm)) / CURVE_PWM_MAX) * 100);
}
function percentToPwm(percent) {
    return Math.round((Math.min(100, Math.max(0, percent)) / 100) * CURVE_PWM_MAX);
}
function parseCurve(text) {
    if (!text)
        return [];
    return text
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean)
        .map((item) => {
        const [tempPart, pwmPart] = item.split(":");
        return { temp: parseInt(tempPart, 10), pwm: parseInt(pwmPart, 10) };
    })
        .filter((point) => Number.isFinite(point.temp) && Number.isFinite(point.pwm))
        .sort((a, b) => a.temp - b.temp);
}
function formatCurve(points) {
    return [...points]
        .sort((a, b) => a.temp - b.temp)
        .map((point) => `${Math.round(point.temp)}:${Math.round(point.pwm)}`)
        .join(",");
}

function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
}
function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
}
function update(obj, path, value) {
    const next = clone(obj);
    let cursor = next;
    for (let i = 0; i < path.length - 1; i += 1) {
        cursor = cursor[path[i]];
    }
    cursor[path[path.length - 1]] = value;
    return next;
}
function titleCase(value) {
    const text = String(value ?? "");
    return text.charAt(0).toUpperCase() + text.slice(1);
}

const WIDTH = 280;
const HEIGHT = 170;
const PAD_LEFT = 26;
const PAD_RIGHT = 8;
const PAD_TOP = 10;
const PAD_BOTTOM = 18;
const PLOT_W = WIDTH - PAD_LEFT - PAD_RIGHT;
const PLOT_H = HEIGHT - PAD_TOP - PAD_BOTTOM;
const TEMP_TICKS = [0, 20, 40, 60, 80, 100, 120];
const PWM_TICK_PERCENTS = [0, 25, 50, 75, 100];
function xForTemp(temp) {
    return PAD_LEFT + ((clamp(temp, CURVE_TEMP_MIN, CURVE_TEMP_MAX) - CURVE_TEMP_MIN) / (CURVE_TEMP_MAX - CURVE_TEMP_MIN)) * PLOT_W;
}
function yForPwm(pwm) {
    return PAD_TOP + (1 - (clamp(pwm, CURVE_PWM_MIN, CURVE_PWM_MAX) - CURVE_PWM_MIN) / (CURVE_PWM_MAX - CURVE_PWM_MIN)) * PLOT_H;
}
function FanCurveGraph({ points, onChange, currentTemp, }) {
    const svgRef = SP_REACT.useRef(null);
    const dragRef = SP_REACT.useRef(null);
    const [livePoints, setLivePoints] = SP_REACT.useState(null);
    const [activeIndex, setActiveIndex] = SP_REACT.useState(null);
    const shown = livePoints ?? points;
    const sorted = SP_REACT.useMemo(() => [...shown].sort((a, b) => a.temp - b.temp), [shown]);
    if (!sorted.length)
        return null;
    const eventToPoint = (e) => {
        const svg = svgRef.current;
        if (!svg)
            return null;
        const rect = svg.getBoundingClientRect();
        const fracX = clamp((e.clientX - rect.left) / rect.width, 0, 1);
        const fracY = clamp((e.clientY - rect.top) / rect.height, 0, 1);
        const vbX = fracX * WIDTH;
        const vbY = fracY * HEIGHT;
        const temp = Math.round(CURVE_TEMP_MIN + clamp((vbX - PAD_LEFT) / PLOT_W, 0, 1) * (CURVE_TEMP_MAX - CURVE_TEMP_MIN));
        const pwm = Math.round(CURVE_PWM_MAX - clamp((vbY - PAD_TOP) / PLOT_H, 0, 1) * (CURVE_PWM_MAX - CURVE_PWM_MIN));
        return { temp: clamp(temp, CURVE_TEMP_MIN, CURVE_TEMP_MAX), pwm: clamp(pwm, CURVE_PWM_MIN, CURVE_PWM_MAX) };
    };
    const onPointerDown = (index) => (e) => {
        e.currentTarget.setPointerCapture(e.pointerId);
        dragRef.current = { points: points.map((p) => ({ ...p })), index };
        setActiveIndex(index);
        setLivePoints(points.map((p) => ({ ...p })));
    };
    const onPointerMove = (e) => {
        const drag = dragRef.current;
        if (!drag)
            return;
        const next = eventToPoint(e);
        if (!next)
            return;
        drag.points[drag.index] = next;
        setLivePoints([...drag.points]);
    };
    const endDrag = (e) => {
        const drag = dragRef.current;
        if (!drag)
            return;
        dragRef.current = null;
        setActiveIndex(null);
        setLivePoints(null);
        onChange(drag.points);
        try {
            e.currentTarget.releasePointerCapture(e.pointerId);
        }
        catch {
            // already released
        }
    };
    const first = sorted[0];
    const last = sorted[sorted.length - 1];
    const pathD = [
        `M ${PAD_LEFT} ${yForPwm(first.pwm)}`,
        `L ${xForTemp(first.temp)} ${yForPwm(first.pwm)}`,
        ...sorted.slice(1).map((p) => `L ${xForTemp(p.temp)} ${yForPwm(p.pwm)}`),
        `L ${PAD_LEFT + PLOT_W} ${yForPwm(last.pwm)}`,
    ].join(" ");
    const fanStopActive = first.pwm === 0;
    let fanStopBoundaryTemp = first.temp;
    for (const point of sorted) {
        if (point.pwm !== 0)
            break;
        fanStopBoundaryTemp = point.temp;
    }
    const fanStopX = xForTemp(fanStopBoundaryTemp);
    const hasCurrentTemp = typeof currentTemp === "number" && Number.isFinite(currentTemp);
    const currentTempX = hasCurrentTemp ? xForTemp(currentTemp) : 0;
    const interpolatePwm = (temp) => {
        if (temp <= first.temp)
            return first.pwm;
        if (temp >= last.temp)
            return last.pwm;
        for (let i = 0; i < sorted.length - 1; i += 1) {
            const a = sorted[i];
            const b = sorted[i + 1];
            if (temp >= a.temp && temp <= b.temp) {
                const t = b.temp === a.temp ? 0 : (temp - a.temp) / (b.temp - a.temp);
                return a.pwm + t * (b.pwm - a.pwm);
            }
        }
        return last.pwm;
    };
    const currentTempY = hasCurrentTemp ? yForPwm(interpolatePwm(currentTemp)) : 0;
    return (SP_JSX.jsxs("svg", { ref: svgRef, viewBox: `0 0 ${WIDTH} ${HEIGHT}`, width: "100%", style: { display: "block", touchAction: "none" }, onPointerMove: onPointerMove, onPointerUp: endDrag, onPointerCancel: endDrag, children: [SP_JSX.jsx("rect", { x: PAD_LEFT, y: PAD_TOP, width: PLOT_W, height: PLOT_H, fill: "rgba(255,255,255,0.04)", rx: 4 }), fanStopActive ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("rect", { x: PAD_LEFT, y: PAD_TOP, width: fanStopX - PAD_LEFT, height: PLOT_H, fill: "rgba(92,200,255,0.08)" }), SP_JSX.jsx("text", { x: PAD_LEFT + 4, y: PAD_TOP + 12, fill: "#5cc8ff", fontSize: 9, opacity: 0.8, children: "FAN STOPPED" })] })) : null, PWM_TICK_PERCENTS.map((percent) => {
                const pwm = percentToPwm(percent);
                return (SP_JSX.jsxs("g", { children: [SP_JSX.jsx("line", { x1: PAD_LEFT, y1: yForPwm(pwm), x2: PAD_LEFT + PLOT_W, y2: yForPwm(pwm), stroke: "rgba(255,255,255,0.08)", strokeWidth: 1 }), SP_JSX.jsx("text", { x: 2, y: yForPwm(pwm) + 3, fill: "rgba(255,255,255,0.45)", fontSize: 8, children: `${percent}%` })] }, percent));
            }), TEMP_TICKS.map((temp) => (SP_JSX.jsxs("g", { children: [SP_JSX.jsx("line", { x1: xForTemp(temp), y1: PAD_TOP, x2: xForTemp(temp), y2: PAD_TOP + PLOT_H, stroke: "rgba(255,255,255,0.08)", strokeWidth: 1 }), SP_JSX.jsx("text", { x: xForTemp(temp) - 6, y: HEIGHT - 2, fill: "rgba(255,255,255,0.45)", fontSize: 8, children: temp })] }, temp))), SP_JSX.jsx("path", { d: pathD, fill: "none", stroke: "#1a9fff", strokeWidth: 2 }), hasCurrentTemp ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("line", { x1: currentTempX, y1: PAD_TOP, x2: currentTempX, y2: PAD_TOP + PLOT_H, stroke: "#ffd166", strokeWidth: 1.5, strokeDasharray: "4 3" }), SP_JSX.jsx("circle", { cx: currentTempX, cy: currentTempY, r: 4, fill: "#ffd166" }), SP_JSX.jsx("text", { x: currentTempX + 6, y: currentTempY - 6, fill: "#ffd166", fontSize: 9, children: `${currentTemp}°C` })] })) : null, sorted.map((point) => {
                const index = shown.indexOf(point);
                const isActive = activeIndex !== null && shown[activeIndex] === point;
                return (SP_JSX.jsxs("g", { children: [SP_JSX.jsx("circle", { cx: xForTemp(point.temp), cy: yForPwm(point.pwm), r: isActive ? 7 : 5, fill: isActive ? "#ffd166" : "#1a9fff", stroke: "#fff", strokeWidth: 1, style: { cursor: "grab" }, onPointerDown: onPointerDown(index) }), isActive ? (SP_JSX.jsx("text", { x: xForTemp(point.temp) + 8, y: yForPwm(point.pwm) - 8, fill: "#ffd166", fontSize: 9, children: `${point.temp}°C / ${pwmToPercent(point.pwm)}%` })) : null] }, `${point.temp}-${point.pwm}-${index}`));
            })] }));
}

function SelectEdit({ label, value, options, onChange, disabled, placeholder, wrapperClassName, }) {
    const rgOptions = options.map((option) => typeof option === "string" ? { data: option, label: option } : option);
    const dropdown = label === undefined ? (SP_JSX.jsx(DFL.Dropdown, { rgOptions: rgOptions, selectedOption: value, disabled: disabled, strDefaultLabel: placeholder, onChange: (option) => onChange(String(option.data)) })) : (SP_JSX.jsx(DFL.Field, { label: label, children: SP_JSX.jsx(DFL.Dropdown, { rgOptions: rgOptions, selectedOption: value, disabled: disabled, strDefaultLabel: placeholder, onChange: (option) => onChange(String(option.data)) }) }));
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: wrapperClassName ? SP_JSX.jsx("div", { className: wrapperClassName, children: dropdown }) : dropdown }));
}
function ToggleRow({ label, value, onChange, disabled, description, wrapperClassName, }) {
    const field = (SP_JSX.jsx(DFL.ToggleField, { label: label, description: description, checked: value, disabled: disabled, onChange: onChange }));
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: wrapperClassName ? SP_JSX.jsx("div", { className: wrapperClassName, children: field }) : field }));
}
function SliderEdit({ label, value, min, max, step, onChange, format, disabled, showValue = true, wrapperClassName = "sm8550-power-slider-field", }) {
    const numeric = Number(value);
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx("div", { className: wrapperClassName, children: SP_JSX.jsx(DFL.SliderField, { label: label, value: numeric, min: min, max: max, step: step, disabled: disabled, showValue: showValue, onChange: (next) => onChange(format ? Number(format(next)) : next) }) }) }));
}

const POLL_INTERVAL_MS = 3000;
function useCurrentTemp() {
    const [temp, setTemp] = SP_REACT.useState(null);
    SP_REACT.useEffect(() => {
        let cancelled = false;
        const poll = async () => {
            try {
                const next = await getCurrentTemp();
                if (!cancelled)
                    setTemp(next);
            }
            catch {
                // Transient read failure — skip this tick.
            }
        };
        poll();
        const timer = window.setInterval(poll, POLL_INTERVAL_MS);
        return () => {
            cancelled = true;
            window.clearInterval(timer);
        };
    }, []);
    return temp;
}

function useFanCurvesSave({ working, saved, setSaved, setWorking, save, onSaved, }) {
    const [saving, setSaving] = SP_REACT.useState(false);
    const [saveError, setSaveError] = SP_REACT.useState("");
    const dirty = !!saved &&
        !!working &&
        JSON.stringify(saved.fan_curves) + JSON.stringify(saved.fan_settings) !==
            JSON.stringify(working.fan_curves) + JSON.stringify(working.fan_settings);
    const handleSave = async () => {
        if (!working || saving)
            return;
        setSaving(true);
        try {
            const next = await save(working.fan_curves, working.fan_settings);
            setSaveError("");
            setWorking(clone(next));
            setSaved(next);
            onSaved?.(next);
        }
        catch (error) {
            setSaveError(String(error));
        }
        finally {
            setSaving(false);
        }
    };
    const handleRevert = () => {
        if (!saved)
            return;
        setSaveError("");
        setWorking(clone(saved));
    };
    return { dirty, saving, saveError, handleSave, handleRevert };
}

const DEFAULT_FAN_STOP_TEMP = 60;
const FAN_STOP_SPAN = 20;
function PointRow({ index, point, isExpanded, onToggle, onCommitTemp, onCommitPwm, onRemove, canRemove, }) {
    return (SP_JSX.jsxs("div", { className: "sfc-point-row", children: [SP_JSX.jsxs("div", { className: "sfc-point-row-header", children: [SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: onToggle, children: `${isExpanded ? "▾" : "▸"} P${index + 1}: ${point.temp}°C / ${pwmToPercent(point.pwm)}%` }), SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: !canRemove, onClick: onRemove, children: "\u00D7" })] }), SP_JSX.jsx("div", { className: "sfc-collapse", style: { maxHeight: isExpanded ? 120 : 0 }, children: SP_JSX.jsxs("div", { className: "sfc-point-details-inner", children: [SP_JSX.jsx(SliderEdit, { label: "Temperature (\u00B0C)", value: point.temp, min: CURVE_TEMP_MIN, max: CURVE_TEMP_MAX, step: 1, wrapperClassName: "sfc-slider-field", onChange: onCommitTemp }), SP_JSX.jsx(SliderEdit, { label: "Fan speed (%)", value: pwmToPercent(point.pwm), min: 0, max: 100, step: 1, wrapperClassName: "sfc-slider-field", onChange: (v) => onCommitPwm(percentToPwm(v)) })] }) })] }));
}
function Fans({ setConfig, }) {
    const [saved, setSaved] = SP_REACT.useState(null);
    const [draft, setDraft] = SP_REACT.useState(null);
    const [message, setMessage] = SP_REACT.useState("Loading");
    const [selectedCurve, setSelectedCurve] = SP_REACT.useState("");
    const [showPoints, setShowPoints] = SP_REACT.useState(false);
    const [expanded, setExpanded] = SP_REACT.useState(new Set());
    const minPwmBeforeFanStop = SP_REACT.useRef(null);
    const preFanStopPoints = SP_REACT.useRef(null);
    const currentTemp = useCurrentTemp();
    const load = SP_REACT.useCallback(async () => {
        try {
            const next = await getFansState();
            setSaved(next);
            setDraft(clone(next));
            const names = Object.keys(next.fan_curves).sort();
            const activeCurve = next.profiles?.[next.active_profile]?.fan_curve;
            setSelectedCurve(activeCurve && names.includes(activeCurve) ? activeCurve : names[0] || "");
            setMessage("");
        }
        catch (error) {
            setMessage(String(error));
        }
    }, []);
    SP_REACT.useEffect(() => {
        load();
    }, [load]);
    const syncSharedFanCurves = (next) => {
        setConfig((current) => current
            ? { ...current, power: { ...current.power, fan_curves: next.fan_curves }, fan_settings: next.fan_settings }
            : current);
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
    const points = SP_REACT.useMemo(() => parseCurve(curve?.curve), [curve?.curve]);
    const names = SP_REACT.useMemo(() => Object.keys(draft?.fan_curves ?? {}).sort(), [draft?.fan_curves]);
    const commitPoints = (nextPoints) => {
        if (!curveName)
            return;
        setDraft((current) => current
            ? update(current, ["fan_curves", curveName, "curve"], formatCurve(nextPoints))
            : current);
    };
    const setFanSetting = (key, value) => {
        setDraft((current) => (current ? update(current, ["fan_settings", key], value) : current));
    };
    const setFanMode = (manual) => {
        setDraft((current) => {
            if (!current)
                return current;
            const next = clone(current);
            next.fan_settings.mode = manual ? "manual" : "auto";
            return next;
        });
    };
    const setManualLevel = (level) => {
        setDraft((current) => {
            if (!current)
                return current;
            const next = clone(current);
            next.fan_settings.manual_level = level;
            return next;
        });
    };
    let zeroRunEnd = 0;
    while (zeroRunEnd < points.length && points[zeroRunEnd].pwm === 0)
        zeroRunEnd += 1;
    const fanStopEnabled = zeroRunEnd > 0;
    const anyFanStop = Object.values(draft?.fan_curves ?? {}).some((fc) => {
        const pts = parseCurve(fc.curve);
        return pts.length > 0 && pts[0].pwm === 0;
    });
    const restoreFanStopPoints = (allPoints, runEnd) => {
        if (runEnd <= 0)
            return allPoints;
        const zeroRun = allPoints.slice(0, runEnd);
        const rest = allPoints.slice(runEnd);
        const restorePwm = rest.length ? rest[0].pwm : DEFAULT_POINT.pwm;
        const restored = zeroRun.map((point) => ({ ...point, pwm: restorePwm || DEFAULT_POINT.pwm }));
        if (rest.length)
            return [...restored, ...rest];
        const lastTemp = restored[restored.length - 1].temp;
        return [
            ...restored,
            { temp: clamp(lastTemp + FAN_STOP_SPAN, lastTemp + 1, CURVE_TEMP_MAX), pwm: DEFAULT_POINT.pwm },
        ];
    };
    const buildFanStopPoints = (temp, allPoints) => {
        const zeroed = allPoints.filter((p) => p.temp <= temp).map((p) => ({ ...p, pwm: 0 }));
        const above = allPoints.filter((p) => p.temp > temp);
        const hasBoundary = zeroed.some((p) => p.temp === temp);
        const zone = hasBoundary ? zeroed : [...zeroed, { temp, pwm: 0 }];
        if (above.length)
            return [...zone, ...above];
        const fallbackPwm = allPoints.length ? allPoints[allPoints.length - 1].pwm : DEFAULT_POINT.pwm;
        return [
            ...zone,
            { temp: clamp(temp + FAN_STOP_SPAN, temp + 1, CURVE_TEMP_MAX), pwm: fallbackPwm || DEFAULT_POINT.pwm },
        ];
    };
    const toggleFanStop = (checked) => {
        if (!curveName || !draft)
            return;
        let nextPoints;
        if (checked) {
            preFanStopPoints.current = { name: curveName, points };
            nextPoints = buildFanStopPoints(clamp(DEFAULT_FAN_STOP_TEMP, CURVE_TEMP_MIN, CURVE_TEMP_MAX), points);
        }
        else {
            const cached = preFanStopPoints.current;
            nextPoints =
                cached && cached.name === curveName ? cached.points : restoreFanStopPoints(points, zeroRunEnd);
            preFanStopPoints.current = null;
        }
        setDraft((current) => {
            if (!current)
                return current;
            const next = update(current, ["fan_curves", curveName, "curve"], formatCurve(nextPoints));
            if (checked) {
                minPwmBeforeFanStop.current = current.fan_settings.min_pwm;
                next.fan_settings.min_pwm = 0;
            }
            else {
                const anotherStops = Object.entries(next.fan_curves).some(([name, fc]) => {
                    if (name === curveName)
                        return false;
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
        return (SP_JSX.jsx(DFL.PanelSection, { title: "Fan Curves", children: SP_JSX.jsx(DFL.PanelSectionRow, { children: message || "Loading…" }) }));
    }
    const manualMode = draft.fan_settings.mode === "manual";
    const maxLevel = 7;
    return (SP_JSX.jsxs("div", { className: "sfc-scope", children: [saveError ? SP_JSX.jsx("div", { className: "sfc-error", children: saveError }) : null, SP_JSX.jsxs(DFL.PanelSection, { title: "Fan Curve", children: [names.length ? (SP_JSX.jsx(SelectEdit, { label: "Curve", value: curveName, options: names.map((name) => ({
                            data: name,
                            label: draft.fan_curves[name]?.label || titleCase(name),
                        })), onChange: setSelectedCurve })) : (SP_JSX.jsx(DFL.PanelSectionRow, { children: "No fan curves configured." })), curveName ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx("div", { className: "sfc-field-note sfc-used-by-note", children: usedBy.length
                                ? `Used by: ${usedBy.map((p) => p.label).join(", ")}`
                                : "Not assigned to any profile" }) })) : null, curve ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx("div", { className: "sfc-graph-focusable", children: SP_JSX.jsx(FanCurveGraph, { points: points, onChange: commitPoints, currentTemp: currentTemp ?? draft.current_temp }) }) }), SP_JSX.jsx(ToggleRow, { label: "Fan stop (0% below threshold)", value: fanStopEnabled, onChange: toggleFanStop })] })) : null] }), SP_JSX.jsxs(DFL.PanelSection, { title: "Curve Points", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => setShowPoints((v) => !v), children: showPoints ? "Hide Points" : "Edit Curve Points" }) }), showPoints && curve ? (SP_JSX.jsxs("div", { className: "sfc-points-drawer", children: [points.map((point, index) => (SP_JSX.jsx(PointRow, { index: index, point: point, isExpanded: expanded.has(index), onToggle: () => setExpanded((cur) => {
                                    const next = new Set(cur);
                                    if (next.has(index))
                                        next.delete(index);
                                    else
                                        next.add(index);
                                    return next;
                                }), onCommitTemp: (v) => {
                                    const next = points.map((p, i) => (i === index ? { ...p, temp: v } : p));
                                    commitPoints(next);
                                }, onCommitPwm: (v) => {
                                    const next = points.map((p, i) => (i === index ? { ...p, pwm: v } : p));
                                    commitPoints(next);
                                }, onRemove: () => {
                                    if (points.length <= 1)
                                        return;
                                    commitPoints(points.filter((_, i) => i !== index));
                                }, canRemove: points.length > 1 }, index))), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => commitPoints([
                                        ...points,
                                        { temp: clamp((points[points.length - 1]?.temp ?? 50) + 5, 0, CURVE_TEMP_MAX), pwm: DEFAULT_POINT.pwm },
                                    ]), children: "Add Point" }) })] })) : null] }), SP_JSX.jsxs(DFL.PanelSection, { title: "Fan Behavior", children: [SP_JSX.jsx(SliderEdit, { label: "Ramp up", value: draft.fan_settings.ramp_up, min: 1, max: 255, step: 1, wrapperClassName: "sfc-slider-field", onChange: (v) => setFanSetting("ramp_up", v) }), SP_JSX.jsx("div", { className: "sfc-field-note", children: "How fast the fan speeds up per tick as the target rises." }), SP_JSX.jsx(SliderEdit, { label: "Ramp down", value: draft.fan_settings.ramp_down, min: 1, max: 255, step: 1, wrapperClassName: "sfc-slider-field", onChange: (v) => setFanSetting("ramp_down", v) }), SP_JSX.jsx("div", { className: "sfc-field-note", children: "How fast the fan slows down once the target drops." }), SP_JSX.jsx(SliderEdit, { label: "Smoothing", value: Math.round(Number(draft.fan_settings.smoothing) * 100), min: 0, max: 99, step: 1, wrapperClassName: "sfc-slider-field", onChange: (v) => setFanSetting("smoothing", Number((v / 100).toFixed(2))) }), SP_JSX.jsx("div", { className: "sfc-field-note", children: "Evens out temperature readings before they reach the curve." }), SP_JSX.jsx(SliderEdit, { label: "Minimum fan speed", value: pwmToPercent(draft.fan_settings.min_pwm), min: 0, max: 100, step: 1, disabled: anyFanStop, wrapperClassName: "sfc-slider-field", onChange: (v) => setFanSetting("min_pwm", percentToPwm(v)) })] }), SP_JSX.jsxs(DFL.PanelSection, { title: "Manual Mode", children: [SP_JSX.jsx(ToggleRow, { label: "Manual fan control", value: manualMode, onChange: (v) => setFanMode(v) }), manualMode ? (SP_JSX.jsx(SliderEdit, { label: "Fan level", value: draft.fan_settings.manual_level, min: 0, max: maxLevel, step: 1, wrapperClassName: "sfc-slider-field", onChange: setManualLevel })) : null] }), SP_JSX.jsxs(DFL.PanelSection, { title: "Save", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: !dirty || saving, onClick: handleSave, children: saving ? "Saving…" : "Save Changes" }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: !dirty || saving, onClick: handleRevert, children: "Revert Changes" }) }), dirty ? (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx("div", { className: "sfc-note", children: "You have unsaved changes." }) })) : null] })] }));
}

function StatRow({ label, value }) {
    return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsxs("div", { style: { display: "flex", justifyContent: "space-between", width: "100%" }, children: [SP_JSX.jsx("span", { style: { opacity: 0.7 }, children: label }), SP_JSX.jsx("span", { children: value })] }) }));
}
function Monitor({ config }) {
    const { monitor: m, device } = config;
    const gpu = m.gpu ?? {};
    const battery = m.battery ?? { present: false };
    const fan = m.fan ?? { present: false };
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs(DFL.PanelSection, { title: "Device", children: [SP_JSX.jsx(StatRow, { label: "Name", value: device.name }), SP_JSX.jsx(StatRow, { label: "SoC", value: device.soc }), SP_JSX.jsx(StatRow, { label: "Active profile", value: config.active_profile })] }), SP_JSX.jsxs(DFL.PanelSection, { title: "GPU", children: [SP_JSX.jsx(StatRow, { label: "Governor", value: gpu.governor ?? "—" }), SP_JSX.jsx(StatRow, { label: "Clock", value: `${gpu.cur_mhz ?? "—"} / ${gpu.max_mhz ?? "—"} MHz` }), SP_JSX.jsx(StatRow, { label: "Runtime PM", value: gpu.runtime_pm ?? "—" })] }), SP_JSX.jsxs(DFL.PanelSection, { title: "CPU", children: [(m.cpus ?? []).map((cpu) => (SP_JSX.jsx(StatRow, { label: `${cpu.label} (${cpu.id})`, value: `${cpu.cur_mhz} MHz · ${cpu.governor}` }, cpu.id))), !m.cpus?.length ? SP_JSX.jsx(StatRow, { label: "Status", value: "No CPU data" }) : null] }), SP_JSX.jsx(DFL.PanelSection, { title: "Battery", children: battery.present ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(StatRow, { label: "Capacity", value: `${battery.capacity ?? "—"}%` }), SP_JSX.jsx(StatRow, { label: "Status", value: battery.status ?? "—" }), SP_JSX.jsx(StatRow, { label: "Power", value: `${battery.power_w ?? 0} W` })] })) : (SP_JSX.jsx(StatRow, { label: "Status", value: "Not present" })) }), SP_JSX.jsxs(DFL.PanelSection, { title: "Thermals", children: [(m.thermals ?? []).map((t) => (SP_JSX.jsx(StatRow, { label: t.name, value: `${t.temp_c}°C` }, t.name))), !m.thermals?.length ? SP_JSX.jsx(StatRow, { label: "Status", value: "No sensors" }) : null] }), SP_JSX.jsx(DFL.PanelSection, { title: "Fan", children: fan.present ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(StatRow, { label: "PWM", value: String(fan.pwm ?? "—") }), SP_JSX.jsx(StatRow, { label: "RPM", value: String(fan.rpm ?? "—") }), SP_JSX.jsx(StatRow, { label: "Level", value: `${fan.level ?? "—"} / ${fan.max_level ?? "—"}` })] })) : (SP_JSX.jsx(StatRow, { label: "Status", value: "Not detected" })) }), SP_JSX.jsx(DFL.PanelSection, { title: "Storage", children: SP_JSX.jsx(StatRow, { label: "UFS keepalive", value: m.ufs_keepalive ? "On" : "Off" }) })] }));
}

const underclocks = [
    { data: "none", label: "None" },
    { data: "small", label: "Small" },
    { data: "medium", label: "Medium" },
    { data: "large", label: "Large" },
];
function Power({ config, setConfig, }) {
    const [profile, setProfile] = SP_REACT.useState(config.power.general.default_profile || "balanced");
    const p = config.power.profiles[profile] ?? {};
    const profiles = Object.entries(config.power.profiles).map(([name, prof]) => ({
        data: name,
        label: prof.label || titleCase(name),
    }));
    const fanCurves = Object.entries(config.power.fan_curves).map(([name, curve]) => ({
        data: name,
        label: curve.label || titleCase(name),
    }));
    const setProfileValue = (name, value) => {
        setConfig((current) => current ? update(current, ["power", "profiles", profile, name], value) : current);
    };
    const setGpuValue = (name, value) => {
        setConfig((current) => {
            if (!current)
                return current;
            const next = clone(current);
            const target = next.power.profiles[profile];
            target[name] = value;
            if (name === "gpu_min" && value > Number(target.gpu_max ?? 0)) {
                target.gpu_max = value;
            }
            if (name === "gpu_max" && value < Number(target.gpu_min ?? 0)) {
                target.gpu_min = value;
            }
            return next;
        });
    };
    const resetProfile = () => {
        const defaults = config.power_defaults?.[profile];
        if (!defaults)
            return;
        setConfig((current) => current ? update(current, ["power", "profiles", profile], defaults) : current);
    };
    const supportsUnderclockPresets = !!config.power.underclocks?.[config.perf.cpu_device_class];
    return (SP_JSX.jsx("div", { className: "sfc-scope", children: SP_JSX.jsxs(DFL.PanelSection, { title: "Edit Profile", children: [SP_JSX.jsx(SelectEdit, { label: "Profile to edit", value: profile, options: profiles, onChange: setProfile }), SP_JSX.jsx(SelectEdit, { label: "Fan curve", value: p.fan_curve ?? "", options: fanCurves, onChange: (v) => setProfileValue("fan_curve", v) }), (config.perf?.governors?.length ?? 0) > 0 ? (SP_JSX.jsx(SelectEdit, { label: "CPU governor", value: p.cpu_governor ?? "", options: config.perf.governors.map((g) => ({ data: g, label: titleCase(g) })), onChange: (v) => setProfileValue("cpu_governor", v) })) : null, supportsUnderclockPresets ? (SP_JSX.jsx(SelectEdit, { label: "CPU underclock", value: p.cpu_underclock ?? "none", options: underclocks, onChange: (v) => setProfileValue("cpu_underclock", v) })) : (SP_JSX.jsx(SliderEdit, { label: "CPU max", value: Math.round(Number(p.cpu_max ?? 1) * 100), min: 0, max: 100, step: 1, onChange: (v) => setProfileValue("cpu_max", Number((v / 100).toFixed(2))) })), SP_JSX.jsx(SliderEdit, { label: "GPU min", value: Math.round(Number(p.gpu_min ?? 0) * 100), min: 0, max: 100, step: 1, onChange: (v) => setGpuValue("gpu_min", Number((v / 100).toFixed(2))) }), SP_JSX.jsx(SliderEdit, { label: "GPU max", value: Math.round(Number(p.gpu_max ?? 1) * 100), min: 0, max: 100, step: 1, onChange: (v) => setGpuValue("gpu_max", Number((v / 100).toFixed(2))) }), SP_JSX.jsx("div", { className: "sfc-reset-row", children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: resetProfile, children: "Reset to Default" }) })] }) }));
}

const PROFILE_ORDER = ["eco", "balanced", "performance", "gaming"];

const PROFILE_LABELS = {
    eco: "Eco",
    balanced: "Balanced",
    performance: "Performance",
    gaming: "Gaming",
};
function Content() {
    const [tab, setTab] = SP_REACT.useState("power");
    const [config, setConfig] = SP_REACT.useState(null);
    const [message, setMessage] = SP_REACT.useState("Loading");
    const [switchingProfile, setSwitchingProfile] = SP_REACT.useState(false);
    const savedPowerSnapshot = SP_REACT.useRef("");
    const load = SP_REACT.useCallback(async () => {
        try {
            const next = await getConfig();
            setConfig((current) => {
                if (!current) {
                    savedPowerSnapshot.current = JSON.stringify({
                        general: next.power.general,
                        profiles: next.power.profiles,
                    });
                    return next;
                }
                return {
                    ...next,
                    power: current.power,
                    monitor: next.monitor,
                    current_temp: next.current_temp,
                    active_profile: next.active_profile,
                };
            });
            setMessage("");
        }
        catch (error) {
            setMessage(String(error));
        }
    }, []);
    SP_REACT.useEffect(() => {
        load();
        const id = window.setInterval(load, 4000);
        return () => window.clearInterval(id);
    }, [load]);
    useDebouncedSave({
        config,
        snapshot: savedPowerSnapshot,
        save: savePowerConfig,
        setConfig,
        onError: (error) => {
            toaster.toast({ title: "Save failed", body: String(error) });
            load();
        },
    });
    const onQuickProfile = async (profileId) => {
        if (!config || switchingProfile || profileId === config.active_profile)
            return;
        setSwitchingProfile(true);
        try {
            const next = await setActiveProfile(profileId);
            setConfig(next);
            savedPowerSnapshot.current = JSON.stringify({
                general: next.power.general,
                profiles: next.power.profiles,
            });
        }
        catch (error) {
            toaster.toast({ title: "Profile switch failed", body: String(error) });
        }
        finally {
            setSwitchingProfile(false);
        }
    };
    if (!config) {
        return (SP_JSX.jsx(DFL.PanelSection, { title: "SM8550 Power", children: SP_JSX.jsx(DFL.PanelSectionRow, { children: message || "Loading…" }) }));
    }
    if (!config.supported) {
        return (SP_JSX.jsx(DFL.PanelSection, { title: "Unsupported device", children: SP_JSX.jsx(DFL.PanelSectionRow, { children: "Qualcomm SM8550 handhelds only (Odin 2, Thor, Portal, RP6, etc.)." }) }));
    }
    const battery = config.monitor?.battery;
    const temp = config.current_temp != null ? `${config.current_temp}°C` : "—";
    const batteryText = battery?.present
        ? `${battery.capacity ?? "—"}% · ${battery.status ?? "—"}`
        : "No battery";
    const tabContent = (content) => (SP_JSX.jsx("div", { className: "sm8550-power-tab-content", children: content }));
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("style", { children: styles }), SP_JSX.jsxs(DFL.PanelSection, { title: "Active Profile", children: [SP_JSX.jsx("div", { className: "sm8550-power-profile-row", children: PROFILE_ORDER.map((id) => (SP_JSX.jsx("div", { className: "sm8550-power-profile-btn", children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: switchingProfile, onClick: () => onQuickProfile(id), children: config.active_profile === id
                                    ? `● ${PROFILE_LABELS[id] ?? titleCase(id)}`
                                    : PROFILE_LABELS[id] ?? titleCase(id) }) }, id))) }), SP_JSX.jsxs("div", { className: "sm8550-power-status-row", children: [SP_JSX.jsx("span", { children: temp }), SP_JSX.jsx("span", { children: batteryText })] })] }), SP_JSX.jsx(DFL.Tabs, { className: "sm8550-power-tabs", activeTab: tab, onShowTab: (id) => setTab(id), tabs: [
                    {
                        id: "power",
                        title: "Power",
                        content: tabContent(SP_JSX.jsx(Power, { config: config, setConfig: setConfig })),
                    },
                    {
                        id: "fan",
                        title: "Fan",
                        content: tabContent(SP_JSX.jsx(Fans, { setConfig: setConfig })),
                    },
                    {
                        id: "monitor",
                        title: "Monitor",
                        content: tabContent(SP_JSX.jsx(Monitor, { config: config })),
                    },
                ] })] }));
}

var index = definePlugin(() => ({
    name: "SM8550-Power",
    content: SP_JSX.jsx(Content, {}),
    icon: SP_JSX.jsx("div", { style: { fontWeight: 700 }, children: "PWR" }),
    alwaysRender: true,
}));

export { index as default };
//# sourceMappingURL=index.js.map
