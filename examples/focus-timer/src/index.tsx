import { useEffect, useState } from "react";
import {
  Actions, Activity, Badge, Button, Column, ListItem, Picker, Prompt, Ring, Row, Section, Settings,
  Spacer, Symbol, Text, Toggle, Value, useStoredState,
} from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

// Example extension: shows an Activity with a progress ring and a live
// reading, a Settings page built from sections, and a Prompt that asks
// before starting a break.

type Phase = "idle" | "focus" | "break";
const durations = [
  { value: "15", label: "15 min" },
  { value: "25", label: "25 min" },
  { value: "50", label: "50 min" },
] as const;
type Duration = (typeof durations)[number]["value"];

function clock(seconds: number) {
  const value = Math.max(0, Math.ceil(seconds));
  return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, "0")}`;
}

function FocusTimer() {
  // Preferences survive app restarts through extension storage.
  const [minutes, setMinutes] = useStoredState<Duration>("minutes", "25");
  const [askBeforeBreak, setAskBeforeBreak] = useStoredState<boolean>("askBeforeBreak", true);
  const [phase, setPhase] = useState<Phase>("idle");
  const [paused, setPaused] = useState(false);
  const [remaining, setRemaining] = useState(0);
  const [total, setTotal] = useState(1);
  const [completed, setCompleted] = useState(0);
  const [asking, setAsking] = useState(false);

  function begin(next: Exclude<Phase, "idle">) {
    const seconds = next === "focus" ? Number(minutes) * 60 : 5 * 60;
    setPhase(next); setPaused(false); setRemaining(seconds); setTotal(seconds); setAsking(false);
  }
  function stop() { setPhase("idle"); setPaused(false); setAsking(false); }

  const running = phase !== "idle" && !paused && !asking;
  useEffect(() => {
    if (!running) return;
    const timer = setInterval(() => setRemaining((value) => value - 1), 1000);
    return () => clearInterval(timer);
  }, [running]);

  useEffect(() => {
    if (phase === "idle" || remaining > 0) return;
    if (phase === "focus") {
      setCompleted((value) => value + 1);
      if (askBeforeBreak) setAsking(true); else begin("break");
    } else stop();
  }, [remaining, phase]);

  const label = phase === "break" ? "Break" : "Focus";
  const tone = phase === "break" ? "success" : "accent";
  const progress = Math.min(1, Math.max(0, 1 - remaining / total));
  return <>
    <Settings>
      <Section title="Session" footer="Changes apply to the next session.">
        <Picker label="Focus length" options={durations} value={minutes} onChange={setMinutes} />
        <Toggle label="Ask before starting a break" value={askBeforeBreak} onChange={setAskBeforeBreak} />
      </Section>
      <Section title="Today">
        <ListItem icon="checkmark.circle" tone="success" title="Completed sessions">
          <Badge tone="success">{completed}</Badge>
        </ListItem>
        <Row><Button title="Start Focus" icon="play.fill" tone="accent" disabled={phase !== "idle"} onPress={() => begin("focus")} /></Row>
      </Section>
    </Settings>

    {phase !== "idle" ? <Activity id="session" title={label} phase={paused || asking ? "paused" : "active"}>
      <Activity.Compact
        leading={<Ring value={progress} tone={tone} label={`${label} session`} />}
        trailing={<Text size="caption" tone={tone}>{clock(remaining)}</Text>} />
      <Activity.Expanded>
        <Row spacing="loose">
          <Ring value={progress} size="title" tone={tone} label={`${label} session`}>
            <Symbol name={phase === "break" ? "cup.and.saucer.fill" : "timer"} tone={tone} />
          </Ring>
          <Column spacing="none">
            <Text size="caption" tone="secondary">{label.toUpperCase()}</Text>
            <Value unit="left" tone={paused ? "secondary" : tone}>{clock(remaining)}</Value>
          </Column>
          <Spacer />
          {paused ? <Badge tone="warning">Paused</Badge> : null}
        </Row>
        <Actions>
          <Button icon="stop.fill" label="Stop" tone="danger" onPress={stop} />
          <Button title={paused ? "Resume" : "Pause"} icon={paused ? "play.fill" : "pause.fill"} tone="accent"
            onPress={() => setPaused((value) => !value)} />
        </Actions>
      </Activity.Expanded>
    </Activity> : null}

    {asking ? <Prompt id="break" title="Focus session complete">
      <Prompt.Compact leading={<Symbol name="checkmark.circle.fill" tone="success" />} trailing={<Text size="caption">Break?</Text>} />
      <Prompt.Expanded>
        <Text tone="secondary">{`Nice work — that was session ${completed} today. Take a five-minute break?`}</Text>
        <Actions>
          <Button title="Skip" onPress={() => begin("focus")} />
          <Button title="Done for now" onPress={stop} />
          <Button title="Start Break" tone="accent" onPress={() => begin("break")} />
        </Actions>
      </Prompt.Expanded>
    </Prompt> : null}
  </>;
}
start(<FocusTimer />);
