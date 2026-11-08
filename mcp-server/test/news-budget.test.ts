import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { callTool } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0056 §9, §14 item 2 and the amendment of 2026-11-08, C5 (Sprint 27
// closing act, AG1): the budgets of the news reads are measured on the text
// the tool returns, where every character an operator cannot see is spelled
// [U+XXXX] (ADR-0054 §4). The fixtures are the server's answers to the worst
// cases of test/portfolixir_web/controllers/api_v1_news_budget_test.exs,
// ids and times normalized; that test fails when they no longer match what
// the server answers.
const FIXTURES = new URL("./fixtures/news-budget/", import.meta.url);

function answer(name: string): unknown {
  return JSON.parse(readFileSync(new URL(`${name}.json`, FIXTURES), "utf8"));
}

async function returned(tool: string, args: Record<string, unknown>, fixture: string): Promise<string> {
  const { client } = createRecordingClient({ data: (answer(fixture) as { data: unknown }).data });
  const result = await callTool(client, tool, args);
  return result.content[0].text;
}

// Characters / 4, counted in code points, of the text the agent receives.
const tokens = (text: string) => Array.from(text).length / 4;

describe("the news reads' budgets, as the tool returns them", () => {
  // User story (ADR-0056 §9, §14 item 2; the amendment of 2026-11-08, C5):
  // As the operator whose agent pays for every token it reads,
  // I want a news read to hold its budget on the text my agent receives,
  // soft hyphens and tag characters spelled out,
  // so that a feed that fills its titles with invisible characters cannot
  // make a read cost ten times its budget.
  //
  // Acceptance criteria:
  // - The digest at its default max_rows, titles with a soft hyphen after
  //   every letter: at most 800 tokens, the soft hyphens spelled [U+00AD].
  // - 20 list rows with tag-character titles: at most 1,500, the tag
  //   characters spelled [U+E0041].
  // - news.get with a tag-character title and excerpt and a link of 2,048
  //   characters: the link cut to 300 characters, and at most 400 tokens
  //   besides it.
  it("holds the digest, list and get budgets with invisible characters spelled", async () => {
    const digest = await returned("portfolixir.news.digest", {}, "digest-soft-hyphens");
    assert.match(digest, /\[U\+00AD\]/);
    assert.equal((JSON.parse(digest) as { data: { truncated: boolean } }).data.truncated, true);
    assert.ok(tokens(digest) <= 800, `digest: ${tokens(digest)} tokens`);

    const list = await returned("portfolixir.news.list", { security_id: 1 }, "list-tag-characters");
    assert.match(list, /\[U\+E0041\]/);
    assert.equal((JSON.parse(list) as { data: { rows: unknown[] } }).data.rows.length, 20);
    assert.ok(tokens(list) <= 1_500, `list: ${tokens(list)} tokens`);

    const get = await returned("portfolixir.news.get", { cluster_id: 1 }, "get-tag-characters");
    const url = (JSON.parse(get) as { data: { url: string } }).data.url;
    assert.match(get, /\[U\+E0041\]/);
    assert.equal(Array.from(url).length, 300);
    assert.ok(url.endsWith("…"));
    assert.ok(tokens(get) - tokens(url) <= 400, `get: ${tokens(get)} tokens, ${tokens(url)} of them the link`);
  });
});
