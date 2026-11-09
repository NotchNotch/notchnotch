import { build as esbuild, context } from "esbuild";
import { spawnSync } from "node:child_process";
import { access, constants, copyFile, cp, lstat, mkdir, readFile, readdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { validateManifest } from "./manifest.mjs";

export { validateManifest } from "./manifest.mjs";

const isFile = (file) => stat(file).then((value) => value.isFile(), () => false);
const isDirectory = (file) => stat(file).then((value) => value.isDirectory(), () => false);

export async function readManifest(source) {
  const manifest = JSON.parse(await readFile(path.join(source, "notchnotch.json"), "utf8"));
  validateManifest(manifest);
  return manifest;
}

/**
 * Builds one extension folder into an installable package:
 * `notchnotch.json`, `bundle.js` (from `src/index.tsx`), `helpers/`, `assets/`,
 * plus whatever an optional `build.mjs` writes.
 *
 * `build.mjs` may export `async build({ source, destination, root })`. It is
 * trusted development-time code and never part of the installed package.
 * Returns an esbuild context when `watch` is set.
 */
export async function buildExtension({ source, destination, watch = false, root, clean = true, logLevel = "info" }) {
  source = path.resolve(source);
  destination = path.resolve(destination);
  root = path.resolve(root ?? source);
  if (destination === source || source.startsWith(destination + path.sep)) throw new Error("Output must not contain the extension source");
  await readManifest(source);
  if (clean && (await readdir(destination).catch(() => [])).length) {
    // Only replace a previous build output, never an unrelated folder named by --out.
    if (!(await isFile(path.join(destination, "notchnotch.json")))) {
      throw new Error(`Refusing to replace ${destination}: it is not empty and is not a previous build`);
    }
    await rm(destination, { recursive: true, force: true });
  }
  await mkdir(destination, { recursive: true });
  const builder = path.join(source, "build.mjs");
  if (await isFile(builder)) await (await import(pathToFileURL(builder).href)).build({ source, destination, root });
  await copyFile(path.join(source, "notchnotch.json"), path.join(destination, "notchnotch.json"));
  for (const folder of ["helpers", "assets"]) {
    if (await isDirectory(path.join(source, folder))) await cp(path.join(source, folder), path.join(destination, folder), { recursive: true });
  }
  const options = {
    absWorkingDir: root,
    entryPoints: [path.join(source, "src/index.tsx")],
    outfile: path.join(destination, "bundle.js"),
    bundle: true, format: "iife", platform: "neutral", target: "es2022",
    mainFields: ["module", "main"], conditions: ["default"], jsx: "automatic",
    define: { "process.env.NODE_ENV": '"production"' },
    sourcemap: "linked", logLevel,
  };
  if (!watch) { await esbuild(options); return null; }
  const instance = await context(options);
  await instance.watch();
  return instance;
}

/**
 * Zips a built package into `<id>-<version>.notchext`, which NotchNotch installs
 * on double-click. Refuses packages that would fail the app's install checks.
 */
export async function packExtension({ directory, out }) {
  directory = path.resolve(directory);
  const problems = await checkPackage(directory);
  if (problems.length) throw new Error(problems.join("\n"));
  const manifest = await readManifest(directory);
  out = path.resolve(out ?? path.join(path.dirname(directory), `${manifest.id}-${manifest.version}.notchext`));
  if (out.startsWith(directory + path.sep)) throw new Error("Write the .notchext outside the package folder");
  await rm(out, { force: true });
  // zip keeps Unix permissions (executable helpers); -X drops macOS extended attributes.
  const result = spawnSync("/usr/bin/zip", ["-q", "-r", "-X", out, "."], { cwd: directory, encoding: "utf8" });
  if (result.status !== 0) throw new Error(`zip failed: ${result.stderr || result.error?.message}`);
  return out;
}

/** Mirrors the app's install checks so problems show up before **Install from Folder…**. */
export async function checkPackage(directory) {
  directory = path.resolve(directory);
  const problems = [];
  let manifest;
  try { manifest = await readManifest(directory); } catch (error) { return [String(error.message ?? error)]; }
  const manifestInfo = await stat(path.join(directory, "notchnotch.json"));
  if (manifestInfo.size > 65_536) problems.push("notchnotch.json is larger than 64 KiB");
  const entry = await lstat(path.join(directory, "bundle.js")).catch(() => null);
  if (!entry?.isFile() || entry.size < 1 || entry.size > 8_388_608) problems.push("bundle.js must be a regular file of at most 8 MiB");
  let count = 0, bytes = 0;
  const pending = [directory];
  while (pending.length) {
    const folder = pending.pop();
    for (const name of await readdir(folder)) {
      const file = path.join(folder, name);
      const info = await lstat(file);
      count += 1;
      if (info.isSymbolicLink()) problems.push(`Symbolic links are not allowed: ${path.relative(directory, file)}`);
      else if (info.isDirectory()) pending.push(file);
      else if (!info.isFile()) problems.push(`Only regular files and folders are allowed: ${path.relative(directory, file)}`);
      bytes += info.isFile() ? info.size : 0;
    }
  }
  if (count > 512) problems.push(`The package has ${count} files and folders; the limit is 512`);
  if (bytes > 64 * 1024 * 1024) problems.push("The package exceeds 64 MiB");
  for (const [id, connection] of Object.entries(manifest.connections ?? {})) {
    if (connection.transport !== "stdio" || !connection.executable.startsWith("./")) continue;
    const executable = path.join(directory, connection.executable);
    if (!(await access(executable, constants.X_OK).then(() => true, () => false))) {
      problems.push(`Connection "${id}" points to a missing or non-executable helper: ${connection.executable}`);
    }
  }
  return problems;
}
