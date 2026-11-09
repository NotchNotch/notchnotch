// Builds the publishable SDK packages into packages/<name>/dist.
//
// In this repository the packages export their TypeScript sources; npm users get
// the dist output through each package.json's publishConfig.
import { build } from "esbuild";
import { spawnSync } from "node:child_process";
import { copyFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
/** Dependency order: each package's declarations are built before its dependents. */
export const packages = [
  { name: "protocol", entry: "index.ts" },
  { name: "react-renderer", entry: "index.ts" },
  { name: "runtime", entry: "index.ts", extra: ["globals.d.ts"] },
  { name: "sdk", entry: "index.tsx" },
];
const globals = path.join(root, "packages/runtime/src/globals.d.ts");

export async function buildPackages() {
  for (const { name, entry, extra = [] } of packages) {
    const directory = path.join(root, "packages", name);
    const dist = path.join(directory, "dist");
    await rm(dist, { recursive: true, force: true });
    // One ESM file per package; React and the other packages stay external so
    // an extension bundles exactly one copy of each.
    await build({
      entryPoints: [path.join(directory, "src", entry)], outfile: path.join(dist, "index.js"),
      bundle: true, packages: "external", format: "esm", platform: "neutral", target: "es2022",
      jsx: "automatic", logLevel: "warning",
    });
    // Declarations resolve sibling packages through their already built dist.
    const config = path.join(directory, "tsconfig.build.json");
    await writeFile(config, JSON.stringify({
      extends: "../../tsconfig.json",
      compilerOptions: {
        noEmit: false, declaration: true, emitDeclarationOnly: true, rootDir: "src", outDir: "dist",
        baseUrl: ".", paths: Object.fromEntries(packages.map((item) => [`@notchnotch/${item.name}`, [`../${item.name}/dist/index.d.ts`]])),
      },
      include: ["src"], files: name === "runtime" ? [] : [path.relative(directory, globals)],
    }, null, 2));
    const result = spawnSync(path.join(root, "node_modules/.bin/tsc"), ["-p", config], { stdio: "inherit" });
    await rm(config);
    if (result.status !== 0) throw new Error(`Declarations failed for @notchnotch/${name}`);
    for (const file of extra) await copyFile(path.join(directory, "src", file), path.join(dist, file));
  }
}
if (process.argv[1] === fileURLToPath(import.meta.url)) await buildPackages();
