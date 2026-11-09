# Extension API v1 — preview

## Create an extension

```sh
npm create notchnotch-extension@latest my-extension
cd my-extension
npm install
npm run build
```

Then open **Settings & Extensions…**, click **+** at the bottom of the sidebar and choose `my-extension/dist`. The project depends on `@notchnotch/sdk` (components and APIs), `@notchnotch/runtime` (`start`) and, for building, `@notchnotch/cli`. Nothing from this repository is needed.

An extension consists of `notchnotch.json` and `src/index.tsx`. `notchnotch build` bundles it into `bundle.js`; the app runs that bundle in JavaScriptCore. Inside this repository, `pnpm build:extensions` does the same for `extensions/*`.

```json
{
  "id": "dev.example.counter",
  "name": "My counter",
  "version": "0.1.0",
  "apiVersion": 1,
  "entry": "bundle.js",
  "permissions": []
}
```

```tsx
import { useState } from "react";
import { Activity, Button, Symbol, Text } from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

function Counter() {
  const [count, setCount] = useState(0);
  return (
    <Activity id="counter" title="Counter">
      <Activity.Compact
        leading={<Symbol name="plus.circle" />}
        trailing={<Text>{count}</Text>}
      />
      <Activity.Expanded>
        <Text size="title">{count} little steps</Text>
        <Button title="One more" onPress={() => setCount((value) => value + 1)} />
      </Activity.Expanded>
    </Activity>
  );
}
start(<Counter />);
```

See [`examples/focus-timer`](../examples/focus-timer/src/index.tsx) for a complete extension using an activity, a prompt and a settings page. Run it with `pnpm dev:examples`.

## Surfaces

- `Activity`: stable `id`, human-readable `title`, optional `phase` (`active`, `paused`, `completed`), and `initialView` (`compact` by default).
- `Prompt`: stable `id`, `title`, and `initialView` (`expanded` by default). Its phase is always `pending`. Store the answer and unmount the prompt to resolve it. Skipping is an explicit extension action.
- `Activity.Compact` / `Prompt.Compact`: `leading` and `trailing` React content. Both belong to a single host click target. Keep the content short and noninteractive.
- `Activity.Expanded` / `Prompt.Expanded`: required detailed content. A surface without compact content must request `initialView="expanded"`.
- `Activity.Peek`: optional announcement with a stable event `id`, one-line `text` (up to 256 characters), and `duration` in seconds (1–10, default 4). Requires `Activity.Compact`.

The initial view is a presentation request. The host can defer it while another surface is open. Do not use mount/unmount repeatedly to force attention.

## Temporary announcements

The host supports three presentations: compact, peek, and expanded. A peek keeps the compact wings around the camera and briefly opens a text row below them. The row slides into the notch as the shell returns to compact. Clicking opens the full activity and cancels automatic dismissal; Escape or an outside click dismisses only the announcement. Hover does not expand a peek.

```tsx
<Activity.Peek
  id={track.playbackEventID}
  text={`${track.artist} • ${track.title}`}
  duration={4}
/>
```

Place this beside `Activity.Compact` and `Activity.Expanded`. Change the id for each new playback event, including replaying the same track. Keep it stable for progress ticks and metadata updates: ordinary renders neither restart the deadline nor replay a dismissed announcement. A new event replaces an existing peek and starts a fresh deadline. Events received while a full panel or hover preview is open are consumed silently; incoming expanded prompts take priority. After dismissal, the announced activity remains selected in compact mode. Removing the Peek, surface, or extension cancels its active announcement.

Paused surfaces do not automatically claim the notch. Completion announces automatically when an activity supplies a new peek event. Use **Preview announcement** in the menu bar to replay the selected activity’s current announcement.

## Components

| Component | Props |
| --- | --- |
| `Text` | children containing text/numbers, `tone`, `size` |
| `Symbol` | SF Symbol `name`, `tone`, `size` (follows the text scale) |
| `Badge` | short text children, `tone` |
| `Progress` | `value` in `[0, 1]`, `tone` |
| `Button` | `title` and/or SF Symbol `icon`, `onPress`, `tone`, `disabled` |
| `TextField` | controlled `value`, `onChange`, `placeholder`, `disabled` |
| `Toggle` | controlled `value`, `onChange(boolean)`, optional `label`, `disabled` |
| `Picker` | `options` (`{ value, label }`, 1–32), controlled `value`, `onChange`, optional `label`; segmented in the notch, a menu in Settings |
| `Row`, `Column` | children, `spacing` (`none`/`tight`/`regular`/`loose`), `align` (`start`/`center`/`end`) |
| `Spacer`, `Divider` | — |
| `Section` | `title`, `footer`, `spacing`, children |
| `ListItem` | `title`, `subtitle`, SF Symbol `icon`, `tone`, optional `onPress`, trailing accessory children |
| `Actions` | buttons, aligned to the trailing edge; put the `accent` action last |

