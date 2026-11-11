import { access, mkdir, readdir, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildExtension } from "../packages/cli/src/index.mjs";

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
/** Folder names of the extensions bundled with the app: those with a manifest, so a leftover folder doesn't count. */
export async function bundledExtensionNames() {
  const folders = (await readdir(path.join(root, "extensions"), { withFileTypes: true })).filter((entry) => entry.isDirectory());
  const names = [];
  for (const { name } of folders) {
    if (await access(path.join(root, "extensions", name, "notchnotch.json")).then(() => true, () => false)) names.push(name);
  }
  return names.sort();
}

/** Builds `extensions/*` (and `examples/*` when requested) into dist/extensions. */
export async function buildExtensions({ watch = false, examples = false } = {}) {
  const contexts = [];
  const sources = (await bundledExtensionNames()).map((name) => ({ name, source: path.join(root, "extensions", name) }));
  if (examples) {
    for (const entry of await readdir(path.join(root, "examples"), { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      if (sources.some((item) => item.name === entry.name)) throw new Error(`Example name collides with an extension: ${entry.name}`);
      sources.push({ name: entry.name, source: path.join(root, "examples", entry.name) });
    }
  }
  const names = sources.map((item) => item.name);
  const output = path.join(root, "dist/extensions");
  await mkdir(output, { recursive: true });
  for (const name of await readdir(output)) {
    if (!names.includes(name)) await rm(path.join(output, name), { recursive: true, force: true });
  }
  for (const { name, source } of sources) {
    // Same build path as third-party extensions; `root` lets bundled helpers
    // reuse this repository's SwiftPM build and lets esbuild resolve the workspace.
    const instance = await buildExtension({ source, destination: path.join(output, name), watch, root });
    if (instance) contexts.push(instance);
  }
  return contexts;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) await buildExtensions({ examples: process.argv.includes("--examples") });
