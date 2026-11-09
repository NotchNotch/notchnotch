# Preferences

Declare the settings your extension needs in the manifest, and NotchNotch draws them as native fields at the top of your extension's **Setup**. You don't write any UI for them.

```json
{
  "preferences": [
    { "name": "apiToken", "type": "password", "title": "API Token", "required": true,
      "description": "Create one at example.com/settings/tokens." },
    { "name": "city", "type": "text", "title": "City", "default": "Paris" },
    { "name": "units", "type": "dropdown", "title": "Units", "default": "metric",
      "options": [{ "value": "metric", "title": "Metric" }, { "value": "imperial", "title": "Imperial" }] },
    { "name": "showWind", "type": "toggle", "title": "Show Wind", "default": true }
  ]
}
```

```tsx
import { getPreferenceValues } from "@notchnotch/sdk";

type Preferences = { apiToken: string; city: string; units: "metric" | "imperial"; showWind: boolean };
const { apiToken, city, units, showWind } = getPreferenceValues<Preferences>();
```

Requires NotchNotch 0.5 or later.

## Types

| `type` | Field | Value | `default` |
| --- | --- | --- | --- |
| `text` | text field | string | text |
| `password` | secure field; stored in the Keychain | string | not allowed |
| `toggle` | switch | boolean | `true` or `false` |
| `dropdown` | menu of `options` (1–32 `{ value, title }`) | the chosen `value` | one of the values |

Each preference has a `name` (letters, digits and `_`, starting with a letter), a `title` of up to 64 characters, and optionally a `description` and a `placeholder`. An extension can declare up to 16.

## Values

- `getPreferenceValues()` works anywhere, including top-level code: NotchNotch hands the values to your extension before it runs.
- Defaults fill in what the person hasn't set. An optional preference with no value and no default is missing from the object.
- Saving in Setup restarts your extension with the new values, so values never change while it runs.

## Required preferences

With `"required": true`, your extension doesn't start until the person fills the field in. Its page shows **Needs setup** and names what's missing; it starts as soon as they save. Use it for things the extension can't work without, such as an API token. A toggle can't be required.

## Passwords

`password` values live in the login Keychain, like [secrets](storage.md#secrets), and a saved password is never shown again in Setup. Typing a new one replaces it. Prefer a `password` preference over your own token field: people get a familiar form, and you get the value without asking.
