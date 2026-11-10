#!/usr/bin/env node
import path from "node:path";
import { parseArgs } from "node:util";
import { buildExtension, checkPackage, lintExtension, packExtension } from "../src/index.mjs";
import { developExtension, isAppRunning } from "../src/dev.mjs";
import { publishExtension } from "../src/publish.mjs";

const usage = `Usage:
  notchnotch build [folder] [--out <dir>] [--watch] [--pack]
                                    Build an installable package (default out: <folder>/dist);
                                    --pack also writes <id>-<version>.notchext next to it
  notchnotch dev [folder] [--out <dir>]
                                    Run the extension in NotchNotch and reload it on every change;
                                    its console output appears here. Press Ctrl+C to stop
  notchnotch pack [package] [--out <file.notchext>]
                                    Zip a built package into a .notchext people can double-click
  notchnotch check [package]        Check a built package against the app's install rules
  notchnotch lint [folder]          Check store guidelines: icon, title, description, README…
  notchnotch publish [folder] [--dry-run]
                                    Open or update a pull request that adds this extension to the
                                    Store. Uses the GitHub CLI (gh auth login)`;

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { out: { type: "string", short: "o" }, watch: { type: "boolean", short: "w" }, pack: { type: "boolean", short: "p" }, "dry-run": { type: "boolean" },
    help: { type: "boolean", short: "h" } },
});
const [command, folder = "."] = positionals;
if (values.help || !["build", "check", "dev", "lint", "pack", "publish"].includes(command)) {
  console.log(usage);
  process.exit(values.help ? 0 : 1);
}
try {
  if (command === "build") {
    const out = path.resolve(values.out ?? path.join(folder, "dist"));
    await buildExtension({ source: folder, destination: out, watch: values.watch });
    if (!values.watch) {
      const problems = await checkPackage(out);
      for (const problem of problems) console.error(`✗ ${problem}`);
      if (problems.length) process.exit(1);
      if (values.pack) {
        const file = await packExtension({ directory: out });
        console.log(`Built ${out}\nPacked ${file}\nDouble-click it to install, or share it.`);
      } else {
        console.log(`Built ${out}\nInstall it from Settings & Extensions…: click + at the bottom of the sidebar.`);
      }
    }
  } else if (command === "dev") {
    if (process.platform !== "darwin") throw new Error("notchnotch dev needs NotchNotch running on this Mac.");
    const session = await developExtension({
      source: folder, destination: values.out,
      onLog: (level, message) => (level === "error" ? console.error : console.log)(`${level === "error" ? "✗" : "›"} ${message}`),
    });
    console.log(`Running ${session.manifest.name} in NotchNotch from ${session.destination}.`);
    console.log("It reloads when you save. Console output appears below. Press Ctrl+C to stop.");
    if (!isAppRunning()) console.error("NotchNotch isn't running. Open it, and the extension loads within a second.");
    const stop = async () => { await session.stop(); process.exit(0); };
    process.on("SIGINT", stop);
    process.on("SIGTERM", stop);
  } else if (command === "pack") {
    const file = await packExtension({ directory: folder, out: values.out });
    console.log(`Packed ${file}\nDouble-click it to open NotchNotch's install review, or share it.`);
  } else if (command === "publish") {
    await publishExtension({ source: folder, dryRun: values["dry-run"] });
  } else if (command === "lint") {
    const warnings = await lintExtension(folder);
    for (const warning of warnings) console.error(`⚠ ${warning}`);
    if (warnings.length) {
      console.error(`\n${warnings.length} store guideline ${warnings.length === 1 ? "issue" : "issues"}. The app still installs this extension.`);
      process.exit(1);
    }
    console.log("No store guideline issues.");
  } else {
    const problems = await checkPackage(folder);
    for (const problem of problems) console.error(`✗ ${problem}`);
    if (problems.length) process.exit(1);
    console.log("Package passes the app's install checks.");
  }
} catch (error) {
  console.error(error.message ?? error);
  process.exit(1);
}
