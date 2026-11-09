#!/usr/bin/env node
import path from "node:path";
import { parseArgs } from "node:util";
import { buildExtension, checkPackage, packExtension } from "../src/index.mjs";

const usage = `Usage:
  notchnotch build [folder] [--out <dir>] [--watch] [--pack]
                                    Build an installable package (default out: <folder>/dist);
                                    --pack also writes <id>-<version>.notchext next to it
  notchnotch pack [package] [--out <file.notchext>]
                                    Zip a built package into a .notchext people can double-click
  notchnotch check [package]        Check a built package against the app's install rules`;

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { out: { type: "string", short: "o" }, watch: { type: "boolean", short: "w" }, pack: { type: "boolean", short: "p" },
    help: { type: "boolean", short: "h" } },
});
const [command, folder = "."] = positionals;
if (values.help || !["build", "check", "pack"].includes(command)) {
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
  } else if (command === "pack") {
    const file = await packExtension({ directory: folder, out: values.out });
    console.log(`Packed ${file}\nDouble-click it to open NotchNotch's install review, or share it.`);
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
