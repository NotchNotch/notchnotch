// Signing and helper packaging for extension build modules.
//
// NOTCHNOTCH_SIGN_IDENTITY=<name|SHA-1>
//   unset / "-"                      ad hoc: fine on this Mac; macOS forgets granted permissions
//                                    (Automation, Calendars) whenever the binaries change.
//   a self-signed identity           stable signature, so permissions survive updates.
//   "Developer ID Application: …"    adds a secure timestamp and allows notarization.
// NOTCHNOTCH_SIGN_KEYCHAIN           optional keychain that holds the identity.
import { spawnSync } from "node:child_process";
import { chmod, copyFile, mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";

export const identity = process.env.NOTCHNOTCH_SIGN_IDENTITY || "-";
export const signed = identity !== "-";
export const developerID = identity.startsWith("Developer ID Application");
const keychain = process.env.NOTCHNOTCH_SIGN_KEYCHAIN;

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

const xml = (value) => String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/**
 * Wraps a compiled helper executable in `helpers/<name>.app` and signs it.
 *
 * NotchNotch starts every helper as its own responsible process, so macOS
 * privacy prompts (Automation, Calendars, Contacts, Location…) use this
 * bundle's name and `usageDescriptions`, and grants belong to this helper
 * alone. A protected resource without its usage description is denied.
 *
 * Returns the manifest `executable` path, e.g. `./helpers/Adapter.app/Contents/MacOS/Adapter`.
 */
export async function helperApp({ destination, name, binary, bundleIdentifier, displayName = name,
  usageDescriptions = {}, entitlements, minimumSystemVersion = "14.0" }) {
  if (!/^[A-Za-z][A-Za-z0-9-]{0,63}$/.test(name)) throw new Error(`Invalid helper name: ${name}`);
  if (!/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(bundleIdentifier ?? "")) throw new Error(`Invalid bundle identifier: ${bundleIdentifier}`);
  for (const [key, text] of Object.entries(usageDescriptions)) {
    if (!/^NS[A-Za-z]+UsageDescription$/.test(key) || typeof text !== "string" || !text.trim()) {
      throw new Error(`Invalid usage description: ${key}`);
    }
  }
  const bundle = path.join(destination, "helpers", `${name}.app`);
  const contents = path.join(bundle, "Contents");
  await rm(bundle, { recursive: true, force: true });
  await mkdir(path.join(contents, "MacOS"), { recursive: true });
  const executable = path.join(contents, "MacOS", name);
  await copyFile(binary, executable);
  await chmod(executable, 0o755);
  const usage = Object.entries(usageDescriptions).map(([key, text]) => `<key>${key}</key><string>${xml(text)}</string>`).join("\n");
  await writeFile(path.join(contents, "Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>${xml(bundleIdentifier)}</string>
<key>CFBundleName</key><string>${xml(displayName)}</string>
<key>CFBundleExecutable</key><string>${name}</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>${xml(minimumSystemVersion)}</string>
<key>LSUIElement</key><true/>
${usage}
</dict></plist>
`);
  codesign(bundle, { entitlements });
  return `./helpers/${name}.app/Contents/MacOS/${name}`;
}
