import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { MCP_PROFILES, type McpProfile } from "../src/profiles.js";
import { publishedToolList } from "../src/server.js";
import { publishedTools } from "./support/companion.js";
import { schemaBytes, tokenRange } from "./support/schema-budget.js";

// THE SCHEMA BUDGET (Sprint 17 A3, #994). The ceilings were set at the
// figures measured on 2026-10-01, the day the budget landed, each rounded up
// to the next 1,000 bytes (a margin under 1 %): read 105,541, book 178,654,
// full 208,406 bytes.
//
// A ceiling only ever moves down. When the surface shrinks, lower it to the
// new figure; never raise it. A tool or a description that needs more room
// pays for it by trimming another, so connecting never silently costs more.
const CEILINGS: Record<McpProfile, number> = {
  read: 106_000,
  book: 179_000,
  full: 209_000
};

describe("the schema budget", () => {
  // User story (A3, #994):
  // As the operator whose agent loads every tool schema at connect time,
  // I want the context the companion's tool list costs measured per profile
  // and held under a ceiling that only moves down,
  // so that connecting does not grow more expensive unnoticed.
  //
  // Acceptance criteria:
  // - The measured list is exactly what a host receives from tools/list.
  // - Each profile's list stays at or under its ceiling, and the profiles
  //   order read < book < full.
  it("holds each profile's tool list under its ceiling", async (t) => {
    for (const profile of MCP_PROFILES) {
      assert.deepEqual(
        await publishedTools({ profile }),
        JSON.parse(JSON.stringify(publishedToolList({ profile }))),
        `${profile}: the measured list is the published one`
      );

      const bytes = schemaBytes(profile);
      const tokens = tokenRange(bytes);
      t.diagnostic(
        `${profile}: ${publishedToolList({ profile }).length} tools, ${bytes} bytes, ` +
          `about ${tokens.low}-${tokens.high} tokens`
      );

      assert.ok(
        bytes <= CEILINGS[profile],
        `${profile}: ${bytes} bytes is over its ceiling of ${CEILINGS[profile]}; trim a ` +
          "description rather than raise the ceiling, which only ever moves down"
      );
    }

    assert.ok(schemaBytes("read") < schemaBytes("book"));
    assert.ok(schemaBytes("book") < schemaBytes("full"));
  });
});
