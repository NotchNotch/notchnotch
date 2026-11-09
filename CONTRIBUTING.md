# Contributing

Thanks for helping. This page covers building NotchNotch from source and sending changes.

## Requirements

- Xcode 26 (Swift 6.2 or later and the macOS 26 SDK). The app itself runs on macOS 14 or later.
- Node.js 22 or later and pnpm.

## Run it

```sh
pnpm install
pnpm dev
```

`pnpm dev` builds the app and the bundled extensions, starts `dist/NotchNotch.app`, and reloads an extension when you edit it. `pnpm dev:examples` also loads the [example extensions](examples/). Quit any installed copy of NotchNotch first: both use the same extension library.

## Test

```sh
pnpm check
```

This runs the JavaScript tests and the Swift tests, then builds the app. Run it before sending a change. If Swift tests crash after you change a type shared between modules, touch the affected test files to rebuild them.

## Repository layout

| Folder | What's there |
| --- | --- |
| `apps/macos` | The app: notch window, Settings & Extensions, updates |
| `native` | Swift libraries: protocol, notch state, extension store, runtime, connections, rendering |
| `packages` | The extension SDK, runtime, CLI and project template, published to npm |
| `extensions` | Music and Calendar, built like any third-party extension |
| `examples` | Example extensions for development |
| `schemas` | JSON Schemas for the manifest and the wire protocol |
| `docs` | User, developer and internal documentation |

## Documentation

Docs are Markdown in [`docs/`](docs/README.md), and change in the same pull request as the code they describe.

- `docs/guide` is for people who use NotchNotch.
- `docs/extensions` is for people who build extensions.
- `docs/internals` is for people who work on NotchNotch itself.

Write short sentences in plain English, lead with the task, and make every code sample runnable. Use `example.com` addresses and neutral examples (a weather service, a build server) rather than real products.

## Changes

- Keep each commit to one logical change, with a message that says what it does and why.
- Add a line to **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for anything a user or extension author would notice.
- Manifest and protocol rules exist in both Swift and the CLI. Change both, and the JSON Schema, together.

Releases are described in [Releasing](docs/internals/releasing.md).
