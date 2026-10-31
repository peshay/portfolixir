import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

const INT4_MAX = 2_147_483_647;
const INT4_MIN = -2_147_483_648;

function calls(position: number): Array<[string, Record<string, any>]> {
  return [
    ["portfolixir.classifications.create", { classification: { name: "Satellite", position } }],
    ["portfolixir.classifications.update", { id: 1, classification: { position } }],
    [
      "portfolixir.classifications.categories.create",
      { classification_id: 1, category: { name: "Edge", position } }
    ],
    [
      "portfolixir.classifications.categories.update",
      { classification_id: 1, id: 2, category: { position } }
    ]
  ];
}

// User story (security review 2026-10-12, H31):
// As the agent ordering classifications and categories through the companion,
// I want a position the database cannot hold refused by the tool's own schema,
// so that my call answers with the bound instead of reaching the API as a
// server error.
//
// Acceptance criteria:
// - The four write tools refuse a position past the int4 range before any
//   request, and advertise the bounds on every position property.
// - The int4 edges themselves are forwarded.
describe("classification and category position bounds", () => {
  it("refuses a position past the int4 range before any API request", async () => {
    const forwarded: string[] = [];

    for (const position of [INT4_MAX + 1, INT4_MIN - 1, 3_000_000_000]) {
      for (const [name, args] of calls(position)) {
        const { client, requests } = createRecordingClient();
        let refused = false;

        try {
          await callTool(client, name, args);
        } catch {
          refused = true;
        }

        if (!refused || requests.length > 0) {
          forwarded.push(
            `${name} position=${position} -> ${JSON.stringify(
              requests.map((r) => [r.method, r.path, r.body])
            )}`
          );
        }
      }
    }

    assert.deepEqual(forwarded, [], `forwarded to the API:\n${forwarded.join("\n")}`);
  });

  it("advertises the int4 bounds on every position property", () => {
    const names = new Set(calls(0).map(([name]) => name));
    const unbounded: string[] = [];

    for (const tool of listTools()) {
      if (!names.has(tool.name)) continue;
      const props = (tool.inputSchema as any).properties;
      const inner = props.classification ?? props.category;
      const position = inner.properties.position;

      if (!(position.minimum >= INT4_MIN && position.maximum <= INT4_MAX)) {
        unbounded.push(`${tool.name}: ${JSON.stringify(position)}`);
      }
    }

    assert.deepEqual(unbounded, [], `unbounded position schemas:\n${unbounded.join("\n")}`);
  });

  it("still accepts the int4 edges", async () => {
    for (const position of [INT4_MAX, INT4_MIN]) {
      for (const [name, args] of calls(position)) {
        const { client, requests } = createRecordingClient();
        await callTool(client, name, args);
        assert.equal(requests.length, 1, `${name} position=${position} made no request`);
      }
    }
  });
});
