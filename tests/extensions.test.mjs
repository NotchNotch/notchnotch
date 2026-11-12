import { after, before, test } from "node:test";
import { build } from "esbuild";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import path from "node:path";
import { root } from "../scripts/build-extensions.mjs";

// Exercise the runtime without shipping test activities as installed extensions.
let fixtureDirectory;
before(async () => {
  fixtureDirectory = await mkdtemp(path.join(tmpdir(), "notchnotch-runtime-"));
  await build({
    absWorkingDir: root,
    entryPoints: ["tests/fixtures/runtime.tsx"],
    outfile: path.join(fixtureDirectory, "bundle.js"),
    bundle: true, format: "iife", platform: "neutral", target: "es2022",
    mainFields: ["module", "main"], conditions: ["default"], jsx: "automatic",
    define: { "process.env.NODE_ENV": '"production"' },
  });
});
after(async () => {
  if (fixtureDirectory) await rm(fixtureDirectory, { recursive: true, force: true });
});
function launchFixture() {
  return launchProcess(path.join(root, ".build/debug/ExtensionRunner"),
    [path.join(fixtureDirectory, "bundle.js"), "test.runtime"]);
}

function launch(name, id, storage) {
  return launchProcess(path.join(root, ".build/debug/ExtensionRunner"),
    [path.join(root, "dist/extensions", name, "bundle.js"), id, ...(storage ? [storage] : [])]);
}
function launchProcess(executable, args) {
  const child = spawn(executable, args);
  const messages = [];
  const waiters = new Set();
  let stderr = "";
  let exited = false;
  createInterface({ input: child.stdout }).on("line", (line) => {
    const message = JSON.parse(line);
    messages.push(message);
    for (const notify of waiters) notify();
  });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.on("exit", () => { exited = true; for (const notify of waiters) notify(); });
  child.on("error", (error) => { stderr += error.message; exited = true; for (const notify of waiters) notify(); });
  return {
    child, messages,
    send(action, value) { child.stdin.write(JSON.stringify({ protocolVersion: 1, type: "event", action, value }) + "\n"); },
    message(message) { child.stdin.write(JSON.stringify({ protocolVersion: 1, ...message }) + "\n"); },
    wait(predicate) { return this.waitMessage((message) => message.type === "snapshot" && predicate(message)); },
    waitMessage(predicate) {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { waiters.delete(check); reject(new Error(`Runner timeout: ${stderr}; ${JSON.stringify(messages.slice(-2))}`)); }, 6000);
        function check() {
          const error = messages.find((message) => message.type === "error");
          const found = messages.find(predicate);
          if (error || found || exited) {
            clearTimeout(timer); waiters.delete(check);
            if (error || !found) reject(new Error(error?.message ?? `Runner exited: ${stderr}`));
            else resolve(found);
          }
        }
        waiters.add(check); check();
      });
    },
    async stop() {
      if (exited) return;
      child.stdin.end();
      await new Promise((resolve) => child.on("exit", resolve));
    },
  };
}
function nodes(node) { return [node, ...node.children.flatMap(nodes)]; }
/** Extensions try a silent reconnect at launch; answer it as "no stored grant". */
async function denySilentOpen(runner) {
  const silent = await runner.waitMessage((message) => message.operation === "open" && message.interactive === false);
  runner.message({ type: "connectionResponse", requestID: silent.requestID,
    error: "Connection access is required. Connect from the extension's settings." });
  await runner.waitMessage((message) => message.operation === "close" && message.sessionID === silent.sessionID);
  return silent;
}
function findToggle(tree, title) {
  const item = tree && nodes(tree).find((node) => node.type === "listItem" && node.props.text === title);
  return item && nodes(item).find((node) => node.type === "toggle");
}
function toggle(tree, title) {
  const control = findToggle(tree, title);
  assert.ok(control?.props.action, `Missing toggle: ${title}`);
  return control;
}
function action(surface, title) {
  const button = nodes(surface.expanded).find((node) => node.type === "button" && node.props.text === title);
  assert.ok(button?.props.action, `Missing action: ${title}`);
  return button.props.action;
}

