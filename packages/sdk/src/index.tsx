import { createElement, type ReactNode } from "react";
import type { Alignment, MediaRequest, NowPlayingState, Spacing, TextSize, Tone } from "@notchnotch/protocol";
export type { Alignment, Spacing, TextSize, Tone } from "@notchnotch/protocol";
export * from "./connections";

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

/** The entire compact surface is one host-owned click target. */
export const Activity = Object.assign(
  function Activity({ initialView = "compact", phase = "active", ...props }: SurfaceProps & {
    phase?: "active" | "paused" | "completed";
    /** Eligible as a hover fallback even before this activity has been used. */
    idlePreview?: boolean;
  }) { return createElement("activity", { ...props, initialView, phase }); },
  { Compact, Expanded, Peek },
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
/** Thin separator line. */
export function Divider() { return createElement("divider", null); }

export function Text({ children, tone = "primary", size = "body" }: Children & { tone?: Tone; size?: TextSize }) {
  return createElement("text", { tone, size }, children);
}
/** SF Symbol. `size` follows the text scale so icons line up with adjacent text. */
export function Symbol({ name, tone = "primary", size = "body" }: { name: string; tone?: Tone; size?: TextSize }) {
  return createElement("symbol", { name, tone, size });
}
/** Short status label, e.g. a count or "Live". */
export function Badge({ children, tone = "secondary" }: Children & { tone?: Tone }) {
  return createElement("badge", { tone }, children);
}
export function Progress({ value, tone = "accent" }: { value: number; tone?: Tone }) {
  return createElement("progress", { value, tone });
}

type ButtonProps = {
  onPress: () => void;
  /** `accent` is the single primary action; `danger` is destructive. */
  tone?: Tone;
  disabled?: boolean;
} & ({ title: string; icon?: string } | { title?: undefined; icon: string });
/** Capsule button with a title, an SF Symbol `icon`, or both. Icon-only buttons are labeled by the symbol name. */
export function Button({ title, icon, onPress, tone = "secondary", disabled = false }: ButtonProps) {
  return createElement("button", { text: title ?? "", name: icon, onPress, tone, disabled });
}
export function TextField({ value, onChange, placeholder, disabled = false }: {
  value: string; onChange: (value: string) => void; placeholder: string; disabled?: boolean;
}) { return createElement("textField", { text: value, onChange, placeholder, disabled }); }
/** On/off switch. Controlled: render the new `value` after `onChange`. */
export function Toggle({ label, value, onChange, disabled = false }: {
  label?: string; value: boolean; onChange: (value: boolean) => void; disabled?: boolean;
}) {
  return createElement("toggle", { text: label, value: value ? 1 : 0, disabled,
    onChange: (next?: string) => onChange(next === "true") });
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
export function ListItem({ title, subtitle, icon, tone, onPress, disabled = false, children }: Children & {
  title: string; subtitle?: string; icon?: string; tone?: Tone; onPress?: () => void; disabled?: boolean;
}) {
  return createElement("listItem", { text: title, detail: subtitle, name: icon, tone, onPress, disabled }, children);
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
