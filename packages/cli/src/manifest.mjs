/** The file name in `assets/` when `icon` names a PNG, otherwise `undefined`. */
export function iconFile(manifest) {
  if (typeof manifest.icon !== "string" || !manifest.icon.endsWith(".png")) return undefined;
  return manifest.icon;
}

/** Categories an extension can list in its manifest, in display order. A test keeps this in step with schemas/manifest.schema.json. */
export const categories = [
  "Communication", "Developer Tools", "Finance", "Fun", "Health", "Media",
  "News", "Productivity", "Sports", "System", "Weather", "Other",
];

/** The `accent` names the app draws in shades tuned for the notch. A test keeps this in step with schemas/manifest.schema.json. */
export const accents = ["orange", "yellow", "green", "mint", "cyan", "blue", "purple", "pink", "red"];

export const preferenceTypes = new Set(["text", "password", "toggle", "dropdown"]);

/** Same rules as ExtensionPreference.validate in the app. */
function validatePreferences(manifest) {
  const list = manifest.preferences;
  if (list === undefined) return;
  const fail = (message) => { throw new Error(`Unsupported manifest: ${manifest.id}: ${message}`); };
  if (!Array.isArray(list) || list.length > 16 || new Set(list.map((item) => item?.name)).size !== list.length) {
    fail("preferences must list up to 16 entries with unique names");
  }
  const short = (value, max) => value === undefined || (typeof value === "string" && value.length <= max);
  for (const item of list) {
    if (!item || typeof item !== "object" || typeof item.name !== "string" || !/^[A-Za-z][A-Za-z0-9_]{0,31}$/.test(item.name)) {
      fail("preference names use letters, digits and _, start with a letter, up to 32 characters");
    }
    const at = (message) => fail(`preference ${item.name}: ${message}`);
    if (!preferenceTypes.has(item.type)) at("type is text, password, toggle or dropdown");
    if (typeof item.title !== "string" || item.title.length < 1 || item.title.length > 64 ||
        !short(item.description, 256) || !short(item.placeholder, 128)) at("title is 1–64 characters, description up to 256, placeholder up to 128");
    if (item.required !== undefined && typeof item.required !== "boolean") at("required is true or false");
    const fallback = item.default;
    if (item.type === "text" && fallback !== undefined && !(typeof fallback === "string" && Buffer.byteLength(fallback) <= 4096)) at("default must be text");
    if (item.type === "password" && fallback !== undefined) at("a password can't have a default");
    if (item.type === "toggle" && item.required) at("a toggle can't be required");
    if (item.type === "toggle" && fallback !== undefined && typeof fallback !== "boolean") at("default must be true or false");
    if (item.type === "dropdown") {
      const options = item.options;
      if (!Array.isArray(options) || options.length < 1 || options.length > 32 ||
          new Set(options.map((option) => option?.value)).size !== options.length ||
          options.some((option) => !short(option?.value, 64) || !option.value || !short(option?.title, 64) || !option.title)) {
        at("a dropdown needs 1–32 options with unique values and titles of up to 64 characters");
      }
      if (fallback !== undefined && !options.some((option) => option.value === fallback)) at("default must be one of the option values");
    } else if (item.options !== undefined) at("only a dropdown has options");
  }
}

function validateStoreMetadata(manifest) {
  const fail = (message) => { throw new Error(`Unsupported manifest: ${manifest.id}: ${message}`); };
  const { author, categories: listed, homepage, repository, license } = manifest;
  if (author !== undefined && (typeof author !== "string" || !/^[a-z0-9]([a-z0-9-]{0,37}[a-z0-9])?$/.test(author))) {
    fail("author must be a store handle: lowercase letters, digits and hyphens, up to 39 characters");
  }
  if (listed !== undefined && (!Array.isArray(listed) || listed.length < 1 || listed.length > 3 ||
      new Set(listed).size !== listed.length || listed.some((category) => !categories.includes(category)))) {
    fail(`categories must list one to three of: ${categories.join(", ")}`);
  }
  for (const [field, value] of [["homepage", homepage], ["repository", repository]]) {
    if (value === undefined) continue;
    let url;
    try { url = typeof value === "string" && value.length <= 2048 ? new URL(value) : null; } catch { url = null; }
    if (!url || url.protocol !== "https:" || !url.hostname || url.username || url.password) fail(`${field} must be an https:// address`);
  }
  if (license !== undefined && (typeof license !== "string" || license.length > 64 ||
      !/^[A-Za-z0-9.+-]+( (AND|OR|WITH) [A-Za-z0-9.+-]+)*$/.test(license))) {
    fail("license must be an SPDX license identifier, such as MIT");
  }
}

