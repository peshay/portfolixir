// The MCP boundary over Unicode's whole Default_Ignorable_Code_Point set
// (security review 2026-10-12, H12): every character that renders as
// nothing reaches the agent spelled [U+XXXX], and a variation selector with
// no base it can vary is spelled too. Synthetic text only; fetch is faked,
// no network.
import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { createApiClient } from "../src/api-client.js";
import { escapeInvisibleText } from "../src/invisible-text.js";

const c = (codePoint: number): string => String.fromCodePoint(codePoint);
const hex = (codePoint: number): string =>
  `U+${codePoint.toString(16).toUpperCase().padStart(4, "0")}`;

// Default_Ignorable_Code_Point beyond the format characters the escape first
// wrote out, each range by its ends.
const GAP = [
  0x034f, 0x115f, 0x1160, 0x17b4, 0x17b5, 0x180b, 0x180c, 0x180d, 0x180f, 0x3164, 0xffa0,
  0xfff0, 0xfff8, 0xe0080, 0xe00ff, 0xe01f0, 0xe0fff
];

// One variation selector per hidden byte, one after each visible letter.
const vsByte = (byte: number): string => c(byte < 16 ? 0xfe00 + byte : 0xe0100 + byte - 16);

function interleave(visible: string, hidden: string): string {
  const bytes = Array.from(Buffer.from(hidden, "utf8"));
  return Array.from(visible)
    .map((letter) => (letter !== " " && bytes.length > 0 ? letter + vsByte(bytes.shift()!) : letter))
    .join("");
}

const spellAll = (text: string): string =>
  Array.from(text)
    .map((ch) => {
      const cp = ch.codePointAt(0)!;
      return cp >= 0x20 && cp <= 0x7e ? ch : `[${hex(cp)}]`;
    })
    .join("");

describe("the MCP boundary spells every default-ignorable character", () => {
  // User story (security review 2026-10-12, H12):
  // As the operator whose agent reads stored text through the companion,
  // I want every default-ignorable character, and a variation selector with
  // no base it can vary, handed to the agent as a visible [U+XXXX],
  // so that a payload I cannot see never reaches the agent unspelled.
  //
  // Acceptance criteria:
  // - escapeInvisibleText spells each default-ignorable code point.
  // - Selectors interleaved one per Latin letter are spelled.
  // - An API answer carrying U+034F reaches the agent spelled.
  it("escapeInvisibleText spells each default-ignorable code point", () => {
    // Control: the written-out set holds.
    assert.equal(escapeInvisibleText("Fund" + c(0x200b)), "Fund[U+200B]");

    const leaks = GAP.filter(
      (cp) => escapeInvisibleText("Synthetic Fund" + c(cp)) !== `Synthetic Fund[${hex(cp)}]`
    ).map(hex);

    assert.deepEqual(leaks, [], `reach the agent unspelled: ${leaks.join(", ")}`);
  });

  it("escapes single variation selectors interleaved one per letter", () => {
    const text = interleave("Note on fund", "HIDDEN");

    assert.equal(Array.from(text).length, 18);
    assert.notEqual(
      escapeInvisibleText(text),
      text,
      `escapeInvisibleText left every selector raw (test spells them): ${spellAll(escapeInvisibleText(text))}`
    );
  });

  it("an API answer carrying U+034F reaches the agent spelled", async () => {
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async () =>
        new Response(JSON.stringify({ data: { body: "Fleet renewal on plan." + c(0x034f) } }), {
          status: 200,
          headers: { "content-type": "application/json" }
        })
    });

    const answer = (await client.request("GET", "/api/v1/securities/1/notes")) as {
      data: { body: string };
    };

    assert.equal(
      answer.data.body,
      "Fleet renewal on plan.[U+034F]",
      `the companion hands the agent the raw character (test spells it as ${spellAll(answer.data.body).slice(-8)}; companion output length ${answer.data.body.length})`
    );
  });
});
