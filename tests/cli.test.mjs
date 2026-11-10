import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmod, cp, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { checkPackage, titleCaseProblem, validateManifest } from "../packages/cli/src/index.mjs";
import { helperApp } from "../packages/cli/src/native.mjs";
import { developExtension } from "../packages/cli/src/dev.mjs";
import { publishPlan } from "../packages/cli/src/publish.mjs";

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

/** Only the signature and IHDR header matter to the CLI's check. */
const pngHeader = (width, height = width) => {
  const buffer = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buffer);
  buffer.writeUInt32BE(13, 8);
  buffer.write("IHDR", 12, "latin1");
  buffer.writeUInt32BE(width, 16);
  buffer.writeUInt32BE(height, 20);
  return buffer;
};

test("checkPackage requires a declared PNG icon to be 512×512, dark variant included", async (t) => {
  const directory = await temporary(t);
  await writeFile(path.join(directory, "notchnotch.json"), JSON.stringify({
    id: "dev.test.icon", name: "Icon", version: "1", apiVersion: 1, entry: "bundle.js", permissions: [], icon: "icon.png",
  }));
  await writeFile(path.join(directory, "bundle.js"), "void 0;");
  assert.match((await checkPackage(directory)).join("\n"), /assets\/icon.png is missing/);
  await mkdir(path.join(directory, "assets"));
  await writeFile(path.join(directory, "assets/icon.png"), pngHeader(256));
  assert.match((await checkPackage(directory)).join("\n"), /512×512 PNG/);
  await writeFile(path.join(directory, "assets/icon.png"), pngHeader(512));
  assert.deepEqual(await checkPackage(directory), []);
  await writeFile(path.join(directory, "assets/icon@dark.png"), "not a png");
  assert.match((await checkPackage(directory)).join("\n"), /icon@dark.png must be/);
  await writeFile(path.join(directory, "assets/icon@dark.png"), pngHeader(512));
  assert.deepEqual(await checkPackage(directory), []);
});

test("checkPackage rejects a README or CHANGELOG that is not UTF-8 text", async (t) => {
  const directory = await temporary(t);
  await writeFile(path.join(directory, "notchnotch.json"), JSON.stringify({
    id: "dev.test.docs", name: "Docs", version: "1", apiVersion: 1, entry: "bundle.js", permissions: [],
  }));
  await writeFile(path.join(directory, "bundle.js"), "void 0;");
  await writeFile(path.join(directory, "README.md"), "# Docs\n\nHello.");
  assert.deepEqual(await checkPackage(directory), []);
  await writeFile(path.join(directory, "CHANGELOG.md"), Buffer.from([0xff, 0xfe, 0x00]));
  assert.match((await checkPackage(directory)).join("\n"), /CHANGELOG.md must be a UTF-8 text file/);
  await writeFile(path.join(directory, "CHANGELOG.md"), "x".repeat(256 * 1024 + 1));
  assert.match((await checkPackage(directory)).join("\n"), /CHANGELOG.md must be/);
});

test("validateManifest accepts store metadata and rejects what the app rejects", () => {
  const base = { id: "dev.test.meta", name: "Meta", version: "1", apiVersion: 1, entry: "bundle.js", permissions: [] };
  validateManifest({ ...base, author: "jane-doe", categories: ["Media", "Productivity"], license: "MIT OR Apache-2.0",
    homepage: "https://example.com", repository: "https://github.com/example/repo" });
  for (const extra of [
    { author: "Jane Doe" }, { author: "-jane" }, { categories: [] }, { categories: ["Games"] }, { categories: ["Fun", "Fun"] },
    { categories: ["Fun", "Media", "News", "System"] }, { homepage: "http://example.com" }, { homepage: "javascript:alert(1)" },
    { repository: "https://user:secret@example.com" }, { license: "MIT; rm -rf" }, { license: "" },
  ]) assert.throws(() => validateManifest({ ...base, ...extra }), /Unsupported manifest/, JSON.stringify(extra));
});

test("validateManifest keeps PNG icon names inside assets/", () => {
  const base = { id: "dev.test.icon", name: "Icon", version: "1", apiVersion: 1, entry: "bundle.js", permissions: [] };
  for (const icon of ["../icon.png", "assets/icon.png", ".png", "icon@dark.png"]) {
    assert.throws(() => validateManifest({ ...base, icon }), /icon must be/, icon);
  }
  validateManifest({ ...base, icon: "icon.png" });
  validateManifest({ ...base, icon: "timer" });
});

test("titleCaseProblem follows the Apple Style Guide", () => {
  for (const title of ["Focus Timer", "Music", "Search in Database", "Notes for iOS", "macOS Battery", "Built With Love", "Things to Do", "2FA Codes"]) {
    assert.equal(titleCaseProblem(title), undefined, title);
  }
  assert.match(titleCaseProblem("focus timer"), /"Focus timer"/);
  assert.match(titleCaseProblem("Hacker news"), /"Hacker News"/);
  assert.match(titleCaseProblem("Made with care"), /"Made With care"/);
  assert.match(titleCaseProblem("Where to"), /"Where To"/);
});

