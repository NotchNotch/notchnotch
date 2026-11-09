# Connections

Extension JavaScript can't open files or reach the network. To show data from an app or tool on the same Mac, declare a **connection** in the manifest. NotchNotch carries the messages and asks the person before anything connects; your extension owns the protocol and the UI.

## Choose a transport

| The other side | Transport | Permission |
| --- | --- | --- |
| A local server with a request/response API | `http` | `local-network` |
| A local server that sends events as they happen | `websocket` | `local-network` |
| A command-line tool or protocol server | `stdio` | `process` |
| An app that needs custom native code | your own helper over `stdio` | `process` |

WebSockets and processes stay open, so you get events without polling. For `stdio`, see [Native helpers](native-helpers.md).

## Declare it

```json
{
  "permissions": ["local-network"],
  "connections": {
    "api": { "transport": "http", "endpoint": "http://127.0.0.1:4277" },
    "events": { "transport": "websocket", "endpoint": "ws://127.0.0.1:4277/events" }
  }
}
```

- Use `127.0.0.1` or `[::1]` with an explicit port. Host names, remote addresses, credentials, query strings and fragments are rejected.
- An `http` endpoint is an origin; each request supplies its path. A `websocket` endpoint is the full address, including a fixed path.
- Up to eight connections per extension.

Declaring a connection grants nothing. The first time the extension uses it, NotchNotch asks: **Allow Once** lasts until the extension stops, **Always Allow** is remembered, and **Don't Allow** is asked again next time. People can review and forget remembered access in the extension's **Access** tab.

## Example: build status

Suppose a local build server on port 4277 answers `GET /status` and sends `build/progress` and `build/finished` events over a WebSocket. This extension shows the running build in the notch and asks to retry a failed one.

```tsx
import { useEffect, useState } from "react";
import { Activity, Actions, Button, ConnectionStream, Progress, Prompt, Settings, Symbol, Text, localHTTP } from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

const api = localHTTP("api");
const events = new ConnectionStream("events");
type Build = { id: string; name: string; progress: number; state: "running" | "passed" | "failed" };

function BuildStatus() {
  const [build, setBuild] = useState<Build | null>(null);
  const [error, setError] = useState("");

  // Subscribe before opening, so no event is missed.
  useEffect(() => events.subscribe((event) => {
    if (event.event === "closed") { setError(event.error ?? "Disconnected from the build server."); return; }
    const message = event.message as { type?: string; build?: Build };
    if (message.build && (message.type === "build/progress" || message.type === "build/finished")) setBuild(message.build);
  }), []);

  async function connect(interactive: boolean) {
    try {
      await events.open({ interactive });
      const response = await api.request("/status");
      if (response.status === 200) setBuild(JSON.parse(response.body) as Build);
      setError("");
    } catch (reason) { if (interactive) setError(String(reason)); }
  }

  // Reconnect silently at launch if the person chose Always Allow.
  useEffect(() => { void connect(false); }, []);

  async function retry(id: string) {
    const response = await api.request(`/builds/${encodeURIComponent(id)}/retry`, { method: "POST" });
    if (response.status !== 202) setError(`Retry failed (${response.status}).`);
  }

  return <>
    <Settings>
      <Button title="Connect to Build Server" tone="accent" onPress={() => { void connect(true); }} />
      {error ? <Text tone="warning">{error}</Text> : null}
    </Settings>
    {build?.state === "running" ? <Activity id={`build-${build.id}`} title={build.name}>
      <Activity.Compact leading={<Symbol name="hammer" />} trailing={<Text size="caption">{Math.round(build.progress * 100)}%</Text>} />
      <Activity.Expanded>
        <Text size="headline">{build.name}</Text>
        <Progress value={build.progress} />
      </Activity.Expanded>
    </Activity> : null}
    {build?.state === "failed" ? <Prompt id={`failed-${build.id}`} title="Build failed">
      <Prompt.Expanded>
        <Text>{build.name}</Text>
        <Actions>
          <Button title="Dismiss" onPress={() => setBuild(null)} />
          <Button title="Retry" tone="accent" onPress={() => { void retry(build.id); }} />
        </Actions>
      </Prompt.Expanded>
    </Prompt> : null}
  </>;
}

start(<BuildStatus />);
```

Treat everything the other side sends as untrusted: check its shape before you render it, and expect duplicates, reconnects and failures.

## HTTP

`localHTTP(name).request(path, options)` returns `{ status, headers, body }`.

- `method` defaults to `GET`. Bodies are UTF-8 text; parse JSON yourself.
- `timeoutMs` is 1–30,000 (default 15,000).
- Redirects are returned to you, not followed. No cookies, cache or proxy are used.

## Streams

`new ConnectionStream(name)` is one WebSocket or process.

- Call `subscribe` before `open`. Each event is a `message` (one JSON value) or `closed` (with an `error` when it failed).
- `open({ interactive: false })` connects only with a remembered **Always Allow**, without a dialog. Use it at launch, and keep the interactive `open()` behind a button in `Settings`.
- Streams don't reconnect on their own, so an app that is offline never causes repeated dialogs.
- Closing a stream, stopping the extension or choosing **Disconnect** in its **Access** tab closes it.

## JSON-RPC

`JSONRPCClient` wraps a stream for tools that speak JSON-RPC 2.0 in both directions.

```ts
import { ConnectionStream, JSONRPCClient } from "@notchnotch/sdk";

const rpc = new JSONRPCClient(new ConnectionStream("tool"));
rpc.onNotification(({ method, params }) => {
  // Update your activity from progress or messages.
});
rpc.onRequest((request) => {
  // Show a Prompt; when the person decides, call rpc.respond(request.id, result).
});
await rpc.connect();
const info = await rpc.request("initialize", { client: "my-extension" });
```

- Requests run concurrently and time out; remote errors reject the promise; a disconnect rejects everything pending.
- With an `onRequest` handler, answer every request explicitly with `respond` or `reject`. Without one, requests get a method-not-found error.
- `disconnect()` keeps the client reusable; `dispose()` releases it.

## Limits

- Messages and HTTP bodies: 64 KiB each. Process output is one JSON value per line.
- Up to 32 operations waiting at once, and 256 stream messages per second.
- Data that breaks a limit, or isn't valid JSON, closes that connection.

Secrets don't belong in the manifest. Keep tokens with [`secrets`](storage.md#secrets). To reach a service on the internet rather than this Mac, use [`fetch`](network.md).
