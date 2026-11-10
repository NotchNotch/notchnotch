// `notchnotch publish`: opens or updates a pull request that adds an extension
// to the Store repository, the way `ray publish` does for Raycast.
//
// Authentication is the GitHub CLI's: git pushes through `gh auth
// git-credential`, so no token passes through here.
import { spawnSync } from "node:child_process";
import { cp, mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { buildExtension, checkPackage } from "./index.mjs";
import { lintExtension } from "./lint.mjs";

export const storeRepository = process.env.NOTCHNOTCH_STORE_REPOSITORY || "sadeqi-ah/notchnotch-extensions";
const HANDLE = /^[a-z0-9][a-z0-9-]{0,38}\/[a-z0-9][a-z0-9-]{0,63}$/;
/** Never copied into the Store repository: builds, dependencies and local files. */
const SKIPPED = new Set(["node_modules", "dist", ".git", ".DS_Store", ".env"]);

/**
 * What would be published from `source` by GitHub user `login`: the handle,
 * branch and files, or the problems that stop it. Reads files only.
 */
export async function publishPlan(source, login) {
  source = path.resolve(source);
  const problems = [];
  const manifest = JSON.parse(await readFile(path.join(source, "notchnotch.json"), "utf8"));
  const pkg = JSON.parse(await readFile(path.join(source, "package.json"), "utf8").catch(() => "{}"));
  const name = String(pkg.name ?? path.basename(source)).replace(/^@[^/]+\//, "").toLowerCase();
  if (!manifest.author) problems.push(`notchnotch.json needs "author": "${login}", your GitHub user name`);
  const author = manifest.author ?? login;
  const handle = `${author}/${name}`;
  if (!HANDLE.test(handle)) problems.push(`${handle} isn't a valid Store address: use lowercase letters, digits and dashes in "author" and package.json "name"`);
  if (!pkg.name) problems.push("package.json with a \"name\" is required; the name becomes the extension's Store address");
  for (const [file, reason] of [["build.mjs", "a custom build.mjs"], ["helpers", "native helpers"]]) {
    if (await readdir(path.join(source, file)).then(() => true, (error) => error.code === "ENOTDIR")) {
      problems.push(`The Store doesn't accept ${reason} yet`);
    }
  }
  return {
    handle, manifest, problems,
    branch: `ext/${handle}`,
    files: await sourceFiles(source),
    notes: author !== login ? [`You're proposing a change to ${author}'s extension; they'll be asked to approve it.`] : [],
  };
}

/** Files to copy, relative to `source`, skipping builds, dependencies and packages. */
export async function sourceFiles(source, folder = source) {
  const files = [];
  for (const entry of await readdir(folder, { withFileTypes: true })) {
    if (SKIPPED.has(entry.name) || entry.name.endsWith(".notchext")) continue;
    const file = path.join(folder, entry.name);
    if (entry.isDirectory()) files.push(...await sourceFiles(source, file));
    else if (entry.isFile()) files.push(path.relative(source, file));
  }
  return files.sort();
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...options });
  if (result.error?.code === "ENOENT") throw new Error(`${command} isn't installed`);
  if (result.status !== 0) throw new Error(`${command} ${args[0]} failed: ${(result.stderr || result.stdout).trim()}`);
  return result.stdout.trim();
}
const gitWithGitHub = ["-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential"];

export async function publishExtension({ source, dryRun = false, log = console.log }) {
  source = path.resolve(source);
  try { run("gh", ["auth", "status"]); } catch {
    throw new Error("Publishing uses the GitHub CLI. Install it from https://cli.github.com and run: gh auth login");
  }
  const login = run("gh", ["api", "user", "--jq", ".login"]);
  const plan = await publishPlan(source, login);
  if (plan.problems.length) throw new Error(plan.problems.map((problem) => `✗ ${problem}`).join("\n"));
  for (const note of plan.notes) log(`› ${note}`);

  // The same checks the Store's CI runs, before anyone has to wait for it.
  const warnings = await lintExtension(source);
  if (warnings.length) throw new Error(`Fix these first (notchnotch lint):\n${warnings.map((w) => `⚠ ${w}`).join("\n")}`);
  const work = await mkdtemp(path.join(tmpdir(), "notchnotch-publish-"));
  try {
    await buildExtension({ source, destination: path.join(work, "build"), logLevel: "warning" });
    const problems = await checkPackage(path.join(work, "build"));
    if (problems.length) throw new Error(problems.map((problem) => `✗ ${problem}`).join("\n"));

    const clone = path.join(work, "repository");
    log(`› Preparing ${plan.handle} ${plan.manifest.version} for ${storeRepository}…`);
    run("git", ["clone", "--quiet", "--depth", "1", `https://github.com/${storeRepository}.git`, clone]);
    const target = path.join(clone, "extensions", ...plan.handle.split("/"));
    const isUpdate = await readdir(target).then(() => true, () => false);
    await rm(target, { recursive: true, force: true });
    for (const file of plan.files) await cp(path.join(source, file), path.join(target, file));
    run("git", ["add", "--all", "--", target], { cwd: clone });
    const changed = run("git", ["diff", "--cached", "--stat"], { cwd: clone });
    if (!changed) { log("Nothing changed since the version in the Store."); return null; }
    const title = isUpdate ? `Update ${plan.manifest.name} to ${plan.manifest.version}` : `Add ${plan.manifest.name}`;
    run("git", ["commit", "--quiet", "-m", title], { cwd: clone });
    if (dryRun) { log(`${changed}\n\nDry run: would push ${plan.branch} and open “${title}”.`); return null; }

    const [owner] = storeRepository.split("/");
    let head = storeRepository;
    if (login !== owner) {
      run("gh", ["repo", "fork", storeRepository, "--clone=false", "--remote=false"]);
      head = `${login}/${storeRepository.split("/")[1]}`;
    }
    run("git", [...gitWithGitHub, "push", "--quiet", "--force", `https://github.com/${head}.git`, `HEAD:refs/heads/${plan.branch}`], { cwd: clone });
    const existing = run("gh", ["pr", "list", "--repo", storeRepository, "--head", plan.branch, "--author", login, "--state", "open", "--json", "url", "--jq", ".[0].url // empty"]);
    if (existing) { log(`Updated ${existing}`); return existing; }
    const body = `${plan.manifest.description ?? ""}\n\nOpened with \`notchnotch publish\`.`.trim();
    const url = run("gh", ["pr", "create", "--repo", storeRepository, "--base", "main", "--head", `${login === owner ? "" : `${login}:`}${plan.branch}`,
      "--title", title, "--body", body]);
    log(`Opened ${url}`);
    return url;
  } finally {
    await rm(work, { recursive: true, force: true });
  }
}