Tones: `primary`, `secondary`, `accent`, `success`, `warning`, `danger`. Text sizes: `caption`, `body`, `headline`, `title`, `timer`. The native host controls the actual metrics, typography, colors, window dimensions and animation through a single theme, so extensions look consistent with each other and with the system.

Guidelines:

- Use one `accent` button per view for the primary action. `danger` is for destructive actions.
- In `Settings`, top-level `Section`s become native form sections. Prefer `ListItem` + `Toggle` over pairs of on/off buttons.
- Compact content is a single click target: it cannot contain `Button`, `TextField`, `Toggle` or `Picker`.
- The host shows the extension icon, the prompt `title` and the extension name above every prompt. Do not repeat the title inside `Prompt.Expanded`.

```tsx
<Prompt id="rename" title="Name this timer">
  <Prompt.Expanded>
    <TextField value={name} onChange={setName} placeholder="Focus" />
    <Actions>
      <Button title="Skip" onPress={skip} />
      <Button title="Save" tone="accent" onPress={save} />
    </Actions>
  </Prompt.Expanded>
</Prompt>
```

React hooks, promises, `setTimeout`, `setInterval`, and `console` are available. Console output appears under **Settings & Extensions… → your extension → Console** (the last 300 lines; errors are kept longest). DOM components, CSS, global `fetch`, Node built-ins and native modules are not exposed to extension JavaScript. API v1 accepts `local-network` and `process` permissions. Local networking and native tools additionally require named manifest connections and explicit session consent. The SDK packages are published to npm with the app's version; the API is a preview and may change between minor versions.

## Storage

`storage` and `useStoredState` keep small JSON values across app restarts (256 KiB per extension). Reads are synchronous; a write that would exceed the limit returns `false` and leaves the stored data unchanged. Storage is removed with the extension.

```tsx
import { storage, useStoredState } from "@notchnotch/sdk";

const [minutes, setMinutes] = useStoredState("minutes", "25"); // like useState, but persisted
storage.set("lastRun", Date.now());
const lastRun = storage.get<number>("lastRun");
```

Do not store secrets: the file is plain JSON in the user's Application Support folder.

## Local services and third-party apps

Use `localHTTP`, `ConnectionStream` and `JSONRPCClient` to connect to a declared loopback service or JSONL command-line tool. A bundled helper can adapt another app's public integration interface. Transport support is generic; new app integrations do not need changes to the host. See [Connections](connections.md) for manifest schemas, the Zeytun decision example, lifecycle/permission rules and the bundled Music adapter.


## Music extension

The bundled Music extension declares `process` and a named `stdio` connection to its own `helpers/MusicAdapter.app/Contents/MacOS/MusicAdapter`. It uses `ConnectionStream` and `JSONRPCClient` to receive playback snapshots and send controls. `extensions/music/helper-src` owns Spotify/Apple Music discovery, Automation permission requests, Apple events, polling, errors and playback confirmation. The host has no MusicProvider, media permission or privileged media-message route.

`MusicPlayer`, `Artwork` and `Waveform` remain reusable native UI components. They render extension-supplied state and return user actions to the extension; displaying a player grants no access to an application. `NowPlayingState.player` is an opaque source identifier, with an optional `playerName` for accessibility.

```tsx
const stream = new ConnectionStream("player");
const rpc = new JSONRPCClient(stream);
// Subscribe before connecting; update React state on music/state notifications.
const snapshot = await rpc.request("music/getState");
await rpc.request("music/connect", { player: "com.spotify.client" }, 120_000);
await rpc.request("music/command", { command: "seek", value: 0.5 });
```

These `music/*` methods are the bundled extension's protocol, not host APIs. See [the Music adapter contract](../extensions/music/README.md). The old `useNowPlaying`, `controlMedia` and `media` permission have been removed from this preview. A paused surface should use `phase="paused"` so it remains in the switcher while its compact wings stay hidden. Artwork accepts bounded JPEG/PNG data (up to 64 KiB as a `data:` URL) or an HTTPS URL on a host listed in the manifest's `imageHosts`, for example `["i.ytimg.com", "*.mzstatic.com"]` (up to eight exact DNS names or `*.` subdomain wildcards; a wildcard does not match the bare domain). The app downloads remote artwork itself, so the hosts are shown in the install review and no host is allowed by default. The bundled Music extension declares its CDNs the same way. Filesystem URLs are never accepted.


## Calendar extension

