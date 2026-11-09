import { mkdir, cp, writeFile, chmod, readdir, rm, readFile } from "node:fs/promises";
import path from "node:path";
import { bundledExtensionNames, root } from "./build-extensions.mjs";
import { spawnSync } from "node:child_process";
import { codesign, productPath, release } from "./native.mjs";
import { committedPublicKey, feedURL } from "./sparkle.mjs";

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`${command} failed: ${result.stderr}`);
  return result.stdout;
}

/** Embeds Sparkle.framework and signs it inside out, as Sparkle documents for apps built outside Xcode. */
async function embedSparkle(contents) {
  const framework = path.join(contents, "Frameworks/Sparkle.framework");
  await rm(framework, { recursive: true, force: true });
  await mkdir(path.dirname(framework), { recursive: true });
  // verbatimSymlinks keeps the framework's relative Versions/Current links intact.
  await cp(productPath(root, "Sparkle.framework"), framework, { recursive: true, verbatimSymlinks: true });
  // The XPC services are only needed by sandboxed apps; NotchNotch is not sandboxed.
  await rm(path.join(framework, "Versions/B/XPCServices"), { recursive: true, force: true });
  await rm(path.join(framework, "XPCServices"), { force: true });
  codesign(path.join(framework, "Versions/B/Autoupdate"));
  codesign(path.join(framework, "Versions/B/Updater.app"));
  codesign(framework);
  const binary = path.join(contents, "MacOS/NotchNotch");
  if (!run("otool", ["-l", binary]).includes("@executable_path/../Frameworks")) {
    run("install_name_tool", ["-add_rpath", "@executable_path/../Frameworks", binary]);
  }
}

export async function packageApp() {
  // package.json is the single source of truth for the app version.
  const { version } = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version)) throw new Error(`Invalid app version: ${version}`);
  const build = process.env.NOTCHNOTCH_BUILD_NUMBER ?? "1";
  if (!/^\d{1,9}$/.test(build)) throw new Error(`Invalid build number: ${build}`);
  const app = path.join(root, "dist/NotchNotch.app");
  const contents = path.join(app, "Contents");
  await mkdir(path.join(contents, "MacOS"), { recursive: true });
  await mkdir(path.join(contents, "Helpers"), { recursive: true });
  await mkdir(path.join(contents, "Resources"), { recursive: true });
  await cp(productPath(root, "NotchNotch"), path.join(contents, "MacOS/NotchNotch"));
  await cp(productPath(root, "ExtensionRunner"), path.join(contents, "Helpers/ExtensionRunner"));
  await chmod(path.join(contents, "MacOS/NotchNotch"), 0o755);
  await chmod(path.join(contents, "Helpers/ExtensionRunner"), 0o755);
  await embedSparkle(contents);
  await cp(path.join(root, "apps/macos/Resources/AppIcon.icns"), path.join(contents, "Resources/AppIcon.icns"));
  const extensions = path.join(contents, "Resources/extensions");
  const source = path.join(root, "dist/extensions");
  await mkdir(extensions, { recursive: true });
  // Only extensions/* ship in the app; examples built for development stay out.
  const names = await bundledExtensionNames();
  for (const name of await readdir(extensions)) {
    if (!names.includes(name)) await rm(path.join(extensions, name), { recursive: true, force: true });
  }
  for (const name of names) await cp(path.join(source, name), path.join(extensions, name), { recursive: true });
  // Only release builds check for updates, so a development build is never replaced by a release.
  const publicKey = release ? await committedPublicKey() : null;
  if (release && !publicKey) console.warn("No apps/macos/SparklePublicKey: this build cannot update itself (node scripts/sparkle.mjs keys).");
  const updates = publicKey ? `<key>SUFeedURL</key><string>${feedURL}</string>
<key>SUPublicEDKey</key><string>${publicKey}</string>
<key>SUEnableAutomaticChecks</key><true/>
` : "";
  await writeFile(path.join(contents, "Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.notchnotch.app</string>
<key>CFBundleName</key><string>NotchNotch</string>
<key>CFBundleDisplayName</key><string>NotchNotch</string>
<key>CFBundleExecutable</key><string>NotchNotch</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${version.split("-")[0]}</string>
<key>CFBundleVersion</key><string>${build}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array><dict>
  <key>CFBundleTypeName</key><string>NotchNotch Extension</string>
  <key>CFBundleTypeRole</key><string>Viewer</string>
  <key>LSHandlerRank</key><string>Owner</string>
  <key>LSItemContentTypes</key><array><string>dev.notchnotch.extension-package</string></array>
</dict></array>
<key>UTExportedTypeDeclarations</key><array><dict>
  <key>UTTypeIdentifier</key><string>dev.notchnotch.extension-package</string>
  <key>UTTypeDescription</key><string>NotchNotch Extension</string>
  <key>UTTypeConformsTo</key><array><string>public.zip-archive</string><string>public.data</string></array>
  <key>UTTypeIconFile</key><string>AppIcon</string>
  <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>notchext</string></array></dict>
</dict></array>
<key>NSAppleEventsUsageDescription</key><string>Read the current song and control Spotify or Apple Music for the Music extension.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Read your selected calendars to show the next event and its countdown in the notch. The Calendar extension does not change your events.</string>
<key>NSCalendarsUsageDescription</key><string>Read your selected calendars to show upcoming events in the notch.</string>
${updates}</dict></plist>
`);
  // Inside out: bundled extension helpers were signed by their build modules.
  codesign(path.join(contents, "Helpers/ExtensionRunner"),
    { entitlements: path.join(root, "native/ExtensionRunner/ExtensionRunner.entitlements") });
  codesign(app, { entitlements: path.join(root, "apps/macos/NotchNotch.entitlements") });
  console.log(`App ready: ${app}`);
  return app;
}
if (process.argv[1] === new URL(import.meta.url).pathname) await packageApp();
