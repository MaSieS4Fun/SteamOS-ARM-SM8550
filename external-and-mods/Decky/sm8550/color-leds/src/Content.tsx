import {
  ButtonItem,
  PanelSection,
  PanelSectionRow,
  SliderField,
  ToggleField,
} from "@decky/ui";
import { toaster } from "@decky/api";
import { useCallback, useEffect, useMemo, useState } from "react";
import * as backend from "./backend";
import { ColorPalette } from "./components/ColorPalette";
import { ColorPreview } from "./components/ColorPreview";
import { CustomSliders } from "./components/CustomSliders";
import { SelectEdit } from "./components/widgets";
import { styles } from "./styles";
import {
  colorForZone,
  DEFAULT_LED_STATE,
  EFFECT_INFO,
  LED_EFFECTS,
  type LedEffect,
  type LedState,
  type LedZone,
  rgbToHex,
} from "./types";

const ZONE_OPTIONS: { value: LedZone; label: string }[] = [
  { value: "all", label: "All Zones" },
  { value: "sticks", label: "Sticks" },
  { value: "sides", label: "Side Rails" },
];

const PAGE_TABS = [
  { id: "lighting", label: "Lighting" },
  { id: "effects", label: "Effects" },
  { id: "system", label: "System" },
] as const;

type PageTab = (typeof PAGE_TABS)[number]["id"];

