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
  for (const file of ["src/index.tsx", "README.md", "CHANGELOG.md"]) {
    assert.doesNotMatch(await readFile(path.join(target, file), "utf8"), /\{\{/, file);
  }
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
  assert.match(await readFile(path.join(out, "README.md"), "utf8"), /About/);
  assert.match(await readFile(path.join(out, "CHANGELOG.md"), "utf8"), /## \[0\.1\.0\]/);
  const runner = spawnSync(process.execPath, ["-e", `
    globalThis.__notchnotchExtensionID = "com.example.templatecheck";
    globalThis.__notchnotchSend = (json) => { const m = JSON.parse(json); if (m.type === "snapshot") { console.log(JSON.stringify(m.surfaces.map(s => s.id))); process.exit(0); } };
    require(${JSON.stringify(path.join(out, "bundle.js"))});`], { encoding: "utf8", timeout: 10_000 });
  assert.equal(runner.stdout.trim(), '["main"]', runner.stderr);
});

test("the template typechecks against the packed npm packages", async (t) => {
  // Install exactly what npm users get: the packed tarballs with their
  // publishConfig, built declarations and package.json rewrites.
  const { buildPackages } = await import("../scripts/build-packages.mjs");
  await buildPackages();
  const directory = await temporary(t);
  const target = await create({ folder: path.join(directory, "typed") });
  const modules = path.join(target, "node_modules");
  await mkdir(path.join(modules, "@notchnotch"), { recursive: true });
  for (const name of ["protocol", "react-renderer", "runtime", "sdk"]) {
    const pack = spawnSync("pnpm", ["pack", "--pack-destination", directory], { cwd: path.resolve("packages", name), encoding: "utf8" });
    assert.equal(pack.status, 0, pack.stderr);
    const tarball = path.join(directory, `notchnotch-${name}-${JSON.parse(await readFile(path.resolve("packages", name, "package.json"), "utf8")).version}.tgz`);
    const destination = path.join(modules, "@notchnotch", name);
    await mkdir(destination);
    assert.equal(spawnSync("tar", ["-xzf", tarball, "-C", destination, "--strip-components", "1"]).status, 0);
  }
  await symlink(path.resolve("node_modules/react"), path.join(modules, "react"));
  await mkdir(path.join(modules, "@types"));
  await symlink(path.resolve("node_modules/@types/react"), path.join(modules, "@types/react"));
  const tsc = spawnSync(path.resolve("node_modules/.bin/tsc"), ["--noEmit", "-p", target], { encoding: "utf8" });
  assert.equal(tsc.status, 0, tsc.stdout + tsc.stderr);
});
