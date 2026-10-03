import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { MCP_PROFILES } from "../src/profiles.js";
import { publishedToolList } from "../src/server.js";
import { publishedTools } from "./support/companion.js";
import {
  CEILING_HISTORY,
  SCHEMA_CEILINGS as CEILINGS,
  schemaBytes,
  tokenRange
} from "./support/schema-budget.js";

// The ceilings and the rule that they only ever move down live with the
// measurement, in ./support/schema-budget.ts.

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

  // User story (#1027):
  // As the operator whose agent pays for the tool list at connect time,
  // I want "a ceiling only ever moves down" to be a test rather than a
  // comment,
  // so that a commit cannot raise a ceiling and stay green.
  //
  // Acceptance criteria:
  // - Every ceiling the budget has had is recorded, oldest first, with its
  //   date and its reason; no row sets any profile above the row before it.
  // - The ceilings in force are the last row's.
  // - The first row is the budget's own baseline (Sprint 17 A3, #994), so a
  //   history rewritten from its start fails here as well.
  it("only ever lowers a ceiling", () => {
    assert.ok(CEILING_HISTORY.length > 0);

    assert.deepEqual(
      { ...CEILING_HISTORY[0], why: undefined },
      { since: "2026-10-01", read: 106_000, book: 179_000, full: 209_000, why: undefined }
    );

    for (let i = 1; i < CEILING_HISTORY.length; i++) {
      const before = CEILING_HISTORY[i - 1];
      const row = CEILING_HISTORY[i];
      assert.ok(row.since >= before.since, `row ${i}: dated before the row it follows`);

      for (const profile of MCP_PROFILES) {
        assert.ok(
          row[profile] <= before[profile],
          `row ${i} (${row.since}) raises ${profile} from ${before[profile]} to ${row[profile]}: ` +
            "a ceiling only ever moves down; trim a description instead"
        );
      }
    }

    const last = CEILING_HISTORY[CEILING_HISTORY.length - 1];
    for (const profile of MCP_PROFILES) {
      assert.equal(CEILINGS[profile], last[profile], `${profile}: the ceiling in force is the last row's`);
    }
  });
});
