# Native helpers

Some apps can only be reached from native code: through Apple events, a framework such as EventKit, or a command-line tool. A **helper** is a program your extension runs and talks to over a `stdio` [connection](connections.md).

For calendars and what's playing in Spotify or Apple Music, use a [capability](capabilities.md) instead: NotchNotch reads the data itself, so there's no program to build or sign, and the extension can be in the Store. The Store doesn't accept helpers yet.

The other app doesn't have to be yours, but it needs some interface a helper can use: a documented CLI, a local API, Apple events or a system framework. A helper can't reach into an app's private state.

## Declare it

```json
{
  "permissions": ["process"],
  "connections": {
    "adapter": { "transport": "stdio", "executable": "./helpers/my-adapter", "arguments": [] }
  }
}
```

`executable` is one of:

- `./helpers/…`: a file inside your package, with no `..`. It must stay inside the package even after resolving links.
- A tool name such as `"jq"`, looked up in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin` and `~/.local/bin`.
- An absolute path.

`arguments` are fixed in the manifest; extension JavaScript can't change them, and no shell is involved. The consent dialog shows the exact program and arguments.

## The protocol

- Write exactly one JSON value per line to stdout (JSONL). Write diagnostics to stderr: when the helper exits with an error, the last 2 KiB of it are part of the stream's `closed` error.
- Messages are limited to 64 KiB.
- When stdin closes, exit. NotchNotch closes it when the connection or extension stops, then ends your process. Clean up any processes you start yourself.
- `JSONRPCClient` in the SDK speaks JSON-RPC 2.0 over this, in both directions.

Helpers get a small environment: `HOME`, a fixed `PATH` and `LANG`. A bundled helper starts in the package folder; an installed tool starts in the home folder. Shell variables such as API keys aren't passed on.

## Build a helper

`notchnotch build` copies your `helpers/` folder into the package. To compile a helper first, add a `build.mjs` next to the manifest:

```js
// build.mjs — runs on your machine during `notchnotch build`, never in NotchNotch.
import { helperApp } from "@notchnotch/cli/native";

export async function build({ source, destination }) {
  // Compile your helper first: swift build, cargo build, go build…
  await helperApp({
    destination,
    name: "ContactsAdapter",
    binary: `${source}/.build/release/ContactsAdapter`,
    bundleIdentifier: "dev.jane.birthdays.adapter",
    displayName: "Birthdays",
    usageDescriptions: { NSContactsUsageDescription: "Show upcoming birthdays in the notch." },
  });
  // In the manifest: "executable": "./helpers/ContactsAdapter.app/Contents/MacOS/ContactsAdapter"
}
```

Mark script helpers executable and give them a shebang line. The installer never runs `build.mjs`.

## Privacy access

macOS asks for access to Contacts, Calendars, Automation and other protected data **on behalf of the helper**, not NotchNotch. The prompt shows your helper's name, the grant appears separately in **System Settings › Privacy & Security**, and neither NotchNotch nor another extension can use it.

To use a protected resource:

- Ship the helper as an app bundle whose `Info.plist` has the matching usage description, such as `NSContactsUsageDescription`. Without it, macOS denies the request. `helperApp` builds that bundle.
- Give each helper its own `bundleIdentifier`, under a domain you own. macOS keys grants to the identifier and the code signature.
- Sign it with a stable identity. Helpers are signed ad hoc unless `NOTCHNOTCH_SIGN_IDENTITY` names an identity, and macOS asks again after every ad hoc rebuild. With a real identity, pass `entitlements` for the hardened runtime, such as `com.apple.security.personal-information.addressbook`.

## Trust

A helper is an ordinary program running with the person's account. It can read their files and use the network; NotchNotch doesn't sandbox it. The `process` permission and the consent dialog say so. Keep helpers small, do one job, and explain in your README what yours does.

If you share a `.notchext` with a helper, sign and notarize the helper, or Gatekeeper may block it on other Macs.
