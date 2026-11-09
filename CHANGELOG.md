# Changelog

All notable changes to NotchNotch are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Security
- Extension runners are sandboxed by macOS before any extension code runs: they can't read your files, write files, use the network or start programs. Everything extensions do goes through the app. A built-in probe tests that each of these is blocked.

- NotchNotch stops an extension that uses more than 400 MB of memory, keeps the processor busy for 30 seconds, or sends more than 30 messages a second after a short burst, and says which limit it hit.

### Changed
- Extension storage is written by the app instead of the extension's process, and holds up to 255 KiB.

## [0.5.0] - 2026-11-10

### Added
- `fetch` in `@notchnotch/sdk` for HTTPS requests to hosts listed in the manifest's new `network` field. NotchNotch makes the request without cookies or cache, follows redirects only to listed hosts and drops credentials when the host changes. The install review and **Access** tab list the hosts.
- `notchnotch dev` (and `npm run dev` in new projects) runs an extension from its project folder in the open NotchNotch app, reloads it on every save, and prints its console output in the terminal. A development copy stands in for an installed one with the same id until you press Ctrl+C.
- Manifest `preferences`: text, password, toggle and dropdown settings that NotchNotch draws in the extension's **Setup** and passes to it through `getPreferenceValues()`, even in top-level code. Passwords are kept in the Keychain. An extension with an empty required preference waits, marked **Needs setup**, until it is filled in.
- `open(url)` in `@notchnotch/sdk` opens a web page or an app link, such as `mailto:` or a meeting link, right after a click or key press in the extension: once per interaction, within five seconds. Local files, scripts and system links are refused.
- `secrets` in `@notchnotch/sdk` keeps tokens and passwords in the login Keychain, readable only by the extension that saved them. The **Access** tab lists their names and can delete them; removing the extension deletes them.

## [0.4.0] - 2026-11-10

### Added
- Extensions can use their own icon: set `icon` to the name of a 512×512 PNG in `assets/`, such as `"icon.png"`, with an optional `icon@dark.png` for dark backgrounds. It appears in Settings, the install review, connection requests and above prompts in the notch. `notchnotch check` and the installer validate it. SF Symbol names keep working.
- Optional manifest fields `author`, `categories`, `license`, `homepage` and `repository`, shown in the install review and under **Developer › Package**. Projects from `npm create notchnotch-extension` start with a category and the MIT license.
- An **About** tab on each extension's page that shows the package's `README.md` and, under **Version History**, its `CHANGELOG.md`. `notchnotch build` includes both files, and new projects start with them.
- `notchnotch lint` checks store guidelines: title case, a short description, author, categories, license, your own icon, README and CHANGELOG. New projects have `npm run lint` and a placeholder icon that `lint` asks you to replace.

### Changed
- Rewritten documentation: a guide for using NotchNotch, a developer guide split by topic (getting started, concepts, components, storage, connections, native helpers, manifest, publishing), and internal notes in `docs/internals`. The README is about the app; building it from source moved to `CONTRIBUTING.md`.
- Music, Calendar and the Focus Timer example have their own icons and a README written for the people who use them. The helpers' developer documentation moved to `ADAPTER.md`.

## [0.3.2] - 2026-11-09

### Added
- `.notchext` packages: one file that opens NotchNotch's install review on double-click, or with **+**. Make one with `notchnotch pack` or `notchnotch build --pack`; new projects get `npm run pack`. The app unpacks them with its own validating extractor and keeps the download's quarantine flag on the unpacked files.

## [0.3.1] - 2026-11-09

### Fixed
- `@notchnotch/runtime` types now include the runtime globals (`setTimeout`, `setInterval`, `console`…). In 0.3.0 a new project created with `npm create notchnotch-extension` failed `npm run typecheck`.

### Changed
- The SDK is published to npm with Trusted Publishing when it is configured, and release workflows run on Node 24.

## [0.3.0] - 2026-11-09

