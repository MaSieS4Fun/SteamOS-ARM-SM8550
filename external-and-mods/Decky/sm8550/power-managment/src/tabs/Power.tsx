import { ButtonItem, PanelSection } from "@decky/ui";
import { useState } from "react";
import type { Dispatch, SetStateAction } from "react";
import { SelectEdit, SliderEdit } from "../components/widgets";
import { clone, titleCase, update } from "../lib/util";
import type { Config, PowerProfile } from "../types";

const underclocks = [
  { data: "none", label: "None" },
  { data: "small", label: "Small" },
  { data: "medium", label: "Medium" },
  { data: "large", label: "Large" },
];

export function Power({
  config,
  setConfig,
}: {
  config: Config;
  setConfig: Dispatch<SetStateAction<Config | null>>;
}) {
  const [profile, setProfile] = useState(config.power.general.default_profile || "balanced");
  const p = config.power.profiles[profile] ?? ({} as PowerProfile);

  const profiles = Object.entries(config.power.profiles).map(([name, prof]) => ({
    data: name,
    label: prof.label || titleCase(name),
  }));

  const fanCurves = Object.entries(config.power.fan_curves).map(([name, curve]) => ({
    data: name,
    label: curve.label || titleCase(name),
  }));

  const setProfileValue = (name: keyof PowerProfile, value: unknown) => {
    setConfig((current) =>
      current ? update(current, ["power", "profiles", profile, name], value) : current,
    );
  };

  const setGpuValue = (name: "gpu_min" | "gpu_max", value: number) => {
    setConfig((current) => {
      if (!current) return current;
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
    if (!defaults) return;
    setConfig((current) =>
      current ? update(current, ["power", "profiles", profile], defaults) : current,
    );
  };

  const supportsUnderclockPresets = !!config.power.underclocks?.[config.perf.cpu_device_class];

  return (
    <div className="sfc-scope">
      <PanelSection title="Edit Profile">
        <SelectEdit
          label="Profile to edit"
          value={profile}
          options={profiles}
          onChange={setProfile}
        />
        <SelectEdit
          label="Fan curve"
          value={p.fan_curve ?? ""}
          options={fanCurves}
          onChange={(v) => setProfileValue("fan_curve", v)}
        />
        {(config.perf?.governors?.length ?? 0) > 0 ? (
          <SelectEdit
            label="CPU governor"
            value={p.cpu_governor ?? ""}
            options={config.perf.governors.map((g) => ({ data: g, label: titleCase(g) }))}
            onChange={(v) => setProfileValue("cpu_governor", v)}
          />
        ) : null}
        {supportsUnderclockPresets ? (
          <SelectEdit
            label="CPU underclock"
            value={p.cpu_underclock ?? "none"}
            options={underclocks}
            onChange={(v) => setProfileValue("cpu_underclock", v)}
          />
        ) : (
          <SliderEdit
            label="CPU max"
            value={Math.round(Number(p.cpu_max ?? 1) * 100)}
            min={0}
            max={100}
            step={1}
            onChange={(v) => setProfileValue("cpu_max", Number((v / 100).toFixed(2)))}
          />
        )}
        <SliderEdit
          label="GPU min"
          value={Math.round(Number(p.gpu_min ?? 0) * 100)}
          min={0}
          max={100}
          step={1}
          onChange={(v) => setGpuValue("gpu_min", Number((v / 100).toFixed(2)))}
        />
        <SliderEdit
          label="GPU max"
          value={Math.round(Number(p.gpu_max ?? 1) * 100)}
          min={0}
          max={100}
          step={1}
          onChange={(v) => setGpuValue("gpu_max", Number((v / 100).toFixed(2)))}
        />
        <div className="sfc-reset-row">
          <ButtonItem layout="below" onClick={resetProfile}>
            Reset to Default
          </ButtonItem>
        </div>
      </PanelSection>
    </div>
  );
}
