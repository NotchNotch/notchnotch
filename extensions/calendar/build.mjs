import path from "node:path";
import { fileURLToPath } from "node:url";
import { helperApp, productPath, swiftBuild } from "../../scripts/native.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));

export async function build({ root, destination }) {
  swiftBuild(root, "CalendarAdapter");
  await helperApp({
    destination, name: "CalendarAdapter", binary: productPath(root, "CalendarAdapter"),
    bundleIdentifier: "dev.notchnotch.calendar.adapter", displayName: "NotchNotch Calendar",
    usageDescriptions: {
      NSCalendarsFullAccessUsageDescription: "Read your selected calendars to show the next event and its countdown in the notch. This extension does not change your events.",
      NSCalendarsUsageDescription: "Read your selected calendars to show upcoming events in the notch.",
    },
    entitlements: path.join(here, "helper.entitlements"),
  });
}
