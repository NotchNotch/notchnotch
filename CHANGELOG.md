# Changelog

All notable changes to NotchNotch are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Design tokens (`NotchTheme`) for typography, spacing and color in the notch.
- SDK components: `Spacer`, `Divider`, `Toggle`, `Picker`, `Section`, `ListItem`, `Badge`, `Actions`, icon buttons, and `spacing`/`align` on rows and columns.
- Extension storage: `storage` and `useStoredState` (256 KiB per extension).
- Remembered connection access (**Always Allow**), silent reconnect with `interactive: false`, and **Forget App Access**.
- Prompt header showing the asking extension, and a pending-question badge in the compact notch.
- Console for extension logs in Settings & Extensions.
- Runner supervision: liveness checks, automatic restart with backoff.
- Display choice for multi-monitor setups and **Open at login**.
- App icon and menu bar icon.
- Focus Timer example extension (`pnpm dev:examples`).
- Universal release build, Developer ID signing, notarization and DMG (`pnpm release`), CI and tagged release workflows.

### Changed
- Calendar settings and activity rebuilt with the new components.
- Connection consent no longer blocks the notch while asking; a denial can be retried.
- Runner stderr is logged instead of stopping the extension.
- The pointer is sampled slowly away from the notch to save energy.

### Removed
- Marketplace placeholder page.

## [0.1.0] - 2026-10-30

First developer preview: native notch host, React extension runtime, Music and Calendar extensions, local extension install.
