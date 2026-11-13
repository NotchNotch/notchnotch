import { createElement, type ReactNode } from "react";
import type { Alignment, FileHandle, MediaRequest, NowPlayingState, PickerOption, Spacing, TextSize, Tone } from "@notchnotch/protocol";
import type { DropItem } from "./files";
export type { Alignment, PickerOption, Spacing, TextSize, Tone } from "@notchnotch/protocol";
export * from "./connections";
export * from "./storage";
export * from "./preferences";
export * from "./files";

type Children = { children?: ReactNode };
/** Extension-owned setup UI displayed in the management window, outside the notch. */
export function Settings({ children }: Children) { return createElement("settings", null, children); }
type SurfaceProps = Children & {
  id: string;
  title: string;
  initialView?: "compact" | "expanded";
};
function Compact({ leading, trailing }: { leading: ReactNode; trailing: ReactNode }) {
  return createElement("compact", null,
    createElement("leading", null, leading), createElement("trailing", null, trailing));
}
function Expanded({ children }: Children) { return createElement("expanded", null, children); }

/** Show a short announcement, then return to Compact. A new id starts a new event. */
function Peek({ id, text, duration = 4 }: { id: string; text: string; duration?: number }) {
  return createElement("peek", { id, text, duration });
}

/**
 * The activity's tile in Home: readings such as a `Ring`, a `Value` or a line
 * of `Text`, no buttons. The whole tile opens the activity. `small` fills one
 * of Home's four columns, `wide` two; the user can change it. Without a Tile,
 * Home builds one from Compact and the title.
 */
function Tile({ size = "small", children }: Children & { size?: "small" | "wide" }) {
  return createElement("tile", { size }, children);
}

/**
 * The entire compact surface is one host-owned click target. An `active`
 * activity is live: it can take the wings. A `paused` one waits in Home.
 */
export const Activity = Object.assign(
  function Activity({ initialView = "compact", phase = "active", ...props }: SurfaceProps & {
    phase?: "active" | "paused" | "completed";
    /** Eligible as a hover fallback even before this activity has been used. */
    idlePreview?: boolean;
  }) { return createElement("activity", { ...props, initialView, phase }); },
  { Compact, Expanded, Peek, Tile },
);

/** Unmount a prompt after recording its answer; collapsing it does not answer it. */
export const Prompt = Object.assign(
  function Prompt({ initialView = "expanded", ...props }: SurfaceProps) {
    return createElement("prompt", { ...props, initialView, phase: "pending" });
  },
  { Compact, Expanded },
);
type Stack = Children & {
  /** Gap between children. Defaults to `regular` (columns) or `loose` (rows in the notch). */
  spacing?: Spacing;
  /** Cross-axis alignment: leading/center/trailing for columns, top/center/bottom for rows. */
  align?: Alignment;
};
/** Vertical stack. */
export function Column({ children, spacing, align }: Stack) { return createElement("column", { spacing, align }, children); }
/** Horizontal stack. Add a `Spacer` to push items apart. */
export function Row({ children, spacing, align }: Stack) { return createElement("row", { spacing, align }, children); }
/** Flexible empty space inside a `Row` or `Column`. */
export function Spacer() { return createElement("spacer", null); }
/** Trailing-aligned row of buttons, e.g. a prompt's answers. Put the primary (`accent`) action last. */
export function Actions({ children }: Children) {
  return createElement("row", { spacing: "regular" }, createElement(Spacer), children);
}
/** Thin separator line. */
export function Divider() { return createElement("divider", null); }

export function Text({ children, tone = "primary", size = "body" }: Children & { tone?: Tone; size?: TextSize }) {
  return createElement("text", { tone, size }, children);
}
/**
 * SF Symbol. `size` follows the text scale so icons line up with adjacent text.
 * Symbols are decorative and VoiceOver skips them; give one a `label` when it
 * carries meaning no text beside it does, such as a status.
 */
