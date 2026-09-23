import { Focusable } from "@decky/ui";
import { PRESET_COLORS, rgbToHex } from "../types";

interface ColorPaletteProps {
  selectedColor: [number, number, number];
  onSelect: (color: [number, number, number]) => void;
  disabled?: boolean;
}

export function ColorPalette({ selectedColor, onSelect, disabled = false }: ColorPaletteProps) {
  const selectedHex = rgbToHex(selectedColor);

  return (
    <div className="sm8550-led-preset-wrap">
      {PRESET_COLORS.map((preset) => {
        const hex = rgbToHex(preset.rgb);
        const isSelected = hex === selectedHex;

        return (
          <div key={preset.name} className="sm8550-led-preset-cell">
            <Focusable
              className={`sm8550-led-preset-btn${isSelected ? " selected" : ""}`}
              style={{ backgroundColor: hex }}
              onActivate={() => {
                if (!disabled) onSelect(preset.rgb);
              }}
              onClick={() => {
                if (!disabled) onSelect(preset.rgb);
              }}
              aria-label={preset.name}
            >
              <span aria-hidden="true" />
            </Focusable>
            <div className="sm8550-led-preset-name">{preset.name}</div>
          </div>
        );
      })}
    </div>
  );
}
