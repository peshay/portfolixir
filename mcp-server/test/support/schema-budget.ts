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
  }
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