export function Symbol({ name, tone = "primary", size = "body", label }: { name: string; tone?: Tone; size?: TextSize; label?: string }) {
  return createElement("symbol", { name, tone, size, label });
}
/** Short status label, e.g. a count or "Live". */
export function Badge({ children, tone = "secondary" }: Children & { tone?: Tone }) {
  return createElement("badge", { tone }, children);
}
/** `label` says what is progressing, such as "Focus session"; VoiceOver reads it with the percentage. */
export function Progress({ value, tone = "accent", label }: { value: number; tone?: Tone; label?: string }) {
  return createElement("progress", { value, tone, label });
}

/**
 * A reading: a big number with a small unit beside it, such as 45 min or
 * 82 mmhg. It takes the extension's accent, and its digits roll when it changes.
 */
export function Value({ children, unit, tone = "accent", size = "timer" }: Children & { unit?: string; tone?: Tone; size?: TextSize }) {
  return createElement("value", { unit, tone, size }, children);
}
/**
 * Circular progress, filled with the extension's accent. Children, such as a
 * Symbol or a short Text, sit inside it. `size` follows the text scale.
 * `label` says what is progressing; VoiceOver reads it with the percentage.
 */
export function Ring({ value, tone = "accent", size = "headline", label, children }: Children & {
  value: number; tone?: Tone; size?: TextSize; label?: string;
}) {
  return createElement("ring", { value, tone, size, label }, children);
}

type ButtonProps = {
  onPress: () => void;
  /** `accent` is the single primary action; `danger` is destructive. */
  tone?: Tone;
  disabled?: boolean;
} & ({ title: string; icon?: string; label?: string } | { title?: undefined; icon: string; label: string });
/**
 * Capsule button with a title, an SF Symbol `icon`, or both. An icon-only
 * button needs a `label`, which VoiceOver reads and the tooltip shows.
 */
export function Button({ title, icon, label, onPress, tone = "secondary", disabled = false }: ButtonProps) {
  return createElement("button", { text: title ?? "", name: icon, label, onPress, tone, disabled });
}
/** `label` names the field for VoiceOver; without one it reads the placeholder. */
export function TextField({ value, onChange, placeholder, label, disabled = false }: {
  value: string; onChange: (value: string) => void; placeholder: string; label?: string; disabled?: boolean;
}) { return createElement("textField", { text: value, onChange, placeholder, label, disabled }); }
/** On/off switch. Controlled: render the new `value` after `onChange`. */
export function Toggle({ label, value, onChange, disabled = false }: {
  label?: string; value: boolean; onChange: (value: boolean) => void; disabled?: boolean;
}) {
  return createElement("toggle", { text: label, value: value ? 1 : 0, disabled,
    onChange: (next?: string) => onChange(next === "true") });
}

/**
 * Choose one of up to 32 options. In the notch it renders as a segmented
 * control (keep it to 2–4 short labels); in Settings as a pop-up menu.
 */
export function Picker<Value extends string>({ label, options, value, onChange, disabled = false }: {
  label?: string;
  options: readonly { value: Value; label: string }[];
  value: Value | undefined;
  onChange: (value: Value) => void;
  disabled?: boolean;
}) {
  return createElement("picker", { text: label, options: options as readonly PickerOption[], selection: value, disabled,
    onChange: (next?: string) => {
      const option = options.find((item) => item.value === next);
      if (option) onChange(option.value);
    } });
}

/**
 * Titled group. In Settings, top-level sections become native form sections;
 * in the notch they render as a rounded group with a small caps header.
 */
export function Section({ title, footer, spacing, children }: Children & { title?: string; footer?: string; spacing?: Spacing }) {
  return createElement("section", { text: title, detail: footer, spacing }, children);
}
/**
 * One row of a list: optional icon tile, title, subtitle and trailing
 * accessories (children such as `Badge`, `Toggle` or an icon `Button`).
 * With `onPress` the whole row becomes one button; don't also pass interactive children.
 */
