import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { MCP_PROFILES } from "../src/profiles.js";
import { publishedToolList } from "../src/server.js";
import { listTools } from "../src/tools.js";
import { publishedTools } from "./support/companion.js";
import {
  CEILING_HISTORY,
  ceilingViolations,
  type CeilingRow,
  contractToolDebuts,
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
  },
  {
    since: "2026-11-05",
    why:
      "Sprint 24, D1 (FR-49): the position dossier, portfolixir.securities.dossier, a read in " +
      "every profile, whose own schema the plan's D-2 lets the ceilings grow by and no more: " +
      "its tools/list entry measures 1,423 bytes in each profile, so read 102,887 + 1,423 = " +
      "104,310, book 171,958 + 1,423 = 173,381 and full 206,513 + 1,423 = 207,936; no other " +
      "tool's bytes are added",
    read: 104_310,
    book: 173_381,
    full: 207_936,
    raisedBy: { tools: ["portfolixir.securities.dossier"], read: 1_423, book: 1_423, full: 1_423 }
  },
  {
    since: "2026-11-06",
    why:
      "Sprint 25, S2 (FR-50): what each sale missed, portfolixir.sales.hindsight, a read in " +
      "every profile, whose own schema the rule of Sprint 24's D-2 lets the ceilings grow by " +
      "and no more: its tools/list entry measures 2,302 bytes in each profile, so read " +
      "104,310 + 2,302 = 106,612, book 173,381 + 2,302 = 175,683 and full 207,936 + 2,302 = " +
      "210,238; no other tool's bytes are added",
    read: 106_612,
    book: 175_683,
    full: 210_238,
    raisedBy: { tools: ["portfolixir.sales.hindsight"], read: 2_302, book: 2_302, full: 2_302 }
  },
  {
    since: "2026-11-06",
    why:
      "Sprint 25, F4 (ADR-0055 §5): the predictions, portfolixir.predictions.create, a write " +
      "in the book and full profiles, and portfolixir.predictions.list, .get and .calibration, " +
      "reads in every profile, whose own schemas the rule of Sprint 24's D-2 lets the ceilings " +
      "grow by and no more: their tools/list entries, with the Sprint 25 closing act's wording " +
      "(the start close, the wait for the end close, the rate as a fraction, the lifecycle " +
      "lock), measure 2,958 + 1,607 + 1,049 + 1,685 = 7,299 bytes in book and full and 4,341 " +
      "in read, which lists no create, so read 106,612 + 4,341 = 110,953, book 175,683 + " +
      "7,299 = 182,982 and full 210,238 + 7,299 = 217,537; the merge preview and the delete " +
      "of a security name predictions, and notes.append names notes.unreviewed, each paid for " +
      "by tightening its own wording, and no other tool's bytes are added",
    read: 110_953,
    book: 182_982,
    full: 217_537,
    raisedBy: {
      tools: [
        "portfolixir.predictions.create",
        "portfolixir.predictions.list",
        "portfolixir.predictions.get",
        "portfolixir.predictions.calibration"
      ],
      read: 4_341,
      book: 7_299,
      full: 7_299
    }
  },
  // --- Sprint 27 S2 begin ---
  {
    since: "2026-11-08",
    why:
      "Sprint 27, S2 (I23, FR-53): the stacked chart's bands, portfolixir.portfolios.bands " +
      "and portfolixir.views.bands, reads in every profile, whose own schemas the rule of " +
      "Sprint 24's D-2 lets the ceilings grow by and no more: their tools/list entries " +
      "measure 2,076 + 1,281 = 3,357 bytes in each profile, so read 110,953 + 3,357 = " +
      "114,310, book 182,982 + 3,357 = 186,339 and full 217,537 + 3,357 = 220,894; no other " +
      "tool's bytes are added",
    read: 114_310,
    book: 186_339,
    full: 220_894,
    raisedBy: {
      tools: ["portfolixir.portfolios.bands", "portfolixir.views.bands"],
      read: 3_357,
      book: 3_357,
      full: 3_357
    }
  },
  // --- Sprint 27 S2 end ---
  // --- Sprint 27 N8 begin ---
  {
    since: "2026-11-08",
    why:
      "Sprint 27, N8 (ADR-0056 §9, B1): the news layer's upkeep writes, " +
      "portfolixir.news.feeds_put and portfolixir.news.sources_put in book and full and " +
      "portfolixir.news.feeds_delete in full (admin), whose own schemas the rule of Sprint " +
      "24's D-2 lets the ceilings grow by and no more: their tools/list entries measure " +
      "1,221 + 738 = 1,959 bytes in book and 1,221 + 494 + 738 = 2,453 in full and none in " +
      "read, so read stays 114,310, book 186,339 + 1,959 = 188,298 and full 220,894 + 2,453 " +
      "= 223,347; securities.update's news_identity and news_watch and the two fields in " +
      "securities.list's fields enum are paid for by tightening securities.update's, " +
      "securities.create's and securities.list's own wording, and no other tool's bytes " +
      "are added",
    read: 114_310,
    book: 188_298,
    full: 223_347,
    raisedBy: {
      tools: [
        "portfolixir.news.feeds_put",
        "portfolixir.news.feeds_delete",
        "portfolixir.news.sources_put"
      ],
      read: 0,
      book: 1_959,
      full: 2_453
    }
  }
  // --- Sprint 27 N8 end ---
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

    const debuts = contractToolDebuts();
    assert.deepEqual(ceilingViolations(CEILING_HISTORY, toolBytes, (name) => debuts.get(name)), []);

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
  // - Closing act (D1, the correctness hunter; a gate that partly checked
  //   nothing): every raisedBy row is measured, not only the row in force,
  //   so the ceilings in force are refused above the history with each
  //   raise credited no more than its tools measure now, and a raise then
  //   lowered by a byte no longer hides a bogus figure; a tool shrunk later
  //   asks for the ceilings to come down with it.
  // - Closing act: a tool a row names must be new on the row's date, the
  //   date of the contract entry that adds it, and paid for by one row only,
  //   so naming an existing tool raises nothing.
  it("lets a ceiling grow only by the new tools' own bytes", () => {
    const base: CeilingRow = { since: "2026-11-01", why: "base", read: 100, book: 200, full: 300 };
    const sizes: Record<string, number> = { "portfolixir.example.read": 7, "portfolixir.example.old": 7 };
    const measured = (name: string) => sizes[name] ?? 0;
    const debuts: Record<string, string> = {
      "portfolixir.example.read": "2026-11-02",
      "portfolixir.example.old": "2026-10-01"
    };
    const debut = (name: string) => debuts[name];
    const check = (history: readonly CeilingRow[], measure = measured) =>
      ceilingViolations(history, measure, debut);
    // Each breach the rule sees is one sentence, so a refusal is named by the
    // sentence it must contain.
    const refuses = (history: readonly CeilingRow[], phrase: string, measure = measured) =>
      check(history, measure).some((violation) => violation.includes(phrase));

    assert.deepEqual(
      check([base, { ...base, since: "2026-11-02", read: 99 }], measured),
      [],
      "lowering is allowed"
    );
    assert.ok(
      refuses([base, { ...base, since: "2026-11-02", book: 201 }], "raises book from 200 to 201"),
      "an unpaid raise is refused"
    );
    assert.equal(
      check([base, { ...base, since: "2026-10-31", read: 99 }], measured).length,
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
    assert.deepEqual(check([base, paid], measured), [], "a raise by the tool's bytes");
    assert.ok(
      refuses([base, { ...paid, full: 308 }], "raises full from 300 to 308"),
      "a raise past the recorded bytes is refused"
    );
    assert.ok(
      refuses(
        [base, { ...paid, read: 108, raisedBy: { ...paid.raisedBy, read: 8 } }],
        "records 8 read bytes"
      ),
      "the row in force records what its tools measure"
    );
    const superseded = { ...paid, raisedBy: { ...paid.raisedBy, read: 8 } };
    const later: CeilingRow = { ...base, since: "2026-11-03", why: "later", read: 107, book: 207, full: 307 };
    assert.deepEqual(
      check([base, superseded, later], measured),
      [],
      "a row no longer in force keeps the bytes it recorded"
    );

    // Attack (a): a +9,000 raise with a bogus raisedBy, then a row lowering
    // by one byte so the bogus row is no longer the one in force.
    const bogus: CeilingRow = {
      ...paid,
      read: 9_100,
      raisedBy: { ...paid.raisedBy, read: 9_000 }
    };
    const lowered: CeilingRow = { ...base, since: "2026-11-03", why: "lowered", read: 9_099, book: 207, full: 307 };
    assert.deepEqual(
      check([base, bogus, lowered]),
      [
        "the read ceiling in force, 9099, is above 107, what the history allows with each raise " +
          "credited what its tools measure now: lower it to that figure"
      ],
      "a bogus raise is refused after a later row lowers it by a byte"
    );

    // Attack (b): naming a tool that already existed raises nothing.
    const old = { ...paid, raisedBy: { ...paid.raisedBy, tools: ["portfolixir.example.old"] } };
    assert.ok(refuses([base, old], "which the contract added on 2026-10-01"), "a tool older than the row is refused");
    assert.ok(refuses([base, old], "read ceiling in force, 107, is above 100"), "and it raises nothing");
    const unknown = { ...paid, raisedBy: { ...paid.raisedBy, tools: ["portfolixir.example.unlisted"] } };
    assert.ok(
      refuses([base, unknown], "which no contract entry adds"),
      "a tool no contract entry adds is refused"
    );
    const twice = { ...paid, since: "2026-11-02", why: "again", read: 114, book: 214, full: 314 };
    assert.ok(
      refuses([base, paid, twice], "which an earlier row already paid for"),
      "a tool is paid for by one row only"
    );

    // A tool trimmed after its row: the ceilings come down with it.
    const trimmed = (name: string) => (name === "portfolixir.example.read" ? 5 : 0);
    assert.ok(
      refuses([base, paid, later], "read ceiling in force, 107, is above 105", trimmed),
      "a ceiling left above a trimmed tool's bytes is refused"
    );
    assert.deepEqual(
      check([base, paid, { ...later, read: 105, book: 205, full: 305 }], trimmed),
      [],
      "lowered with the trim, the history keeps the rule"
    );
  });

  // Closing act (D1): the debut dates come from the contract manifest, read
  // from its source the way the Elixir meta-test reads tools.ts. The parse is
  // held to the companion's inventory, so it can never silently read nothing.
  it("reads each tool's debut from the contract manifest", () => {
    const debuts = contractToolDebuts();

    assert.deepEqual(
      [...debuts.keys()].sort(),
      listTools()
        .map((tool) => tool.name)
        .sort(),
      "the manifest's tools, removals applied, are the companion's"
    );
    assert.equal(debuts.get("portfolixir.securities.dossier"), "2026-11-05");
    assert.equal(debuts.get("portfolixir.sales.hindsight"), "2026-11-06");
    for (const name of [
      "portfolixir.predictions.create",
      "portfolixir.predictions.list",
      "portfolixir.predictions.get",
      "portfolixir.predictions.calibration"
    ]) {
      assert.equal(debuts.get(name), "2026-11-06", name);
    }
    assert.equal(debuts.get("portfolixir.transactions.cash_mismatch"), "2026-11-04");
    // --- Sprint 27 S2 begin ---
    for (const name of ["portfolixir.portfolios.bands", "portfolixir.views.bands"]) {
      assert.equal(debuts.get(name), "2026-11-08", name);
    }
    // --- Sprint 27 S2 end ---
    // --- Sprint 27 N8 begin ---
    for (const name of [
      "portfolixir.news.feeds_put",
      "portfolixir.news.feeds_delete",
      "portfolixir.news.sources_put"
    ]) {
      assert.equal(debuts.get(name), "2026-11-08", name);
    }
    // --- Sprint 27 N8 end ---
  });
});