test("React timer runs inside JavaScriptCore and round-trips actions across the process boundary", async () => {
  const runner = launchFixture();
  try {
    const initial = await runner.wait((message) => message.surfaces[0]?.phase === "paused");
    assert.equal(initial.protocolVersion, 1);
    assert.equal(initial.extensionID, "test.runtime");
    assert.equal(initial.surfaces[0].compact.trailing[0].props.text, "5");
    assert.deepEqual(initial.surfaces[0].peek, {
      id: "ready", text: "Runtime ready", duration: 4,
    });
    runner.send(action(initial.surfaces[0], "Start"));
    const running = await runner.wait((message) => message.surfaces[0]?.phase === "active");
    const ticked = await runner.wait((message) => message.revision > running.revision && message.surfaces[0]?.compact.trailing[0].props.text !== "5");
    // Live progress retains the event id, so the host's deadline stays fixed.
    assert.deepEqual(ticked.surfaces[0].peek, initial.surfaces[0].peek);
    runner.send(action(ticked.surfaces[0], "Pause"));
    const paused = await runner.wait((message) => message.revision > ticked.revision && message.surfaces[0]?.phase === "paused");
    runner.send(action(paused.surfaces[0], "Reset"));
    const reset = await runner.wait((message) => message.revision > paused.revision && message.surfaces[0]?.compact.trailing[0].props.text === "5");
    assert.equal(reset.surfaces[0].phase, "paused");
  } finally { await runner.stop(); }
});

test("An expanded-only prompt accepts text and resolves without removing the activity", async () => {
  const runner = launchFixture();
  try {
    const initial = await runner.wait((message) => message.surfaces.length === 1);
    runner.send(action(initial.surfaces[0], "Ask"));
    const question = await runner.wait((message) => message.surfaces.some((surface) => surface.kind === "prompt"));
    const prompt = question.surfaces.find((surface) => surface.kind === "prompt");
    assert.equal(prompt.initialView, "expanded");
    assert.equal(prompt.compact, undefined);
    const input = nodes(prompt.expanded).find((node) => node.type === "textField");
    runner.send(input.props.action, "Building NotchNotch");
    const typed = await runner.wait((message) => message.revision > question.revision && message.surfaces.some((surface) =>
      nodes(surface.expanded).some((node) => node.type === "textField" && node.props.text === "Building NotchNotch")));
    runner.send(action(typed.surfaces.find((surface) => surface.kind === "prompt"), "Save"));
    const resolved = await runner.wait((message) => message.revision > typed.revision && message.surfaces.length === 1);
    assert.ok(nodes(resolved.surfaces[0].expanded).some((node) => node.props.text === "Building NotchNotch"));
    assert.equal(resolved.surfaces[0].kind, "activity");
  } finally { await runner.stop(); }
});

test("Unknown action identifiers do not execute extension callbacks", async () => {
  const runner = launchFixture();
  try {
    const initial = await runner.wait((message) => message.surfaces.length === 1);
    runner.send("not-an-action");
    runner.send(action(initial.surfaces[0], "Start"));
    const running = await runner.wait((message) => message.surfaces[0]?.phase === "active");
    assert.equal(running.revision, initial.revision + 1);
  } finally { await runner.stop(); }
});


