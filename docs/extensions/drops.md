# Drops

People drag files, links and text to the top of the screen. When a drag comes near the notch, it opens to the **drop zones** of the extensions that take what's being dragged. Letting go on yours hands you the items.

```tsx
import { Activity, DropTypes, DropZone, FileGrid, useStoredState, type DropItem } from "@notchnotch/sdk";

function Inbox() {
  const [items, setItems] = useStoredState<DropItem[]>("items", []);
  return <>
    <DropZone id="keep" title="Inbox" icon="tray.and.arrow.down.fill" accepts={[DropTypes.anything]} multiple
      opens="inbox" onDrop={(dropped) => setItems((before) => [...before, ...dropped])} />
    <Activity id="inbox" title="Inbox" phase="paused">
      <Activity.Expanded>
        <FileGrid files={items.flatMap((item) => item.kind === "file" ? [item.file] : [])} />
      </Activity.Expanded>
    </Activity>
  </>;
}
```

Requires NotchNotch 0.14 or later. Older versions leave out `DropZone`, `FileItem` and `FileGrid` and draw the rest.

## Drop zones

`DropZone` sits beside your `Activity` and `Settings`, at the top of what you render. You can have up to two, and they can come and go with your state, such as a "Send to iPhone" zone only while the phone is reachable.

| Prop | |
| --- | --- |
| `id` | stays the same while the zone exists |
| `title` | what happens, up to 64 characters: "Shelf", "AirDrop", "Compress". While hovered, the notch adds the count: "Shelf · 3 files" |
| `icon` | an SF Symbol |
| `accepts` | 1–16 uniform type identifiers. The zone shows only when **every** dragged item conforms to one of them. `DropTypes` has the common ones |
| `multiple` | `true` to take more than one item at once; without it, the zone hides when several are dragged |
| `opens` | the `id` of one of your activities. The notch opens it right after the drop and keeps it open until the person closes it, so they can act on what they dropped |
| `onDrop` | gets the items, `DropItem[]` |

The notch draws zones from your last render, while the pointer is still moving: your code doesn't run during a drag. Up to four zones show at once, in the order the person chose for Home; with more, the last becomes **More**, and resting on it shows them all.

`DropTypes`: `anything` (`public.item`), `files`, `folders`, `images`, `movies`, `audio`, `pdf`, `links`, `text`. Any UTI works.

## What arrives

```ts
type DropItem =
  | { kind: "file"; file: FileHandle }
  | { kind: "url"; url: string; title?: string }
  | { kind: "text"; text: string };

interface FileHandle { id: string; name: string; type: string; size: number; kind: "file" | "folder" }
```

- **Files and folders** arrive as handles, never paths. `type` is the file's UTI, `size` is in bytes, and a folder is one handle. A `file://` link arrives as a file.
- **Links** from a browser arrive as `url`, with the page's title when the browser gives one. A zone gets them only if it accepts `public.url`.
- **Text** arrives as `text`, up to 64 KiB. A zone gets it only if it accepts `public.plain-text`.

All the items from one drop arrive in one `onDrop`; if they're too many for one message, the last ones are left out.

A handle is yours alone and lasts across restarts, so keep it with [`useStoredState`](storage.md). The app keeps a bookmark for each, which follows the file when it's moved or renamed. When you no longer need one, call `files.release`; uninstalling your extension releases all of them.

## Showing files

[`FileItem`](components.md#files) shows one handle and [`FileGrid`](components.md#files) shows many, with the file's real thumbnail as Finder shows it. Both drag back out to Finder or any app. `FileGrid` can select like Finder, so your buttons can act on the selection:

```tsx
const [selected, setSelected] = useState<string[]>([]);
const chosen = files.filter((file) => selected.includes(file.id));

<FileGrid files={files} selected={selected} onSelect={setSelected}
  onRemove={(gone) => forget(gone)} onDragOut={(gone) => forget(gone)} />
<Actions>
  <Button title="Share" icon="square.and.arrow.up" tone="accent" onPress={() => files.share(chosen)} />
</Actions>
```

## The `files` API

The app does these with your handles. Each takes a handle, its `id`, or a list of them.

| Call | Does |
| --- | --- |
| `files.share(files)` | macOS's Share menu beside the pointer: AirDrop, Messages, Mail, Notes and more |
| `files.airDrop(files)` | The AirDrop sheet |
| `files.open(files, app?)` | Opens them with their default app, or the app with this bundle identifier |
| `files.openWith(files)` | A menu beside the pointer of the apps that open them; the person picks one |
| `files.reveal(files)` | Selects them in Finder |
| `files.preview(files)` | Quick Look |
| `files.copyToClipboard(files)` | Puts them on the clipboard, as Finder's Copy does |
| `files.copy(files)` / `files.move(files)` | Into a folder the person picks; `false` if they cancel. A moved file keeps its handle |
| `files.thumbnail(file, size?)` | The file's thumbnail as a PNG data URL for `Artwork` |
| `files.keepCopy(files)` | Copies them into NotchNotch's own folder and returns handles to the copies; the originals' handles are released. A copy survives the original being moved or deleted, and is deleted when you release it |
| `files.release(files)` | Lets go of handles you no longer keep |

And for text:

| Call | Does |
| --- | --- |
| `clipboard.copy(text)` | Copies text, up to 64 KiB |

Calls that show something or change files need a click or key press in your extension, like [`open`](concepts.md#opening-links): call them from an `onPress`. `thumbnail`, `keepCopy` and `release` don't.

## Reading files

Without a permission, you learn a file's name, type and size, and nothing else. To read contents, list `file-read` in `permissions`:

```json
{ "permissions": ["file-read"] }
```

The install review says "The files you drop on it: their contents, and saving results where you choose".

| Call | Does |
| --- | --- |
| `files.read(file, { as, offset, limit })` | Up to 144 KiB of the file from `offset`, as `"text"` (UTF-8, the default) or `"base64"`. Read a larger file in parts by moving `offset`. Folders can't be read |
| `files.save(name, base64)` | Saves up to 144 KiB as `name` in a folder the person picks, and returns a handle to the new file, or `undefined` if they cancel |

Every message between your extension and the app is at most 256 KiB, which sets the 144 KiB per call.

The Store installs an extension that uses `file-read` only on NotchNotch 0.14 or later.
