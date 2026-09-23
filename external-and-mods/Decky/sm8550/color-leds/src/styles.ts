import { gamepadSliderClasses } from "@decky/ui";

export const styles = `
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

  .sm8550-led-page .${gamepadSliderClasses.SliderTrack} {
    --left-track-color: #1a9fff;
  }
`;
