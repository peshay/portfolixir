import { readFileSync } from "node:fs";

import type { McpProfile } from "../../src/profiles.js";
import { publishedToolList, serverInstructions } from "../../src/server.js";

// THE SCHEMA BUDGET (Sprint 17 A3, #994). The ceilings were set at the
// figures measured on 2026-10-01, the day the budget landed, each rounded up
// to the next 1,000 bytes (a margin under 1 %): read 105,541, book 178,654,
// full 208,406 bytes.
//
// A ceiling only ever moves down. When the surface shrinks, lower it to the
// new figure; never raise it. A tool or a description that needs more room
// pays for it by trimming another, so connecting never silently costs more.
// docs/llms.txt states figures no higher than these (test/llms-entry.test.ts).
//
// One exception, signed by the Sprint 24 plan's D-2 (D1, the position
// dossier): a row may raise a profile's ceiling by no more than the own
// published bytes of the new tools it names in `raisedBy`, which records
// those bytes per profile. While that row is in force, what it records is
// what the named tools measure (`toolBytes`), so the raise is paid once and
// openly; a later row lowers as before. A named tool is new on the row's
// date (the contract entry that adds it, `contractToolDebuts`) and paid for
// by one row only, and the ceilings in force never exceed the history with
// each raise credited what its tools measure now (Sprint 24 closing act).
// `ceilingViolations` is the rule.
//
// Lowering a ceiling appends a row below, with its date and why; a row is
// history and is never edited or deleted. The test refuses a row that sets
// any profile above the row before it (#1027), and the ceilings in force are
// the last row's. It also holds a literal copy of every row (#1027 review
// round), so the same row is appended there too, and a row deleted or edited
// here alone fails it.
export interface CeilingRow {
  since: string;
  why: string;
  read: number;
  book: number;
  full: number;
  raisedBy?: NewToolAllowance;
}

/**
 * The new tools a row pays for (Sprint 24 plan D-2) and their own published
 * bytes per profile, as measured the day the row lands: each tool's entry in
 * the profile's `tools/list` answer as compact JSON, 0 where the profile does
 * not list it.
 */
export interface NewToolAllowance {
  tools: readonly string[];
  read: number;
  book: number;
  full: number;
}

export const CEILING_HISTORY: readonly CeilingRow[] = [
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
    read: 102986,
    book: 172005,
    full: 206560
  },
  {
    since: "2026-10-31",
    why:
      "Sprint 21, stacked PR 1 (the money stories, alpha and beta): every byte the stories' " +
      "descriptions added (plan_id on the target reads, the fees-in-figures bases, the " +
      "unavailable trade, the settlement-leg counts) was paid by a trim in the same tool, and " +
      "the ceilings are lowered once, at the end, to the figures measured with the whole PR " +
      "(the amendment's D-9; D-10's rule)",
    read: 102911,
    book: 171982,
    full: 206537
  },
  {
    since: "2026-11-01",
    why:
      "Sprint 21, stacked PR 2 (the UI batch): the Costs read's month totals paid their bytes in " +
      "the same tool, and the ceilings are lowered once, at the end, to the figures measured " +
      "with the whole PR (the amendment's D-9; D-10's rule)",
    read: 102909,
    book: 171980,
    full: 206535
  },
  {
    since: "2026-11-02",
    why:
      "Sprint 22, the stacked PR's closing act: the plan's criterion holds the ceilings no " +
      "higher than Sprint 21's, and the sprint's descriptions paid their bytes in the same " +
      "tools, so the ceilings are lowered once, at the end, to the figures measured with the " +
      "whole sprint, with no slack (D-10's rule)",
    read: 102887,
    book: 171958,
    full: 206513
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
  },
  // --- Sprint 27 N8 end ---
  // --- Sprint 27 N7 begin ---
  {
    since: "2026-11-08",
    why:
      "Sprint 27, N7 (ADR-0056 §9, §11): the news layer's reads, portfolixir.news.list, " +
      "portfolixir.news.get, portfolixir.news.health and portfolixir.news.digest, reads in " +
      "every profile, whose own schemas the rule of Sprint 24's D-2 lets the ceilings grow " +
      "by and no more: their tools/list entries measure 1,272 + 638 + 578 + 936 = 3,424 " +
      "bytes in each profile, so read 114,310 + 3,424 = 117,734, book 188,298 + 3,424 = " +
      "191,722 and full 223,347 + 3,424 = 226,771; the four commas between the entries are " +
      "paid for by tightening tax_snapshots.trim_budget's wording, and no other tool's " +
      "bytes are added",
    read: 117_734,
    book: 191_722,
    full: 226_771,
    raisedBy: {
      tools: [
        "portfolixir.news.list",
        "portfolixir.news.get",
        "portfolixir.news.health",
        "portfolixir.news.digest"
      ],
      read: 3_424,
      book: 3_424,
      full: 3_424
    }
  },
  // --- Sprint 27 N7 end ---
  // --- Sprint 27 closing act S begin ---
  {
    since: "2026-11-08",
    why:
      "Sprint 27 closing act on S2 (the money lens, M1): portfolixir.views.bands takes " +
      "base_currency, paid for by tightening the two bands tools' own wording, which now " +
      "measure 2,025 + 1,329 = 3,354 bytes in each profile, 3 fewer than S2's row credited " +
      "them, so each ceiling is lowered by those 3 bytes: read 117,731, book 191,719 and " +
      "full 226,768",
    read: 117_731,
    book: 191_719,
    full: 226_768
  },
  // --- Sprint 27 closing act S end ---
  // --- Sprint 27 closing act, Fix-2 begin ---
  {
    since: "2026-11-08",
    why:
      "Sprint 27 closing act, Fix-2 (ADR-0056 amendment of 2026-11-08, C3 to C5): the news " +
      "reads say what changed (scope_at, tier order, the cut link, hidden, max_rows 12 of " +
      "40, yield not measured), feeds_put says what a new feed needs and how to register " +
      "an SEC filing feed, news_identity what cik and aliases do, and notes.append where a " +
      "news note's as_of, source_url and source_quality come from; paid for by tightening " +
      "the same tools' wording and notes.append's, and lowered to the figure measured with " +
      "them",
    read: 117_722,
    book: 191_718,
    full: 226_748
  },
  // --- Sprint 27 closing act, Fix-2 end ---
  // --- ADR-0059 pilot begin ---
  {
    since: "2026-11-09",
    why:
      "ADR-0059 (lifecycles named once), the policy-rule pilot: the list read names permits " +
      "(the writes a rule accepts today) and status_basis, and the get read points at them; " +
      "paid for by tightening the list's wording and the two shared policy snippets, and " +
      "lowered to the figure measured with them",
    read: 117_644,
    book: 191_588,
    full: 226_633
  }
  // --- ADR-0059 pilot end ---
];

