# Concepts

An extension is a React component tree. Instead of HTML, it renders **surfaces** that NotchNotch draws natively in the notch, and an optional **settings** page in Settings & Extensions. Your code runs in its own process; the app owns layout, typography, color and animation, so every extension looks at home.

## Activities

An activity is something ongoing: a timer, a song, a build, your next meeting.

```tsx
<Activity id="session" title="Focus" phase="active">
  <Activity.Compact leading={<Symbol name="timer" />} trailing={<Text size="caption">24:12</Text>} />
  <Activity.Expanded>
    <Text size="timer">24:12</Text>
  </Activity.Expanded>
</Activity>
```

- `id` stays the same for the life of the activity. `title` is a short human-readable name.
- `Activity.Compact` sits on either side of the camera. Keep it short; it is a single click target, so it can't contain buttons, fields, toggles or pickers.
- `Activity.Expanded` opens on hover or click. It must fit without scrolling: **the notch never scrolls**.
- `phase` is `active`, `paused` or `completed`. An active activity is **live**: it can sit beside the camera. A paused one gives up that place and waits in Home.
- `initialView` is `compact` (the default) or `expanded`. It's a request; the app may wait while something else is open. An activity without compact content must ask for `expanded`.

The wings show one live activity: the one opened last, else the first in the user's Home order, else the one that started most recently. Up to three more live activities join the wings as small circles at their outer edges, in your extension's color with its progress ring; more than that shows a `+N` count. They appear once an announcement has finished. Every activity is in **Home**.

## Home

Home is a grid of every activity, four columns wide. Live activities come first as wide tiles, then the rest. A click on a tile opens the activity; the grid button beside the gear returns to Home. Home never scrolls: it grows to three rows, then widens up to six columns.

People can change Home: right-click a tile to make it small or wide, pin it to the top, or hide it, and reorder or bring back hidden activities under Settings & Extensions → Notch. A size the person chose replaces your tile's `size`. Hiding only affects Home; a live activity still shows in the wings.

Without a tile of its own, an activity's tile shows its compact content and its title. Give it a better one with `Activity.Tile`:

```tsx
<Activity.Tile size="wide">
  <Ring value={0.62}><Symbol name="timer" /></Ring>
  <Text>18 min left</Text>
</Activity.Tile>
```

- `size` is `small` (one column, the default) or `wide` (two). The person can change it.
- A tile holds readings: `Value`, `Ring`, `Symbol`, `Text`, `Artwork`, `Progress`, in rows and columns. No buttons, fields, toggles or pickers: the whole tile opens the activity.
- The app sizes the tile and uses one type size in every tile. Text is one line; a small tile whose content doesn't fit becomes wide, and what still doesn't fit ends with an ellipsis.
- A tile with its own content doesn't get the title underneath; say what it is.

Requires NotchNotch 0.13 or later. Older versions ignore `Activity.Tile`.

## Prompts

A prompt asks the person a question and waits for an answer.

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

- A prompt opens expanded by default and always shows your extension's icon, its `title` and your extension's name above the content. Don't repeat the title inside.
- To resolve it, store the answer and stop rendering the prompt. Skipping is an action you offer, too.
- Closing the notch doesn't answer a prompt. It stays pending, with a badge, until the person answers.
- Don't mount and unmount a prompt to get attention again.

## Announcements

`Activity.Peek` briefly opens a line of text below the camera, for a moment worth noticing: a new song, a finished timer.

```tsx
<Activity.Peek id={track.playbackEventID} text={`${track.artist} • ${track.title}`} duration={4} />
```

- Put it beside `Activity.Compact` and `Activity.Expanded`; it needs the compact part.
- Change `id` for each new event, and keep it the same for routine updates such as progress. Re-rendering never replays an announcement.
- `text` is one line of up to 256 characters. `duration` is 1–10 seconds (default 4).
- Clicking the announcement opens the activity; Escape or a click elsewhere dismisses only the announcement. An announcement that arrives while the notch is open is skipped.

To see an announcement again while you work on it, choose **Preview announcement** in the menu bar.

## Settings

For plain settings such as a token, a city or a unit, declare [preferences](preferences.md) in the manifest instead: NotchNotch draws them for you. For anything richer, render a single `Settings` component at the root, next to your surfaces. Its content appears under **Settings & Extensions… › your extension › Setup**, even when nothing is in the notch. Use it for connecting apps, onboarding and preferences.

```tsx
start(<>
  <Settings>
    <Section title="Session" footer="Changes apply to the next session.">
      <Picker label="Focus length" options={durations} value={minutes} onChange={setMinutes} />
    </Section>
  </Settings>
  {running ? <TimerActivity /> : null}
</>);
```

- Top-level `Section`s become native form sections.
- Buttons in settings never open the notch.
- Settings support every component except the media components.

## Opening links

`open` shows a web page in the browser, or opens an app link such as `mailto:` or a meeting link in its app.

```tsx
import { Button, open } from "@notchnotch/sdk";

<Button title="Join Meeting" tone="accent" onPress={() => { void open(meeting.url); }} />
```

- It works only right after a click or key press in your extension: once per interaction, within five seconds, like a browser's pop-up rule. Opening something on its own fails.
- Web addresses must be `http` or `https` with a host. App links need an installed app that handles them. `file:`, `data:`, `javascript:` and `x-apple…` links are refused.

Requires NotchNotch 0.5 or later.

## When the notch is idle

When nothing is live, hovering over the notch shows the most useful thing to resume: a pending prompt first, then the activity used most recently. An activity can offer itself as a fallback with `idlePreview`; it must have compact content. Music uses this to let people resume a paused song. With nothing to resume, it shows Home.

## What extension code can do

Extensions run in JavaScriptCore, not in a browser or Node.js, in a process that macOS sandboxes: it can't read files, use the network or start programs on its own. Everything below goes through the app.

- Available: React and hooks, promises, `setTimeout`, `setInterval`, `console`, [storage and secrets](storage.md), [`fetch`](network.md) to hosts you declare, [`open`](#opening-links) for links, and [connections](connections.md) to local apps and tools.
- Not available: the DOM, CSS, the browser's global `fetch`, Node built-ins and native modules.

## Limits

NotchNotch stops an extension that uses more than 400 MB of memory, keeps the processor busy for 30 seconds, or sends more than 30 updates a second for long. Its page then says which limit it hit. Render when something changes, not on a fast timer, and keep large data out of React state.

## Design guidelines

- One `accent` button per view, for the main action, placed last. Use `danger` only for destructive actions.
- Keep compact content to a symbol and a few characters.
- In settings, prefer a `ListItem` with a `Toggle` over a pair of on and off buttons.
- Write titles in title case and messages in plain sentences.
- Give icon-only buttons and meaningful symbols a `label`, and never show state by color alone. See [Accessibility](components.md#accessibility).
