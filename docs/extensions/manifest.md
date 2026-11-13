# Manifest

`notchnotch.json` describes your extension. NotchNotch reads it before running any code and shows what it asks for in the install review. The JSON Schema is [`schemas/manifest.schema.json`](../../schemas/manifest.schema.json).

```json
{
  "id": "dev.jane.weather",
  "name": "Weather",
  "version": "1.0.0",
  "apiVersion": 1,
  "entry": "bundle.js",
  "permissions": [],
  "icon": "icon.png",
  "accent": "cyan",
  "description": "Today's forecast at a glance.",
  "author": "jane",
  "categories": ["Weather"],
  "license": "MIT",
  "homepage": "https://example.com/weather",
  "repository": "https://example.com/jane/weather"
}
```

## Required fields

| Field | Value |
| --- | --- |
| `id` | Unique and stable across versions: lowercase letters, digits, `.` and `-`, 3–80 characters, starting with a letter. Use a domain or handle you own, such as `dev.jane.weather` |
| `name` | 1–128 characters, in title case |
| `version` | 1–64 characters, such as `1.0.0` |
| `apiVersion` | `1` |
| `entry` | `"bundle.js"` |
| `permissions` | `[]`, or what your [connections](connections.md) need (`local-network`, `process`) the [capabilities](capabilities.md) you use (`calendar`, `now-playing`, `battery`, `system`), and `file-read` to [read dropped files](drops.md#reading-files) |

## Identity

| Field | Value |
| --- | --- |
| `icon` | The file name of a 512×512 PNG in `assets/`, such as `"icon.png"`, or an SF Symbol name. See [Icons](publishing.md#icon) |
| `description` | One sentence, up to 512 characters (160 or fewer reads best) |
| `accent` | Your extension's color in the notch: one of `orange`, `yellow`, `green`, `mint`, `cyan`, `blue`, `purple`, `pink`, `red`. See [Color](components.md#color). Without one, accents are white |

## Store information

Optional. They describe the extension in the install review and under **Developer › Package**, and grant nothing.

| Field | Value |
| --- | --- |
| `author` | Your store handle, such as your GitHub user name: lowercase letters, digits and hyphens, up to 39 characters |
| `categories` | One to three of `Communication`, `Developer Tools`, `Finance`, `Fun`, `Health`, `Media`, `News`, `Productivity`, `Sports`, `System`, `Weather`, `Other` |
| `license` | An SPDX identifier or expression, such as `MIT` or `MIT OR Apache-2.0` |
| `homepage`, `repository` | `https://` addresses without a user name or password |

## preferences

Up to 16 settings NotchNotch draws in Setup and hands to your extension. See [Preferences](preferences.md).

## network

Up to 16 `https` hosts the extension may call with [`fetch`](network.md), such as `["api.github.com", "*.example.com"]`. A `*.` wildcard matches subdomains, not the bare domain. The install review lists them.

## connections

Up to eight named local destinations. Names use lowercase letters, digits and `-`. See [Connections](connections.md) and [Native helpers](native-helpers.md).

```json
"permissions": ["local-network"],
"connections": {
  "api": { "transport": "http", "endpoint": "http://127.0.0.1:4277" }
}
```

## imageHosts

Up to eight `https` hosts that `Artwork` may load images from, such as `["i.scdn.co", "*.mzstatic.com"]`. A `*.` wildcard matches subdomains, not the bare domain. No host is allowed unless you list it.

## Package limits

The installer, and `notchnotch check`, reject a package that breaks these:

- `notchnotch.json` at most 64 KiB; `bundle.js` at most 8 MiB.
- At most 512 files and folders and 64 MiB in total. No symbolic links.
- Icons: PNG, exactly 512×512, at most 512 KiB.
- `README.md` and `CHANGELOG.md`: UTF-8 text, at most 256 KiB each.
