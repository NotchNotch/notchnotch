<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-white.svg">
    <img src="assets/logo.svg" width="72" height="72" alt="NotchNotch logo">
  </picture>
</p>

# NotchNotch

A native macOS notch hub for music, calendar events, and extensible live activities.

**Developer preview.** Built with SwiftUI and AppKit, with extensions written in React and TypeScript.

## Features

- Music controls for Spotify and Apple Music.
- Upcoming calendar events with a live countdown and meeting links.
- An extension SDK in React and TypeScript with native components, prompts, storage and local app connections.
- Settings for extensions, displays, hover behavior and opening at login.

## Install

Requires macOS 14 or later.

1. Download the latest `NotchNotch-<version>.dmg` from [Releases](https://github.com/sadeqi-ah/notchnotch/releases).
2. Open it and drag **NotchNotch** to **Applications**.
3. Open NotchNotch. This developer preview is not notarized by Apple, so macOS blocks the first launch. Choose **Done**, then open **System Settings › Privacy & Security**, scroll to *“NotchNotch” was blocked* and choose **Open Anyway**. Confirm with your password. This is needed only once.

From 0.3.0 on, NotchNotch updates itself: choose **Check for Updates…** in the menu bar, or let it check daily. Updates are verified with the project's signing key before they install. Download releases only from this repository. If you prefer Terminal, `xattr -dr com.apple.quarantine /Applications/NotchNotch.app` removes the download quarantine instead of step 3.

## Development

Building requires Xcode 26 (Swift 6.2 or later and the macOS 26 SDK), Node.js 22+ and pnpm. The app runs on macOS 14 or later.

```sh
pnpm install
pnpm dev
```

Connect Music and Calendar from **Settings & Extensions…** in the menu bar. `pnpm dev:examples` also loads the [example extensions](examples/).

## Build and test

```sh
pnpm build
pnpm test
```

The app is built at `dist/NotchNotch.app`. `pnpm release` creates a universal DMG; see [Releasing](docs/releasing.md) for signing and notarization. Only install extensions you trust.

## Documentation

[Architecture](docs/architecture.md) · [Extension API](docs/extension-api.md) · [App connections](docs/connections.md) · [Releasing](docs/releasing.md) · [Changelog](CHANGELOG.md) · [Privacy](PRIVACY.md) · [Security](SECURITY.md)

## License

Copyright © 2026 AmirHossein Sadeghi. Licensed under [GNU GPL v3.0](LICENSE) (GPL-3.0-only).

The extension SDK packages in [`packages/`](packages) (`@notchnotch/sdk`, `@notchnotch/runtime`, `@notchnotch/protocol`, `@notchnotch/react-renderer`, `@notchnotch/cli` and `create-notchnotch-extension`) are licensed under the [MIT License](packages/sdk/LICENSE), so extensions built with them can use any license.
