# {{displayName}}

Describe what {{displayName}} shows in the notch and why it's useful. NotchNotch shows this file as the extension's **About** page, so write it for the people who install it.

## Set up

1. Explain any setup step, such as connecting an app.

## Development

```sh
npm install
npm run dev          # runs it in NotchNotch and reloads on save
npm run build        # builds and checks dist/
npm run watch        # rebuilds on change
npm run typecheck
npm run lint         # store guidelines: icon, title, README…
npm run pack         # also writes <id>-<version>.notchext to share
```

`npm run dev` needs NotchNotch open; press Ctrl+C to stop. To install the extension for good, click **+** at the bottom of the sidebar in **Settings & Extensions…** and choose `dist`, or double-click the `.notchext` from `npm run pack`.

- [Getting started](https://github.com/NotchNotch/notchnotch/blob/main/docs/extensions/getting-started.md)
- [Concepts](https://github.com/NotchNotch/notchnotch/blob/main/docs/extensions/concepts.md) · [Components](https://github.com/NotchNotch/notchnotch/blob/main/docs/extensions/components.md) · [Connections](https://github.com/NotchNotch/notchnotch/blob/main/docs/extensions/connections.md)
- [Publishing](https://github.com/NotchNotch/notchnotch/blob/main/docs/extensions/publishing.md)

Extension JavaScript has no DOM or Node APIs. To call a web API, list its host in `network` in `notchnotch.json` and use `fetch` from `@notchnotch/sdk`; to talk to an app on this Mac, declare a connection.
