import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { generate, generateSwift, generateTypeScript } from "../scripts/generate-protocol.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

test("the Swift and TypeScript models match the schemas", async () => {
  for (const [file, text] of Object.entries(await generate())) {
    assert.equal(await readFile(path.join(root, file), "utf8"), text, `${file} is out of date: run node scripts/generate-protocol.mjs`);
  }
});

test("names, defaults, constants and optional JSON come from the schema's annotations", () => {
  const schema = {
    $defs: {
      json: { "x-name": "JSONValue", "x-swift-external": true, "x-ts-type": "unknown" },
      message: {
        "x-name": "Message", description: "A test message.", type: "object", required: ["type", "kind", "count"],
        properties: {
          type: { const: "message" },
          kind: { "x-swift-name": "MessageKind", "x-ts-name": "Kind", enum: ["plain", "repeat"], default: "plain" },
          count: { type: "integer", default: 1 },
          payload: { $ref: "#/$defs/json", description: "Anything." },
          default: { type: "string" },
        },
      },
    },
  };
  const swift = generateSwift([schema]);
  assert.match(swift, /public struct Message: Codable, Equatable, Sendable \{/);
  assert.match(swift, /public var type = "message"/);
  assert.match(swift, /case `repeat` = "repeat"|case `repeat`/);
  assert.match(swift, /public init\(kind: MessageKind = \.plain, count: Int = 1, payload: JSONValue\? = nil, default value: String\? = nil\)/);
  assert.match(swift, /payload = values\.contains\(\.payload\) \? try values\.decode\(JSONValue\.self/);
  assert.doesNotMatch(swift, /enum JSONValue/);
  const ts = generateTypeScript([schema]);
  assert.match(ts, /export type Kind = "plain" \| "repeat";/);
  assert.match(ts, /\/\*\* Anything\. \*\/\n  payload\?: JSONValue;/);
  assert.match(ts, /type: "message";/);
});

test("the CLI's manifest lists match the schema", async () => {
  const schema = JSON.parse(await readFile(path.join(root, "schemas/manifest.schema.json"), "utf8"));
  const { categories, accents, allowedPermissions, preferenceTypes } = await import("../packages/cli/src/manifest.mjs");
  assert.deepEqual(categories, schema.properties.categories.items.enum);
  assert.deepEqual(accents, schema.properties.accent.enum);
  assert.deepEqual([...allowedPermissions], schema.properties.permissions.items.enum);
  assert.deepEqual([...preferenceTypes], schema.properties.preferences.items.properties.type.enum);
});
