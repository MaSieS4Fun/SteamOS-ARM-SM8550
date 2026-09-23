const manifest = {"name":"SM8550-LED"};
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

const PRESET_COLORS = [
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
const LED_EFFECTS = [
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
const EFFECT_INFO = {
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
function rgbToHex(rgb) {
    return `#${rgb
        .map((c) => Math.max(0, Math.min(255, Math.round(c))).toString(16).padStart(2, "0"))
        .join("")}`;
}
function colorForZone(state, zone) {
    if (zone === "sticks")
        return [...state.sticks_color];
    if (zone === "sides")
        return [...state.sides_color];
    return [...state.color];
}
const DEFAULT_LED_STATE = {
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

const getState = callable("get_state");
const setEnabled = callable("set_enabled");
const setBrightness = callable("set_brightness");
const setColor = callable("set_color");
const setSecondaryColor = callable("set_secondary_color");
const setEffect = callable("set_effect");
const setSyncZones = callable("set_sync_zones");
const setIncludePowerLed = callable("set_include_power_led");
const setSleepOff = callable("set_sleep_off");
const rediscoverZones = callable("rediscover_zones");
function normalizeZones(zones) {
    if (!Array.isArray(zones))
        return [];
    return zones.map((zone) => {
        if (typeof zone === "string") {
            return { id: zone, name: zone, type: "" };
        }
        if (zone && typeof zone === "object") {
            const item = zone;
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
function normalizeState(raw) {
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
function normalizeRgb(value, fallback) {
    if (!Array.isArray(value) || value.length < 3)
        return fallback;
    return [
        Math.max(0, Math.min(255, Number(value[0]) || 0)),
        Math.max(0, Math.min(255, Number(value[1]) || 0)),
        Math.max(0, Math.min(255, Number(value[2]) || 0)),
    ];
}
function withTimeout(promise, ms, message) {
    return new Promise((resolve, reject) => {
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
async function refreshState() {
    try {
        const raw = await withTimeout(getState(), 15000, "LED backend timed out");
        return normalizeState(raw);
    }
    catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(`get_state failed: ${message}`);
    }
}

function ColorPalette({ selectedColor, onSelect, disabled = false }) {
    const selectedHex = rgbToHex(selectedColor);
    return (SP_JSX.jsx("div", { className: "sm8550-led-preset-wrap", children: PRESET_COLORS.map((preset) => {
            const hex = rgbToHex(preset.rgb);
            const isSelected = hex === selectedHex;
            return (SP_JSX.jsxs("div", { className: "sm8550-led-preset-cell", children: [SP_JSX.jsx(DFL.Focusable, { className: `sm8550-led-preset-btn${isSelected ? " selected" : ""}`, style: { backgroundColor: hex }, onActivate: () => {
                            if (!disabled)
                                onSelect(preset.rgb);
                        }, onClick: () => {
                            if (!disabled)
                                onSelect(preset.rgb);
                        }, "aria-label": preset.name, children: SP_JSX.jsx("span", { "aria-hidden": "true" }) }), SP_JSX.jsx("div", { className: "sm8550-led-preset-name", children: preset.name })] }, preset.name));
        }) }));
}

function ColorPreview({ color, label = "Current Color", secondaryColor, showGradient = false, }) {
    const hex = rgbToHex(color);
    const background = showGradient && secondaryColor
        ? `linear-gradient(90deg, ${rgbToHex(color)}, ${rgbToHex(secondaryColor)})`
        : rgbToHex(color);
    return (SP_JSX.jsxs("div", { children: [SP_JSX.jsxs("div", { className: "sm8550-led-preview-label", children: [SP_JSX.jsx("span", { children: label }), SP_JSX.jsx("span", { className: "sm8550-led-preview-hex", children: hex.toUpperCase() })] }), SP_JSX.jsx("div", { className: "sm8550-led-preview-bar", style: { background } })] }));
}

function CustomSliders({ color, onChange, disabled = false, label = "Custom Color", }) {
    const [r, g, b] = color;
    const hex = rgbToHex(color);
    const updateChannel = (index, value) => {
        const next = [...color];
        next[index] = value;
        onChange(next);
    };
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsxs("div", { className: "sm8550-led-preview-label", children: [SP_JSX.jsx("span", { children: label }), SP_JSX.jsx("span", { className: "sm8550-led-preview-hex", children: hex.toUpperCase() })] }), SP_JSX.jsx("div", { className: "sm8550-led-preview-bar", style: {
                    margin: "0 14px 8px",
                    background: `linear-gradient(90deg, rgb(${r}, ${g}, ${b}), rgba(${r}, ${g}, ${b}, 0.35))`,
                } }), SP_JSX.jsx(DFL.SliderField, { label: "Red", value: r, min: 0, max: 255, step: 1, showValue: true, disabled: disabled, onChange: (value) => updateChannel(0, value) }), SP_JSX.jsx(DFL.SliderField, { label: "Green", value: g, min: 0, max: 255, step: 1, showValue: true, disabled: disabled, onChange: (value) => updateChannel(1, value) }), SP_JSX.jsx(DFL.SliderField, { label: "Blue", value: b, min: 0, max: 255, step: 1, showValue: true, disabled: disabled, onChange: (value) => updateChannel(2, value) })] }));
}

function SelectEdit({ label, description, options, value, onChange, disabled = false, bottomSeparator = "standard", }) {
    return (SP_JSX.jsx(DFL.DropdownItem, { label: label, description: description, bottomSeparator: bottomSeparator, disabled: disabled, rgOptions: options.map((option) => ({
            data: option.value,
            label: option.label,
        })), selectedOption: value, onChange: (option) => onChange(option.data) }));
}

const styles = `
  .sm8550-led-status-row {
    display: flex;
    justify-content: space-between;
    gap: 8px;
    padding: 4px 16px 8px;
    font-size: 13px;
    opacity: 0.85;
  }

  .sm8550-led-nav-row {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 4px 14px 8px;
  }

  .sm8550-led-nav-btn {
    width: 100%;
    min-width: 0;
  }

  .sm8550-led-page {
    padding-bottom: 32px;
  }

  .sm8550-led-preview-bar {
    width: 100%;
    height: 28px;
    border-radius: 6px;
    border: 1px solid rgba(255, 255, 255, 0.15);
    box-shadow: inset 0 0 12px rgba(0, 0, 0, 0.35);
    margin-top: 6px;
  }

  .sm8550-led-preview-label {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 12px;
    opacity: 0.85;
    margin-bottom: 4px;
    padding: 0 14px;
  }

  .sm8550-led-preview-hex {
    font-family: monospace;
    letter-spacing: 0.04em;
  }

  .sm8550-led-preset-wrap {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    padding: 8px 14px 4px;
    box-sizing: border-box;
    width: 100%;
  }

  .sm8550-led-preset-cell {
    width: 56px;
    flex: 0 0 56px;
    text-align: center;
  }

  .sm8550-led-preset-btn {
    width: 40px;
    height: 40px;
    margin: 0 auto;
    border-radius: 8px;
    border: 2px solid rgba(255, 255, 255, 0.12);
    cursor: pointer;
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.25);
  }

  .sm8550-led-preset-btn:focus,
  .sm8550-led-preset-btn.focused {
    border-color: rgba(255, 255, 255, 0.85);
    box-shadow: 0 0 0 2px rgba(26, 159, 255, 0.55), 0 4px 10px rgba(0, 0, 0, 0.35);
    outline: none;
  }

  .sm8550-led-preset-btn.selected {
    border-color: #1a9fff;
    box-shadow: 0 0 0 2px rgba(26, 159, 255, 0.45);
  }

  .sm8550-led-preset-name {
    font-size: 10px;
    opacity: 0.75;
    margin-top: 4px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .sm8550-led-effect-desc {
    font-size: 13px;
    line-height: 1.45;
    opacity: 0.82;
    padding: 4px 14px 8px;
  }

  .sm8550-led-zone-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 4px 14px;
  }

  .sm8550-led-zone-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 12px;
    border-radius: 6px;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid rgba(255, 255, 255, 0.08);
    font-size: 13px;
  }

  .sm8550-led-zone-type {
    opacity: 0.65;
    font-size: 12px;
  }

  .sm8550-led-device-name {
    font-size: 14px;
    font-weight: 500;
    padding: 4px 14px;
  }

  .sm8550-led-secondary-section {
    margin-top: 8px;
    padding-top: 4px;
    border-top: 1px solid rgba(255, 255, 255, 0.08);
  }

  .sm8550-led-disabled-overlay {
    opacity: 0.45;
    pointer-events: none;
  }

  .sm8550-led-page .${DFL.gamepadSliderClasses.SliderTrack} {
    --left-track-color: #1a9fff;
  }
`;

const ZONE_OPTIONS = [
    { value: "all", label: "All Zones" },
    { value: "sticks", label: "Sticks" },
    { value: "sides", label: "Side Rails" },
];
const PAGE_TABS = [
    { id: "lighting", label: "Lighting" },
    { id: "effects", label: "Effects" },
    { id: "system", label: "System" },
];
function Content() {
    const [state, setState] = SP_REACT.useState(DEFAULT_LED_STATE);
    const [loading, setLoading] = SP_REACT.useState(true);
    const [loadError, setLoadError] = SP_REACT.useState("");
    const [activeTab, setActiveTab] = SP_REACT.useState("lighting");
    const [editZone, setEditZone] = SP_REACT.useState("all");
    const [showCustomSliders, setShowCustomSliders] = SP_REACT.useState(false);
    const [busy, setBusy] = SP_REACT.useState(false);
    const refresh = SP_REACT.useCallback(async () => {
        try {
            const next = await refreshState();
            setState(next);
            setLoadError("");
        }
        catch (error) {
            console.error("SM8550 LED: failed to load state", error);
            setLoadError(String(error));
            toaster.toast({
                title: "LED Control",
                body: "Could not read device state.",
            });
        }
        finally {
            setLoading(false);
        }
    }, []);
    SP_REACT.useEffect(() => {
        void refresh();
    }, [refresh]);
    const activeColor = SP_REACT.useMemo(() => colorForZone(state, state.sync_zones ? "all" : editZone), [state, editZone]);
    const run = SP_REACT.useCallback(async (action, errorMessage) => {
        setBusy(true);
        try {
            await action();
            await refresh();
        }
        catch (error) {
            console.error(errorMessage, error);
            toaster.toast({ title: "LED Control", body: errorMessage });
        }
        finally {
            setBusy(false);
        }
    }, [refresh]);
    const handleEnabled = (enabled) => void run(() => setEnabled(enabled), "Failed to update power state.");
    const handleBrightness = (brightness) => void run(() => setBrightness(brightness), "Failed to update brightness.");
    const handleSyncZones = (sync) => {
        setState((prev) => ({ ...prev, sync_zones: sync }));
        void run(() => setSyncZones(sync), "Failed to update zone sync.");
    };
    const handleColor = (color) => {
        const zone = state.sync_zones ? "all" : editZone;
        setState((prev) => {
            if (zone === "sticks")
                return { ...prev, sticks_color: color };
            if (zone === "sides")
                return { ...prev, sides_color: color };
            return {
                ...prev,
                color,
                sticks_color: color,
                sides_color: color,
            };
        });
        void run(() => setColor(color, zone), "Failed to apply color.");
    };
    const handleSecondaryColor = (color) => {
        setState((prev) => ({ ...prev, secondary_color: color }));
        void run(() => setSecondaryColor(color), "Failed to apply secondary color.");
    };
    const handleEffect = (effect) => void run(() => setEffect(effect), "Failed to change effect.");
    const handleSpeed = (speed) => {
        setState((prev) => ({ ...prev, speed }));
        void run(() => setEffect(String(state.effect), speed), "Failed to update speed.");
    };
    const handleIncludePowerLed = (include) => void run(() => setIncludePowerLed(include), "Failed to update power LED setting.");
    const handleSleepOff = (sleepOff) => void run(() => setSleepOff(sleepOff), "Failed to update sleep setting.");
    const handleRediscover = () => void run(() => rediscoverZones(), "Failed to rediscover LED zones.");
    const effectInfo = EFFECT_INFO[state.effect] ?? {
        label: String(state.effect),
        description: "Custom lighting effect.",
    };
    const showSecondary = state.effect === "gradient";
    const effectLabel = EFFECT_INFO[state.effect]?.label ?? String(state.effect);
    if (loading) {
        return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("style", { children: styles }), SP_JSX.jsx(DFL.PanelSection, { title: "SM8550 LED", children: SP_JSX.jsx(DFL.PanelSectionRow, { children: "Loading\u2026" }) })] }));
    }
    if (loadError) {
        return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("style", { children: styles }), SP_JSX.jsxs(DFL.PanelSection, { title: "SM8550 LED", children: [SP_JSX.jsxs(DFL.PanelSectionRow, { children: ["Backend error: ", loadError] }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => void refresh(), children: "Retry" }) })] })] }));
    }
    const lightingDisabled = !state.enabled || busy;
    const lightingTab = (SP_JSX.jsxs("div", { className: `sm8550-led-page${lightingDisabled ? " sm8550-led-disabled-overlay" : ""}`, children: [SP_JSX.jsxs(DFL.PanelSection, { title: "Power", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Enable LEDs", description: "Master switch for all RGB lighting", checked: state.enabled, disabled: busy, onChange: handleEnabled }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: "Brightness", description: "Overall LED intensity", value: state.brightness, min: 0, max: 255, step: 1, showValue: true, disabled: lightingDisabled, onChange: handleBrightness }) })] }), SP_JSX.jsxs(DFL.PanelSection, { title: "Zones", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Sync All Zones", description: "Use one color for every LED zone", checked: state.sync_zones, disabled: lightingDisabled, onChange: handleSyncZones }) }), !state.sync_zones && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(SelectEdit, { label: "Edit Zone", description: "Choose which zone receives color changes", options: ZONE_OPTIONS, value: editZone, disabled: lightingDisabled, onChange: setEditZone }) }))] }), SP_JSX.jsx(DFL.PanelSection, { title: "Color", children: SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(ColorPreview, { label: state.sync_zones
                            ? "Active Color"
                            : `Color — ${ZONE_OPTIONS.find((z) => z.value === editZone)?.label ?? editZone}`, color: activeColor, secondaryColor: state.secondary_color, showGradient: showSecondary }) }) }), SP_JSX.jsxs(DFL.PanelSection, { title: "Presets", children: [SP_JSX.jsx(ColorPalette, { selectedColor: activeColor, disabled: lightingDisabled, onSelect: handleColor }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Custom RGB Sliders", description: "Fine-tune color with red, green, and blue channels", checked: showCustomSliders, disabled: lightingDisabled, onChange: setShowCustomSliders }) }), showCustomSliders && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(CustomSliders, { color: activeColor, disabled: lightingDisabled, onChange: handleColor }) })), showSecondary && (SP_JSX.jsxs("div", { className: "sm8550-led-secondary-section", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(ColorPreview, { label: "Secondary Color (Gradient)", color: state.secondary_color }) }), SP_JSX.jsx(ColorPalette, { selectedColor: state.secondary_color, disabled: lightingDisabled, onSelect: handleSecondaryColor }), showCustomSliders && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(CustomSliders, { label: "Secondary RGB", color: state.secondary_color, disabled: lightingDisabled, onChange: handleSecondaryColor }) }))] }))] })] }));
    const effectsTab = (SP_JSX.jsx("div", { className: `sm8550-led-page${lightingDisabled ? " sm8550-led-disabled-overlay" : ""}`, children: SP_JSX.jsxs(DFL.PanelSection, { title: "Animation", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(SelectEdit, { label: "Effect", description: "Choose a lighting animation preset", options: LED_EFFECTS.map((effect) => ({
                            value: effect,
                            label: EFFECT_INFO[effect].label,
                        })), value: state.effect, disabled: lightingDisabled, onChange: handleEffect }) }), SP_JSX.jsxs("div", { className: "sm8550-led-effect-desc", children: [SP_JSX.jsx("strong", { children: effectInfo.label }), SP_JSX.jsx("div", { children: effectInfo.description })] }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: "Speed", description: "Animation speed (1 slow \u2014 10 fast)", value: state.speed, min: 1, max: 10, step: 1, showValue: true, disabled: lightingDisabled ||
                            state.effect === "static" ||
                            state.effect === "battery" ||
                            state.effect === "temp", onChange: handleSpeed }) })] }) }));
    const systemTab = (SP_JSX.jsx("div", { className: "sm8550-led-page", children: SP_JSX.jsxs(DFL.PanelSection, { title: "Device", children: [SP_JSX.jsx("div", { className: "sm8550-led-device-name", children: state.device_name || "Unknown device" }), state.has_power_led && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Include Power LED", description: "Extend lighting effects to the power indicator", checked: state.include_power_led, disabled: busy, onChange: handleIncludePowerLed }) })), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ToggleField, { label: "Turn Off When Sleeping", description: "Disable LEDs while the device is suspended", checked: state.sleep_off, disabled: busy, onChange: handleSleepOff }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", disabled: busy, onClick: handleRediscover, children: "Rediscover LED Zones" }) }), SP_JSX.jsx("div", { className: "sm8550-led-zone-list", children: state.zones.length === 0 ? (SP_JSX.jsxs("div", { className: "sm8550-led-zone-item", children: [SP_JSX.jsx("span", { children: "No zones detected" }), SP_JSX.jsx("span", { className: "sm8550-led-zone-type", children: "Tap rediscover" })] })) : (state.zones.map((zone) => (SP_JSX.jsxs("div", { className: "sm8550-led-zone-item", children: [SP_JSX.jsx("span", { children: zone.name || zone.id }), SP_JSX.jsx("span", { className: "sm8550-led-zone-type", children: zone.type || zone.id })] }, zone.id)))) }), !state.sync_zones && state.zones.length > 0 && (SP_JSX.jsxs("div", { className: "sm8550-led-effect-desc", children: ["Sticks: ", rgbToHex(state.sticks_color).toUpperCase(), " \u00B7 Sides:", " ", rgbToHex(state.sides_color).toUpperCase()] }))] }) }));
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("style", { children: styles }), SP_JSX.jsx(DFL.PanelSection, { title: "Status", children: SP_JSX.jsxs("div", { className: "sm8550-led-status-row", children: [SP_JSX.jsx("span", { children: state.device_name || "SM8550 Handheld" }), SP_JSX.jsxs("span", { children: [state.enabled ? "On" : "Off", " \u00B7 ", effectLabel] })] }) }), SP_JSX.jsx(DFL.PanelSection, { title: "View", children: SP_JSX.jsx("div", { className: "sm8550-led-nav-row", children: PAGE_TABS.map((tab) => (SP_JSX.jsx("div", { className: "sm8550-led-nav-btn", children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => setActiveTab(tab.id), children: activeTab === tab.id ? `● ${tab.label}` : tab.label }) }, tab.id))) }) }), activeTab === "lighting" && lightingTab, activeTab === "effects" && effectsTab, activeTab === "system" && systemTab] }));
}

var index = definePlugin(() => ({
    name: "SM8550 LED",
    content: SP_JSX.jsx(Content, {}),
    icon: SP_JSX.jsx("div", { style: { fontWeight: 700 }, children: "LED" }),
    alwaysRender: true,
}));

export { index as default };
//# sourceMappingURL=index.js.map
