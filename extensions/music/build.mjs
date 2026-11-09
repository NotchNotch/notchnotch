import path from "node:path";
import { fileURLToPath } from "node:url";
import { helperApp, productPath, swiftBuild } from "../../scripts/native.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));

export async function build({ root, destination }) {
  swiftBuild(root, "MusicAdapter");
  await helperApp({
    destination, name: "MusicAdapter", binary: productPath(root, "MusicAdapter"),
    bundleIdentifier: "dev.notchnotch.music.adapter", displayName: "NotchNotch Music",
    usageDescriptions: {
      NSAppleEventsUsageDescription: "Read the current song and control Spotify or Apple Music for the Music extension.",
    },
    entitlements: path.join(here, "helper.entitlements"),
  });
}