test("Music connects through the generic SDK, receives state, and sends playback RPCs", async () => {
  const runner = launch("music", "dev.notchnotch.music");
  const state = { id: "spotify:track:example", eventID: "playback-1", player: "com.spotify.client", playerName: "Spotify",
    title: "Thisavros Mou", artist: "Katerina", album: "Thisavros Mou", duration: 204,
    position: 12, isPlaying: true, volume: 0.6, shuffle: false, repeating: false,
    updatedAt: Date.now() / 1000 };
  const status = (state) => ({ state, authorized: ["com.spotify.client"], errors: {} });
  function acknowledge(command) {
    runner.message({ type: "connectionResponse", requestID: command.requestID, result: null });
  }
  function incoming(sessionID, message) {
    runner.message({ type: "connectionEvent", connectionID: "capability:now-playing", sessionID, event: "message", message });
  }
  try {
    const initial = await runner.wait((message) => !!message.settings);
    assert.deepEqual(initial.surfaces, []);
    assert.ok(nodes(initial.settings).some((node) => node.props.text === "Connect Spotify"));
    await denySilentOpen(runner);
    runner.send(action({ expanded: initial.settings }, "Connect Spotify"));
    const open = await runner.waitMessage((message) => message.type === "connectionCommand" && message.operation === "open" && message.interactive !== false);
    assert.equal(open.connectionID, "capability:now-playing");
    acknowledge(open);
    const get = await runner.waitMessage((message) => message.message?.method === "music/getState");
    acknowledge(get);
    incoming(open.sessionID, { jsonrpc: "2.0", id: get.message.id, result: status(state) });
    const connect = await runner.waitMessage((message) => message.message?.method === "music/connect");
    assert.deepEqual(connect.message.params, { player: "com.spotify.client" });
    acknowledge(connect);
    incoming(open.sessionID, { jsonrpc: "2.0", id: connect.message.id, result: status(state) });
    const playing = await runner.wait((message) => message.surfaces[0]?.phase === "active");
    const surface = playing.surfaces[0];
    assert.equal(surface.idlePreview, true);
    assert.equal(surface.compact.leading[0].type, "artwork");
    assert.equal(surface.compact.trailing[0].type, "waveform");
    assert.equal(surface.peek.id, state.eventID);
    assert.equal(surface.peek.text, "Katerina • Thisavros Mou");
    const player = nodes(surface.expanded).find((node) => node.type === "player");
    assert.equal(player.props.media.title, state.title);
    assert.equal(nodes(surface.expanded).some((node) => /Connect|Players/.test(node.props.text ?? "")), false);
    assert.ok(nodes(playing.settings).some((node) => node.props.text === "Connect Apple Music"));
    runner.send(player.props.action, JSON.stringify({ command: "seek", value: 0.5 }));
    const command = await runner.waitMessage((message) => message.message?.method === "music/command");
    assert.equal(command.type, "connectionCommand");
    assert.equal(command.extensionID, "dev.notchnotch.music");
    assert.deepEqual(command.message.params, { command: "seek", value: 0.5 });
    acknowledge(command);
    incoming(open.sessionID, { jsonrpc: "2.0", id: command.message.id, result: null });
    incoming(open.sessionID, { jsonrpc: "2.0", method: "music/state", params: status({ ...state, position: 13 }) });
    const tick = await runner.wait((message) => message.revision > playing.revision &&
      nodes(message.surfaces[0].expanded).some((node) => node.props.media?.position === 13));
    assert.equal(tick.surfaces[0].peek.id, state.eventID);
    incoming(open.sessionID, { method: "music/state", params: status({ ...state, isPlaying: false }) });
    const paused = await runner.wait((message) => message.revision > tick.revision && message.surfaces[0]?.phase === "paused");
    assert.equal(paused.surfaces[0].compact.trailing[0].props.name, "pause.fill");
    const artwork = "data:image/jpeg;base64," + "a".repeat(24000);
    incoming(open.sessionID, { method: "music/state", params: status({ ...state, artwork, eventID: "playback-2" }) });
    const art = await runner.wait((message) => message.surfaces[0]?.peek?.id === "playback-2");
    assert.equal(art.surfaces[0].compact.leading[0].props.source, artwork);
    incoming(open.sessionID, { method: "music/state", params: { ...status(state), commandError: "Player unavailable" } });
    await runner.wait((message) => message.revision > art.revision &&
      nodes(message.surfaces[0].expanded).some((node) => node.props.text === "Player unavailable"));
    runner.message({ type: "connectionEvent", connectionID: "capability:now-playing", sessionID: open.sessionID, event: "closed" });
    await runner.wait((message) => message.revision > art.revision &&
      message.surfaces.length === 0 && nodes(message.settings).some((node) => node.props.text === "Connect Spotify"));
    assert.equal(runner.messages.filter((message) => message.operation === "open" && message.interactive !== false).length, 1);
    assert.equal(runner.messages.some((message) => message.type === "mediaCommand"), false);
  } finally { await runner.stop(); }
});

