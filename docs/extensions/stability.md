# API stability

An extension written for API v1 keeps working on every NotchNotch release that supports API v1, without a rebuild. This page says what that promise covers and how the API changes without breaking it.

## What API v1 covers

- Everything `@notchnotch/sdk` exports: components, their props and defaults, and the functions and types beside them, as documented here.
- `notchnotch.json` with `"apiVersion": 1`: every field, permission and connection kind in the [manifest](manifest.md).
- The documented behavior: what each phase does, when an announcement shows, what a permission allows.

Not covered:

- `@notchnotch/protocol`, `@notchnotch/react-renderer` and `@notchnotch/runtime` internals. They are how the SDK talks to the app, and change with it. Use `@notchnotch/runtime` only for `start`.
- Globals beginning with `__notchnotch`.
- How things look. The app owns layout, type, color and motion, and refines them in any release; an extension says what to show, not how.
- Anything undocumented.

## What can change in API v1

Only additions:

- New components, functions, permissions and manifest fields.
- New optional props, with defaults that keep today's behavior.
- New values for a prop where the old ones keep their meaning.

Nothing is removed or renamed, no default changes, and no required prop is added.

## New features need a newer app

An addition works only in the NotchNotch release that brought it. Its documentation says so, as in "Needs NotchNotch 0.14". The Store offers an extension only to apps new enough for what it uses, and an older app leaves out a component it doesn't know, rather than failing.

## Deprecation

Something that should no longer be used is **deprecated**: it keeps working through all of API v1, and:

- Its type carries `@deprecated` with the replacement, so your editor strikes it through.
- Its documentation names the replacement.
- It's listed below.

A deprecated part is removed only in API v2.

| Deprecated | Use instead | Since |
| --- | --- | --- |
| `Symbol` | `Icon`, which doesn't hide JavaScript's own `Symbol` | SDK 1.0 |

## API v2

A change that would break extensions waits for API v2: a new `apiVersion` in the manifest and a new major version of the SDK. An app that supports API v2 keeps running API v1 extensions for at least a year after v2 ships. An app that doesn't know an extension's `apiVersion` refuses to install it, instead of running it wrong.

The SDK's version follows the app's: SDK 1.x is API v1.
