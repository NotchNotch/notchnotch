import { useEffect, useState } from "react";
import { Activity, Button, Section, Settings, Symbol, Text, Toggle, useStoredState } from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

// A minimal extension: a live activity in the notch and a settings page in
// Settings & Extensions. Edit, run `npm run build`, then reinstall the folder.
function Extension() {
  const [count, setCount] = useStoredState("count", 0);
  const [showSeconds, setShowSeconds] = useStoredState("showSeconds", true);
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  const time = new Date(now).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: showSeconds ? "2-digit" : undefined });
  return <>
    <Settings>
      <Section title="Display" footer="Settings are stored on this Mac with useStoredState.">
        <Toggle label="Show seconds" value={showSeconds} onChange={setShowSeconds} />
      </Section>
    </Settings>
    <Activity id="main" title="{{displayName}}">
      <Activity.Compact leading={<Symbol name="sparkles" />} trailing={<Text>{count}</Text>} />
      <Activity.Expanded>
        <Text size="title">{time}</Text>
        <Text tone="secondary">{`Pressed ${count} times`}</Text>
        <Button title="Press" tone="accent" onPress={() => setCount(count + 1)} />
      </Activity.Expanded>
    </Activity>
  </>;
}
start(<Extension />);
