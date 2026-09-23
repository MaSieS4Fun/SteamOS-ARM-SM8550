import { Dropdown, Field, PanelSectionRow, SliderField, ToggleField } from "@decky/ui";
import type { ReactNode } from "react";
import type { DropdownChoice } from "../types";

type Option = string | DropdownChoice;

export function SelectEdit({
  label,
  value,
  options,
  onChange,
  disabled,
  placeholder,
  wrapperClassName,
}: {
  label?: ReactNode;
  value: unknown;
  options: Option[];
  onChange: (data: string) => void;
  disabled?: boolean;
  placeholder?: string;
  wrapperClassName?: string;
}) {
  const rgOptions = options.map((option) =>
    typeof option === "string" ? { data: option, label: option } : option,
  );
  const dropdown =
    label === undefined ? (
      <Dropdown
        rgOptions={rgOptions}
        selectedOption={value}
        disabled={disabled}
        strDefaultLabel={placeholder}
        onChange={(option) => onChange(String(option.data))}
      />
    ) : (
      <Field label={label}>
        <Dropdown
          rgOptions={rgOptions}
          selectedOption={value}
          disabled={disabled}
          strDefaultLabel={placeholder}
          onChange={(option) => onChange(String(option.data))}
        />
      </Field>
    );
  return (
    <PanelSectionRow>
      {wrapperClassName ? <div className={wrapperClassName}>{dropdown}</div> : dropdown}
    </PanelSectionRow>
  );
}

export function ToggleRow({
  label,
  value,
  onChange,
  disabled,
  description,
  wrapperClassName,
}: {
  label: ReactNode;
  value: boolean;
  onChange: (value: boolean) => void;
  disabled?: boolean;
  description?: ReactNode;
  wrapperClassName?: string;
}) {
  const field = (
    <ToggleField
      label={label}
      description={description}
      checked={value}
      disabled={disabled}
      onChange={onChange}
    />
  );
  return (
    <PanelSectionRow>
      {wrapperClassName ? <div className={wrapperClassName}>{field}</div> : field}
    </PanelSectionRow>
  );
}

export function SliderEdit({
  label,
  value,
  min,
  max,
  step,
  onChange,
  format,
  disabled,
  showValue = true,
  wrapperClassName = "sm8550-power-slider-field",
}: {
  label: ReactNode;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (value: number) => void;
  format?: (value: number) => string;
  disabled?: boolean;
  showValue?: boolean;
  wrapperClassName?: string;
}) {
  const numeric = Number(value);
  return (
    <PanelSectionRow>
      <div className={wrapperClassName}>
        <SliderField
          label={label}
          value={numeric}
          min={min}
          max={max}
          step={step}
          disabled={disabled}
          showValue={showValue}
          onChange={(next) => onChange(format ? Number(format(next)) : next)}
        />
      </div>
    </PanelSectionRow>
  );
}