test("Focus Timer example renders settings components and starts a session", async () => {
  const runner = launch("focus-timer", "dev.notchnotch.example.focus");
  try {
    const initial = await runner.wait((message) => !!message.settings);
    assert.deepEqual(initial.surfaces, []);
    const picker = nodes(initial.settings).find((node) => node.type === "picker");
    assert.equal(picker.props.selection, "25");
    assert.deepEqual(picker.props.options.map((option) => option.value), ["15", "25", "50"]);

    runner.send(picker.props.action, "15");
    const shorter = await runner.wait((message) =>
      nodes(message.settings).some((node) => node.type === "picker" && node.props.selection === "15"));
    assert.ok(nodes(shorter.settings).some((node) => node.type === "toggle" && node.props.value === 1));

    runner.send(action({ expanded: shorter.settings }, "Start Focus"));
    const running = await runner.wait((message) => message.surfaces[0]?.id === "session");
    assert.equal(running.surfaces[0].compact.trailing[0].props.text, "15:00");
    const timer = nodes(running.surfaces[0].expanded).find((node) => node.type === "value");
    assert.deepEqual([timer.props.text, timer.props.unit], ["15:00", "left"]);
    const ring = nodes(running.surfaces[0].expanded).find((node) => node.type === "ring");
    assert.equal(ring.props.value, 0);
    assert.equal(ring.children[0].type, "symbol");
    assert.equal(running.surfaces[0].compact.leading[0].type, "ring");
  } finally { await runner.stop(); }
});

test("Music reconnects silently at launch when access was always allowed", async () => {
  const runner = launch("music", "dev.notchnotch.music");
  const state = { id: "spotify:track:resume", eventID: "playback-9", player: "com.spotify.client", playerName: "Spotify",
    title: "Resume", artist: "Artist", album: "Album", duration: 100, position: 5, isPlaying: false, volume: 0.5,
    shuffle: false, repeating: false, updatedAt: Date.now() / 1000 };
  try {
    const silent = await runner.waitMessage((message) => message.operation === "open" && message.interactive === false);
    runner.message({ type: "connectionResponse", requestID: silent.requestID, result: null });
    const get = await runner.waitMessage((message) => message.message?.method === "music/getState");
    runner.message({ type: "connectionResponse", requestID: get.requestID, result: null });
    runner.message({ type: "connectionEvent", connectionID: "capability:now-playing", sessionID: silent.sessionID, event: "message",
      message: { jsonrpc: "2.0", id: get.message.id, result: { state, authorized: ["com.spotify.client"], errors: {} } } });
    const resumed = await runner.wait((message) => message.surfaces[0]?.id === "now-playing");
    assert.equal(resumed.surfaces[0].phase, "paused");
    assert.equal(runner.messages.some((message) => message.message?.method === "music/connect"), false);
  } finally { await runner.stop(); }
});

test("Extension storage persists across runner restarts", async () => {
  const storage = path.join(fixtureDirectory, "focus-storage.json");
  let runner = launch("focus-timer", "dev.notchnotch.example.focus", storage);
  try {
    const initial = await runner.wait((message) => !!message.settings);
    const picker = nodes(initial.settings).find((node) => node.type === "picker");
    runner.send(picker.props.action, "50");
    await runner.wait((message) => nodes(message.settings).some((node) => node.type === "picker" && node.props.selection === "50"));
    // The runner writes no files; it hands storage to the app, which this test plays.
    const saved = await runner.waitMessage((message) => message.type === "storage" && message.values.minutes === "50");
    assert.equal(saved.extensionID, "dev.notchnotch.example.focus");
    const { writeFile } = await import("node:fs/promises");
    await writeFile(storage, JSON.stringify(saved.values));
  } finally { await runner.stop(); }
  runner = launch("focus-timer", "dev.notchnotch.example.focus", storage);
  try {
    const restored = await runner.wait((message) => !!message.settings);
    assert.equal(nodes(restored.settings).find((node) => node.type === "picker").props.selection, "50");
  } finally { await runner.stop(); }
});

