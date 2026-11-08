import { mkdir, copyFile, writeFile, chmod } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { codesign, productPath, swiftBuild } from "../../scripts/native.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));

export async function build({ root, destination }) {
  swiftBuild(root, "CalendarAdapter");
  const bundle = path.join(destination, "helpers/CalendarAdapter.app");
  const contents = path.join(bundle, "Contents");
  await mkdir(path.join(contents, "MacOS"), { recursive: true });
  const binary = path.join(contents, "MacOS/CalendarAdapter");
  await copyFile(productPath(root, "CalendarAdapter"), binary);
  await chmod(binary, 0o755);
  await writeFile(path.join(contents, "Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.notchnotch.calendar.adapter</string>
<key>CFBundleName</key><string>NotchNotch Calendar</string>
<key>CFBundleExecutable</key><string>CalendarAdapter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>Read your selected calendars to show the next event and its countdown in the notch. This extension does not change your events.</string>
<key>NSCalendarsUsageDescription</key><string>Read your selected calendars to show upcoming events in the notch.</string>
</dict></plist>
`);
  codesign(bundle, { entitlements: path.join(here, "helper.entitlements") });
}