**Upgrading from 0.2.0:** install this DMG by hand once. From 0.3.0 on, NotchNotch updates itself. Music and Calendar may ask for macOS access once more.

### Added
- A welcome window on first launch, and a short greeting in the notch on every launch so it's clear NotchNotch is running.
- Automatic updates with Sparkle: **Check for Updates…** in the menu bar, and update settings in **About**. Updates are EdDSA-signed and published from GitHub Releases.
- The extension SDK as npm packages (`@notchnotch/sdk`, `@notchnotch/runtime`, `@notchnotch/cli`) and `npm create notchnotch-extension` to start a project outside this repository.
- `@notchnotch/cli` with `notchnotch build` and `notchnotch check`, so extensions can be built and checked outside this repository with the same rules as the installer.
- `helperApp` in `@notchnotch/cli/native` packages and signs a helper app bundle with its own privacy usage descriptions.
- Manifest `imageHosts` to allow artwork from declared HTTPS hosts. The install review lists them.

### Changed
- The extension SDK packages are MIT licensed, so extensions can use any license. The app remains GPL-3.0-only.
- Redesigned **Settings & Extensions**: General, Notch and About pages; extensions listed with live status; each extension page has a header with its on/off switch and **Setup**, **Access** and **Developer** tabs; install with **+** at the bottom of the sidebar; confirmations fade out on their own.
- `useStoredState("count", 0)` now infers `number` and boolean values infer `boolean`, instead of their literal types.
- Helpers of installed extensions are their own responsible process for macOS privacy permissions. Prompts name the helper, and access granted to one extension's helper can't be used by NotchNotch or by other extensions. The bundled Music and Calendar helpers still ask as NotchNotch, because macOS attributes code inside the app bundle to the app.
- Remote artwork is no longer allowed by default from Spotify and Apple Music CDNs; the Music extension declares them in `imageHosts`.
- The bundled extensions are built through the same `@notchnotch/cli` code path as third-party extensions.

## [0.2.0] - 2026-11-09

### Added
- Design tokens (`NotchTheme`) for typography, spacing and color in the notch.
- SDK components: `Spacer`, `Divider`, `Toggle`, `Picker`, `Section`, `ListItem`, `Badge`, `Actions`, icon buttons, and `spacing`/`align` on rows and columns.
- Extension storage: `storage` and `useStoredState` (256 KiB per extension).
- Remembered connection access (**Always Allow**), silent reconnect with `interactive: false`, and **Forget App Access**.
- Prompt header showing the asking extension, and a pending-question badge in the compact notch.
- Console for extension logs in Settings & Extensions.
- Runner supervision: liveness checks, automatic restart with backoff.
- Display choice for multi-monitor setups and **Open at login**.
- New NotchNotch logo, used for the app icon, the menu bar icon and the README.
- Focus Timer example extension (`pnpm dev:examples`).
- Universal release build and DMG (`pnpm release`), CI, and a tagged release workflow that works without paid signing.
- Optional self-signed signing identity (`scripts/create-signing-identity.sh`) so macOS keeps permissions across updates; Developer ID signing and notarization when available.
- Install guide for unnotarized builds, CHANGELOG, privacy and security policies.

### Changed
- Calendar settings and activity rebuilt with the new components.
- Connection consent no longer blocks the notch while asking; a denial can be retried.
- Runner stderr is logged instead of stopping the extension.
- The pointer is sampled slowly away from the notch to save energy.
- Building requires Xcode 26 (macOS 26 SDK); the app still runs on macOS 14 and later.

### Removed
- Marketplace placeholder page.

## [0.1.0] - 2026-10-30

First developer preview: native notch host, React extension runtime, Music and Calendar extensions, local extension install.

[Unreleased]: https://github.com/sadeqi-ah/notchnotch/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/sadeqi-ah/notchnotch/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/sadeqi-ah/notchnotch/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/sadeqi-ah/notchnotch/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/sadeqi-ah/notchnotch/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/sadeqi-ah/notchnotch/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/sadeqi-ah/notchnotch/releases/tag/v0.2.0
