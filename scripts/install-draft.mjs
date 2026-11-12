// Installs a release draft's DMG over /Applications/NotchNotch.app, to test
// exactly what users will download before publishing it.
//
//   pnpm install:draft              the newest draft
//   pnpm install:draft v0.11.0      a given release, draft or not
//   pnpm install:draft --dry-run    download and check, but change nothing
//
// Needs `gh` signed in with access to the repository (drafts are private to it).
// macOS keeps granted permissions because the release is signed with the same
// identity as the installed app; the script checks that before replacing it.
// `gh` doesn't quarantine what it downloads, so there is no Open Anyway step.
import { spawnSync } from "node:child_process";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { repository } from "./sparkle.mjs";

const installed = "/Applications/NotchNotch.app";
const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const force = args.includes("--force");
const requested = args.find((arg) => !arg.startsWith("--"));

function run(command, list, options = {}) {
  const result = spawnSync(command, list, { encoding: "utf8", ...options });
  if (result.status !== 0) throw new Error(`${command} ${list.join(" ")} failed:\n${result.stderr || result.stdout}`);
  return result.stdout;
}
/** The designated requirement: what macOS keys permissions to. */
const requirement = (app) => run("codesign", ["-d", "-r-", app], { stdio: ["ignore", "pipe", "pipe"] })
  .split("\n").find((line) => line.startsWith("designated =>"))?.trim();
const version = (app) => run("defaults", ["read", path.join(app, "Contents/Info.plist"), "CFBundleShortVersionString"]).trim();

const releases = JSON.parse(run("gh", ["release", "list", "--repo", repository, "--limit", "20", "--json", "tagName,isDraft"]));
const tag = requested ?? releases.find((release) => release.isDraft)?.tagName;
if (!tag) throw new Error("There is no draft release. Push a v* tag first, or name a release: pnpm install:draft v0.11.0");

const work = await mkdtemp(path.join(tmpdir(), "notchnotch-draft-"));
const mount = path.join(work, "volume");
let attached = false;
try {
  console.log(`▸ Downloading the ${tag} DMG`);
  run("gh", ["release", "download", tag, "--repo", repository, "--pattern", "*.dmg", "--dir", work]);
  const dmg = (await readdir(work)).find((name) => name.endsWith(".dmg"));
  if (!dmg) throw new Error(`${tag} has no DMG`);
  run("hdiutil", ["attach", path.join(work, dmg), "-nobrowse", "-readonly", "-mountpoint", mount]);
  attached = true;
  const app = path.join(mount, "NotchNotch.app");
  run("codesign", ["--verify", "--deep", "--strict", app]);
  const next = requirement(app);
  const present = spawnSync("test", ["-d", installed]).status === 0;
  const current = present ? requirement(installed) : null;
  console.log(`▸ ${tag} contains NotchNotch ${version(app)}${present ? `; installed is ${version(installed)}` : ""}`);
  if (current && next !== current) {
    const message = `The draft is signed differently from the installed app, so macOS would ask for every permission again.\n  installed: ${current}\n  draft:     ${next}`;
    if (!force) throw new Error(`${message}\nRun with --force to install it anyway.`);
    console.warn(message);
  }
  if (dryRun) {
    console.log("▸ Dry run: the draft checks out. Nothing was changed.");
  } else {
    await install(app);
  }
} finally {
  if (attached) spawnSync("hdiutil", ["detach", mount, "-quiet"]);
  await rm(work, { recursive: true, force: true });
}

async function install(app) {
  console.log("▸ Quitting NotchNotch");
  spawnSync("osascript", ["-e", 'tell application id "dev.notchnotch.app" to quit']);
  for (let attempt = 0; attempt < 50 && spawnSync("pgrep", ["-x", "NotchNotch"]).status === 0; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (spawnSync("pgrep", ["-x", "NotchNotch"]).status === 0) throw new Error("NotchNotch didn't quit. Quit it and run again.");

  // Copy beside the old app first, so a failed copy never leaves no app at all.
  const staged = `${installed}.installing`;
  await rm(staged, { recursive: true, force: true });
  run("ditto", [app, staged]);
  run("xattr", ["-dr", "com.apple.quarantine", staged]);
  await rm(installed, { recursive: true, force: true });
  run("mv", [staged, installed]);
  console.log(`▸ Installed NotchNotch ${version(installed)} from ${tag}; opening it`);
  run("open", [installed]);
}
