declare global {
  var __notchnotchPreferences: Readonly<Record<string, string | boolean>> | undefined;
}

/** A preference value: text, password and dropdown values are strings, toggles are booleans. */
export type PreferenceValue = string | boolean;

/**
 * The values of the preferences your manifest declares, as the person set
 * them in Setup, with defaults filled in. An optional preference without a
 * value or default is missing from the object. Changing a value in Setup
 * restarts the extension, so the values never change while it runs.
 */
export function getPreferenceValues<T extends Record<string, PreferenceValue | undefined> = Record<string, PreferenceValue | undefined>>(): T {
  return (globalThis.__notchnotchPreferences ?? {}) as T;
}
