# Storage

`useStoredState` works like `useState`, but the value survives app restarts.

```tsx
import { storage, useStoredState } from "@notchnotch/sdk";

const [minutes, setMinutes] = useStoredState("minutes", "25");

storage.set("lastRun", Date.now());
const lastRun = storage.get<number>("lastRun");
```

- Values are JSON. Each extension has 256 KiB.
- Reads are immediate. A write that would go over the limit returns `false` and changes nothing.
- Removing the extension deletes its storage.

Don't put passwords or tokens here: storage is a plain JSON file in the user's Application Support folder. Use secrets instead.

## Secrets

`secrets` keeps text such as API tokens in the login Keychain. Only your extension can read them.

```tsx
import { secrets } from "@notchnotch/sdk";

await secrets.set("api-token", token);
const saved = await secrets.get("api-token"); // undefined when there is none
await secrets.delete("api-token");
```

- Keys use letters, digits, `.`, `_` and `-`, up to 64 characters. Values are text up to 8 KiB. An extension can keep up to 32.
- Every call is asynchronous. The first time, macOS may ask to allow Keychain access, so read secrets when you need them rather than at every render.
- People see the names of your secrets, never the values, in your extension's **Access** tab, and can delete them there. Removing the extension deletes them.

For a token people paste once, a `password` [preference](preferences.md) is simpler. Use `secrets` for values your extension gets on its own, such as a token from a sign-in flow.

Requires NotchNotch 0.5 or later.
