// Sparkle update signing and appcast generation.
//
//   node scripts/sparkle.mjs keys     Create the EdDSA key pair (once). Stores the private
//                                     key outside the repository and writes the public key
//                                     to apps/macos/SparklePublicKey.
//
// Updates are signed with Ed25519 like Sparkle's own sign_update, so the release
// workflow needs no keychain: the private key comes from SPARKLE_PRIVATE_KEY.
import { createPrivateKey, createPublicKey, generateKeyPairSync, sign } from "node:crypto";
import { chmod, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const publicKeyFile = path.join(root, "apps/macos/SparklePublicKey");
export const privateKeyFile = path.join(homedir(), ".config/notchnotch/sparkle-ed25519-private-key");
export const repository = process.env.GITHUB_REPOSITORY || "NotchNotch/notchnotch";
/** Published by .github/workflows/appcast.yml when a release is published. */
export const feedURL = `https://raw.githubusercontent.com/${repository}/appcast/appcast.xml`;

// PKCS#8 / SPKI headers for a raw 32-byte Ed25519 seed / public key.
export const pkcs8 = Buffer.from("302e020100300506032b657004220420", "hex");
const spki = Buffer.from("302a300506032b6570032100", "hex");

/** Accepts Sparkle's exported private key: base64 of the 32-byte seed (or the legacy 64/96-byte forms). */
export function privateKey(base64) {
  const bytes = Buffer.from(base64.trim(), "base64");
  if (![32, 64, 96].includes(bytes.length)) throw new Error("SPARKLE_PRIVATE_KEY is not a Sparkle EdDSA private key");
  return createPrivateKey({ key: Buffer.concat([pkcs8, bytes.subarray(0, 32)]), format: "der", type: "pkcs8" });
}

export function publicKeyFor(privateBase64) {
  return createPublicKey(privateKey(privateBase64)).export({ format: "der", type: "spki" }).subarray(spki.length).toString("base64");
}

export async function committedPublicKey() {
  const key = (await readFile(publicKeyFile, "utf8").catch(() => "")).trim();
  if (key && Buffer.from(key, "base64").length !== 32) throw new Error(`${publicKeyFile} is not an EdDSA public key`);
  return key || null;
}

/** Returns the `sparkle:edSignature` and length for an update archive. */
export async function signArchive(file, privateBase64) {
  const data = await readFile(file);
  return { signature: sign(null, data, privateKey(privateBase64)).toString("base64"), length: data.length };
}

const escape = (value) => String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** The release notes for `version` from CHANGELOG.md as small, safe HTML. */
export function releaseNotesHTML(changelog, version) {
  const lines = changelog.split("\n");
  const start = lines.findIndex((line) => new RegExp(`^## \\[?${version.replace(/\./g, "\\.")}\\]?`).test(line));
  if (start < 0) return "";
  const end = lines.findIndex((line, index) => index > start && line.startsWith("## "));
  const inline = (text) => escape(text).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/`(.+?)`/g, "<code>$1</code>");
  let html = "", list = false;
  for (const line of lines.slice(start + 1, end < 0 ? undefined : end)) {
    const item = /^- (.*)/.exec(line);
    if (item) { if (!list) { html += "<ul>"; list = true; } html += `<li>${inline(item[1])}</li>`; continue; }
    if (list) { html += "</ul>"; list = false; }
    const heading = /^### (.*)/.exec(line);
    if (heading) html += `<h3>${inline(heading[1])}</h3>`;
    else if (line.trim()) html += `<p>${inline(line)}</p>`;
  }
  return list ? html + "</ul>" : html;
}

export function appcast({ version, build, url, signature, length, notes = "", minimumSystemVersion = "14.0", date = new Date() }) {
  return `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>NotchNotch</title>
    <item>
      <title>NotchNotch ${escape(version)}</title>
      <pubDate>${date.toUTCString()}</pubDate>
      <sparkle:version>${escape(build)}</sparkle:version>
      <sparkle:shortVersionString>${escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${escape(minimumSystemVersion)}</sparkle:minimumSystemVersion>
      <link>https://github.com/${repository}/releases/tag/v${escape(version)}</link>
      <description><![CDATA[${notes.replaceAll("]]>", "]]&gt;")}]]></description>
      <enclosure url="${escape(url)}" length="${length}" type="application/octet-stream" sparkle:edSignature="${escape(signature)}"/>
    </item>
  </channel>
</rss>
`;
}

async function generateKeys() {
  if (await committedPublicKey()) throw new Error(`${publicKeyFile} already exists. Keep using its key pair; a new one breaks updates for installed copies.`);
  if (await stat(privateKeyFile).then(() => true, () => false)) throw new Error(`${privateKeyFile} already exists`);
  const { privateKey: key } = generateKeyPairSync("ed25519");
  const seed = key.export({ format: "der", type: "pkcs8" }).subarray(pkcs8.length).toString("base64");
  await mkdir(path.dirname(privateKeyFile), { recursive: true, mode: 0o700 });
  await writeFile(privateKeyFile, seed + "\n", { mode: 0o600 });
  await chmod(privateKeyFile, 0o600);
  await writeFile(publicKeyFile, publicKeyFor(seed) + "\n");
  console.log(`Private key: ${privateKeyFile} (back it up; losing it means installed copies can't be updated)
Public key:  ${path.relative(root, publicKeyFile)} (commit it)

Let the release workflow sign updates:
  gh secret set SPARKLE_PRIVATE_KEY < ${privateKeyFile}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv[2] === "keys") await generateKeys();
  else { console.log("Usage: node scripts/sparkle.mjs keys"); process.exitCode = 1; }
}
