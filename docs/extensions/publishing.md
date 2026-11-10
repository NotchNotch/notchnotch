# Publishing

Make your extension ready for other people, then share it as a single file.

## Icon

Draw your own icon. It appears in Settings, the install review, connection requests and above your prompts in the notch.

```json
{ "icon": "icon.png" }
```

- `assets/icon.png`: PNG, exactly 512×512 pixels, at most 512 KiB. Draw the whole shape; NotchNotch shows it as is, without a mask or background.
- `assets/icon@dark.png` (optional): the same icon for dark backgrounds. The notch is always dark, so it uses this variant when there is one, as does Settings in dark mode. Add it when your icon is dark and would disappear on black.
- The name may contain letters, digits, `.`, `_` and `-`, and ends in `.png`.

Start from the [icon template](https://example.com/figma-icon-template): a 512 canvas with the tile shape, the area for your glyph, and previews at the sizes NotchNotch uses.

An SF Symbol name also works, such as `"icon": "timer"`, but your own icon is what makes an extension recognizable. NotchNotch 0.3 and earlier show a generic icon for PNG icons.

## About page and version history

Put a `README.md` and a `CHANGELOG.md` next to `notchnotch.json`. Your extension's page in Settings gets an **About** tab with the README, then the changelog under **Version History**.

Write the README for the people who install the extension: what it does and how to set it up. A leading `# Title` is hidden, because the page already shows the name.

```markdown
# Weather Changelog

## [1.1.0]

- Show tomorrow's forecast.

## [1.0.0]

- First version.
```

NotchNotch shows headings, paragraphs, lists, quotes, code blocks, emphasis and `https` links. Images show their alt text, and HTML appears as plain text.

## Store guidelines

`npm run lint` (`notchnotch lint`) checks what a store review would ask you to fix. NotchNotch installs the extension either way.

- `name` in title case: "Focus Timer", "Search in Database". Short words such as *in*, *of* and *to* stay lowercase; names like iOS keep their own case.
- A one-sentence `description` of at most 160 characters.
- Your own `id`, not `com.example.…`, plus `author`, `categories` and `license`.
- Your own PNG icon, not an SF Symbol and not the template's placeholder.
- A `README.md` and a `CHANGELOG.md`, without the template's placeholder text.

A new project fails `lint` until you replace each placeholder.

## Share a .notchext file

```sh
npm run pack
```

This builds the extension, runs the install checks and writes `<id>-<version>.notchext`. Double-clicking it opens NotchNotch's install review; it can also be chosen with **+** in Settings & Extensions. Share it however you like, for example as a GitHub release asset.

To update an installed extension, keep the same `id` and raise `version`. The review shows it as an update. The extension's stored data and its on or off setting are kept.

### What NotchNotch checks

Before writing anything, NotchNotch unpacks the file with its own extractor and checks each entry: relative paths only, no symbolic links, no encryption, at most 512 files and 64 MiB, and a matching checksum for every file. Then it applies the [package limits](manifest.md#package-limits).

If the file was downloaded, macOS's quarantine flag carries over to every unpacked file, so Gatekeeper still checks native helpers. Sign and notarize helpers you distribute, or tell people how to allow them.

## Trust

The install review lists what your extension can do beyond its sandbox, riskiest first: programs it runs, websites it exchanges data with, apps on the Mac it talks to, websites it shows pictures from, and settings it asks for. In an update, anything the installed version didn't have is marked **New**, so ask only for what you need, and say in your changelog why a new permission is there.

Installing an extension is a trust decision. Its JavaScript runs in a sandbox that can't touch files, the network or other programs, but a native helper runs with the person's account. The install review lists everything the extension asks for. Only install extensions you trust, and say plainly in your README what yours does.
