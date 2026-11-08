// Shared native build and signing rules for the app, the runner and bundled helpers.
//
// NOTCHNOTCH_CONFIGURATION=release  builds optimized universal (arm64 + x86_64) binaries.
// NOTCHNOTCH_SIGN_IDENTITY="Developer ID Application: …"  signs with hardened runtime and
//   a secure timestamp; otherwise code is signed ad hoc for local use.
import { spawnSync } from "node:child_process";
import path from "node:path";

export const release = process.env.NOTCHNOTCH_CONFIGURATION === "release";
export const identity = process.env.NOTCHNOTCH_SIGN_IDENTITY || "-";
export const distributionSigned = identity !== "-";

function swiftArgs() {
  return release ? ["-c", "release", "--arch", "arm64", "--arch", "x86_64"] : [];
}

/** Builds one SwiftPM product (or everything when product is omitted). */
export function swiftBuild(root, product) {
  const args = ["build", "--disable-sandbox", "--cache-path", ".build/cache", ...swiftArgs(),
    ...(product ? ["--product", product] : [])];
  const result = spawnSync("swift", args, {
    cwd: root, stdio: "inherit", env: { ...process.env,
      CLANG_MODULE_CACHE_PATH: path.join(root, ".build/cache/clang"),
      SWIFTPM_MODULECACHE_OVERRIDE: path.join(root, ".build/cache/swift") },
  });
  if (result.status !== 0) throw new Error(`swift build failed${product ? ` for ${product}` : ""}`);
}

/** Location of a built executable for the current configuration. */
export function productPath(root, name) {
  return release ? path.join(root, ".build/apple/Products/Release", name) : path.join(root, ".build/debug", name);
}

/** Signs one bundle or binary. Sign nested code first; never use --deep. */
export function codesign(target, { entitlements } = {}) {
  const args = ["--force", "--sign", identity];
  if (distributionSigned) args.push("--options", "runtime", "--timestamp");
  if (entitlements && distributionSigned) args.push("--entitlements", entitlements);
  args.push(target);
  const result = spawnSync("codesign", args, { stdio: "inherit" });
  if (result.status !== 0) throw new Error(`Signing failed: ${target}`);
}
