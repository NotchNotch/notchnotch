import { mkdir, cp, writeFile, chmod, readdir, rm, readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { bundledExtensionNames, root } from "./build-extensions.mjs";

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
  await cp(path.join(root, ".build/debug/NotchNotch"), path.join(contents, "MacOS/NotchNotch"));
  await cp(path.join(root, ".build/debug/ExtensionRunner"), path.join(contents, "Helpers/ExtensionRunner"));
  await chmod(path.join(contents, "MacOS/NotchNotch"), 0o755);
  await chmod(path.join(contents, "Helpers/ExtensionRunner"), 0o755);
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
<key>NSAppleEventsUsageDescription</key><string>Allow extensions you choose to read and control other applications.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Allow the Calendar extension to read selected calendars and show upcoming events in the notch.</string>
<key>NSCalendarsUsageDescription</key><string>Allow the Calendar extension to show upcoming events in the notch.</string>
</dict></plist>
`);
  for (const target of [path.join(contents, "Helpers/ExtensionRunner"), app]) {
    const result = spawnSync("codesign", ["--force", "--sign", "-", target], { stdio: "inherit" });
    if (result.status !== 0) throw new Error("Local ad-hoc signing failed");
  }
  console.log(`App ready: ${app}`);
  return app;
}
if (process.argv[1] === new URL(import.meta.url).pathname) await packageApp();
