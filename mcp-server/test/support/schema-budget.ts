import type { McpProfile } from "../../src/profiles.js";
import { publishedToolList } from "../../src/server.js";

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
