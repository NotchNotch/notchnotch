// Builds a distributable NotchNotch-<version>.dmg.
//
//   pnpm release
//
// Environment:
//   NOTCHNOTCH_SIGN_IDENTITY    Signing identity (see scripts/native.mjs). A self-signed identity keeps
//                               macOS permissions across updates; only "Developer ID Application"
//                               builds can be notarized. Unset: ad hoc.
//   NOTCHNOTCH_NOTARY_PROFILE   notarytool keychain profile; with a Developer ID identity the DMG is
//                               notarized and stapled.
//   NOTCHNOTCH_BUILD_NUMBER     CFBundleVersion (defaults to 1). Sparkle compares it between
//                               releases, so it must increase; the release workflow uses its run number.
//   SPARKLE_PRIVATE_KEY         EdDSA key from `node scripts/sparkle.mjs keys`; signs the update
//                               archive and writes dist/appcast.xml. Unset: no update is published.
process.env.NOTCHNOTCH_CONFIGURATION = "release";

const { spawnSync } = await import("node:child_process");
const { mkdtemp, readFile, rm, symlink, cp, writeFile } = await import("node:fs/promises");
const { tmpdir } = await import("node:os");
const path = (await import("node:path")).default;
const { buildExtensions, root } = await import("./build-extensions.mjs");
const { packageApp } = await import("./package-app.mjs");
const { codesign, developerID, signed, swiftBuild } = await import("./native.mjs");
const sparkle = await import("./sparkle.mjs");

function run(command, args) {
  console.log(`$ ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, { stdio: "inherit" });
  if (result.status !== 0) throw new Error(`${command} failed`);
}

const { version } = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
await buildExtensions();
swiftBuild(root, "NotchNotch");
swiftBuild(root, "ExtensionRunner");
swiftBuild(root, "NowPlayingAdapter");
const app = await packageApp();

run("codesign", ["--verify", "--strict", "--verbose=2", app]);
// Print what macOS will key permissions to: the designated requirement must stay
// identical across releases for granted access to survive updates.
for (const target of [app, path.join(app, "Contents/Helpers/ExtensionRunner"),
  path.join(app, "Contents/Frameworks/Sparkle.framework")]) {
  run("codesign", ["--display", "--requirements", "-", "--verbose=1", target]);
}
run("lipo", ["-archs", path.join(app, "Contents/MacOS/NotchNotch")]);

// Smoke test the signed runner: hardened runtime must still allow JavaScriptCore
// to evaluate a bundle (JIT entitlement) and answer a liveness ping.
{
  const runner = path.join(app, "Contents/Helpers/ExtensionRunner");
  const bundle = path.join(app, "Contents/Resources/extensions/music/bundle.js");
  const result = spawnSync(runner, [bundle, "dev.notchnotch.music"], {
    input: JSON.stringify({ protocolVersion: 1, type: "ping", id: 1 }) + "\n", timeout: 10_000, encoding: "utf8",
  });
  const messages = result.stdout.split("\n").filter(Boolean).map((line) => JSON.parse(line));
  if (!messages.some((message) => message.type === "snapshot") || !messages.some((message) => message.type === "pong")) {
    throw new Error(`Signed runner smoke test failed: ${result.stderr || result.error?.message || "no snapshot or pong"}`);
  }
  console.log("Signed runner smoke test passed.");
}

const staging = await mkdtemp(path.join(tmpdir(), "notchnotch-dmg-"));
const dmg = path.join(root, "dist", `NotchNotch-${version}.dmg`);
try {
  await cp(app, path.join(staging, "NotchNotch.app"), { recursive: true, verbatimSymlinks: true });
  await symlink("/Applications", path.join(staging, "Applications"));
  await rm(dmg, { force: true });
  run("hdiutil", ["create", "-volname", `NotchNotch ${version}`, "-srcfolder", staging, "-ov", "-format", "UDZO", dmg]);
} finally { await rm(staging, { recursive: true, force: true }); }
if (signed) codesign(dmg);

const profile = process.env.NOTCHNOTCH_NOTARY_PROFILE;
if (profile && developerID) {
  run("xcrun", ["notarytool", "submit", dmg, "--keychain-profile", profile, "--wait"]);
  run("xcrun", ["stapler", "staple", dmg]);
  run("spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose", dmg]);
} else {
  console.warn(`Not notarized (${signed ? "self-signed" : "ad hoc"}). On other Macs, first launch needs ` +
    "System Settings › Privacy & Security › Open Anyway.");
}
// Sparkle installs from a zip of the app; the DMG stays the first-install download.
const archiveName = `NotchNotch-${version}.zip`;
const archive = path.join(root, "dist", archiveName);
const appcastFile = path.join(root, "dist/appcast.xml");
await rm(archive, { force: true });
await rm(appcastFile, { force: true });
run("ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app, archive]);
const privateKey = process.env.SPARKLE_PRIVATE_KEY;
if (privateKey) {
  const publicKey = await sparkle.committedPublicKey();
  if (!publicKey || sparkle.publicKeyFor(privateKey) !== publicKey) {
    throw new Error("SPARKLE_PRIVATE_KEY does not match apps/macos/SparklePublicKey; installed copies would reject this update");
  }
  const { signature, length } = await sparkle.signArchive(archive, privateKey);
  const notes = sparkle.releaseNotesHTML(await readFile(path.join(root, "CHANGELOG.md"), "utf8"), version);
  await writeFile(appcastFile, sparkle.appcast({
    version, build: process.env.NOTCHNOTCH_BUILD_NUMBER ?? "1", signature, length, notes,
    url: `https://github.com/${sparkle.repository}/releases/download/v${version}/${archiveName}`,
  }));
  console.log(`Update ready: ${archive} and ${appcastFile}`);
} else {
  console.warn("SPARKLE_PRIVATE_KEY is not set: no appcast, so installed copies won't be offered this release.");
}
console.log(`Release ready: ${dmg}`);
