import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { MCP_PROFILES } from "../src/profiles.js";
import { publishedToolList } from "../src/server.js";
import { SCHEMA_CEILINGS, schemaBytes, tokenRange } from "./support/schema-budget.js";

// Sprint 17 A5 (#982) with A3 (#994): docs/llms.txt tells an agent what
// connecting costs per profile. The figures are measured here, so this test
// keeps the entry from understating them.
const ENTRY = new URL("../../docs/llms.txt", import.meta.url);

const number = (text: string) => Number.parseInt(text.replaceAll(",", ""), 10);

describe("the LLM-facing entry's schema figures", () => {
  // User story (A5, #982; A3, #994):
  // As an agent reading llms.txt before I connect,
  // I want the context cost it states per profile to be true,
  // so that I can plan for it and the operator is not surprised.
  //
  // Acceptance criteria:
  // - The entry states, for read, book and full, the tool count, a byte
  //   figure and a token range.
  // - The tool count is the published one; the bytes are no fewer than
  //   measured and no more than the budget's ceiling; the upper token figure
  //   is no lower than the measured bytes over 3.5.
  it("states each profile's cost without understating it", () => {
    const entry = readFileSync(ENTRY, "utf8");

    for (const profile of MCP_PROFILES) {
      const line = new RegExp(
        `^- \`${profile}\`: (\\d+) tools, at most ([\\d,]+) bytes, about ([\\d,]+) to ([\\d,]+) tokens`,
        "m"
      ).exec(entry);

      assert.ok(line, `llms.txt states no figure line for ${profile}`);

      const [, tools, bytes, low, high] = line;
      const measured = schemaBytes(profile);

      assert.equal(Number(tools), publishedToolList({ profile }).length, `${profile}: tool count`);
      assert.ok(number(bytes) >= measured, `${profile}: states ${bytes} bytes, measured ${measured}`);
      assert.ok(
        number(bytes) <= SCHEMA_CEILINGS[profile],
        `${profile}: states more bytes than the budget's ceiling allows`
      );
      assert.ok(number(low) <= number(high), `${profile}: token range`);
      assert.ok(
        number(high) >= tokenRange(measured).high,
        `${profile}: states at most ${high} tokens, measured up to ${tokenRange(measured).high}`
      );
    }
  });
});
