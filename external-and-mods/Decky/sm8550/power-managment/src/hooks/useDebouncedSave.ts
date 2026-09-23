import { useEffect } from "react";
import type { Dispatch, MutableRefObject, SetStateAction } from "react";
import type { Config, PowerConfigPatch } from "../types";

interface DebouncedSaveOptions {
  config: Config | null;
  snapshot: MutableRefObject<string>;
  save: (value: PowerConfigPatch) => Promise<Config>;
  setConfig: Dispatch<SetStateAction<Config | null>>;
  onError?: (error: unknown) => void;
  delay?: number;
}

export function useDebouncedSave(options: DebouncedSaveOptions) {
  const { config, snapshot, save, setConfig, onError, delay = 900 } = options;
  const power = config?.power;

  useEffect(() => {
    if (!config || !snapshot.current || !power) return;
    const patch: PowerConfigPatch = {
      general: power.general,
      profiles: power.profiles,
    };
    const current = JSON.stringify(patch);
    if (current === snapshot.current) return;

    const timer = window.setTimeout(async () => {
      try {
        const saved = current;
        const next = await save(patch);
        const nextPatch: PowerConfigPatch = {
          general: next.power.general,
          profiles: next.power.profiles,
        };
        snapshot.current = JSON.stringify(nextPatch);
        setConfig((stored) => {
          if (!stored) return next;
          const storedPatch: PowerConfigPatch = {
            general: stored.power.general,
            profiles: stored.power.profiles,
          };
          if (JSON.stringify(storedPatch) !== saved) return stored;
          return { ...stored, power: next.power, active_profile: next.active_profile };
        });
      } catch (error) {
        onError?.(error);
      }
    }, delay);

    return () => window.clearTimeout(timer);
  }, [power, config, snapshot, save, setConfig, onError, delay]);
}
