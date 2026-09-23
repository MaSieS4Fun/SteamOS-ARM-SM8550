export function clone<T>(obj: T): T {
  return JSON.parse(JSON.stringify(obj));
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export function update<T>(obj: T, path: (string | number)[], value: unknown): T {
  const next = clone(obj);
  let cursor: Record<string | number, unknown> = next as Record<string | number, unknown>;
  for (let i = 0; i < path.length - 1; i += 1) {
    cursor = cursor[path[i]] as Record<string | number, unknown>;
  }
  cursor[path[path.length - 1]] = value;
  return next;
}

export function titleCase(value: unknown): string {
  const text = String(value ?? "");
  return text.charAt(0).toUpperCase() + text.slice(1);
}
