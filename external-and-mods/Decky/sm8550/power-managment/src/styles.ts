import { gamepadSliderClasses } from "@decky/ui";

export const styles = `
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
  .sfc-scope .${gamepadSliderClasses.SliderTrack} {
    --left-track-color: #1a9fff;
  }
`;
