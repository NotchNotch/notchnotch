import { useCallback, useState } from "react";
import type { JSONValue } from "@notchnotch/protocol";

declare global {
  var __nativeStorageRead: (() => string) | undefined;
  var __nativeStorageWrite: ((json: string) => boolean) | undefined;
}

let cache: Record<string, JSONValue> | undefined;
function load(): Record<string, JSONValue> {
  if (cache) return cache;
  try {
    const value = JSON.parse(globalThis.__nativeStorageRead?.() ?? "{}");
    cache = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  } catch { cache = {}; }
  return cache!;
}

/**
 * Small persistent key-value storage for this extension (JSON values, 256 KiB
 * in total). Survives app restarts; removed together with the extension.
 * Reads are synchronous. A write that would exceed the limit is rejected and
 * returns `false`.
 */
export const storage = {
  get<T extends JSONValue = JSONValue>(key: string): T | undefined {
    return load()[key] as T | undefined;
  },
  set(key: string, value: JSONValue): boolean {
    const next = { ...load(), [key]: value };
    if (!globalThis.__nativeStorageWrite?.(JSON.stringify(next))) return false;
    cache = next;
    return true;
  },
  remove(key: string): boolean {
    const next = { ...load() };
    delete next[key];
    if (!globalThis.__nativeStorageWrite?.(JSON.stringify(next))) return false;
    cache = next;
    return true;
  },
  keys(): string[] { return Object.keys(load()); },
};

/** `useState` that is saved to `storage` under `key` and restored on the next launch. */
export function useStoredState<T extends JSONValue>(key: string, initial: T): [T, (value: T | ((previous: T) => T)) => void] {
  const [value, setValue] = useState<T>(() => storage.get<T>(key) ?? initial);
  const update = useCallback((next: T | ((previous: T) => T)) => {
    setValue((previous) => {
      const resolved = typeof next === "function" ? (next as (previous: T) => T)(previous) : next;
      storage.set(key, resolved);
      return resolved;
    });
  }, [key]);
  return [value, update];
}
