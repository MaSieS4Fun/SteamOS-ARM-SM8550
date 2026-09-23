import { rgbToHex } from "../types";

interface ColorPreviewProps {
  color: [number, number, number];
  label?: string;
  secondaryColor?: [number, number, number];
  showGradient?: boolean;
}

export function ColorPreview({
  color,
  label = "Current Color",
  secondaryColor,
  showGradient = false,
}: ColorPreviewProps) {
  const hex = rgbToHex(color);
  const background =
    showGradient && secondaryColor
      ? `linear-gradient(90deg, ${rgbToHex(color)}, ${rgbToHex(secondaryColor)})`
      : rgbToHex(color);

  return (
    <div>
      <div className="sm8550-led-preview-label">
        <span>{label}</span>
        <span className="sm8550-led-preview-hex">{hex.toUpperCase()}</span>
      </div>
      <div className="sm8550-led-preview-bar" style={{ background }} />
    </div>
  );
}
