import { test } from "node:test";
import assert from "node:assert/strict";
import { build } from "esbuild";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

// API v1's surface: these break extensions if they change, so changing one is an API v2 decision.
async function sdk(t) {
  const directory = await mkdtemp(path.join(tmpdir(), "notchnotch-sdk-api-"));
  const outfile = path.join(directory, "sdk.mjs");
  await build({ entryPoints: ["packages/sdk/src/index.tsx"], outfile, bundle: true, platform: "node", format: "esm", logLevel: "silent" });
  t.after(() => rm(directory, { recursive: true, force: true }));
  return import(pathToFileURL(outfile).href);
}

test("an activity is paused unless it asks to be live", async (t) => {
  const { Activity } = await sdk(t);
  assert.equal(Activity({ id: "a", title: "A" }).props.phase, "paused");
  assert.equal(Activity({ id: "a", title: "A", phase: "active" }).props.phase, "active");
});

test("Icon draws a symbol, and the deprecated Symbol is the same component", async (t) => {
  const { Icon, Symbol } = await sdk(t);
  assert.equal(Icon({ name: "timer" }).type, "symbol");
  assert.equal(Symbol, Icon);
});

test("the SDK's channel to the app is not part of the API", async (t) => {
  const exports = await sdk(t);
  assert.equal("command" in exports, false);
  assert.equal("nextSerial" in exports, false);
  assert.equal("listeners" in exports, false);
});