test("The runner answers pings only while JavaScript is responsive", async () => {
  const { writeFile } = await import("node:fs/promises");
  const healthy = launchFixture();
  try {
    await healthy.wait((message) => message.surfaces.length > 0);
    healthy.child.stdin.write(JSON.stringify({ protocolVersion: 1, type: "ping", id: 7 }) + "\n");
    const pong = await healthy.waitMessage((message) => message.type === "pong");
    assert.deepEqual(pong, { protocolVersion: 1, type: "pong", extensionID: "test.runtime", id: 7 });
  } finally { await healthy.stop(); }

  const busyBundle = path.join(fixtureDirectory, "busy.js");
  await writeFile(busyBundle, "setTimeout(() => { for (;;) {} }, 50);");
  const busy = launchProcess(path.join(root, ".build/debug/ExtensionRunner"), [busyBundle, "test.busy"]);
  try {
    await new Promise((resolve) => setTimeout(resolve, 300));
    busy.child.stdin.write(JSON.stringify({ protocolVersion: 1, type: "ping", id: 1 }) + "\n");
    await new Promise((resolve) => setTimeout(resolve, 700));
    assert.equal(busy.messages.some((message) => message.type === "pong"), false);
  } finally { busy.child.kill("SIGKILL"); }
});

test("a runner started with --preferences runs the extension with them, after earlier messages", async (t) => {
  const outfile = path.join(fixtureDirectory, "preferences.js");
  await build({
    absWorkingDir: root,
    stdin: { contents: `
      import { Activity, Text, getPreferenceValues } from "@notchnotch/sdk";
      import { start } from "@notchnotch/runtime";
      const { greeting, loud } = getPreferenceValues();
      start(<Activity id="hello" title={String(greeting) + (loud ? "!" : "")} initialView="expanded">
        <Activity.Expanded><Text>{String(greeting)}</Text></Activity.Expanded>
      </Activity>);`, loader: "tsx", resolveDir: root },
    outfile, bundle: true, format: "iife", platform: "neutral", target: "es2022",
    mainFields: ["module", "main"], conditions: ["default"], jsx: "automatic",
    define: { "process.env.NODE_ENV": '"production"' },
  });
  const runner = launchProcess(path.join(root, ".build/debug/ExtensionRunner"), [outfile, "test.preferences", "--preferences"]);
  t.after(() => runner.stop());
  runner.message({ type: "ping", id: 7 });
  runner.message({ type: "preferences", values: { greeting: "Hello", loud: true } });
  const snapshot = await runner.wait(() => true);
  assert.equal(snapshot.surfaces[0].title, "Hello!");
  await runner.waitMessage((message) => message.type === "pong" && message.id === 7);
});

test("the runner's sandbox blocks files, network and processes once it is entered", async (t) => {
  const { mkdtemp, writeFile, readdir } = await import("node:fs/promises");
  const directory = await mkdtemp(path.join(tmpdir(), "notchnotch-sandbox-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const secret = path.join(directory, "secret.txt");
  await writeFile(secret, "secret");
  const probe = launchProcess(path.join(root, ".build/debug/ExtensionRunner"), ["--sandbox-probe", secret, directory]);
  const result = await probe.waitMessage((message) => "readUserFile" in message);
  assert.deepEqual(result, {
    readBeforeSandbox: true, readSystem: true,
    readUserFile: false, writeFile: false, listHome: false, network: false, spawn: false,
  });
  assert.deepEqual(await readdir(directory), ["secret.txt"]);
});

