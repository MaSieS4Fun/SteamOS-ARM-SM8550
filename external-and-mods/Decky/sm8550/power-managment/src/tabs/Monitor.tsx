import { PanelSection, PanelSectionRow } from "@decky/ui";
import type { Config } from "../types";

function StatRow({ label, value }: { label: string; value: string }) {
  return (
    <PanelSectionRow>
      <div style={{ display: "flex", justifyContent: "space-between", width: "100%" }}>
        <span style={{ opacity: 0.7 }}>{label}</span>
        <span>{value}</span>
      </div>
    </PanelSectionRow>
  );
}

export function Monitor({ config }: { config: Config }) {
  const { monitor: m, device } = config;
  const gpu = m.gpu ?? {};
  const battery = m.battery ?? { present: false };
  const fan = m.fan ?? { present: false };

  return (
    <>
      <PanelSection title="Device">
        <StatRow label="Name" value={device.name} />
        <StatRow label="SoC" value={device.soc} />
        <StatRow label="Active profile" value={config.active_profile} />
      </PanelSection>

      <PanelSection title="GPU">
        <StatRow label="Governor" value={gpu.governor ?? "—"} />
        <StatRow
          label="Clock"
          value={`${gpu.cur_mhz ?? "—"} / ${gpu.max_mhz ?? "—"} MHz`}
        />
        <StatRow label="Runtime PM" value={gpu.runtime_pm ?? "—"} />
      </PanelSection>

      <PanelSection title="CPU">
        {(m.cpus ?? []).map((cpu) => (
          <StatRow
            key={cpu.id}
            label={`${cpu.label} (${cpu.id})`}
            value={`${cpu.cur_mhz} MHz · ${cpu.governor}`}
          />
        ))}
        {!m.cpus?.length ? <StatRow label="Status" value="No CPU data" /> : null}
      </PanelSection>

      <PanelSection title="Battery">
        {battery.present ? (
          <>
            <StatRow label="Capacity" value={`${battery.capacity ?? "—"}%`} />
            <StatRow label="Status" value={battery.status ?? "—"} />
            <StatRow label="Power" value={`${battery.power_w ?? 0} W`} />
          </>
        ) : (
          <StatRow label="Status" value="Not present" />
        )}
      </PanelSection>

      <PanelSection title="Thermals">
        {(m.thermals ?? []).map((t) => (
          <StatRow key={t.name} label={t.name} value={`${t.temp_c}°C`} />
        ))}
        {!m.thermals?.length ? <StatRow label="Status" value="No sensors" /> : null}
      </PanelSection>

      <PanelSection title="Fan">
        {fan.present ? (
          <>
            <StatRow label="PWM" value={String(fan.pwm ?? "—")} />
            <StatRow label="RPM" value={String(fan.rpm ?? "—")} />
            <StatRow
              label="Level"
              value={`${fan.level ?? "—"} / ${fan.max_level ?? "—"}`}
            />
          </>
        ) : (
          <StatRow label="Status" value="Not detected" />
        )}
      </PanelSection>

      <PanelSection title="Storage">
        <StatRow label="UFS keepalive" value={m.ufs_keepalive ? "On" : "Off"} />
      </PanelSection>
    </>
  );
}
