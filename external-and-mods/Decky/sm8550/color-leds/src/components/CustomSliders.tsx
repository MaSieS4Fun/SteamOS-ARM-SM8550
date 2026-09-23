import { SliderField } from "@decky/ui";
import { rgbToHex } from "../types";

interface CustomSlidersProps {
  color: [number, number, number];
  onChange: (color: [number, number, number]) => void;
  disabled?: boolean;
  label?: string;
}

export function CustomSliders({
  color,
  onChange,
  disabled = false,
  label = "Custom Color",
}: CustomSlidersProps) {
  const [r, g, b] = color;
  const hex = rgbToHex(color);

  const updateChannel = (index: 0 | 1 | 2, value: number) => {
    const next: [number, number, number] = [...color] as [number, number, number];
    next[index] = value;
    onChange(next);
  };

  return (
    <>
      <div className="sm8550-led-preview-label">
        <span>{label}</span>
        <span className="sm8550-led-preview-hex">{hex.toUpperCase()}</span>
      </div>
      <div
        className="sm8550-led-preview-bar"
        style={{
          margin: "0 14px 8px",
          background: `linear-gradient(90deg, rgb(${r}, ${g}, ${b}), rgba(${r}, ${g}, ${b}, 0.35))`,
        }}
      />
      <SliderField
        label="Red"
        value={r}
        min={0}
        max={255}
        step={1}
        showValue
        disabled={disabled}
        onChange={(value) => updateChannel(0, value)}
      />
      <SliderField
        label="Green"
        value={g}
        min={0}
        max={255}
        step={1}
        showValue
        disabled={disabled}
        onChange={(value) => updateChannel(1, value)}
      />
      <SliderField
        label="Blue"
        value={b}
        min={0}
        max={255}
        step={1}
        showValue
        disabled={disabled}
        onChange={(value) => updateChannel(2, value)}
      />
    </>
  );
}
