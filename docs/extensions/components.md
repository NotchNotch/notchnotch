# Components

Import components from `@notchnotch/sdk`. NotchNotch draws them natively and controls their size, font, color and animation through one theme, so you describe *what* to show, not how it looks.

## Text and symbols

| Component | Props |
| --- | --- |
| `Text` | text or number children, `tone`, `size` |
| `Symbol` | SF Symbol `name`, `tone`, `size` (follows the text sizes), `label` when it carries meaning |
| `Badge` | short text children, `tone` |
| `Progress` | `value` from 0 to 1, `tone`, `label` |
| `Value` | a number as children, `unit` (up to 32 characters), `tone` (default `accent`), `size` (default `timer`). Draws the number large with the unit small beside it |
| `Ring` | `value` from 0 to 1, `tone`, `size` (default `headline`), `label`. Children, such as a `Symbol`, sit inside. Fits in `Activity.Compact` too |

```tsx
<Row spacing="loose">
  <Ring value={done} size="title" label="Focus session"><Symbol name="timer" tone="accent" /></Ring>
  <Value unit="left">{clock(remaining)}</Value>
</Row>
```

`Value` and `Ring` need NotchNotch 0.11 or later. Older versions can't show an extension that uses them.

Text sizes: `caption`, `body`, `headline`, `title`, `timer`.

Tones: `primary`, `secondary`, `accent`, `success`, `warning`, `danger`.

## Controls

| Component | Props |
| --- | --- |
| `Button` | `title` and/or SF Symbol `icon`, `onPress`, `tone`, `disabled`. An icon-only button needs a `label` |
| `TextField` | `value`, `onChange`, `placeholder`, `label`, `disabled` |
| `Toggle` | `value`, `onChange(boolean)`, `label`, `disabled` |
| `Picker` | `options` (1–32 `{ value, label }`), `value`, `onChange`, `label`. Segmented in the notch, a menu in Settings |
| `Actions` | buttons, aligned to the trailing edge. Put the `accent` action last |

Fields, toggles and pickers are controlled: keep their value in React state.

```tsx
<Actions>
  <Button title="Skip" onPress={skip} />
  <Button title="Start Break" tone="accent" onPress={startBreak} />
</Actions>
```

## Layout

| Component | Props |
| --- | --- |
| `Row`, `Column` | children, `spacing` (`none`, `tight`, `regular`, `loose`), `align` (`start`, `center`, `end`) |
| `Spacer` | pushes the following content to the end of a row |
| `Divider` | a separator line |
| `Section` | `title`, `footer`, `spacing`, children |
| `ListItem` | `title`, `subtitle`, SF Symbol `icon`, `tone`, optional `onPress`, trailing children |

## Color

Set an [`accent`](manifest.md#identity) in the manifest, ideally the color of your icon. NotchNotch draws it in a shade tuned for the black notch and uses it for:

- every `Progress` without a `tone`, as a gradient from a neighboring hue into your color
- anything with `tone="accent"`: give it to your main number, symbol or button

```tsx
<Text size="timer" tone="accent">{clock(remaining)}</Text>
<Progress value={done} />
<Button title="Pause" icon="pause.fill" tone="accent" onPress={pause} />
```

Keep `success`, `warning` and `danger` for status. Short text with digits, such as a time or a price, rolls digit by digit when it changes, and progress slides to its new value.

## Accessibility

NotchNotch draws every component natively, so VoiceOver, Increase Contrast and Reduce Motion work without extra code. A few things only you know:

```tsx
<Button icon="arrow.clockwise" label="Refresh" onPress={refresh} />
<Symbol name="xmark.octagon.fill" tone="danger" label="Major outage" />
<Progress value={done} label="Focus session" />
<TextField value={city} onChange={setCity} placeholder="London" label="City" />
```

- **Icon-only buttons need a `label`.** TypeScript requires it. VoiceOver reads it and the pointer shows it as a tooltip.
- **Symbols are skipped by VoiceOver** unless you give them a `label`. Add one when the symbol says something its neighbors don't, such as a status shown only by color and icon.
- **Don't rely on color alone.** Pair a `danger` or `success` tone with words, a symbol with a `label`, or a `Badge`.
- Announcements (`Activity.Peek`) and new prompts are read aloud by VoiceOver, so write their text as a full sentence.

## Media

`MusicPlayer`, `Artwork` and `Waveform` show playback that your extension supplies; they don't play anything themselves. They work in the notch, not in settings.

`Artwork` accepts a JPEG or PNG `data:` URL of up to 64 KiB, or an `https` URL on a host you list in the manifest's [`imageHosts`](manifest.md#imagehosts). NotchNotch downloads remote artwork itself, and the install review lists those hosts.

## Limits

A snapshot of your notch and settings content can have up to 512 nodes, nested up to 16 levels deep, and 16 surfaces. Text typed into a field is capped at 4096 characters. Stay well below these: the notch is small.
