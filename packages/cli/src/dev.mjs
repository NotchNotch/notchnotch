import { spawnSync } from "node:child_process";
import { mkdir, open, readFile, rm, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { buildExtension, checkPackage, readManifest } from "./index.mjs";

/** Where the app looks for `notchnotch dev` registrations. */
export function developmentDirectory() {
  return process.env.NOTCHNOTCH_DEVELOPMENT_DIR ??
    path.join(homedir(), "Library", "Application Support", "NotchNotch", "Development");
}

/**
 * Builds an extension, keeps rebuilding it on change, and registers the build
 * with the running NotchNotch app, which loads it while this process lives and
 * reloads it after each rebuild. Log lines from the app are passed to `onLog`.
 * Returns `stop()`, which unregisters the extension and stops watching.
 */
export async function developExtension({ source, destination, onLog = () => {}, logLevel = "info" }) {
  source = path.resolve(source);
  destination = path.resolve(destination ?? path.join(source, "dist"));
  const manifest = await readManifest(source);
  await buildExtension({ source, destination, logLevel });
  const problems = await checkPackage(destination);
  if (problems.length) throw new Error(problems.map((problem) => `✗ ${problem}`).join("\n"));

  const watcher = await buildExtension({ source, destination, watch: true, clean: false, logLevel });
  const directory = developmentDirectory();
  await mkdir(directory, { recursive: true });
  const registration = path.join(directory, `${manifest.id}.json`);
  const log = path.join(directory, `${manifest.id}.log`);
  await writeFile(log, "");
  await writeFile(registration, JSON.stringify({ path: destination, pid: process.pid, source }));

  // Follow the log the app appends to.
  let offset = 0;
  let pending = "";
  let lastLevel = "log";
  let reading = false;
  const poll = setInterval(async () => {
    if (reading) return;
    reading = true;
    try {
    const size = (await stat(log).catch(() => null))?.size ?? 0;
    if (size <= offset) return;
    const handle = await open(log, "r");
    try {
      const { buffer, bytesRead } = await handle.read(Buffer.alloc(size - offset), 0, size - offset, offset);
      offset += bytesRead;
      pending += buffer.subarray(0, bytesRead).toString("utf8");
    } finally { await handle.close(); }
    const lines = pending.split("\n");
    pending = lines.pop();
    for (const line of lines) {
      // A line starting with a tab continues the previous message.
      const [level, ...rest] = line.split("\t");
      if (level) lastLevel = level === "error" ? "error" : "log";
      onLog(lastLevel, rest.join("\t"));
    }
    } finally { reading = false; }
  }, 250);

  let stopped = false;
  return {
    manifest,
    destination,
    async stop() {
      if (stopped) return;
      stopped = true;
      clearInterval(poll);
      await watcher?.dispose();
      await rm(registration, { force: true });
      await rm(log, { force: true });
    },
  };
}

/** Whether a NotchNotch app is running on this Mac. */
export function isAppRunning() {
  return spawnSync("/usr/bin/pgrep", ["-x", "NotchNotch"]).status === 0;
}

/**
 * Asks the running NotchNotch to draw Store screenshots of an extension that
 * `notchnotch dev` is running, into the project's `metadata/`. Returns the files.
 */
export async function captureScreenshots({ source, timeout = 15_000 }) {
  const manifest = await readManifest(path.resolve(source));
  const directory = developmentDirectory();
  if (!(await stat(path.join(directory, `${manifest.id}.json`)).then(() => true, () => false))) {
    throw new Error(`${manifest.name} isn't running. Start it with notchnotch dev in another terminal, then capture.`);
  }
  const request = path.join(directory, `${manifest.id}.screenshot`);
  const result = path.join(directory, `${manifest.id}.screenshot-result`);
  await rm(result, { force: true });
  await writeFile(request, "");
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const text = await readFile(result, "utf8").catch(() => null);
    if (text) {
      await rm(result, { force: true });
      const { files, error } = JSON.parse(text);
      if (error) throw new Error(error);
      return files;
    }
    await new Promise((done) => setTimeout(done, 200));
  }
  await rm(request, { force: true });
  throw new Error(isAppRunning() ? "NotchNotch didn't answer. Update it to 0.8 or later." : "NotchNotch isn't running.");
}
