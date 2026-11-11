<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-white.svg">
    <img src="assets/logo.svg" width="72" height="72" alt="NotchNotch logo">
  </picture>
</p>

# NotchNotch

The notch on your Mac, put to work. NotchNotch shows what's happening now around the camera: the song that's playing, your next meeting, a running timer, or anything an extension adds.

**Developer preview** for macOS 14 or later. Free and open source.

**[notchnotch.github.io](https://notchnotch.github.io)**: download, documentation and the [Store](https://notchnotch.github.io/store/).

## Features

- **Music:** what's playing in Spotify or Apple Music, with playback controls.
- **Calendar:** your next event with a countdown and a button to join the meeting.
- **Extensions:** add your own, written in React and TypeScript and drawn natively by the app. Install one by double-clicking a `.notchext` file.
- **Private:** no account, no analytics. Everything stays on your Mac.

## Install

1. Download the latest `NotchNotch-<version>.dmg` from [Releases](https://github.com/NotchNotch/notchnotch/releases).
2. Open it and drag **NotchNotch** to **Applications**.
3. Open NotchNotch. This preview isn't notarized by Apple yet, so the first time, open **System Settings › Privacy & Security** and choose **Open Anyway** next to *"NotchNotch" was blocked*.

NotchNotch updates itself after that. See [Using NotchNotch](docs/guide/using-notchnotch.md) to connect Music and Calendar.

## Build an extension

```sh
npm create notchnotch-extension@latest my-extension
```

Start with [Getting started](docs/extensions/getting-started.md), then browse the [documentation](docs/README.md), also on [the website](https://notchnotch.github.io/docs/).

## Contributing

Bug reports, ideas and pull requests are welcome. See [Contributing](CONTRIBUTING.md) to build the app, ask questions in [Discussions](https://github.com/NotchNotch/notchnotch/discussions), and report security problems privately as described in [Security](SECURITY.md). Anyone can submit an extension to the Store with `notchnotch publish`. Everyone follows the [code of conduct](CODE_OF_CONDUCT.md).

[Changelog](CHANGELOG.md) · [Privacy](PRIVACY.md) · [Documentation](docs/README.md)

## License

Copyright © 2026 AmirHossein Sadeghi. NotchNotch is licensed under the [GNU GPL v3.0](LICENSE) (GPL-3.0-only).

The extension SDK packages in [`packages/`](packages) (`@notchnotch/sdk`, `@notchnotch/runtime`, `@notchnotch/protocol`, `@notchnotch/react-renderer`, `@notchnotch/cli` and `create-notchnotch-extension`) are licensed under the [MIT License](packages/sdk/LICENSE), so extensions built with them can use any license.
