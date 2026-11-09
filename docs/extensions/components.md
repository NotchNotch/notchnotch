# Components

Import components from `@notchnotch/sdk`. NotchNotch draws them natively and controls their size, font, color and animation through one theme, so you describe *what* to show, not how it looks.

## Text and symbols

| Component | Props |
| --- | --- |
| `Text` | text or number children, `tone`, `size` |
| `Symbol` | SF Symbol `name`, `tone`, `size` (follows the text sizes) |
| `Badge` | short text children, `tone` |
| `Progress` | `value` from 0 to 1, `tone` |

Text sizes: `caption`, `body`, `headline`, `title`, `timer`.

Tones: `primary`, `secondary`, `accent`, `success`, `warning`, `danger`.

## Controls

| Component | Props |
| --- | --- |
| `Button` | `title` and/or SF Symbol `icon`, `onPress`, `tone`, `disabled` |
| `TextField` | `value`, `onChange`, `placeholder`, `disabled` |
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

## Media

`MusicPlayer`, `Artwork` and `Waveform` show playback that your extension supplies; they don't play anything themselves. They work in the notch, not in settings.

`Artwork` accepts a JPEG or PNG `data:` URL of up to 64 KiB, or an `https` URL on a host you list in the manifest's [`imageHosts`](manifest.md#imagehosts). NotchNotch downloads remote artwork itself, and the install review lists those hosts.

## Limits

A snapshot of your notch and settings content can have up to 512 nodes, nested up to 16 levels deep, and 16 surfaces. Text typed into a field is capped at 4096 characters. Stay well below these: the notch is small.
