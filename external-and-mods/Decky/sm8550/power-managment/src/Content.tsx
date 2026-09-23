import { ButtonItem, PanelSection, PanelSectionRow, Tabs } from "@decky/ui";
import { toaster } from "@decky/api";
import { useCallback, useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { getConfig, savePowerConfig, setActiveProfile } from "./backend";
import { useDebouncedSave } from "./hooks/useDebouncedSave";
import { styles } from "./styles";
import { Fans } from "./tabs/Fans";
import { Monitor } from "./tabs/Monitor";
import { Power } from "./tabs/Power";
import type { Config } from "./types";
import { PROFILE_ORDER } from "./types";
import { titleCase } from "./lib/util";

const PROFILE_LABELS: Record<string, string> = {
  eco: "Eco",
  balanced: "Balanced",
  performance: "Performance",
  gaming: "Gaming",
};

export function Content() {
  const [tab, setTab] = useState("power");
  const [config, setConfig] = useState<Config | null>(null);
  const [message, setMessage] = useState("Loading");
  const [switchingProfile, setSwitchingProfile] = useState(false);
  const savedPowerSnapshot = useRef("");

  const load = useCallback(async () => {
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
    } catch (error) {
      setMessage(String(error));
    }
  }, []);

  useEffect(() => {
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

  const onQuickProfile = async (profileId: string) => {
    if (!config || switchingProfile || profileId === config.active_profile) return;
    setSwitchingProfile(true);
    try {
      const next = await setActiveProfile(profileId);
      setConfig(next);
      savedPowerSnapshot.current = JSON.stringify({
        general: next.power.general,
        profiles: next.power.profiles,
      });
    } catch (error) {
      toaster.toast({ title: "Profile switch failed", body: String(error) });
    } finally {
      setSwitchingProfile(false);
    }
  };

  if (!config) {
    return (
      <PanelSection title="SM8550 Power">
        <PanelSectionRow>{message || "Loading…"}</PanelSectionRow>
      </PanelSection>
    );
  }

  if (!config.supported) {
    return (
      <PanelSection title="Unsupported device">
        <PanelSectionRow>
          Qualcomm SM8550 handhelds only (Odin 2, Thor, Portal, RP6, etc.).
        </PanelSectionRow>
      </PanelSection>
    );
  }

  const battery = config.monitor?.battery;
  const temp =
    config.current_temp != null ? `${config.current_temp}°C` : "—";
  const batteryText = battery?.present
    ? `${battery.capacity ?? "—"}% · ${battery.status ?? "—"}`
    : "No battery";

  const tabContent = (content: ReactNode) => (
    <div className="sm8550-power-tab-content">{content}</div>
  );

  return (
    <>
      <style>{styles}</style>
      <PanelSection title="Active Profile">
        <div className="sm8550-power-profile-row">
          {PROFILE_ORDER.map((id) => (
            <div key={id} className="sm8550-power-profile-btn">
              <ButtonItem
                layout="below"
                disabled={switchingProfile}
                onClick={() => onQuickProfile(id)}
              >
                {config.active_profile === id
                  ? `● ${PROFILE_LABELS[id] ?? titleCase(id)}`
                  : PROFILE_LABELS[id] ?? titleCase(id)}
              </ButtonItem>
            </div>
          ))}
        </div>
        <div className="sm8550-power-status-row">
          <span>{temp}</span>
          <span>{batteryText}</span>
        </div>
      </PanelSection>

      <Tabs
        className="sm8550-power-tabs"
        activeTab={tab}
        onShowTab={(id: string) => setTab(id)}
        tabs={[
          {
            id: "power",
            title: "Power",
            content: tabContent(<Power config={config} setConfig={setConfig} />),
          },
          {
            id: "fan",
            title: "Fan",
            content: tabContent(<Fans setConfig={setConfig} />),
          },
          {
            id: "monitor",
            title: "Monitor",
            content: tabContent(<Monitor config={config} />),
          },
        ]}
      />
    </>
  );
}
