import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { MCP_PROFILES } from "../src/profiles.js";
import { publishedToolList } from "../src/server.js";
import { publishedTools } from "./support/companion.js";
import {
  CEILING_HISTORY,
  ceilingViolations,
  type CeilingRow,
  SCHEMA_CEILINGS as CEILINGS,
  schemaBytes,
  tokenRange,
  toolBytes
} from "./support/schema-budget.js";

// The ceilings and the rule that they only ever move down (or up by a new
// tool's own bytes, Sprint 24 plan D-2) live with the measurement, in
// ./support/schema-budget.ts.
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
  },
  {
    since: "2026-10-08",
    why:
      "Sprint 20 PR γ, C2 (#1135): plans.duplicate and plans.delete name the position targets " +
      "they copy and delete beside the category targets, paid for by dropping plans.activate's " +
      "restatement of the one-active-plan rule, and lowered to the figure measured with it (D-10)",
    read: 103_284,
    book: 176_305,
    full: 206_702
  },
  {
    since: "2026-10-08",
    why:
      "Sprint 20 PR γ, C3 (#940): the category writes name the tree's 32-level bound, paid " +
      "for by dropping categories.update's restatement of the fields its schema lists, and " +
      "lowered to the figure measured with it (D-10)",
    read: 103_284,
    book: 176_298,
    full: 206_695
  },
  {
    since: "2026-10-08",
    why:
      "Sprint 20 PR γ, C5 (#1159): merges.list says a record holds an ISIN choice only where " +
      "one was made, paid for by shortening its own actor_label and journal sentences, and " +
      "lowered to the figure measured with it (D-10)",
    read: 103_275,
    book: 176_289,
    full: 206_686
  },
  {
    since: "2026-10-08",
    why:
      "Sprint 20 PR γ, D-14 (#1159's flaw, on collapse_key_equal): merges.list says each choice is " +
      "held only where one was made, shorter than its ISIN-only sentence, and lowered to the " +
      "figure measured with it (D-10)",
    read: 103_265,
    book: 176_279,
    full: 206_676
  },
  {
    since: "2026-10-08",
    why:
      "Sprint 20 PR γ, D-14 (#972): securities_accounts.merge_preview lists rounding_differences " +
      "per position and split date with no bound per split, as ADR-0050's amendment says, in " +
      "fewer bytes, and lowered to the figure measured with it (D-10)",
    read: 103_261,
    book: 176_275,
    full: 206_672
  },
  {
    since: "2026-10-31",
    why:
      "Sprint 21, the security batch (the 2026-10-12 review's S4, S6 and S7 rows): every byte " +
      "the batch's descriptions added was paid by a trim in the same tool, the book profile lost " +
      "policy_rules.add_version to the admin set (H13), and the ceilings are lowered once, at the " +
      "end, to the figures measured with the whole batch (the amendment's D-6; D-10's rule)",
    read: 102_986,
    book: 172_005,
    full: 206_560
  },
  {
    since: "2026-10-31",
    why:
      "Sprint 21, stacked PR 1 (the money stories, alpha and beta): every byte the stories' " +
      "descriptions added (plan_id on the target reads, the fees-in-figures bases, the " +
      "unavailable trade, the settlement-leg counts) was paid by a trim in the same tool, and " +
      "the ceilings are lowered once, at the end, to the figures measured with the whole PR " +
      "(the amendment's D-9; D-10's rule)",
    read: 102_911,
    book: 171_982,
    full: 206_537
  },
  {
    since: "2026-11-01",
    why:
      "Sprint 21, stacked PR 2 (the UI batch): the Costs read's month totals paid their bytes in " +
      "the same tool, and the ceilings are lowered once, at the end, to the figures measured " +
      "with the whole PR (the amendment's D-9; D-10's rule)",
    read: 102_909,
    book: 171_980,
    full: 206_535
  },
  {
    since: "2026-11-02",
    why:
      "Sprint 22, the stacked PR's closing act: the plan's criterion holds the ceilings no " +
      "higher than Sprint 21's, and the sprint's descriptions paid their bytes in the same " +
      "tools, so the ceilings are lowered once, at the end, to the figures measured with the " +
      "whole sprint, with no slack (D-10's rule)",
    read: 102_887,
    book: 171_958,
    full: 206_513
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
  // - The measured list is exactly what a host receives from tools/list,
  //   and so is its size: the SDK's own serialisation of the list an MCP
  //   client receives counts the same bytes (SDK v2, #1115).
  // - Each profile's list stays at or under its ceiling, and the profiles
  //   order read < book < full.
  it("holds each profile's tool list under its ceiling", async (t) => {
    for (const profile of MCP_PROFILES) {
      const received = await publishedTools({ profile });

      assert.deepEqual(
        received,
        JSON.parse(JSON.stringify(publishedToolList({ profile }))),
        `${profile}: the measured list is the published one`
      );

      const bytes = schemaBytes(profile);

      assert.equal(
        Buffer.byteLength(JSON.stringify(received), "utf8"),
        bytes,
        `${profile}: the list the SDK hands a client measures what the budget measures`
      );
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
  // - The one exception (Sprint 24 plan D-2, D1): a row that names the new
  //   tools it pays for (raisedBy) may raise each profile by at most their
  //   own published bytes in that profile, which the row records; while it
  //   is the row in force, what it records is what those tools measure.
  it("only ever lowers a ceiling", () => {
    assert.ok(CEILING_HISTORY.length > 0);

    assert.deepEqual(
      CEILING_HISTORY,
      PINNED_HISTORY,
      "the ceiling history differs from the copy pinned in this test: a row is never deleted " +
        "or edited, and lowering a ceiling appends the same row in both places"
    );

    assert.deepEqual(ceilingViolations(CEILING_HISTORY, toolBytes), []);

    const last = CEILING_HISTORY[CEILING_HISTORY.length - 1];
    for (const profile of MCP_PROFILES) {
      assert.equal(CEILINGS[profile], last[profile], `${profile}: the ceiling in force is the last row's`);
    }
  });
  // User story (Sprint 24 plan D-2, D1):
  // As the operator whose agent pays for the tool list at connect time,
  // I want a new tool's schema to be the only thing a ceiling may grow by,
  // and by no more than that tool's own published bytes,
  // so that a new read is paid for once and openly, never by a quiet raise.
  //
  // Acceptance criteria:
  // - A row that raises a profile without naming the tools it pays for is
  //   refused; so is one dated before the row it follows.
  // - A row naming its tools may raise each profile by at most the bytes it
  //   records for them, and while it is in force those bytes are what the
  //   named tools measure in that profile (0 where the profile omits one).
  // - Lowering stays allowed, with or without raisedBy.
  it("lets a ceiling grow only by the new tools' own bytes", () => {
    const base: CeilingRow = { since: "2026-11-01", why: "base", read: 100, book: 200, full: 300 };
    const measured = (name: string) => (name === "portfolixir.example.read" ? 7 : 0);

    assert.deepEqual(
      ceilingViolations([base, { ...base, since: "2026-11-02", read: 99 }], measured),
      [],
      "lowering is allowed"
    );
    assert.equal(
      ceilingViolations([base, { ...base, since: "2026-11-02", book: 201 }], measured).length,
      1,
      "an unpaid raise is refused"
    );
    assert.equal(
      ceilingViolations([base, { ...base, since: "2026-10-31", read: 99 }], measured).length,
      1,
      "a row dated before the one it follows is refused"
    );

    const paid = {
      ...base,
      since: "2026-11-02",
      read: 107,
      book: 207,
      full: 307,
      raisedBy: { tools: ["portfolixir.example.read"], read: 7, book: 7, full: 7 }
    };
    assert.deepEqual(ceilingViolations([base, paid], measured), [], "a raise by the tool's bytes");
    assert.equal(
      ceilingViolations([base, { ...paid, full: 308 }], measured).length,
      1,
      "a raise past the recorded bytes is refused"
    );
    assert.equal(
      ceilingViolations(
        [base, { ...paid, read: 108, raisedBy: { ...paid.raisedBy, read: 8 } }],
        measured
      ).length,
      1,
      "the row in force records what its tools measure"
    );
    const superseded = { ...paid, raisedBy: { ...paid.raisedBy, read: 8 } };
    const later = { ...paid, since: "2026-11-03", why: "later" };
    assert.deepEqual(
      ceilingViolations([base, superseded, later], measured),
      [],
      "a row no longer in force keeps the bytes it recorded"
    );
  });
});
