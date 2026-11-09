#!/usr/bin/env node
import path from "node:path";
import { parseArgs } from "node:util";
import { buildExtension, checkPackage } from "../src/index.mjs";

const usage = `Usage:
  notchnotch build [folder] [--out <dir>] [--watch]   Build an installable package (default out: <folder>/dist)
  notchnotch check [package]                          Check a built package against the app's install rules`;

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { out: { type: "string", short: "o" }, watch: { type: "boolean", short: "w" }, help: { type: "boolean", short: "h" } },
});
const [command, folder = "."] = positionals;
if (values.help || !["build", "check"].includes(command)) {
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
      console.log(`Built ${out}\nInstall it from Settings & Extensions…: click + at the bottom of the sidebar.`);
    }
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