export function ListItem({ title, subtitle, icon, tone, onPress, disabled = false, drag, children }: Children & {
  title: string; subtitle?: string; icon?: string; tone?: Tone; onPress?: () => void; disabled?: boolean;
  /** Text or a link (up to 64 KiB) that the row drags out to any app. Needs NotchNotch 0.14. */
  drag?: string;
}) {
  return createElement("listItem", { text: title, detail: subtitle, name: icon, tone, onPress, disabled, drag }, children);
}


/**
 * A place in the notch to drop files, links or text while dragging them. The
 * app shows it during a drag when it `accepts` every dragged item (uniform
 * type identifiers; see `DropTypes`), and calls `onDrop` when the person lets
 * go on it. Render it at the top level, beside `Activity` and `Settings`; an
 * extension has at most two. `opens` names one of your activities to open
 * after the drop, so the person can act on what they dropped right away; it
 * stays open until they close it. Needs NotchNotch 0.14; older versions leave it out.
 */
export function DropZone({ id, title, icon, accepts, multiple = false, opens, onDrop }: {
  id: string; title: string; icon?: string; accepts: readonly string[]; multiple?: boolean; opens?: string;
  onDrop: (items: DropItem[]) => void;
}) {
  return createElement("dropZone", { id, title, icon, accepts, multiple, opens, onDrop });
}

/**
 * A dropped file: its real thumbnail, name and size, drawn by the app. In
 * expanded content it can be dragged back out to Finder or any app.
 */
export function FileItem({ file }: { file: FileHandle }) { return createElement("fileItem", { file }); }

/**
 * Many files, laid out by the app so they always fit: up to six columns and
 * three rows, and past 18 files, stacks by kind (Photos, PDFs, …) that open in
 * place. Up to 256 files, in expanded content or a tile. Needs NotchNotch 0.14;
 * older versions leave it out.
 *
 * Files select like in Finder: a click selects one, ⌘-click adds one, ⇧-click
 * a range, and any click on a selected file deselects it; a double-click opens. Pass `selected` and `onSelect`
 * to act on the selection, for example in `Actions`. Dragging a selected file
 * drags the whole selection out to Finder or any app; `onDragOut` hears which
 * files went. Each file's menu has Quick Look, Open, Show in Finder, Share and
 * Copy, plus Remove with `onRemove`; on a selected file they act on the selection.
 */
export function FileGrid({ files, selected, onSelect, onRemove, onDragOut }: {
  files: readonly FileHandle[];
  selected?: readonly string[];
  onSelect?: (ids: string[]) => void;
  onRemove?: (files: FileHandle[]) => void;
  onDragOut?: (files: FileHandle[]) => void;
}) {
  const shown = files.slice(0, 256);
  const pick = (ids: unknown) => Array.isArray(ids) ? shown.filter((file) => ids.includes(file.id)) : [];
  const handled = onSelect || onRemove || onDragOut;
  // The app sends one event per gesture: {"select" | "remove" | "dragOut": [ids]}.
  const onChange = handled && ((json?: string) => {
    const event = JSON.parse(json ?? "{}") as Record<string, unknown>;
    if (event.select) onSelect?.(pick(event.select).map((file) => file.id));
    if (event.remove) { const removed = pick(event.remove); if (removed.length) onRemove?.(removed); }
    if (event.dragOut) { const dragged = pick(event.dragOut); if (dragged.length) onDragOut?.(dragged); }
  });
  const ids = new Set(shown.map((file) => file.id));
  return createElement("fileGrid", {
    files: shown, selected: onSelect ? (selected ?? []).filter((id) => ids.has(id)) : undefined,
    removable: onRemove ? true : undefined, onChange,
  });
}

export function Artwork({ source }: { source?: string }) { return createElement("artwork", { source }); }
export function Waveform({ playing, source }: { playing: boolean; source?: string }) {
  return createElement("waveform", { value: playing ? 1 : 0, source });
}
export function MusicPlayer({ state, onCommand }: { state: NowPlayingState; onCommand: (request: MediaRequest) => void }) {
  return createElement("player", { media: state, onChange: (json?: string) => {
    if (json) onCommand(JSON.parse(json) as MediaRequest);
  } });
}
