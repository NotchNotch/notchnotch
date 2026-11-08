// Builds a distributable NotchNotch-<version>.dmg.
//
//   pnpm release
//
// Environment:
//   NOTCHNOTCH_SIGN_IDENTITY    "Developer ID Application: Name (TEAMID)". Without it the build
//                               is ad-hoc signed: fine for testing, rejected by Gatekeeper elsewhere.
//   NOTCHNOTCH_NOTARY_PROFILE   notarytool keychain profile (xcrun notarytool store-credentials).
//                               When set, the DMG is notarized and stapled.
//   NOTCHNOTCH_BUILD_NUMBER     CFBundleVersion (defaults to 1).
process.env.NOTCHNOTCH_CONFIGURATION = "release";

const { spawnSync } = await import("node:child_process");
const { mkdtemp, readFile, rm, symlink, cp } = await import("node:fs/promises");
const { tmpdir } = await import("node:os");
const path = (await import("node:path")).default;
const { buildExtensions, root } = await import("./build-extensions.mjs");
const { packageApp } = await import("./package-app.mjs");
const { codesign, distributionSigned, swiftBuild } = await import("./native.mjs");

function run(command, args) {
  console.log(`$ ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, { stdio: "inherit" });
  if (result.status !== 0) throw new Error(`${command} failed`);
}

const { version } = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
await buildExtensions();
swiftBuild(root, "NotchNotch");
swiftBuild(root, "ExtensionRunner");
const app = await packageApp();

run("codesign", ["--verify", "--strict", "--verbose=2", app]);
run("lipo", ["-archs", path.join(app, "Contents/MacOS/NotchNotch")]);

const staging = await mkdtemp(path.join(tmpdir(), "notchnotch-dmg-"));
const dmg = path.join(root, "dist", `NotchNotch-${version}.dmg`);
try {
  await cp(app, path.join(staging, "NotchNotch.app"), { recursive: true, verbatimSymlinks: true });
  await symlink("/Applications", path.join(staging, "Applications"));
  await rm(dmg, { force: true });
  run("hdiutil", ["create", "-volname", `NotchNotch ${version}`, "-srcfolder", staging, "-ov", "-format", "UDZO", dmg]);
} finally { await rm(staging, { recursive: true, force: true }); }
if (distributionSigned) codesign(dmg);

const profile = process.env.NOTCHNOTCH_NOTARY_PROFILE;
if (profile && distributionSigned) {
  run("xcrun", ["notarytool", "submit", dmg, "--keychain-profile", profile, "--wait"]);
  run("xcrun", ["stapler", "staple", dmg]);
  run("spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose", dmg]);
} else {
  console.warn(distributionSigned
    ? "Skipping notarization: set NOTCHNOTCH_NOTARY_PROFILE."
    : "Ad-hoc signed preview build: set NOTCHNOTCH_SIGN_IDENTITY and NOTCHNOTCH_NOTARY_PROFILE for a public release.");
}
console.log(`Release ready: ${dmg}`);
