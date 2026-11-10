// Store catalog signing.
//
//   node scripts/catalog.mjs keys              Create the catalog key pair (once). Stores the private
//                                              key outside the repository and writes the public key to
//                                              apps/macos/CatalogPublicKey, which the app trusts.
//   node scripts/catalog.mjs sign index.json   Write index.json.sig with CATALOG_PRIVATE_KEY.
//
// The extensions repository's CI builds index.json after every merge and signs
// it here. The app checks the signature over the file's exact bytes, so the
// signed file must be uploaded unchanged.
import { generateKeyPairSync, sign } from "node:crypto";
import { chmod, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { pkcs8, privateKey, publicKeyFor } from "./sparkle.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const publicKeyFile = path.join(root, "apps/macos/CatalogPublicKey");
export const privateKeyFile = path.join(homedir(), ".config/notchnotch/catalog-ed25519-private-key");

/** The base64 detached signature over `bytes`, as written to index.json.sig. */
export function signCatalog(bytes, privateBase64) {
  if (Buffer.from(privateBase64.trim(), "base64").length !== 32) throw new Error("CATALOG_PRIVATE_KEY is not a base64 Ed25519 seed");
  return sign(null, bytes, privateKey(privateBase64)).toString("base64");
}

async function generateKeys() {
  if (await stat(publicKeyFile).then(() => true, () => false)) {
    throw new Error(`${publicKeyFile} already exists. Keep using its key pair; a new one makes installed copies reject the Store.`);
  }
  if (await stat(privateKeyFile).then(() => true, () => false)) throw new Error(`${privateKeyFile} already exists`);
  const { privateKey: key } = generateKeyPairSync("ed25519");
  const seed = key.export({ format: "der", type: "pkcs8" }).subarray(pkcs8.length).toString("base64");
  await mkdir(path.dirname(privateKeyFile), { recursive: true, mode: 0o700 });
  await writeFile(privateKeyFile, seed + "\n", { mode: 0o600 });
  await chmod(privateKeyFile, 0o600);
  await writeFile(publicKeyFile, publicKeyFor(seed) + "\n");
  console.log(`Private key: ${privateKeyFile} (back it up; losing it means a new key and an app update)
Public key:  ${path.relative(root, publicKeyFile)} (commit it)

Let the extensions repository's CI sign the catalog:
  gh secret set CATALOG_PRIVATE_KEY --repo sadeqi-ah/notchnotch-extensions < ${privateKeyFile}`);
}

async function signFile(file) {
  const key = process.env.CATALOG_PRIVATE_KEY;
  if (!key) throw new Error("Set CATALOG_PRIVATE_KEY to the base64 private key");
  await writeFile(file + ".sig", signCatalog(await readFile(file), key) + "\n");
  console.log(`Signed ${file} → ${file}.sig`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command, file] = process.argv.slice(2);
  if (command === "keys") await generateKeys();
  else if (command === "sign" && file) await signFile(file);
  else { console.log("Usage: node scripts/catalog.mjs keys | sign <index.json>"); process.exitCode = 1; }
}
