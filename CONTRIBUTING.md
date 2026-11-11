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

This runs the JavaScript tests and the Swift tests, then builds the app. Run it before sending a change.

Code that reads untrusted input (`.notchext` packages, snapshots, manifests, Markdown, URLs) has seeded fuzz tests in `native/NotchExtensions/Tests/FuzzTests.swift`. They run a few hundred cases in every test run. Before changing that code, run them for longer:

```sh
NOTCHNOTCH_FUZZ_ITERATIONS=50000 swift test --filter Fuzz
```

A failure names its seed, so it can be replayed. If Swift tests crash after you change a type shared between modules, touch the affected test files to rebuild them.

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

The website, [notchnotch.github.io](https://notchnotch.github.io), is built from `docs/`, `CHANGELOG.md`, `PRIVACY.md`, `SECURITY.md` and this file by [NotchNotch/notchnotch.github.io](https://github.com/NotchNotch/notchnotch.github.io), every three hours. Relative links between them become links between site pages.

Docs are Markdown in [`docs/`](docs/README.md), and change in the same pull request as the code they describe.

- `docs/guide` is for people who use NotchNotch.
- `docs/extensions` is for people who build extensions.
- `docs/internals` is for people who work on NotchNotch itself.

Write short sentences in plain English, lead with the task, and make every code sample runnable. Use `example.com` addresses and neutral examples (a weather service, a build server) rather than real products.

## Changes

- Keep each commit to one logical change, with a message that says what it does and why.
- Add a line to **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for anything a user or extension author would notice.
- The protocol's message and UI types and the manifest's types are generated from `schemas/` into `native/NotchProtocol/Sources/Generated.swift` and `packages/protocol/src/generated.ts`. To add a field, a node type or a manifest key, change the schema, run `node scripts/generate-protocol.mjs` and commit the result; `pnpm test` fails when they're out of date.
- Validation is handwritten on purpose, in Swift extensions beside the generated types and in `packages/cli/src/manifest.mjs`. Change the rule in both places when a limit changes; a test checks that the CLI's category, permission and preference lists match the schema.

Releases are described in [Releasing](docs/internals/releasing.md).

## Issues and Discussions

- **Bugs, extension ideas and API requests** each have an issue template. A
  bug report can include a problem report from **General › Problems ›
  Export…**.
- **Questions** go to [Discussions](https://github.com/NotchNotch/notchnotch/discussions)
  (Q&A), and extensions you built to **Show and tell**.
- **Store extensions** live in
  [notchnotch-extensions](https://github.com/NotchNotch/notchnotch-extensions):
  submit with `notchnotch publish`, report their problems there.
- Labels: `bug`, `api-request`, `extension idea`, `store`, `good first issue`.

Everyone follows the [code of conduct](CODE_OF_CONDUCT.md).