test("developExtension registers the build with the app, forwards its log and unregisters on stop", async (t) => {
  const directory = await temporary(t);
  process.env.NOTCHNOTCH_DEVELOPMENT_DIR = path.join(directory, "Development");
  t.after(() => { delete process.env.NOTCHNOTCH_DEVELOPMENT_DIR; });
  const lines = [];
  const session = await developExtension({ source: "examples/focus-timer", destination: path.join(directory, "out"),
    logLevel: "silent", onLog: (level, message) => lines.push(`${level}:${message}`) });
  t.after(() => session.stop());
  const registration = path.join(directory, "Development", "dev.notchnotch.example.focus.json");
  assert.deepEqual(JSON.parse(await readFile(registration, "utf8")), { path: path.join(directory, "out"), pid: process.pid });
  assert.deepEqual(await checkPackage(path.join(directory, "out")), []);

  await writeFile(path.join(directory, "Development", "dev.notchnotch.example.focus.log"), "log\tstarted\nerror\tfailed\n\tsecond line\n");
  for (let i = 0; i < 40 && lines.length < 3; i++) await new Promise((resolve) => setTimeout(resolve, 50));
  assert.deepEqual(lines, ["log:started", "error:failed", "error:second line"]);

  await session.stop();
  await assert.rejects(readFile(registration));
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

test("the app carries every privacy entitlement and usage description its bundled helpers need", async () => {
  // TCC attributes code inside NotchNotch.app to the app itself, even with
  // responsibility disclaimed. A bundled helper's request is checked against
  // the app's entitlements and Info.plist, and is denied without a prompt if
  // either is missing (the Calendar failure in the first 0.3.0 build).
  const keys = (xml) => [...xml.matchAll(/<key>([^<]+)<\/key>/g)].map((match) => match[1]);
  const host = keys(await readFile("apps/macos/NotchNotch.entitlements", "utf8"));
  const packaging = await readFile("scripts/package-app.mjs", "utf8");
  for (const name of ["music", "calendar"]) {
    for (const key of keys(await readFile(`extensions/${name}/helper.entitlements`, "utf8"))) {
      assert.ok(host.includes(key), `NotchNotch.entitlements is missing ${key} used by ${name}`);
    }
    const builder = await readFile(`extensions/${name}/build.mjs`, "utf8");
    for (const [, key] of builder.matchAll(/(NS[A-Za-z]+UsageDescription)/g)) {
      assert.ok(packaging.includes(`<key>${key}</key>`), `The app's Info.plist is missing ${key} used by ${name}`);
    }
  }
});

test("notchnotch build --pack writes a .notchext with the package at its root", async (t) => {
  const directory = await mkdtemp(path.join(tmpdir(), "notchnotch-pack-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const out = path.join(directory, "dist");
  const result = cli("build", "examples/focus-timer", "--out", out, "--pack");
  assert.equal(result.status, 0, result.stderr);
  const file = path.join(directory, "dev.notchnotch.example.focus-0.1.0.notchext");
  const listing = spawnSync("/usr/bin/zipinfo", ["-1", file], { encoding: "utf8" });
  assert.equal(listing.status, 0, listing.stderr);
  const names = listing.stdout.trim().split("\n");
  assert.ok(names.includes("notchnotch.json") && names.includes("bundle.js"), names.join(", "));
  assert.ok(!names.some((name) => name.startsWith("__MACOSX") || name.includes("..")));
  // A package that fails the install checks is never packed.
  await writeFile(path.join(out, "notchnotch.json"), "{}");
  const bad = cli("pack", out, "--out", path.join(directory, "bad.notchext"));
  assert.notEqual(bad.status, 0);
});

test("notchnotch publish plans the Store folder and copies only source", async (t) => {
  const source = path.join(await temporary(t), "focus");
  await mkdir(path.join(source, "src"), { recursive: true });
  await mkdir(path.join(source, "node_modules/react"), { recursive: true });
  await mkdir(path.join(source, "dist"), { recursive: true });
  const manifest = { id: "dev.amir.focus", name: "Focus", version: "1.2.0", apiVersion: 1, entry: "bundle.js", permissions: [], author: "amir" };
  await writeFile(path.join(source, "notchnotch.json"), JSON.stringify(manifest));
  await writeFile(path.join(source, "package.json"), JSON.stringify({ name: "focus" }));
  for (const file of ["src/index.tsx", "README.md", "node_modules/react/index.js", "dist/bundle.js", ".DS_Store", "focus-1.2.0.notchext"]) {
    await writeFile(path.join(source, file), "x");
  }
  const plan = await publishPlan(source, "amir");
  assert.deepEqual(plan.problems, []);
  assert.equal(plan.handle, "amir/focus");
  assert.equal(plan.branch, "ext/amir/focus");
  assert.deepEqual(plan.files, ["README.md", "notchnotch.json", "package.json", "src/index.tsx"]);
  assert.deepEqual(plan.notes, []);

  // Someone else's extension: allowed, with a note that its author approves.
  assert.match((await publishPlan(source, "sara")).notes[0], /amir's extension/);

  await writeFile(path.join(source, "notchnotch.json"), JSON.stringify({ ...manifest, author: undefined }));
  await writeFile(path.join(source, "package.json"), JSON.stringify({ name: "Focus Timer" }));
  await writeFile(path.join(source, "build.mjs"), "export async function build() {}");
  await mkdir(path.join(source, "helpers"));
  const problems = (await publishPlan(source, "amir")).problems.join("\n");
  assert.match(problems, /"author": "amir"/);
  assert.match(problems, /isn't a valid Store address/);
  assert.match(problems, /custom build\.mjs/);
  assert.match(problems, /native helpers/);
});
