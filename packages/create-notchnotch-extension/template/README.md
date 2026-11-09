# {{displayName}}

A [NotchNotch](https://github.com/sadeqi-ah/notchnotch) extension.

```sh
npm install
npm run build        # builds and checks dist/
npm run watch        # rebuilds on change
npm run typecheck
```

Install it from **Settings & Extensions…**: click **+** at the bottom of the sidebar and choose `dist`. After a rebuild, install the folder again to update it.

- [Extension API](https://github.com/sadeqi-ah/notchnotch/blob/main/docs/extension-api.md)
- [App connections and native helpers](https://github.com/sadeqi-ah/notchnotch/blob/main/docs/connections.md)

Extension JavaScript has no DOM, `fetch` or Node APIs. To talk to an app or a local service, declare a connection in `notchnotch.json`.
