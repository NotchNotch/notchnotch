# Store catalog

The Store lists the extensions reviewed in
[`sadeqi-ah/notchnotch-extensions`](https://github.com/sadeqi-ah/notchnotch-extensions).
There are no servers: after a pull request is merged, that repository's CI
builds each changed extension, uploads the `.notchext` to a GitHub release,
rebuilds `index.json`, signs it, and publishes both files.

The app reads the catalog with `ExtensionCatalog` in
`native/NotchExtensions/Sources/ExtensionCatalog.swift` and fetches it with
`StoreClient`, which keeps the last verified copy in
`~/Library/Application Support/NotchNotch/Store/`. The catalog URL and trusted
keys are in the app's Info.plist (`NotchCatalogURL`, `NotchCatalogPublicKeys`),
written by `scripts/package-app.mjs` for every build.

## Links

`notchnotch://extensions/<author>/<name>` opens an extension's Store page and
`notchnotch://store` the Store; `StoreLink` parses them with the same handle
rule as the catalog and rejects anything else. A link never installs.

## Testing against a local Store

Debug builds (`pnpm dev`) accept a test catalog and also allow
`http://127.0.0.1` links, which release builds never do:

```sh
NOTCHNOTCH_CATALOG_URL=http://127.0.0.1:8765/index.json \
NOTCHNOTCH_CATALOG_KEY=<base64 public key of a throwaway pair> pnpm dev
```

Sign the test `index.json` with that pair's private key and serve the folder
with `python3 -m http.server 8765 --bind 127.0.0.1`.

## Files

| File | Contents |
| --- | --- |
| `index.json` | The catalog, UTF-8 JSON, at most 8 MiB |
| `index.json.sig` | Base64 Ed25519 signature over the exact bytes of `index.json` |

The signature is checked before the JSON is parsed, so the signed file must be
uploaded byte for byte. Nothing re-serializes it.

## Format 1

```json
{
  "format": 1,
  "sequence": 42,
  "generated": "2026-11-10T12:00:00Z",
  "expires": "2026-12-10T12:00:00Z",
  "extensions": [
    {
      "handle": "sadeqi-ah/focus-timer",
      "manifest": { "id": "dev.notchnotch.focus-timer", "name": "Focus Timer", "version": "1.2.0", "author": "sadeqi-ah", "…": "…" },
      "package": {
        "url": "https://github.com/sadeqi-ah/notchnotch-extensions/releases/download/…/focus-timer-1.2.0.notchext",
        "sha256": "…64 lowercase hex…",
        "size": 48213
      },
      "icon": "https://…/icon.png",
      "iconDark": "https://…/icon@dark.png",
      "screenshots": ["https://…/1.png"],
      "minimumAppVersion": "0.7.0",
      "published": "2026-11-09T18:20:00Z"
    }
  ]
}
```

- `handle` is `author/name`: the extension's folder in the repository, its page
  on the website and its `notchnotch://extensions/<author>/<name>` address. It
  must start with the manifest's `author`.
- `manifest` is the whole `notchnotch.json` of that version, validated like an
  installed one. The Store shows its permissions before downloading, and after
  extracting the app requires the package's manifest to equal it.
- Every link is `https`. Up to 6 screenshots.
- A format the app doesn't know is rejected with "update NotchNotch".

## Why a signature isn't enough

Whoever serves the files (GitHub, a proxy, someone between) can't forge a
signature, but could serve an **older** signed catalog that still lists a
version with a known problem, or keep serving the same one forever so fixes
never arrive. Two fields stop that, the same idea as
[TUF](https://theupdateframework.io)'s timestamp role:

- `sequence` grows with every catalog. The app remembers the highest one it
  accepted and rejects anything lower.
- `expires` is about a month after `generated`. The app rejects an expired
  catalog, so CI re-signs it on a schedule even when nothing changed.

## Packages

A download is trusted only if its size and SHA-256 match the catalog entry.
Because the hash is inside the signed catalog, the release asset's host doesn't
need to be trusted. Packages installed from the Store aren't quarantined: trust
comes from review and the signed catalog instead.

## Keys

The catalog key is separate from the Sparkle update key, so a leak of one
doesn't compromise the other.

```sh
node scripts/catalog.mjs keys                 # once; writes apps/macos/CatalogPublicKey
gh secret set CATALOG_PRIVATE_KEY --repo sadeqi-ah/notchnotch-extensions \
  < ~/.config/notchnotch/catalog-ed25519-private-key
CATALOG_PRIVATE_KEY=… node scripts/catalog.mjs sign index.json
```

`ExtensionCatalog.verify` accepts a list of keys, so a new key can ship in an
app update before CI switches to it.
