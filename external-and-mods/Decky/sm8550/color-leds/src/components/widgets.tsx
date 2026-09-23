import { DropdownItem } from "@decky/ui";

export interface SelectOption<T extends string = string> {
  value: T;
  label: string;
}

interface SelectEditProps<T extends string = string> {
  label: string;
  description?: string;
  options: SelectOption<T>[];
  value: T;
  onChange: (value: T) => void;
  disabled?: boolean;
  bottomSeparator?: "none" | "standard" | "thick";
}

export function SelectEdit<T extends string = string>({
  label,
  description,
  options,
  value,
  onChange,
  disabled = false,
  bottomSeparator = "standard",
}: SelectEditProps<T>) {
  return (
    <DropdownItem
      label={label}
      description={description}
      bottomSeparator={bottomSeparator}
      disabled={disabled}
      rgOptions={options.map((option) => ({
        data: option.value,
        label: option.label,
      }))}
      selectedOption={value}
      onChange={(option) => onChange(option.data as T)}
    />
  );
}
