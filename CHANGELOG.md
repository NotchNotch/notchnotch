# Changelog

All notable changes to NotchNotch are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Automatic updates with Sparkle: **Check for Updates…** in the menu bar, and update settings in **General**. Updates are EdDSA-signed and published from GitHub Releases.
- `@notchnotch/cli` with `notchnotch build` and `notchnotch check`, so extensions can be built and checked outside this repository with the same rules as the installer.
- `helperApp` in `@notchnotch/cli/native` packages and signs a helper app bundle with its own privacy usage descriptions.
- Manifest `imageHosts` to allow artwork from declared HTTPS hosts. The install review lists them.

### Changed
- Extension helpers are their own responsible process for macOS privacy permissions. Prompts name the helper, and access granted to one extension's helper can no longer be used by NotchNotch or by other extensions. Users who connected Music or Calendar are asked once more.
- NotchNotch itself no longer has Apple Events or Calendar entitlements or usage descriptions.
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

[Unreleased]: https://github.com/sadeqi-ah/notchnotch/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/sadeqi-ah/notchnotch/releases/tag/v0.2.0
