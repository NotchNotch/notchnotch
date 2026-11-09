# Network

Use `fetch` to call a web API, such as a weather service or GitHub. List the hosts in the manifest; NotchNotch makes the request for your extension.

```json
{
  "network": ["api.weather.example.com"]
}
```

```tsx
import { fetch } from "@notchnotch/sdk";

const response = await fetch("https://api.weather.example.com/today?city=Paris", {
  headers: { Accept: "application/json" },
});
if (!response.ok) throw new Error(`Weather service answered ${response.status}`);
const today = await response.json<{ temperature: number; summary: string }>();
```

Requires NotchNotch 0.5 or later.

## Hosts

- Up to 16 hosts, lowercase: `api.github.com`, or `*.example.com` for any subdomain of `example.com` (not `example.com` itself).
- The install review and the extension's **Access** tab list them. People agree to them when they install, so `fetch` never shows a dialog.
- Any other host fails with an error that names it. Add it to `network` and ship an update; the review shows the new host.

## Requests

`fetch(url, options)` takes:

| Option | Value |
| --- | --- |
| `method` | `GET` (default), `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD` or `OPTIONS` |
| `headers` | Up to 32. `Host`, `Connection`, `Content-Length`, `Transfer-Encoding` and `Proxy-Authorization` are set by NotchNotch |
| `body` | Text, up to 192 KiB. Use `JSON.stringify` for JSON |
| `timeoutMs` | 1–30,000; 15,000 by default |

The response has `ok`, `status`, `url` (after redirects), `headers` with lowercase names, `text()` and `json()`.

## Rules

- `https` only.
- A redirect is followed only to another host you listed. A redirect anywhere else comes back to you as the 3xx response. When a redirect changes host, `Authorization` and `Cookie` headers are dropped.
- No cookies are stored and nothing is cached.
- Response bodies are UTF-8 text of at most 192 KiB. Larger or binary responses fail.

`fetch` is a small function from the SDK, not the browser's: there is no `Request`, `Headers` or streaming. Libraries that expect the global `fetch` won't find one.

## Tokens

Don't put API keys in your code or manifest: anyone can read them in your package. Let people paste their own token in your `Settings`, and send it in a header. Storage is plain JSON, so treat stored tokens as visible to anyone with access to the Mac until secure storage arrives.