export function Content() {
  const [state, setState] = useState<LedState>(DEFAULT_LED_STATE);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [activeTab, setActiveTab] = useState<PageTab>("lighting");
  const [editZone, setEditZone] = useState<LedZone>("all");
  const [showCustomSliders, setShowCustomSliders] = useState(false);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const next = await backend.refreshState();
      setState(next);
      setLoadError("");
    } catch (error) {
      console.error("SM8550 LED: failed to load state", error);
      setLoadError(String(error));
      toaster.toast({
        title: "LED Control",
        body: "Could not read device state.",
      });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const activeColor = useMemo(
    () => colorForZone(state, state.sync_zones ? "all" : editZone),
    [state, editZone],
  );

  const run = useCallback(
    async (action: () => Promise<unknown>, errorMessage: string) => {
      setBusy(true);
      try {
        await action();
        await refresh();
      } catch (error) {
        console.error(errorMessage, error);
        toaster.toast({ title: "LED Control", body: errorMessage });
      } finally {
        setBusy(false);
      }
    },
    [refresh],
  );

  const handleEnabled = (enabled: boolean) =>
    void run(() => backend.setEnabled(enabled), "Failed to update power state.");

  const handleBrightness = (brightness: number) =>
    void run(() => backend.setBrightness(brightness), "Failed to update brightness.");

  const handleSyncZones = (sync: boolean) => {
    setState((prev) => ({ ...prev, sync_zones: sync }));
    void run(() => backend.setSyncZones(sync), "Failed to update zone sync.");
  };

  const handleColor = (color: [number, number, number]) => {
    const zone: LedZone = state.sync_zones ? "all" : editZone;
    setState((prev) => {
      if (zone === "sticks") return { ...prev, sticks_color: color };
      if (zone === "sides") return { ...prev, sides_color: color };
      return {
        ...prev,
        color,
        sticks_color: color,
        sides_color: color,
      };
    });
    void run(() => backend.setColor(color, zone), "Failed to apply color.");
  };

  const handleSecondaryColor = (color: [number, number, number]) => {
    setState((prev) => ({ ...prev, secondary_color: color }));
    void run(() => backend.setSecondaryColor(color), "Failed to apply secondary color.");
  };

  const handleEffect = (effect: LedEffect) =>
    void run(() => backend.setEffect(effect), "Failed to change effect.");

  const handleSpeed = (speed: number) => {
    setState((prev) => ({ ...prev, speed }));
    void run(() => backend.setEffect(String(state.effect), speed), "Failed to update speed.");
  };

  const handleIncludePowerLed = (include: boolean) =>
    void run(() => backend.setIncludePowerLed(include), "Failed to update power LED setting.");

  const handleSleepOff = (sleepOff: boolean) =>
    void run(() => backend.setSleepOff(sleepOff), "Failed to update sleep setting.");

  const handleRediscover = () =>
    void run(() => backend.rediscoverZones(), "Failed to rediscover LED zones.");

  const effectInfo = EFFECT_INFO[state.effect as LedEffect] ?? {
    label: String(state.effect),
    description: "Custom lighting effect.",
  };

  const showSecondary = state.effect === "gradient";
  const effectLabel =
    EFFECT_INFO[state.effect as LedEffect]?.label ?? String(state.effect);

  if (loading) {
    return (
      <>
        <style>{styles}</style>
        <PanelSection title="SM8550 LED">
          <PanelSectionRow>Loading…</PanelSectionRow>
        </PanelSection>
      </>
    );
  }

  if (loadError) {
    return (
      <>
        <style>{styles}</style>
        <PanelSection title="SM8550 LED">
          <PanelSectionRow>Backend error: {loadError}</PanelSectionRow>
          <PanelSectionRow>
            <ButtonItem layout="below" onClick={() => void refresh()}>
              Retry
            </ButtonItem>
          </PanelSectionRow>
        </PanelSection>
      </>
    );
  }

  const lightingDisabled = !state.enabled || busy;

  const lightingTab = (
    <div className={`sm8550-led-page${lightingDisabled ? " sm8550-led-disabled-overlay" : ""}`}>
      <PanelSection title="Power">
        <PanelSectionRow>
          <ToggleField
            label="Enable LEDs"
            description="Master switch for all RGB lighting"
            checked={state.enabled}
            disabled={busy}
            onChange={handleEnabled}
          />
        </PanelSectionRow>
        <PanelSectionRow>
          <SliderField
            label="Brightness"
            description="Overall LED intensity"
            value={state.brightness}
            min={0}
            max={255}
            step={1}
            showValue
            disabled={lightingDisabled}
            onChange={handleBrightness}
          />
        </PanelSectionRow>
      </PanelSection>

      <PanelSection title="Zones">
        <PanelSectionRow>
          <ToggleField
            label="Sync All Zones"
            description="Use one color for every LED zone"
            checked={state.sync_zones}
            disabled={lightingDisabled}
            onChange={handleSyncZones}
          />
        </PanelSectionRow>
        {!state.sync_zones && (
          <PanelSectionRow>
            <SelectEdit
              label="Edit Zone"
              description="Choose which zone receives color changes"
              options={ZONE_OPTIONS}
              value={editZone}
              disabled={lightingDisabled}
              onChange={setEditZone}
            />
          </PanelSectionRow>
        )}
      </PanelSection>

      <PanelSection title="Color">
        <PanelSectionRow>
          <ColorPreview
            label={
              state.sync_zones
                ? "Active Color"
                : `Color — ${ZONE_OPTIONS.find((z) => z.value === editZone)?.label ?? editZone}`
            }
            color={activeColor}
            secondaryColor={state.secondary_color}
            showGradient={showSecondary}
          />
        </PanelSectionRow>
      </PanelSection>

      <PanelSection title="Presets">
        <ColorPalette
          selectedColor={activeColor}
          disabled={lightingDisabled}
          onSelect={handleColor}
        />
        <PanelSectionRow>
          <ToggleField
            label="Custom RGB Sliders"
            description="Fine-tune color with red, green, and blue channels"
            checked={showCustomSliders}
            disabled={lightingDisabled}
            onChange={setShowCustomSliders}
          />
        </PanelSectionRow>
        {showCustomSliders && (
          <PanelSectionRow>
            <CustomSliders
              color={activeColor}
              disabled={lightingDisabled}
              onChange={handleColor}
            />
          </PanelSectionRow>
        )}
        {showSecondary && (
          <div className="sm8550-led-secondary-section">
            <PanelSectionRow>
              <ColorPreview
                label="Secondary Color (Gradient)"
                color={state.secondary_color}
              />
            </PanelSectionRow>
            <ColorPalette
              selectedColor={state.secondary_color}
              disabled={lightingDisabled}
              onSelect={handleSecondaryColor}
            />
            {showCustomSliders && (
              <PanelSectionRow>
                <CustomSliders
                  label="Secondary RGB"
                  color={state.secondary_color}
                  disabled={lightingDisabled}
                  onChange={handleSecondaryColor}
                />
              </PanelSectionRow>
            )}
          </div>
        )}
      </PanelSection>
    </div>
  );

  const effectsTab = (
    <div className={`sm8550-led-page${lightingDisabled ? " sm8550-led-disabled-overlay" : ""}`}>
      <PanelSection title="Animation">
        <PanelSectionRow>
          <SelectEdit
            label="Effect"
            description="Choose a lighting animation preset"
            options={LED_EFFECTS.map((effect) => ({
              value: effect,
              label: EFFECT_INFO[effect].label,
            }))}
            value={state.effect as LedEffect}
            disabled={lightingDisabled}
            onChange={handleEffect}
          />
        </PanelSectionRow>
        <div className="sm8550-led-effect-desc">
          <strong>{effectInfo.label}</strong>
          <div>{effectInfo.description}</div>
        </div>
        <PanelSectionRow>
          <SliderField
            label="Speed"
            description="Animation speed (1 slow — 10 fast)"
            value={state.speed}
            min={1}
            max={10}
            step={1}
            showValue
            disabled={
              lightingDisabled ||
              state.effect === "static" ||
              state.effect === "battery" ||
              state.effect === "temp"
            }
            onChange={handleSpeed}
          />
        </PanelSectionRow>
      </PanelSection>
    </div>
  );

  const systemTab = (
    <div className="sm8550-led-page">
    <PanelSection title="Device">
      <div className="sm8550-led-device-name">{state.device_name || "Unknown device"}</div>
      {state.has_power_led && (
        <PanelSectionRow>
          <ToggleField
            label="Include Power LED"
            description="Extend lighting effects to the power indicator"
            checked={state.include_power_led}
            disabled={busy}
            onChange={handleIncludePowerLed}
          />
        </PanelSectionRow>
      )}
      <PanelSectionRow>
        <ToggleField
          label="Turn Off When Sleeping"
          description="Disable LEDs while the device is suspended"
          checked={state.sleep_off}
          disabled={busy}
          onChange={handleSleepOff}
        />
      </PanelSectionRow>
      <PanelSectionRow>
        <ButtonItem layout="below" disabled={busy} onClick={handleRediscover}>
          Rediscover LED Zones
        </ButtonItem>
      </PanelSectionRow>
      <div className="sm8550-led-zone-list">
        {state.zones.length === 0 ? (
          <div className="sm8550-led-zone-item">
            <span>No zones detected</span>
            <span className="sm8550-led-zone-type">Tap rediscover</span>
          </div>
        ) : (
          state.zones.map((zone) => (
            <div key={zone.id} className="sm8550-led-zone-item">
              <span>{zone.name || zone.id}</span>
              <span className="sm8550-led-zone-type">{zone.type || zone.id}</span>
            </div>
          ))
        )}
      </div>
      {!state.sync_zones && state.zones.length > 0 && (
        <div className="sm8550-led-effect-desc">
          Sticks: {rgbToHex(state.sticks_color).toUpperCase()} · Sides:{" "}
          {rgbToHex(state.sides_color).toUpperCase()}
        </div>
      )}
    </PanelSection>
    </div>
  );

  return (
    <>
      <style>{styles}</style>
      <PanelSection title="Status">
        <div className="sm8550-led-status-row">
          <span>{state.device_name || "SM8550 Handheld"}</span>
          <span>
            {state.enabled ? "On" : "Off"} · {effectLabel}
          </span>
        </div>
      </PanelSection>

      <PanelSection title="View">
        <div className="sm8550-led-nav-row">
          {PAGE_TABS.map((tab) => (
            <div key={tab.id} className="sm8550-led-nav-btn">
              <ButtonItem layout="below" onClick={() => setActiveTab(tab.id)}>
                {activeTab === tab.id ? `● ${tab.label}` : tab.label}
              </ButtonItem>
            </div>
          ))}
        </div>
      </PanelSection>

      {activeTab === "lighting" && lightingTab}
      {activeTab === "effects" && effectsTab}
      {activeTab === "system" && systemTab}
    </>
  );
}
