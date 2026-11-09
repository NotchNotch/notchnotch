# @notchnotch/sdk

React components and APIs for [NotchNotch](https://github.com/sadeqi-ah/notchnotch) extensions: live activities in the MacBook notch, prompts, a settings page, storage and connections to local apps.

```sh
npm create notchnotch-extension@latest my-extension
```

```tsx
import { Activity, Symbol, Text } from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

start(
  <Activity id="hello" title="Hello">
    <Activity.Compact leading={<Symbol name="hand.wave" />} trailing={<Text>Hi</Text>} />
    <Activity.Expanded><Text size="title">Hello from the notch</Text></Activity.Expanded>
  </Activity>,
);
```

See the [Extension API](https://github.com/sadeqi-ah/notchnotch/blob/main/docs/extension-api.md).
