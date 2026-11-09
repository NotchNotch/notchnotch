# {{displayName}}

Describe what {{displayName}} shows in the notch and why it's useful. NotchNotch shows this file as the extension's **About** page, so write it for the people who install it.

## Set up

1. Explain any setup step, such as connecting an app.

## Development

```sh
npm install
npm run build        # builds and checks dist/
npm run watch        # rebuilds on change
npm run typecheck
npm run lint         # store guidelines: icon, title, README…
npm run pack         # also writes <id>-<version>.notchext to share
```

Install it from **Settings & Extensions…**: click **+** at the bottom of the sidebar and choose `dist`, or double-click the `.notchext` from `npm run pack`. After a rebuild, install the folder again to update it.

- [Getting started](https://github.com/sadeqi-ah/notchnotch/blob/main/docs/extensions/getting-started.md)
- [Concepts](https://github.com/sadeqi-ah/notchnotch/blob/main/docs/extensions/concepts.md) · [Components](https://github.com/sadeqi-ah/notchnotch/blob/main/docs/extensions/components.md) · [Connections](https://github.com/sadeqi-ah/notchnotch/blob/main/docs/extensions/connections.md)
- [Publishing](https://github.com/sadeqi-ah/notchnotch/blob/main/docs/extensions/publishing.md)

Extension JavaScript has no DOM, `fetch` or Node APIs. To talk to an app or a local service, declare a connection in `notchnotch.json`.
