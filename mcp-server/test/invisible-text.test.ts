import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { createApiClient } from "../src/api-client.js";
import { escapeInvisible, escapeInvisibleText } from "../src/invisible-text.js";
import { SERVER_INSTRUCTIONS } from "../src/server.js";

interface Case {
  input: string;
  escaped: string;
  count: number;
}

const cases: Case[] = JSON.parse(
  readFileSync(new URL("./fixtures/invisible-text.json", import.meta.url), "utf8")
).cases;

// One character by its code point: the source carries no invisible
// character itself (the repository's pre-commit hook refuses them).
const c = (codePoint: number): string => String.fromCodePoint(codePoint);

describe("the MCP boundary's escape of invisible characters", () => {
  // User story (E25 S7, G20):
  // As an operator whose agent reads stored text through the companion,
  // I want every character I cannot see handed to the agent as a visible
  // [U+XXXX], spelled exactly as my screen spells it,
  // so that a hidden instruction in a record stored before the refusal
  // reaches the agent as visible letters, not as text it would follow
  // unseen by me.
  //
  // Acceptance criteria:
  // - escapeInvisibleText agrees with every shared case the application's
  //   Portfolixir.Input.Text is pinned to: the same set, the same spelling.
  // - escapeInvisible walks a whole API answer — nested objects, lists and
  //   keys — and leaves numbers, booleans and null alone.
  it("escapes the shared cases exactly as the application does", () => {
    assert.ok(cases.length >= 10);

    for (const { input, escaped } of cases) {
      assert.equal(escapeInvisibleText(input), escaped, JSON.stringify(input));
    }
  });

  it("walks a whole answer, keys included", () => {
    const answer = {
      data: {
        name: "Harbour" + c(0x200b) + " Cranes",
        ["k" + c(0x202e) + "ey"]: [1, true, null, "tag" + c(0xe0041)],
        notes: [{ body: "fine" }]
      }
    };

    assert.deepEqual(escapeInvisible(answer), {
      data: {
        name: "Harbour[U+200B] Cranes",
        "k[U+202E]ey": [1, true, null, "tag[U+E0041]"],
        notes: [{ body: "fine" }]
      }
    });
  });

  // Acceptance criteria:
  // - Every answer the API client returns, and every error it raises from an
  //   API answer, carries the escaped text; the request body goes out as the
  //   agent wrote it.
  // - The server instructions tell the agent how such characters reach it.
  it("hands the agent every API answer escaped", async () => {
    let sent = "";

    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        sent = String(init?.body ?? "");

        if (String(url).endsWith("/refused")) {
          return new Response(
            JSON.stringify({ errors: { name: ["taken by Giro" + c(0x200b) + "konto"] } }),
            { status: 422, headers: { "content-type": "application/json" } }
          );
        }

        return new Response(
          JSON.stringify({ data: { body: "Buy now" + c(0xe0049) + c(0xe0047) } }),
          { status: 200, headers: { "content-type": "application/json" } }
        );
      }
    });

    assert.deepEqual(await client.request("GET", "/api/v1/notes/1"), {
      data: { body: "Buy now[U+E0049][U+E0047]" }
    });

    await client.request("POST", "/api/v1/notes", { body: "as written [U+200B]" });
    assert.equal(sent, JSON.stringify({ body: "as written [U+200B]" }));

    await assert.rejects(client.request("POST", "/refused", {}), (error: unknown) => {
      assert.match(String(error), /Giro\[U\+200B\]konto/);
      return true;
    });

    assert.match(SERVER_INSTRUCTIONS, /\[U\+XXXX\]/);
  });
});