The bundled Calendar extension uses the same `process`/`stdio` connection API as Music. Its `CalendarAdapter.app` owns EventKit access, calendar selection and meeting links; no calendar-specific host permission or native UI component is required. It requests full EventKit access only after **Connect Calendar** (macOS has no read-only event permission), and implements reading only. The helper bundle includes the Calendar usage descriptions; the host requests no Calendar access.

`calendar/connect`, `calendar/getState` and `calendar/select` return authorization, selected calendars and upcoming timed events. `calendar/state` notifications refresh the React UI after store changes or a 15-second poll. `calendar/open` and `calendar/join` are explicit user actions. See [the adapter contract](../extensions/calendar/README.md) for payloads and behavior.

## Idle hover selection

The resting notch remains hidden for paused extensions. On hover, the host reveals the current compact activity first, then a pending question, then the most recently used activity, then an extension-declared resumable fallback. Opening an activity or a genuine phase transition records recency; routine metadata/progress updates do not reorder it. Click and long hover open the same chosen surface. If no contextual surface exists, neutral hub icons open the activity hub instead.

An `Activity` may set `idlePreview` to opt into the resumable fallback; it must have `Activity.Compact`. This requests hover visibility only and never claims the resting notch. The music extension opts in only while it has a track, so users can resume a paused song. Its connection setup stays in the management window. Newly installed activities do not take priority merely because they are installed. Recency is local to the running host session and is cleared when a surface or extension disappears.

## Sharing an extension

`notchnotch build . --out dist --pack` (or `npm run pack` in a project from `npm create notchnotch-extension`) also writes `<id>-<version>.notchext`: a zip of the built package. Double-clicking it opens NotchNotch's install review; it can also be chosen with **+**. Share that one file, for example as a GitHub release asset.

NotchNotch unpacks `.notchext` files with its own extractor and checks every entry before writing anything: only relative paths without `..`, no symbolic links, no encryption or Zip64, at most 512 files and 64 MiB unpacked, and a matching CRC-32 for each file. A single top-level folder, as Finder's **Compress** makes, is unwrapped, and `__MACOSX` entries are skipped. If the file was downloaded, its quarantine flag is copied to every unpacked file, as Archive Utility does, so Gatekeeper still assesses native helpers: sign and notarize helpers you distribute, or tell users how to allow them.

## Installing a local extension

Build a folder containing `notchnotch.json`, `bundle.js`, and any bundled helper/assets. `notchnotch build [folder] --out <dir>` (from `@notchnotch/cli`) bundles `src/index.tsx`, copies `helpers/` and `assets/`, runs an optional `build.mjs`, and then applies the same checks as the installer; `notchnotch check <dir>` runs only the checks. In **Settings & Extensions…**, click **+** at the bottom of the sidebar and select that built folder. The manager validates it and shows a review before copying it into the user's extension library. Keep a stable manifest id for updates, and use an id distinct from the included examples. Installed ids cannot shadow included extensions. Package limits are 512 files/folders, no symbolic links, 8 MiB for `bundle.js` and 64 MiB total. Development `build.mjs` files are never executed by the installer.

This preview supports explicitly trusted local packages. Installing native code is a trust decision; transport session consent does not sandbox a helper. A public marketplace is not yet implemented. Use the manager for enable/disable, restart, connection access review and disconnect actions; setup controls use the extension’s `Settings` panel; live activity controls remain in the notch.

## Extension-owned setup in the management window

Render a single root-level `Settings` component alongside `Activity`/`Prompt` components. Its children appear under **Extensions → Your extension → Setup**, even when the extension has no notch surfaces. Buttons and fields use the same runner, React state and action registry as the activity. Settings actions never pin/open the notch. Use this panel for connection, onboarding and configuration controls.

```tsx
import { Settings, Button, Text } from "@notchnotch/sdk";

return <>
  <Settings>
    <Text>Connect your app to start receiving updates.</Text>
    <Button title="Connect" onPress={connect} />
  </Settings>
  {currentActivity ? <YourActivity state={currentActivity} /> : null}
</>;
```

Settings supports every component except the media components (`MusicPlayer`, `Artwork`, `Waveform`). The host renders native window controls using system colors. Settings and notch nodes share the 512-node/16-depth snapshot budget and must have unique node ids. Omit Settings to clear the panel. Disabling, removing or crashing an extension clears its setup UI and action handlers; restarting reconstructs it. Local React state lasts for the runner session. Media and artwork components belong to the notch activity. Closing the management window leaves the runner and its connections alive.

### Library identity

A manifest can include `icon` (an SF Symbol name, at most 128 characters) and `description` (at most 512 characters). These appear in the management sidebar, overview, extension page and install review. Omit them to use the generic extension identity. `name` must contain 1–128 characters, and `version` 1–64. The extension enable switch controls whether its runner is allowed to run; it does not imply that a local app has connected. Keep connection state and recovery controls in `Settings`.