const inForce = CEILING_HISTORY[CEILING_HISTORY.length - 1];

export const SCHEMA_CEILINGS: Record<McpProfile, number> = {
  read: inForce.read,
  book: inForce.book,
  full: inForce.full
};

/**
 * The context a host pays for the companion's tool list (Sprint 17 A3,
 * #994): the `tools` array a `tools/list` answer carries under a profile,
 * every tool's name, title, description, inputSchema and annotations, as
 * compact JSON, counted in UTF-8 bytes. A client that loads every schema at
 * connect time puts this into the model's context; one that defers schemas
 * pays only for the names.
 */
export function schemaBytes(profile: McpProfile): number {
  return Buffer.byteLength(JSON.stringify(publishedToolList({ profile })), "utf8");
}

/**
 * One tool's own published bytes under a profile (Sprint 24 plan D-2): its
 * entry in the `tools/list` answer, as compact JSON in UTF-8 bytes, without
 * the comma that separates it from its neighbour; 0 when the profile does not
 * list it.
 */
export function toolBytes(name: string, profile: McpProfile): number {
  const entry = publishedToolList({ profile }).find((tool) => tool.name === name);
  return entry === undefined ? 0 : Buffer.byteLength(JSON.stringify(entry), "utf8");
}

/**
 * What the ceiling history breaks of its rule, one sentence per breach: a row
 * dated before the row it follows; a profile raised above the row before it
 * by more than the bytes the row's `raisedBy` records (by anything, without
 * one); for the row in force, a recorded figure that is not what its tools
 * measure; a tool in `raisedBy` that is not new on the row's date (`debut`,
 * the date of the contract entry that adds it) or that an earlier row
 * already paid for; and a ceiling in force above what the history allows
 * when each raise is credited no more than its tools measure now.
 *
 * The last rule measures every `raisedBy` row, not only the one in force
 * (Sprint 24 closing act, D1): walking the rows, each ceiling is held to the
 * lower of the row's figure and the one before plus what the row's tools
 * measure today. A bogus figure then cannot hide behind a later row that
 * lowers by a byte. It asks for no equality of an old row, which is history
 * and never edited: a tool trimmed later only asks for the ceilings to come
 * down by its trim, as any shrinking surface does.
 */
