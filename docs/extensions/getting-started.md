# Getting started

Build a NotchNotch extension in a few minutes. You need macOS 14 or later, NotchNotch, and Node.js 22 or later.

## Create a project

```sh
npm create notchnotch-extension@latest my-extension
cd my-extension
npm install
npm run build
```

The project has everything it needs from npm: `@notchnotch/sdk` for components and APIs, `@notchnotch/runtime` to start the extension, and `@notchnotch/cli` to build it.

```
my-extension
├── notchnotch.json     the manifest: id, name, icon, permissions
├── src/index.tsx       your extension
├── assets/icon.png     a placeholder icon to replace
├── README.md           shown as the extension's About page
└── CHANGELOG.md        shown as its version history
```

## Install it

1. Open **Settings & Extensions…** from the menu bar.
2. Click **+** at the bottom of the sidebar and choose the `dist` folder.
3. Review what the extension asks for and choose **Install Extension**.

After you change the code, run `npm run build` and install the folder again to update it. `npm run watch` rebuilds on every save.

## Your first activity

`src/index.tsx` describes what the notch shows, in React:

```tsx
import { useState } from "react";
import { Activity, Button, Symbol, Text } from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

function Counter() {
  const [count, setCount] = useState(0);
  return (
    <Activity id="counter" title="Counter">
      <Activity.Compact
        leading={<Symbol name="plus.circle" />}
        trailing={<Text>{count}</Text>}
      />
      <Activity.Expanded>
        <Text size="title">{count} little steps</Text>
        <Button title="One more" onPress={() => setCount((value) => value + 1)} />
      </Activity.Expanded>
    </Activity>
  );
}

start(<Counter />);
```

The compact part sits beside the camera. Hover or click the notch to open the expanded part. Logs from `console.log` appear in **Settings & Extensions… › your extension › Developer › Console**.

## Share it

`npm run pack` writes `<id>-<version>.notchext`. Anyone with NotchNotch can double-click that file to install it. Before you share, run `npm run lint` and fix what it reports. See [Publishing](publishing.md).

## Next

- [Concepts](concepts.md): activities, prompts, announcements and settings
- [Components](components.md): everything you can put in the notch
- [Manifest](manifest.md): every field of `notchnotch.json`
- [Example: Focus Timer](../../examples/focus-timer/src/index.tsx): an activity, a prompt and settings together
