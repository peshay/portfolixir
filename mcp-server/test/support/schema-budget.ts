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