export function ceilingViolations(
  history: readonly CeilingRow[],
  measure: (name: string, profile: McpProfile) => number,
  debut: (name: string) => string | undefined
): string[] {
  const violations: string[] = [];
  const profiles: readonly McpProfile[] = ["read", "book", "full"];
  const paidFor = new Set<string>();
  const allowed: Partial<Record<McpProfile, number>> = {};

  history.forEach((row, i) => {
    const before = history[i - 1];

    if (before !== undefined && row.since < before.since) {
      violations.push(`row ${i}: dated before the row it follows`);
    }

    const credited: string[] = [];

    for (const name of row.raisedBy?.tools ?? []) {
      const added = debut(name);

      if (paidFor.has(name)) {
        violations.push(`row ${i} (${row.since}) names ${name}, which an earlier row already paid for`);
      } else if (added === undefined) {
        violations.push(`row ${i} (${row.since}) names ${name}, which no contract entry adds`);
      } else if (added !== row.since) {
        violations.push(
          `row ${i} (${row.since}) names ${name}, which the contract added on ${added}: a raise ` +
            "pays only for a tool new on the row's date (D-2)"
        );
      } else {
        credited.push(name);
      }

      paidFor.add(name);
    }

    for (const profile of profiles) {
      const allowance = row.raisedBy?.[profile] ?? 0;

      if (before !== undefined && row[profile] > before[profile] + allowance) {
        violations.push(
          `row ${i} (${row.since}) raises ${profile} from ${before[profile]} to ${row[profile]}, ` +
            `beyond the ${allowance} bytes of the new tools it names: a ceiling only ever moves ` +
            "down, or by a new tool's own bytes (D-2); trim a description instead"
        );
      }

      const measuredNow = credited.reduce((sum, name) => sum + measure(name, profile), 0);
      const previous = allowed[profile];
      allowed[profile] = previous === undefined ? row[profile] : Math.min(row[profile], previous + measuredNow);

      if (row.raisedBy !== undefined && i === history.length - 1) {
        const measured = row.raisedBy.tools.reduce((sum, name) => sum + measure(name, profile), 0);

        if (measured !== row.raisedBy[profile]) {
          violations.push(
            `row ${i} (${row.since}) records ${row.raisedBy[profile]} ${profile} bytes for ` +
              `${row.raisedBy.tools.join(", ")}, which measure ${measured}: append a row with the ` +
              "measured figure"
          );
        }
      }
    }
  });

  const inForce = history[history.length - 1];

  for (const profile of profiles) {
    const bound = allowed[profile];

    if (inForce !== undefined && bound !== undefined && inForce[profile] > bound) {
      violations.push(
        `the ${profile} ceiling in force, ${inForce[profile]}, is above ${bound}, what the history ` +
          "allows with each raise credited what its tools measure now: lower it to that figure"
      );
    }
  }

  return violations;
}

/**
 * The contract manifest (`lib/portfolixir_web/controllers/api/v1/contract.ex`,
 * ADR-0044 §8), whose dated entries name the tools each change added and
 * removed. Read from its source, as the Elixir meta-test reads `src/tools.ts`.
 */
const CONTRACT_SOURCE = new URL("../../../lib/portfolixir_web/controllers/api/v1/contract.ex", import.meta.url);

/**
 * Each tool the manifest offers today and the date of the entry that added
 * it (Sprint 24 closing act, D1): the entries walked oldest first, an add
 * dating a tool only when it is not already offered and a removal
 * forgetting it, as `Contract.tools/0` takes the union. A `raisedBy` row may
 * name a tool only on that date.
 */
export function contractToolDebuts(source = readFileSync(CONTRACT_SOURCE, "utf8")): Map<string, string> {
  const names = (list: string | undefined) => [...(list ?? "").matchAll(/"([^"]+)"/g)].map((m) => m[1]);

  const entries = source
    .split(/^ {4}%\{\s*\n(?= {6}version: \d+,)/m)
    .slice(1)
    .map((chunk) => ({
      version: Number(/^ {6}version: (\d+),/m.exec(chunk)?.[1]),
      date: /^ {6}date: ~D\[(\d{4}-\d{2}-\d{2})\]/m.exec(chunk)?.[1],
      added: names(/^ {6}tools: \[([^\]]*)\]/m.exec(chunk)?.[1]),
      removed: names(/^ {6}removed_tools: \[([^\]]*)\]/m.exec(chunk)?.[1])
    }))
    .sort((a, b) => a.version - b.version);

  const debuts = new Map<string, string>();

  for (const entry of entries) {
    if (entry.date === undefined) {
      throw new Error(`contract entry ${entry.version} has no date the budget can read`);
    }

    for (const name of entry.added) {
      if (!debuts.has(name)) {
        debuts.set(name, entry.date);
      }
    }

    for (const name of entry.removed) {
      debuts.delete(name);
    }
  }

  return debuts;
}

/**
 * The rest of what connecting costs (#1027 review round): the server
 * instructions an `initialize` answer carries under a profile, counted in
 * UTF-8 bytes like the tool list. They hold no budget of their own;
 * docs/llms.txt states their range across the profiles
 * (test/llms-entry.test.ts).
 */
export function instructionsBytes(profile: McpProfile): number {
  return Buffer.byteLength(serverInstructions({ profile }), "utf8");
}

/**
 * Tokens are approximated, not counted: no tokenizer ships with the
 * companion and each client's differs. The range is the usual rule of thumb
 * of four bytes per token for English text, to three and a half for dense
 * JSON (the triage of 2026-10-01 measured about 3.7 for this list). The
 * upper end is the figure not to understate.
 */
export function tokenRange(bytes: number): { low: number; high: number } {
  return { low: Math.ceil(bytes / 4), high: Math.ceil(bytes / 3.5) };
}
