// Shared native build and signing rules for the app, the runner and bundled helpers.
//
// NOTCHNOTCH_CONFIGURATION=release   builds optimized universal (arm64 + x86_64) binaries.
// NOTCHNOTCH_SIGN_IDENTITY=<name|SHA-1>
//   unset / "-"                      ad hoc: fine on this Mac; macOS forgets granted permissions
//                                    (Automation, Calendars) whenever the binaries change.
//   a self-signed identity           stable signature, so permissions survive updates
//                                    (see scripts/create-signing-identity.sh).
//   "Developer ID Application: …"    adds a secure timestamp and allows notarization.
// NOTCHNOTCH_SIGN_KEYCHAIN           optional keychain that holds the identity.
import { spawnSync } from "node:child_process";
import path from "node:path";

export const release = process.env.NOTCHNOTCH_CONFIGURATION === "release";
export const identity = process.env.NOTCHNOTCH_SIGN_IDENTITY || "-";
export const signed = identity !== "-";
export const developerID = identity.startsWith("Developer ID Application");
const keychain = process.env.NOTCHNOTCH_SIGN_KEYCHAIN;

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
  if (keychain) args.push("--keychain", keychain);
  // Hardened runtime with entitlements for any real identity; Apple's timestamp
  // service only accepts Apple-issued certificates.
  if (signed) args.push("--options", "runtime");
  if (developerID) args.push("--timestamp");
  if (entitlements && signed) args.push("--entitlements", entitlements);
  args.push(target);
  const result = spawnSync("codesign", args, { stdio: "inherit" });
  if (result.status !== 0) throw new Error(`Signing failed: ${target}`);
}
