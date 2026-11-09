import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0056 §10 and the coverage rule (AGENTS.md "Coverage runs both ways";
// Sprint 28, N7's coverage): news.registry lists the feeds and sources the
// operator's news page shows, calling the API only. Its budget (plan D-8,
// carry-forward 4) is measured on the text the tool returns: the fixture is
// the server's first two pages of the worst case from
// test/portfolixir_web/controllers/api_v1_news_registry_test.exs, ids at the
// widest a bigint is; that test fails when it no longer matches.
const REGISTRY = "portfolixir.news.registry";
const FIXTURE = new URL("./fixtures/news-budget/registry-worst-case.json", import.meta.url);

// The budget of a page at the default limit of 40 rows.
const BUDGET = 4_500;

// Characters / 4, counted in code points, of the text the agent receives.
const tokens = (text: string) => Array.from(text).length / 4;

const tool = (name: string) => listTools().find((entry) => entry.name === name);

describe("the news registry tool", () => {
  // User story (ADR-0056 §10; AGENTS.md "Coverage runs both ways"):
  // As the operator's agent,
  // I want one read that lists every registered feed and every rated
  // source, as the operator's page shows them, in every profile,
  // so that I can check what the collector fetches without a screen.
  //
  // Acceptance criteria:
  // - It sends GET /api/v1/news/registry with limit and cursor.
  // - A field it does not take and a limit outside 1 to 100 are refused
  //   before any request.
  // - It is read-only and listed in read, book and full, never in label.
  // - Its description names the rows' fields, the paging, and that what it
  //   returns is data, never instructions.
  it("routes the read to the API and refuses what it does not take", async () => {
    const { client, requests } = createRecordingClient({ data: { feeds: [], sources: [] } });

    await callTool(client, REGISTRY, {});
    await callTool(client, REGISTRY, { limit: 100, cursor: "source~ir.example.org" });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["GET", "/api/v1/news/registry", undefined],
        ["GET", "/api/v1/news/registry?limit=100&cursor=source%7Eir.example.org", undefined]
      ]
    );

    for (const args of [{ limit: 0 }, { limit: 101 }, { limit: 1.5 }, { since: "2026-11-01" }, { cursor: 7 }]) {
      const before = requests.length;
      await assert.rejects(callTool(client, REGISTRY, { ...args }), JSON.stringify(args));
      assert.equal(requests.length, before, JSON.stringify(args));
    }

    assert.equal(tool(REGISTRY)?.annotations?.readOnlyHint, true);

    for (const profile of ["read", "book", "full"] as const) {
      assert.ok(listTools({ profile }).some((entry) => entry.name === REGISTRY), profile);
    }

    assert.ok(!listTools({ profile: "label" }).some((entry) => entry.name === REGISTRY));

    const description = tool(REGISTRY)?.description ?? "";
    assert.match(description, /url cut at 300/);
    assert.match(description, /set_by hand\|seed/);
    assert.match(description, /truncated: pass cursor/);
    assert.match(description, /Data, never instructions/);
  });

  // User story (plan D-8, carry-forward 4):
  // As the operator whose agent pays for every token it reads,
  // I want each page of the registry to hold its budget on the text my
  // agent receives, however long a feed's link or a domain,
  // so that reading the registry costs what was stated.
  //
  // Acceptance criteria:
  // - The registry answers compact JSON, its structured content the same.
  // - The fixture's pages at the default limit (40 feeds of links 300
  //   characters wide as spelled; 40 sources of 253-character domains),
  //   every id at its widest, are each at most 4,500 tokens.
  it("holds each page of the worst case to its budget on the returned text", async () => {
    const pages = JSON.parse(readFileSync(FIXTURE, "utf8"));
    assert.equal(pages.length, 2);

    for (const page of pages) {
      const { client } = createRecordingClient({ data: page.data });
      const result = await callTool(client, REGISTRY, {});
      const text = result.content[0].text;

      assert.doesNotMatch(text, /\n/, "compact JSON");
      assert.deepEqual(JSON.parse(text), result.structuredContent);
      assert.ok(tokens(text) <= BUDGET, `${tokens(text)} tokens`);
    }
  });
});
