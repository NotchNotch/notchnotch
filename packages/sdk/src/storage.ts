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
 * Small persistent key-value storage for this extension (JSON values, 255 KiB
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

/** TypeScript infers `true`/`false` literally even here; a stored flag must accept both. */
export type Stored<T> = [T] extends [boolean] ? boolean : T;

/**
 * `useState` that is saved to `storage` under `key` and restored on the next launch.
 * `T` is left unconstrained so `useStoredState("count", 0)` infers `number` rather than
 * the literal `0`; the intersection still requires a JSON value.
 */
export function useStoredState<T>(key: string, initial: T & JSONValue): [Stored<T>, (value: Stored<T> | ((previous: Stored<T>) => Stored<T>)) => void] {
  type V = Stored<T>;
  const [value, setValue] = useState<V>(() => (storage.get(key) as V | undefined) ?? (initial as V));
  const update = useCallback((next: V | ((previous: V) => V)) => {
    setValue((previous) => {
      const resolved = typeof next === "function" ? (next as (previous: V) => V)(previous) : next;
      storage.set(key, resolved as JSONValue);
      return resolved;
    });
  }, [key]);
  return [value, update];
}