/** Capabilities are permissions too; each one is also a stream named `capability:<name>`. */
export const capabilities = ["calendar", "now-playing"];
export const allowedPermissions = new Set(["local-network", "process", ...capabilities]);

export function validateManifest(manifest) {
  const invalid = () => { throw new Error(`Unsupported manifest: ${manifest.id ?? "unknown"}`); };
  if (!/^[a-z][a-z0-9.-]{2,79}$/.test(manifest.id) || typeof manifest.name !== "string" || !manifest.name || manifest.name.length > 128 ||
      typeof manifest.version !== "string" || !manifest.version || manifest.version.length > 64 ||
      manifest.apiVersion !== 1 || manifest.entry !== "bundle.js" || !Array.isArray(manifest.permissions) ||
      new Set(manifest.permissions).size !== manifest.permissions.length ||
      manifest.permissions.some((permission) => !allowedPermissions.has(permission))) invalid();
  if ((manifest.icon !== undefined && (typeof manifest.icon !== "string" || manifest.icon.length > 128)) ||
      (manifest.description !== undefined && (typeof manifest.description !== "string" || manifest.description.length > 512))) invalid();
  if (manifest.accent !== undefined && !accents.includes(manifest.accent)) {
    throw new Error(`Unsupported manifest: ${manifest.id}: accent must be one of: ${accents.join(", ")}`);
  }
  validatePreferences(manifest);
  validateStoreMetadata(manifest);
  if (manifest.icon?.endsWith(".png") && !/^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,99}\.png$/.test(manifest.icon)) {
    throw new Error(`Unsupported manifest: ${manifest.id}: icon must be an SF Symbol name or the file name of a PNG in assets/, such as icon.png`);
  }
  const hostList = (hosts, maximum) => hosts === undefined || (Array.isArray(hosts) && hosts.length <= maximum &&
    new Set(hosts).size === hosts.length && hosts.every((host) => typeof host === "string" && host.length <= 253 &&
      /^(\*\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(host)));
  if (!hostList(manifest.imageHosts, 8)) invalid();
  if (!hostList(manifest.network, 16)) {
    throw new Error(`Unsupported manifest: ${manifest.id}: network must list up to 16 lowercase DNS names, optionally starting with *.`);
  }
  const connections = manifest.connections ?? {};
  if (!connections || typeof connections !== "object" || Array.isArray(connections) || Object.keys(connections).length > 8) invalid();
  for (const [id, value] of Object.entries(connections)) {
    if (!/^[a-z][a-z0-9-]{0,63}$/.test(id) || !value || typeof value !== "object") invalid();
    if (["http", "websocket"].includes(value.transport)) {
      let url;
      try { url = new URL(value.endpoint); } catch { invalid(); }
      const schemes = value.transport === "http" ? ["http:", "https:"] : ["ws:", "wss:"];
      if (!manifest.permissions.includes("local-network") || value.executable !== undefined || value.arguments !== undefined ||
          !schemes.includes(url.protocol) || !["127.0.0.1", "[::1]"].includes(url.hostname) ||
          url.username || url.password || url.search || url.hash || (value.transport === "http" && url.pathname !== "/")) invalid();
      // Reject alternate IP encodings that WHATWG URL silently normalizes.
      const pattern = value.transport === "http"
        ? /^https?:\/\/(?:127\.0\.0\.1|\[::1\]):([0-9]+)\/?$/
        : /^wss?:\/\/(?:127\.0\.0\.1|\[::1\]):([0-9]+)(\/[^?#]*)?$/;
      const origin = pattern.exec(value.endpoint);
      if (!origin || Number(origin[1]) < 1 || Number(origin[1]) > 65535) invalid();
    } else if (value.transport === "stdio") {
      const executable = value.executable;
      if (!manifest.permissions.includes("process") || value.endpoint !== undefined ||
          typeof executable !== "string" || !executable || Buffer.byteLength(executable) > 1024 || executable.includes("\0") ||
          !(executable.startsWith("/") || !executable.includes("/") ||
            (executable.startsWith("./") && !executable.split("/").includes(".."))) ||
          (value.arguments !== undefined && (!Array.isArray(value.arguments) || value.arguments.length > 32 ||
            value.arguments.some((argument) => typeof argument !== "string" || argument.includes("\0") || Buffer.byteLength(argument) > 4096)))) invalid();
    } else invalid();
  }
}
