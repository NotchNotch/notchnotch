import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { create } from "../packages/create-notchnotch-extension/bin/create.mjs";
import { buildExtension, checkPackage } from "../packages/cli/src/index.mjs";

async function temporary(t) {
  const directory = await mkdtemp(path.join(tmpdir(), "notchnotch-create-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

test("create writes a named project whose manifest validates", async (t) => {
  const target = await create({ folder: path.join(await temporary(t), "focus-buddy"), sdkVersion: "1.2.3" });
  const manifest = JSON.parse(await readFile(path.join(target, "notchnotch.json"), "utf8"));
  assert.equal(manifest.name, "Focus Buddy");
  assert.equal(manifest.id, "com.example.focusbuddy");
  const pkg = JSON.parse(await readFile(path.join(target, "package.json"), "utf8"));
  assert.equal(pkg.dependencies["@notchnotch/sdk"], "^1.2.3");
  assert.equal(pkg.devDependencies["@notchnotch/cli"], "^1.2.3");
  assert.match(await readFile(path.join(target, ".gitignore"), "utf8"), /dist/);
  assert.doesNotMatch(await readFile(path.join(target, "src/index.tsx"), "utf8"), /\{\{/);
});

test("create refuses bad identifiers, quotes in names and non-empty folders", async (t) => {
  const directory = await temporary(t);
  await assert.rejects(create({ folder: path.join(directory, "a"), id: "Com.Example" }), /Invalid id/);
  await assert.rejects(create({ folder: path.join(directory, "b"), name: 'Bad "name"' }), /quotes/);
  await writeFile(path.join(directory, "keep.txt"), "x");
  await assert.rejects(create({ folder: directory }), /not empty/);
});

test("the template builds into an installable package", async (t) => {
  const target = await create({ folder: path.join(await temporary(t), "template-check") });
  // Stand in for `npm install` with this checkout's packages.
  const modules = path.join(target, "node_modules");
  await mkdir(path.join(modules, "@notchnotch"), { recursive: true });
  for (const name of ["sdk", "runtime", "protocol", "react-renderer"]) {
    await symlink(path.resolve("packages", name), path.join(modules, "@notchnotch", name));
  }
  await symlink(path.resolve("node_modules/react"), path.join(modules, "react"));
  const out = path.join(target, "dist");
  await buildExtension({ source: target, destination: out, logLevel: "silent" });
  assert.deepEqual(await checkPackage(out), []);
  const runner = spawnSync(process.execPath, ["-e", `
    globalThis.__notchnotchExtensionID = "com.example.templatecheck";
    globalThis.__notchnotchSend = (json) => { const m = JSON.parse(json); if (m.type === "snapshot") { console.log(JSON.stringify(m.surfaces.map(s => s.id))); process.exit(0); } };
    require(${JSON.stringify(path.join(out, "bundle.js"))});`], { encoding: "utf8", timeout: 10_000 });
  assert.equal(runner.stdout.trim(), '["main"]', runner.stderr);
});
