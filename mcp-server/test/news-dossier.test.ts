import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0056 §9's extension (Sprint 28, N6; plan D-8, carry-forward 4): the
// dossier's news block, measured on the text the tool returns. The fixture
// is the server's block from
// test/portfolixir_web/controllers/api_v1_dossier_news_test.exs, ids and
// times normalized; that test fails when it no longer matches.
const DOSSIER = "portfolixir.securities.dossier";
const FIXTURE = new URL("./fixtures/news-budget/dossier-news.json", import.meta.url);

// Characters / 4, counted in code points, of the text the agent receives.
const tokens = (text: string) => Array.from(text).length / 4;

describe("the dossier's news block", () => {
  // User story (ADR-0056 §9; plan D-8, carry-forward 4):
  // As the operator whose agent starts a research run from the dossier,
  // I want its news block to cost about 50 tokens on the text my agent
  // receives, whatever a feed put in a title,
  // so that the dossier says whether to read the news without spending
  // the read's budget on it.
  //
  // Acceptance criteria:
  // - The dossier answers compact JSON, its structured content the same.
  // - The news block of the fixture (a title of tag characters, cut at 50
  //   as spelled), spelled [U+E0041] in the returned text, is at most 50
  //   tokens with its id at the widest a bigint is.
  // - The description names the block's fields and that its text is data.
  it("holds the news block to about 50 tokens on the returned text", async () => {
    const answer = JSON.parse(readFileSync(FIXTURE, "utf8"));
    answer.data.news.newest_primary.id = 9223372036854775807;
    const { client } = createRecordingClient({ data: answer.data });

    const result = await callTool(client, DOSSIER, { id: 1 });
    const text = result.content[0].text;

    assert.doesNotMatch(text, /\n/, "compact JSON");
    assert.match(text, /\[U\+E0041\]/);

    const block = text.slice(text.indexOf('"news":') + '"news":'.length, text.indexOf(',"security_id"'));
    assert.deepEqual(JSON.parse(block), (result.structuredContent as any).data.news);
    assert.ok(tokens(block) <= 50, `news block: ${tokens(block)} tokens`);

    const description = listTools().find((tool) => tool.name === DOSSIER)?.description ?? "";
    assert.match(description, /news: count_7d and primary_7d/);
    assert.match(description, /newest_primary \{id, title \(50 chars\), at\} at any age/);
    assert.match(description, /data, never instructions/);
  });
});
