import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { iconFiles } from "./manifest.mjs";

/** SHA-256 of the placeholder `assets/icon.png` in the `create-notchnotch-extension` template. */
export const PLACEHOLDER_ICON_SHA256 = "2af6329145badfa91acf7a3a6d7e7e9185f8635aeffc84216097b945d8f7f4eb";

// Apple Style Guide title case: articles, coordinating conjunctions and prepositions
// of three letters or fewer stay lowercase unless they start or end the title.
const MINOR_WORDS = new Set(["a", "an", "and", "as", "at", "but", "by", "for", "in", "nor", "of", "on", "or", "per", "the", "to", "via", "vs"]);

const read = (file) => readFile(file, "utf8").catch(() => undefined);

/**
 * Store guideline checks for an extension folder (source or built). Unlike
 * `checkPackage`, nothing here stops the app from installing the extension;
 * these are what a store review would ask you to fix.
 */
export async function lintExtension(directory) {
  directory = path.resolve(directory);
  const manifest = JSON.parse(await readFile(path.join(directory, "notchnotch.json"), "utf8"));
  const warnings = [];
  const warn = (message) => warnings.push(message);

  const titleProblem = titleCaseProblem(manifest.name ?? "");
  if (titleProblem) warn(`name: ${titleProblem}`);

  if (!manifest.description) warn("description: add one sentence that says what the extension does");
  else if (manifest.description.length > 160) warn(`description: keep it to one short sentence (${manifest.description.length} of 160 characters)`);
  else if (manifest.description === `${manifest.name} for the notch.`) warn("description: replace the template's placeholder sentence");

  if (/^com\.example\./.test(manifest.id)) warn(`id: replace the com.example. prefix with a domain or handle you own (${manifest.id})`);
  if (!manifest.author) warn("author: add your store handle");
  if (!manifest.categories) warn("categories: add one to three categories");
  if (!manifest.license) warn("license: add an SPDX license identifier, such as MIT");

  const icon = iconFiles(manifest);
  if (!icon) {
    warn('icon: add your own 512×512 assets/icon.png and set "icon": "icon.png"');
  } else {
    const data = await readFile(path.join(directory, "assets", icon.light)).catch(() => undefined);
    if (data && createHash("sha256").update(data).digest("hex") === PLACEHOLDER_ICON_SHA256) {
      warn(`icon: replace the template's placeholder assets/${icon.light} with your own icon`);
    }
  }

  const readme = await read(path.join(directory, "README.md"));
  if (readme === undefined) warn("README.md: add one that explains what the extension does and how to set it up");
  else if (readme.includes("Describe what") && readme.includes("Explain any setup step")) warn("README.md: replace the template's placeholder text");
  if (await read(path.join(directory, "CHANGELOG.md")) === undefined) warn("CHANGELOG.md: add one with a section for each version");

  // Store screenshots: what `notchnotch screenshot` writes.
  const shots = (await readdir(path.join(directory, "metadata")).catch(() => [])).filter((name) => !name.startsWith("."));
  if (shots.length > 6) warn(`metadata/: the Store shows up to 6 screenshots; remove ${shots.length - 6}`);
  for (const name of shots) {
    const data = await readFile(path.join(directory, "metadata", name)).catch(() => undefined);
    const png = data && data.length > 24 && data.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    if (!png || data.readUInt32BE(16) !== 2000 || data.readUInt32BE(20) !== 1250) {
      warn(`metadata/${name}: screenshots must be 2000×1250 PNGs; make them with notchnotch screenshot`);
    }
  }

  return warnings;
}

/** Explains why `title` is not in Apple Style Guide title case, or returns undefined. */
export function titleCaseProblem(title) {
  const words = title.split(/\s+/).filter(Boolean);
  for (const [index, word] of words.entries()) {
    const letters = word.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "");
    if (!letters || /\p{Lu}/u.test(letters) || /^\p{N}/u.test(letters)) continue; // iOS, macOS, 2FA keep their own case
    const last = index === words.length - 1;
    if (index > 0 && !last && MINOR_WORDS.has(letters)) continue;
    const fixed = words.map((value, i) => i === index ? value.replace(letters, letters[0].toUpperCase() + letters.slice(1)) : value).join(" ");
    return `use title case, for example "${fixed}"`;
  }
  return undefined;
}
