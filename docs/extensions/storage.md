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

Don't store passwords or tokens: storage is a plain JSON file in the user's Application Support folder.
