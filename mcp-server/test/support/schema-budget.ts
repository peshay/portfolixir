import type { McpProfile } from "../../src/profiles.js";
import { publishedToolList } from "../../src/server.js";

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
// history and is never edited. The test refuses a row that sets any profile
// above the row before it (#1027), and the ceilings in force are the last
// row's.
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
 * Tokens are approximated, not counted: no tokenizer ships with the
 * companion and each client's differs. The range is the usual rule of thumb
 * of four bytes per token for English text, to three and a half for dense
 * JSON (the triage of 2026-10-01 measured about 3.7 for this list). The
 * upper end is the figure not to understate.
 */
export function tokenRange(bytes: number): { low: number; high: number } {
  return { low: Math.ceil(bytes / 4), high: Math.ceil(bytes / 3.5) };
}
