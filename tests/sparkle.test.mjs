import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { access, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { appcast, committedPublicKey, publicKeyFor, releaseNotesHTML, signArchive } from "../scripts/sparkle.mjs";

const signUpdate = ".build/artifacts/sparkle/Sparkle/bin/sign_update";
const seed = () => generateKeyPairSync("ed25519").privateKey.export({ format: "der", type: "pkcs8" }).subarray(16).toString("base64");

async function temporary(t) {
  const directory = await mkdtemp(path.join(tmpdir(), "notchnotch-sparkle-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

test("update signatures match Sparkle's own sign_update and verify with it", async (t) => {
  if (!(await access(signUpdate).then(() => true, () => false))) return t.skip("Sparkle tools are not resolved");
  const directory = await temporary(t);
  const key = seed();
  const keyFile = path.join(directory, "key");
  const archive = path.join(directory, "NotchNotch.zip");
  await writeFile(keyFile, key);
  await writeFile(archive, Buffer.from("update archive bytes"));
  const { signature, length } = await signArchive(archive, key);
  assert.equal(length, 20);
  const sparkle = spawnSync(signUpdate, ["--ed-key-file", keyFile, archive], { encoding: "utf8" });
  assert.equal(sparkle.status, 0, sparkle.stderr);
  // Ed25519 is deterministic, so both tools must produce the same signature.
  assert.match(sparkle.stdout, new RegExp(`sparkle:edSignature="${signature.replace(/[+/=]/g, "\\$&")}"`));
  const verify = spawnSync(signUpdate, ["--ed-key-file", keyFile, "--verify", archive, signature], { encoding: "utf8" });
  assert.equal(verify.status, 0, verify.stderr);
  await writeFile(archive, Buffer.from("tampered archive bytes"));
  assert.notEqual(spawnSync(signUpdate, ["--ed-key-file", keyFile, "--verify", archive, signature]).status, 0);
});

test("the committed public key is a valid EdDSA key and mismatched private keys are detectable", async () => {
  const key = await committedPublicKey();
  assert.equal(Buffer.from(key, "base64").length, 32);
  assert.notEqual(publicKeyFor(seed()), key);
  assert.throws(() => publicKeyFor("bm90IGEga2V5"));
});

test("the appcast is well-formed and release notes cannot inject markup", async (t) => {
  const notes = releaseNotesHTML(`# Changelog

## [Unreleased]
- Not yet.

## [0.3.0] - 2026-12-01

### Added
- **Updates** install with \`Sparkle\` <script>alert(1)</script>.

## [0.2.0] - 2026-11-09
- Older.
`, "0.3.0");
  assert.equal(notes, "<h3>Added</h3><ul><li><b>Updates</b> install with <code>Sparkle</code> &lt;script&gt;alert(1)&lt;/script&gt;.</li></ul>");
  const xml = appcast({ version: "0.3.0", build: "42", url: "https://github.com/o/r/releases/download/v0.3.0/NotchNotch-0.3.0.zip",
    signature: "c2ln", length: 10, notes: notes + "]]>" });
  const file = path.join(await temporary(t), "appcast.xml");
  await writeFile(file, xml);
  const lint = spawnSync("xmllint", ["--noout", file], { encoding: "utf8" });
  assert.equal(lint.status, 0, lint.stderr);
  assert.match(xml, /<sparkle:version>42<\/sparkle:version>/);
  assert.match(xml, /sparkle:edSignature="c2ln"/);
});
