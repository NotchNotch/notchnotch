# NotchNotch

A native macOS notch hub for music, calendar events, and extensible live activities.

**Developer preview.** Built with SwiftUI and AppKit, with extensions written in React and TypeScript.

## Features

- Music controls for Spotify and Apple Music.
- Upcoming calendar events with a live countdown and meeting links.
- An extension SDK in React and TypeScript with native components, prompts, storage and local app connections.
- Settings for extensions, displays, hover behavior and opening at login.

## Install

Download the latest DMG from the project's GitHub Releases, open it and drag NotchNotch to Applications. Requires macOS 14 or later.

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
