import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { MCP_PROFILES } from "../src/profiles.js";
import { publishedToolList } from "../src/server.js";
import { publishedTools } from "./support/companion.js";
import {
  CEILING_HISTORY,
  type CeilingRow,
  SCHEMA_CEILINGS as CEILINGS,
  schemaBytes,
  tokenRange
} from "./support/schema-budget.js";

// The ceilings and the rule that they only ever move down live with the
// measurement, in ./support/schema-budget.ts.
//
// The ceiling history as it must read, row for row (#1027 review round): a
// literal copy, so no row there can be deleted or edited, the last one
// included, without this test going red. Lowering a ceiling appends the same
// row in both places; nothing else changes either list.
const PINNED_HISTORY: readonly CeilingRow[] = [
  {
    since: "2026-10-01",
    why: "the budget lands (Sprint 17 A3, #994)",
    read: 106_000,
    book: 179_000,
    full: 209_000
  },
  {
    since: "2026-10-03",
    why:
      "Sprint 18 PR β, F4 and F5 (#901, #1007): paid for by trimming, and lowered to the " +
      "figure measured when β opened, giving up the slack above it; the 1,420 bytes now " +
      "measured under it are left for F2's two tools in the same PR, which lower it to " +
      "their own figure (D-10)",
    read: 105_851,
    book: 178_964,
    full: 208_833
  },
  {
    since: "2026-10-03",
    why:
      "Sprint 18 PR β, F2 (FR-41): the two contribution tools, paid for by trimming the " +
      "performance family's descriptions and #831's re-import sentence, and lowered to the " +
      "figure measured with them (D-10)",
    read: 105_808,
    book: 178_921,
    full: 208_790
  },
  {
    since: "2026-10-03",
    why:
      "Sprint 18 PR β review: views.valuation names the conditions under which the " +
      "view-less total is the dashboard's, paid for by trimming its own description, and " +
      "lowered to the figure measured with it",
    read: 105_807,
    book: 178_920,
    full: 208_789
  },
  {
    since: "2026-10-03",
    why:
      "Sprint 18 PR γ, U1 (#912): the whole-split delete, an admin tool, paid for by " +
      "trimming the split family's and transactions.list's descriptions, and lowered to the " +
      "figure measured with it (D-10)",
    read: 105_308,
    book: 178_155,
    full: 208_768
  },
  {
    since: "2026-10-03",
    why:
      "Sprint 18 PR γ, U7 (#330): a bond's master data on the security writes and its " +
      "reading on securities.get, paid for by tightening the shared bounded-date sentence " +
      "and the securities family's descriptions, and lowered to the figure measured with " +
      "it (D-10)",
    read: 103_991,
    book: 177_091,
    full: 207_454
  },
  {
    since: "2026-10-03",
    why:
      "Sprint 18 PR γ, U7 closing act (#330): face_value_currency_code describes itself, " +
      "paid for by tightening the bond fields' and securities.update's property " +
      "descriptions, and lowered to the figure measured with it",
    read: 103_991,
    book: 177_085,
    full: 207_448
  },
  {
    since: "2026-10-05",
    why:
      "PR #1102: securities.update takes is_retired, the remedy securities.delete names when " +
      "research notes or rule versions reference a security, paid for by tightening " +
      "securities.update's description and its currency_code, treat_quotes_as_raw and " +
      "is_benchmark properties, and lowered to the figure measured with it (D-10)",
    read: 103_991,
    book: 177_080,
    full: 207_443
  },
  {
    since: "2026-10-05",
    why:
      "PR #1102 review: securities.list says no benchmark or retired security is in the three " +
      "hygiene sets, securities.delete names securities.update for retiring, and is_retired " +
      "says it can restate TTWROR history, paid for by tightening securities.list's " +
      "data_quality sentence, the delete's referenced_by example and treat_quotes_as_raw, and " +
      "lowered to the figure measured with them (D-10)",
    read: 103_990,
    book: 177_072,
    full: 207_420
  },
  {
    since: "2026-10-06",
    why:
      "Sprint 19 PR α, M7 (#1068, D-15): securities.list takes data_quality two_scales and " +
      "securities.get says its bond reading reaches a security with no class and a maturity " +
      "or coupon and names the two_scales direction, paid for by tightening the securities " +
      "family's descriptions, dropping requirement and issue ids from eight descriptions and a " +
      "sentence holdings.reconcile's rows repeated, and lowered to the figure measured (D-10)",
    read: 103_986,
    book: 177_068,
    full: 207_416
  },
  {
    since: "2026-10-06",
    why:
      "Sprint 19 PR β, B5 (#1056, #1091, #959): the view performance, benchmark and " +
      "contribution tools read every account in EUR with no id, category_results reads every " +
      "portfolio with no scope and names excluded_members, and the benchmark selector names " +
      "merged_into, paid for by dropping the needs-a-view text from the six twin descriptions, " +
      "the id requirement from three schemas and two repeated clauses of category_results, and " +
      "lowered to the figure measured (D-10)",
    read: 103_457,
    book: 176_539,
    full: 206_887
  },
  {
    since: "2026-10-06",
    why:
      "Sprint 19 PR β, B2 (#933): securities.list's missing_logo wording names a logo whose " +
      "file is gone, in fewer bytes than the wording it replaces, and the ceilings are " +
      "lowered to the figure measured with it",
    read: 103_454,
    book: 176_536,
    full: 206_884
  },
  {
    since: "2026-10-08",
    why:
      "Sprint 20 β, B3 (#1142): trades.list and cashflow.realized_gains name a zero cost " +
      "basis among annualized_return_reason's reasons and say realized_pnl_pct is null on it, " +
      "paid for by dropping realized_gains' neighbouring-date clause the conversion_note " +
      "carries and tightening both descriptions, and lowered to the figure measured (D-10)",
    read: 103_438,
    book: 176_520,
    full: 206_868
  },
  {
    since: "2026-10-08",
    why:
      "Sprint 20 β, B4 (#1101): securities.list takes data_quality implausible_quote and " +
      "says what it holds and that the envelope carries findings and computation_basis, " +
      "paid for by tightening the delta-read sentences of securities.list and notes.list " +
      "and dropping the list's pointer to the security writes, and lowered to the figure " +
      "measured (D-10)",
    read: 103_375,
    book: 176_457,
    full: 206_805
  },
  {
    since: "2026-10-08",
    why:
      "Sprint 20 PR γ, C2 (#1103): securities.list takes is_retired, as it takes is_benchmark, " +
      "and says what each value lists, paid for by naming the benchmarks by ADR-0046 alone and " +
      "dropping targets.list_positions' \"Read ergonomics\" label with its requirement and issue " +
      "ids, and lowered to the figure measured (D-10)",
    read: 103_360,
    book: 176_442,
    full: 206_790
  },
  {
    since: "2026-10-08",
    why:
      "Sprint 20 PR γ, C2 (#1133): the three target writes take plan_id and their descriptions " +
      "say so, plans.duplicate names the way to edit its draft, paid for by tightening " +
      "targets.set's batch and sums sentences, dropping requirement and issue ids from the " +
      "target family and trimming events.delete's and snapshots.delete's closing clauses, and " +
      "lowered to the figure measured with it (D-10)",
    read: 103_284,
    book: 176_346,
    full: 206_730
  }
];

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
  // - The whole history equals the copy pinned in this file, row for row,
  //   from the budget's own baseline (Sprint 17 A3, #994) to the last row
  //   (#1027 review round). Deleting a row or editing one, upward or not,
  //   fails here; lowering a ceiling means appending its row in both places,
  //   and the copy is held to the same rule as the history.
  it("only ever lowers a ceiling", () => {
    assert.ok(CEILING_HISTORY.length > 0);

    assert.deepEqual(
      CEILING_HISTORY,
      PINNED_HISTORY,
      "the ceiling history differs from the copy pinned in this test: a row is never deleted " +
        "or edited, and lowering a ceiling appends the same row in both places"
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
