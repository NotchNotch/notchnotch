import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmod, cp, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { checkPackage, validateManifest } from "../packages/cli/src/index.mjs";
import { helperApp } from "../packages/cli/src/native.mjs";

async function temporary(t) {
  const directory = await mkdtemp(path.join(tmpdir(), "notchnotch-cli-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}
const cli = (...args) => spawnSync(process.execPath, ["packages/cli/bin/notchnotch.mjs", ...args], { encoding: "utf8" });

test("notchnotch build packages an extension that resolves the SDK from its own folder", async (t) => {
  const out = path.join(await temporary(t), "focus");
  const result = cli("build", "examples/focus-timer", "--out", out);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(await checkPackage(out), []);
  const manifest = JSON.parse(await readFile(path.join(out, "notchnotch.json"), "utf8"));
  assert.equal(manifest.id, "dev.notchnotch.example.focus");
  assert.match(await readFile(path.join(out, "bundle.js"), "utf8"), /Focus/);
  assert.equal(cli("check", out).status, 0);
});

test("notchnotch build refuses to replace a folder that is not a previous build", async (t) => {
  const out = await temporary(t);
  await writeFile(path.join(out, "keep.txt"), "important");
  const result = cli("build", "examples/focus-timer", "--out", out);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Refusing to replace/);
  assert.equal(await readFile(path.join(out, "keep.txt"), "utf8"), "important");
});

test("checkPackage reports what the app's installer would reject", async (t) => {
  const directory = await temporary(t);
  await writeFile(path.join(directory, "notchnotch.json"), JSON.stringify({
    id: "dev.test.tool", name: "Tool", version: "1", apiVersion: 1, entry: "bundle.js", permissions: ["process"],
    connections: { tool: { transport: "stdio", executable: "./helpers/tool" } },
  }));
  await writeFile(path.join(directory, "bundle.js"), "void 0;");
  await symlink("/etc/hosts", path.join(directory, "link"));
  const problems = (await checkPackage(directory)).join("\n");
  assert.match(problems, /Symbolic links/);
  assert.match(problems, /missing or non-executable helper/);
  await rm(path.join(directory, "link"));
  await mkdir(path.join(directory, "helpers"));
  await writeFile(path.join(directory, "helpers/tool"), "#!/bin/sh\n");
  await chmod(path.join(directory, "helpers/tool"), 0o755);
  assert.deepEqual(await checkPackage(directory), []);
});

test("helperApp writes usage descriptions so the helper can ask for its own privacy access", async (t) => {
  const destination = await temporary(t);
  const executable = await helperApp({
    destination, name: "Adapter", binary: "/usr/bin/true", bundleIdentifier: "dev.test.adapter",
    usageDescriptions: { NSContactsUsageDescription: "Show <favorite> contacts & birthdays." },
  });
  assert.equal(executable, "./helpers/Adapter.app/Contents/MacOS/Adapter");
  const plist = await readFile(path.join(destination, "helpers/Adapter.app/Contents/Info.plist"), "utf8");
  assert.match(plist, /<key>NSContactsUsageDescription<\/key><string>Show &lt;favorite&gt; contacts &amp; birthdays.<\/string>/);
  assert.equal(spawnSync("codesign", ["--verify", path.join(destination, "helpers/Adapter.app")]).status, 0);
  await assert.rejects(helperApp({ destination, name: "Bad", binary: "/usr/bin/true", bundleIdentifier: "dev.test.bad",
    usageDescriptions: { "NSContacts</key><key>x": "x" } }));
});

test("manifest imageHosts accept DNS names and subdomain wildcards only", () => {
  const base = { id: "dev.test.player", name: "Player", version: "1", apiVersion: 1, entry: "bundle.js", permissions: [] };
  validateManifest({ ...base, imageHosts: ["i.ytimg.com", "*.mzstatic.com"] });
  for (const imageHosts of [["*.com"], ["*"], ["localhost"], ["127.0.0.1"], ["I.YTIMG.COM"], ["https://i.ytimg.com"],
    ["a.example.com", "a.example.com"], Array.from({ length: 9 }, (_, i) => `h${i}.example.com`), "i.ytimg.com"]) {
    assert.throws(() => validateManifest({ ...base, imageHosts }), undefined, JSON.stringify(imageHosts));
  }
});

test("bundled helpers are app bundles that declare their own usage descriptions", async () => {
  // Built by `pnpm test` before these tests run.
  const music = await readFile("dist/extensions/music/helpers/MusicAdapter.app/Contents/Info.plist", "utf8");
  const calendar = await readFile("dist/extensions/calendar/helpers/CalendarAdapter.app/Contents/Info.plist", "utf8");
  assert.match(music, /NSAppleEventsUsageDescription/);
  assert.match(calendar, /NSCalendarsFullAccessUsageDescription/);
  const manifest = JSON.parse(await readFile("dist/extensions/music/notchnotch.json", "utf8"));
  assert.deepEqual(manifest.imageHosts, ["i.scdn.co", "mosaic.scdn.co", "*.mzstatic.com"]);
});
