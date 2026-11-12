# Capabilities

Some data on a Mac is behind a privacy prompt and can only be read from native code. For the most common kinds, NotchNotch reads it for you, so your extension needs no [native helper](native-helpers.md) and can be in the Store.

| Capability | What it gives you | macOS asks for |
| --- | --- | --- |
| `calendar` | The next week's events from the calendars the person chooses | Calendars (full access, read-only use) |
| `now-playing` | The song playing in Spotify or Apple Music, and playback controls | Automation, once per player |
| `battery` | Charge, charging and power state | Nothing |
| `system` | CPU, memory, disk and network activity, thermal state | Nothing |

Capabilities need NotchNotch 0.9 or later; `battery` and `system` need 0.11. The Store marks extensions that use one, and older versions don't install them.

## Use one

List it in `permissions`:

```json
{ "permissions": ["calendar"] }
```

Then open its stream and talk to it with JSON-RPC:

```tsx
import { capability, JSONRPCClient } from "@notchnotch/sdk";

const rpc = new JSONRPCClient(capability("calendar"));
rpc.onNotification(({ method, params }) => {
  if (method === "calendar/state") show(params);
});
const status = await rpc.request("calendar/getState");
```

For `calendar` and `now-playing`, the first `open` (or the first `request`, which opens the stream) asks the person, the same way a [connection](connections.md) does: **Allow Once**, **Always Allow** or **Don't Allow**. Pass `{ interactive: false }` to `rpc.connect` to reconnect silently at launch after **Always Allow**. The install review and the Store page list each capability you ask for, and **Forget** under Access clears the grant.

macOS asks NotchNotch, not your extension, for the underlying access. It asks once, the first time any extension needs it. NotchNotch still gives the data only to extensions that list the capability and that the person allowed.

Every message is JSON-RPC 2.0 and at most 64 KiB. Unknown methods answer `-32601`, bad parameters `-32602`.

## `calendar`

| Method | Parameters | Result |
| --- | --- | --- |
| `calendar/getState` | None | Status. Never prompts. |
| `calendar/connect` | None | Asks macOS for access if it hasn't been asked yet, then returns status |
| `calendar/select` | `{ "ids": ["calendar-id"] }` | Saves which calendars to show and returns status. `[]` shows none. |
| `calendar/open` | None | Opens the Calendar app; returns `null` |
| `calendar/join` | `{ "id": "event-id" }` | Opens the event's meeting link; returns `null` |
| `calendar/state` | Status, as a notification | Sent when anything changes |

Status has `authorization` (`notDetermined`, `authorized`, `denied`, `restricted` or `writeOnly`), `calendars` (`id`, `title`, `selected`), `events` and an optional `error`.

Events have `id`, `title`, `calendarID`, `calendarTitle`, `start` and `end` (Unix seconds), and optional `location` and `meetingURL`. The list holds at most eight events from the next seven days. Ongoing events come first, then upcoming ones by start time. All-day, cancelled, declined and finished events are left out. A recurring event's occurrences have different ids.

Notes and attendees are never sent, and there are no methods that change events. `meetingURL` is an HTTPS link to Zoom, Google Meet, Teams or Webex, found in the event's URL, location or notes. `calendar/join` checks that the event still has it before opening it.

Each extension has its own calendar selection. It holds identifiers only, and it's deleted when the extension is uninstalled. People add accounts in the Calendar app, so there's no separate sign-in.

## `now-playing`

| Method | Parameters | Result |
| --- | --- | --- |
| `music/getState` | None | Status |
| `music/connect` | `{ "player": "com.spotify.client" \| "com.apple.Music" }` | Asks macOS for Automation access to that player, then returns status |
| `music/command` | `{ "command", "value"? }` | `null` once queued; failures show up in status |
| `music/state` | Status, as a notification | Sent when anything changes |

Status has an optional `state` (a `NowPlayingState`), `authorized` (player ids with Automation access), `errors` (by player id) and an optional `commandError`. Each notification is a complete status.

Commands are `playPause`, `previous`, `next`, `seek`, `volume`, `shuffle`, `repeat` and `openPlayer`. `seek` and `volume` take a `value` from 0 to 1; the others take none. There's no way to run a script.

NotchNotch reads only players that are already running, never opens one to look, and reads them only after `music/connect` was allowed. `state.artwork` is a Spotify CDN address or a small inline JPEG from Apple Music. To show it, list `i.scdn.co`, `mosaic.scdn.co` and `*.mzstatic.com` in your manifest's `imageHosts`. Pass `state` to the `MusicPlayer` component to get the same player as the Music extension.

## `battery`

Readings only, so NotchNotch doesn't ask. The install review lists it under "See your Mac's status".

| Method | Parameters | Result |
| --- | --- | --- |
| `battery/getState` | None | Status |
| `battery/state` | Status, as a notification | Sent when macOS reports a change, not on a timer |

Status has `present` (false on a Mac without a battery), `level` from 0 to 1, `charging`, `pluggedIn`, `charged`, `lowPowerMode`, and `minutesToEmpty` or `minutesToFull` once macOS has an estimate.

```tsx
const rpc = new JSONRPCClient(capability("battery"));
const battery = await rpc.request("battery/getState");
<Ring value={battery.level} label="Battery"><Symbol name="bolt.fill" /></Ring>
```

## `system`

Readings only, so NotchNotch doesn't ask. It samples every two seconds while your stream is open, and stops when it closes.

| Method | Parameters | Result |
| --- | --- | --- |
| `system/getState` | None | The latest status |
| `system/state` | Status, as a notification | Every two seconds |

Status has `cpu` (busy share of all cores, 0 to 1), `memory` and `disk` (`used` and `total` in bytes; memory as Activity Monitor's "Memory Used", disk for the startup disk), `network` (`received` and `sent` in bytes per second, every interface but loopback), `thermal` (`nominal`, `fair`, `serious` or `critical`) and `uptime` in seconds. `cpu` and `network` are missing until two samples exist, about two seconds after opening.
