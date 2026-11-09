#!/usr/bin/env node
// npm create notchnotch-extension [folder] [--name "Display Name"] [--id com.example.extension]
import { cp, mkdir, readdir, readFile, rename, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const here = path.dirname(fileURLToPath(import.meta.url));
const template = path.join(here, "../template");
const { version } = JSON.parse(await readFile(path.join(here, "../package.json"), "utf8"));

export const slug = (text) => text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60) || "extension";
const title = (text) => text.split(/[-_\s]+/).filter(Boolean).map((word) => word[0].toUpperCase() + word.slice(1)).join(" ");
export const validID = (id) => /^[a-z][a-z0-9.-]{2,79}$/.test(id);

/** Creates the project; returns its folder. */
export async function create({ folder, name, id, sdkVersion = version }) {
  const target = path.resolve(folder);
  if ((await readdir(target).catch(() => [])).length) throw new Error(`${target} already exists and is not empty`);
  const displayName = (name ?? title(path.basename(target))).trim();
  if (!displayName || displayName.length > 128 || /["\\]/.test(displayName)) throw new Error("The name must be 1–128 characters without quotes or backslashes");
  id ??= `com.example.${slug(path.basename(target)).replace(/-/g, "")}`;
  if (!validID(id)) throw new Error(`Invalid id "${id}": use lowercase letters, digits, dots and dashes, starting with a letter`);
  await mkdir(target, { recursive: true });
  await cp(template, target, { recursive: true });
  await rename(path.join(target, "gitignore"), path.join(target, ".gitignore"));
  const values = { id, displayName };
  for (const file of ["notchnotch.json", "README.md", "src/index.tsx"]) {
    const location = path.join(target, file);
    await writeFile(location, (await readFile(location, "utf8")).replace(/\{\{(\w+)\}\}/g, (_, key) => values[key]));
  }
  const range = `^${sdkVersion}`;
  await writeFile(path.join(target, "package.json"), JSON.stringify({
    name: slug(path.basename(target)), private: true, type: "module",
    scripts: {
      build: "notchnotch build . --out dist", watch: "notchnotch build . --out dist --watch",
      check: "notchnotch check dist", typecheck: "tsc --noEmit",
    },
    dependencies: { "@notchnotch/runtime": range, "@notchnotch/sdk": range, react: "19.3.1" },
    devDependencies: { "@notchnotch/cli": range, "@types/react": "19.3.0", typescript: "5.9.3" },
  }, null, 2) + "\n");
  return target;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url) ||
    process.argv[1]?.endsWith("create-notchnotch-extension")) {
  const { positionals, values } = parseArgs({ allowPositionals: true, options: { name: { type: "string" }, id: { type: "string" } } });
  let [folder] = positionals;
  let { name, id } = values;
  if (process.stdin.isTTY) {
    const prompt = createInterface({ input: process.stdin, output: process.stdout });
    folder ||= (await prompt.question("Folder (my-extension): ")).trim() || "my-extension";
    name ||= (await prompt.question(`Name (${title(path.basename(folder))}): `)).trim() || undefined;
    const fallback = `com.example.${slug(path.basename(folder)).replace(/-/g, "")}`;
    id ||= (await prompt.question(`Identifier (${fallback}): `)).trim() || undefined;
    prompt.close();
  }
  try {
    const target = await create({ folder: folder || "my-extension", name, id });
    const relative = path.relative(process.cwd(), target);
    const shown = !relative ? "." : relative.startsWith("..") ? target : relative;
    console.log(`\nCreated ${shown}\n\n  cd ${shown}\n  npm install\n  npm run build\n\nThen open NotchNotch › Settings & Extensions… › Install from Folder… and choose ${shown}/dist.`);
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
