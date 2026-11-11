# 0002 — System capabilities in the host, starting with Calendar

Status: accepted and built for 0.9.0. Where the build differs from the proposal, [As built](#as-built) says so.

## Problem

Some extensions need data that only native code can reach: calendars, reminders, contacts, battery levels. Today the only way to get it is a native helper over a `stdio` connection (see [native helpers](../../extensions/native-helpers.md)). Music and Calendar both work this way.

The Store doesn't accept helpers yet. Its checks reject `helpers/` and `build.mjs`. There are two reasons:

- **Review.** A compiled helper runs with the person's account and NotchNotch doesn't sandbox it. Reviewers can read JavaScript, but they can't check that a binary matches its source.
- **Signing.** Helpers are signed ad hoc. macOS keys privacy grants to the signature, so it asks again after every update. A helper downloaded with quarantine may also be stopped by Gatekeeper.

So Music and Calendar can only ship inside `NotchNotch.app`. Every extension that needs a calendar or contacts can't be in the Store at all.

## Decision

The host offers a small set of **system capabilities**. These are read-mostly APIs for common protected data, which the app implements itself. Each one is a manifest permission, and an extension uses it like a connection. Calendar comes first. Its helper becomes app code, and the extension becomes plain JavaScript that the Store can review and ship.

Helpers stay for everything else. Building them from source in CI and signing them with a stable identity is separate, later work ([Helpers in the Store](#later-helpers-in-the-store)).

This amends [architecture.md](../architecture.md), which says the host has no privileged, app-specific transport. A capability is privileged on purpose. The rules below keep each one small, gated per extension, and tied to one permission.

### Rules for a capability

1. **One permission each**, such as `calendar`. Install review and the Store page name it in plain words ("Reads your calendars").
2. **The host is the gate.** macOS grants Calendars to NotchNotch as a whole, so the app alone decides which extension sees the data. Extensions without the permission get an error, even if NotchNotch has access.
3. **Explicit first use.** The first request in a session asks through the same consent sheet as connections (Allow Once / Always Allow / Don't Allow). The grant is remembered per extension and capability, and **Forget** under Access clears it.
4. **Minimum data.** The API returns only what a notch needs, with fixed bounds. No notes, attendees or write methods unless a later decision adds them.
5. **Same stream shape.** A capability is a JSON-RPC stream that the host serves instead of a helper. Extension code keeps `JSONRPCClient`, and moving from a helper to a capability is mostly a one-line change.
6. **In the app process, on its own actor.** EventKit and similar frameworks are safe to call in process. A dedicated actor with deadlines keeps a slow query off the main thread, as `MusicProvider` does today.

## Calendar

### Manifest

```json
{ "permissions": ["calendar"] }
```

`calendar` joins `local-network` and `process` in `schemas/manifest.schema.json`. `maxItems` goes from 2 to the length of the enum. No `connections` entry is needed. Older apps reject the unknown permission, so the Store entry sets `minimumAppVersion` to the first release with capabilities.

### SDK

```ts
import { capability, JSONRPCClient } from "@notchnotch/sdk";
const rpc = new JSONRPCClient(capability("calendar"));
```

`capability(name)` returns a `ConnectionStream` whose messages the runner sends with a new `ConnectionOperation`, `capability`, instead of `request`/`open`. The host routes these in `RunnerConnection.handleConnection` before the broker, the same way it already handles `secret*` and `openURL`.

### Methods

They keep the [Calendar adapter protocol](../../../extensions/calendar/ADAPTER.md), minus what the SDK already does:

| Method | Change |
| --- | --- |
| `calendar/getState` | Unchanged. Never prompts. |
| `calendar/connect` | Asks NotchNotch's consent first, then macOS if access is undetermined. |
| `calendar/select` | Unchanged. The selection is stored by the host per extension, not in the helper's `dev.notchnotch.calendar.adapter` defaults. |
| `calendar/state` (notification) | Unchanged. |
| `calendar/join` | Removed. The extension calls `open(event.meetingURL)`, which already requires a recent click. The host keeps the HTTPS meeting-link check when it builds `meetingURL`. |
| `calendar/open` | Removed. The extension calls `open("ical://")`. Check that Calendar.app handles that scheme; if it doesn't, keep the method. |

The bounds don't change: seven days, at most eight events, no all-day, cancelled, declined or finished events, and text limits from `CalendarPolicy`.

### Code moves

| From | To |
| --- | --- |
| `extensions/calendar/helper-core/` (`CalendarEvent`, `CalendarPolicy`) | `native/NotchCapabilities/Sources/Calendar/` (new library target) |
| `extensions/calendar/helper-src/CalendarSource.swift` | Same library. One `CalendarSource` shared by all extensions; each stream filters by that extension's selection. |
| `extensions/calendar/helper-src/main.swift` | Deleted. The JSON-RPC dispatch becomes `CalendarCapability.handle(_:)`. |
| `extensions/calendar/helper-tests/` | `native/NotchCapabilities/Tests/` |
| `CalendarAdapter` target in `Package.swift`, `build.mjs`, `helper.entitlements` | Deleted. |
| `NSCalendars*UsageDescription` in `scripts/package-app.mjs` | Kept. The app now asks for itself. |

Under Access, `ManagementAccessView` and `PermissionSummary` list the capability. Grants reuse `ConnectionGrantStore` with the connection id `capability:calendar`, so **Forget** and uninstall already clear them.

### Store and migration

1. With no helper, Calendar passes the Store checks. It moves to `NotchNotch/notchnotch-extensions` as `sadeqi-ah/calendar`, keeping the id `dev.notchnotch.calendar`, and leaves `extensions/` in this repo. The app then bundles only Music.
2. On first launch of that release, if `installedIncludedIDs` contained `dev.notchnotch.calendar`, the app installs Calendar from the Store without a review sheet. It's the same publisher and asks for no more than the person already allowed. If the Store is unreachable, it tries again with the next Store update check. Until then the extension's page says it's being reinstalled.
3. The host copies `selectedCalendarIDs` from the helper's `dev.notchnotch.calendar.adapter` defaults into the extension's capability preferences once, then deletes that domain.
4. macOS's Calendars grant was already NotchNotch's, because the old helper ran inside the app bundle. Nobody sees a new macOS prompt.

### Tests

- Capability routing: an extension without `calendar` gets an error. One with it gets status. A denied consent never reaches EventKit.
- A fake `CalendarSource` behind a protocol, so runner integration tests (connect, select, imminent, ongoing and ended events, revocation, disconnect) run without Calendar access, as the helper tests do today.
- Migration: selection copy, auto-install, and an offline first launch.
- CLI: `checkPackage` and `lint` accept `calendar`. The schema test keeps Swift and TypeScript in step.

## Next capabilities

Each one needs its own short decision before it's added. These are likely, in order:

| Capability | Framework | Note |
| --- | --- | --- |
| `reminders` | EventKit | Same store as Calendar. Read the next due items; completing one would be the first write. |
| `contacts` | Contacts | Birthdays and names only, never the whole card. |
| `system-stats` | `host_statistics`, IOKit | CPU, memory, battery. No macOS prompt; the permission is for transparency. |
| `bluetooth-batteries` | IOBluetooth | Battery levels of connected devices. |

Not planned: generic Apple events or Accessibility. They give an extension control of other apps, which is what a reviewed helper is for.

## Later: helpers in the Store

For the long tail (one app's Apple events, a device SDK), Store CI builds `helpers/` from reviewed source and signs every helper with a Store signing identity. That can be self-signed, like `scripts/create-signing-identity.sh`, so macOS grants survive updates. The app checks that each helper in a downloaded package carries that signature. Packages that NotchNotch downloads aren't quarantined, but this must be confirmed on a clean Mac before relying on it.

## Open questions

- The permission name: `calendar` or `calendars`? macOS says "Calendars".
- Should the first `calendar/connect` show NotchNotch's consent sheet and then macOS's prompt back to back, or should installing with the permission count as consent? Recommendation: keep the sheet, because it names the extension and macOS's prompt doesn't.
- Should the Music helper become a `now-playing` capability too? It uses Apple events to Spotify and Music, so it fits the "not generic Apple events" rule only as a fixed, named pair of apps.

## As built

- **Names.** The permissions are `calendar` and `now-playing`.
- **Consent.** The first open of a capability stream shows NotchNotch's consent sheet, worded for the data instead of a program. macOS's own prompt follows only when macOS hasn't been asked yet.
- **Calendar methods.** `calendar/open` and `calendar/join` stay. The host already checked the meeting link when it built `meetingURL` and checks again before opening it, so going through `open()` would add nothing. It would also have needed the unverified `ical://` scheme.
- **Music.** It became the `now-playing` capability, with the methods of its helper. It answers the open question above: a fixed pair of named players, with fixed commands and no script method.
- **Stream wiring.** No new `ConnectionOperation` was needed. `capability(name)` is a `ConnectionStream` whose id is `capability:<name>`, and `ConnectionBroker` sends those to a `CapabilityProvider` instead of a transport.
- **Code.** The library is `native/NotchCapabilities` (Calendar and Now Playing). Both helper targets, their build modules and entitlements are gone; the app's entitlements cover both capabilities.
- **Selection storage.** It's kept per extension under `calendarSelections` in the app's defaults. The helper's `dev.notchnotch.calendar.adapter` domain is copied over and deleted the first time it's read.
- **Migration.** `AppModel.movedToStore` maps `dev.notchnotch.calendar` to `sadeqi-ah/calendar`. On the first launch of 0.9, Calendar counts as installed if it was used before: saved storage, an "Always Allow" grant, or a calendar selection. It's then installed from the Store 3 seconds after launch and with every Store check until that works.
- **Store.** The catalog sets each entry's `minimumAppVersion` from its permissions (`minimumAppVersionFor` in the extensions repository), so a capability raises it to 0.9.0.
- **Order of release.** The SDK, runtime and CLI 0.9.0 go to npm first, because the Store's Calendar needs `capability()`. Then the Calendar pull request is merged and the catalog published, and only then is the app released. Released any earlier, people who had Calendar would wait without it until the Store has it.
