import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { LABEL_TOOLS, MCP_PROFILES, profileSwitch } from "../src/profiles.js";
import { allTools, callTool, listTools } from "../src/tools.js";
import { connectCompanion, publishedInstructions, publishedTools } from "./support/companion.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0056 §7 (Sprint 28, N1): the news labeller's two tools, reached only
// under the companion's `label` profile, and the budget of its read on the
// text the tool returns (plan D-8, carry-forward 4).
const LABEL_PUT = "portfolixir.news.label_put";
const UNLABELED = "portfolixir.news.unlabeled";
const LABEL = { profile: "label" as const };

const label = {
  cluster_id: 7,
  model: "synthetic-model-1",
  prompt_version: "v1",
  event_type: "earnings",
  materiality: 2,
  tone: 1,
  confidence: "0.85"
};

const FIXTURES = new URL("./fixtures/news-budget/", import.meta.url);

// Characters / 4, counted in code points, of the text the labeller receives.
const tokens = (text: string) => Array.from(text).length / 4;

describe("the news labeller's tools", () => {
  // User story (ADR-0056 §7: "A companion profile `label` lists only
  // news.unlabeled and news.label_put, and the agent's profiles do not
  // list them"):
  // As the operator who runs a labeller beside my agent,
  // I want the labeller's companion to list its two tools and nothing else,
  // and my agent's companion never to list them,
  // so that neither reaches what the other is for.
  //
  // Acceptance criteria:
  // - PORTFOLIXIR_MCP_PROFILE=label (any case, trimmed) is the label
  //   profile; beside PORTFOLIXIR_MCP_READ_ONLY=true it stops the companion
  //   with both variables named; the agent's profiles stay read, book, full.
  // - Under label, the host lists exactly news.label_put and news.unlabeled.
  // - Under read, book, full and no profile, neither is listed.
  // - The instructions under label name the label profile and the two
  //   tools; no prompt is offered under it.
  it("lists the two tools under the label profile and under no other", async () => {
    assert.equal(profileSwitch("label", undefined), "label");
    assert.equal(profileSwitch(" LABEL ", "false"), "label");
    assert.throws(
      () => profileSwitch("label", "true"),
      (error: Error) =>
        /PORTFOLIXIR_MCP_PROFILE=label/.test(error.message) &&
        /PORTFOLIXIR_MCP_READ_ONLY/.test(error.message)
    );
    assert.deepEqual([...MCP_PROFILES], ["read", "book", "full"]);
    assert.deepEqual([...LABEL_TOOLS.keys()].sort(), [LABEL_PUT, UNLABELED]);

    const names = async (profile?: "read" | "book" | "full" | "label") =>
      (await publishedTools(profile === undefined ? {} : { profile })).map((tool) => tool.name);

    assert.deepEqual((await names("label")).sort(), [LABEL_PUT, UNLABELED]);
    assert.deepEqual(
      listTools(LABEL)
        .map((tool) => tool.name)
        .sort(),
      [LABEL_PUT, UNLABELED]
    );

    for (const profile of [undefined, ...MCP_PROFILES]) {
      const listed = await names(profile);
      assert.ok(listed.length > 50, `${profile}: lists the agent's tools`);
      assert.ok(!listed.includes(LABEL_PUT), `${profile} lists ${LABEL_PUT}`);
      assert.ok(!listed.includes(UNLABELED), `${profile} lists ${UNLABELED}`);
    }

    assert.deepEqual(
      allTools()
        .map((tool) => tool.name)
        .filter((name) => LABEL_TOOLS.has(name))
        .sort(),
      [LABEL_PUT, UNLABELED]
    );

    const instructions = (await publishedInstructions(LABEL)) ?? "";
    assert.match(instructions, /runs the label profile \(PORTFOLIXIR_MCP_PROFILE\)/);
    assert.match(instructions, /portfolixir\.news\.unlabeled and portfolixir\.news\.label_put/);

    const companion = await connectCompanion(undefined, LABEL);

    try {
      assert.deepEqual((await companion.mcp.listPrompts()).prompts, []);
    } finally {
      await companion.close();
    }
  });

  // User story (ADR-0056 §7; ADR-0054 §1: a profile narrows the tools, not
  // the token):
  // As the operator,
  // I want a tool outside the running profile refused at the call, before
  // any request, both ways,
  // so that a labeller cannot reach an agent's tool by guessing its name,
  // nor an agent the labeller's.
  //
  // Acceptance criteria:
  // - Under label, news.list, news.feeds_put, securities.update and
  //   notes.append are refused naming the label profile.
  // - Under read, book and full, news.label_put and news.unlabeled are
  //   refused naming the label profile; no request is made.
  // - Through the server, the refusal is a tool error, not "not found".
  it("refuses a tool outside the profile at the call, both ways", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 1 } });

    for (const name of [
      "portfolixir.news.list",
      "portfolixir.news.feeds_put",
      "portfolixir.securities.update",
      "portfolixir.notes.append"
    ]) {
      await assert.rejects(
        callTool(client, name, {}, LABEL),
        /label profile \(PORTFOLIXIR_MCP_PROFILE=label\)/,
        name
      );
    }

    for (const profile of MCP_PROFILES) {
      for (const name of [LABEL_PUT, UNLABELED]) {
        await assert.rejects(
          callTool(client, name, name === LABEL_PUT ? label : { prompt_version: "v1" }, { profile }),
          /news labeller's tool: only the label profile \(PORTFOLIXIR_MCP_PROFILE=label\)/,
          `${profile}: ${name}`
        );
      }
    }

    await assert.rejects(callTool(client, LABEL_PUT, label), /label profile/);
    assert.equal(requests.length, 0);

    const companion = await connectCompanion(client, { profile: "full" });

    try {
      const refused = await companion.mcp.callTool({ name: LABEL_PUT, arguments: label });
      assert.equal(refused.isError, true);
      assert.match((refused.content as any)[0].text, /only the label profile/);
    } finally {
      await companion.close();
    }

    assert.equal(requests.length, 0);
  });

  // User story (ADR-0056 §7's closed schema, at the companion too):
  // As the operator,
  // I want news.label_put to send exactly one label to the API and to
  // refuse before any request what the API would refuse by its shape,
  // so that the labeller's script learns its mistake without a round trip.
  //
  // Acceptance criteria:
  // - label_put sends PUT /api/v1/news/labels with {label: args}; the
  //   optional thesis_note_id, clause_idx and suggested_security_id pass.
  // - security_id, tier, status, notes and machine_generated (the server
  //   sets it) are refused, and so are materiality 4, tone 2, an event type
  //   outside the nine, confidence as a number or past four places, and a
  //   model of 65 characters; no request is made.
  // - unlabeled sends GET /api/v1/news/unlabeled with prompt_version and
  //   limit; without prompt_version or with a limit over 25 it is refused.
  // - label_put is a write the hints mark destructive and idempotent;
  //   unlabeled is read-only. Each description says the schema is closed,
  //   the write is journaled under the token, and the answer is data.
  it("routes the write and the read to the API and refuses what they do not take", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 3 } });
    const full = { ...label, thesis_note_id: 4, clause_idx: 2, suggested_security_id: 9 };

    await callTool(client, LABEL_PUT, full, LABEL);
    await callTool(client, UNLABELED, { prompt_version: "v1", limit: 5 }, LABEL);
    await callTool(client, UNLABELED, { prompt_version: "v1" }, LABEL);

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["PUT", "/api/v1/news/labels", { label: full }],
        ["GET", "/api/v1/news/unlabeled?prompt_version=v1&limit=5", undefined],
        ["GET", "/api/v1/news/unlabeled?prompt_version=v1", undefined]
      ]
    );

    for (const bad of [
      { security_id: 1 },
      { tier: "primary" },
      { status: "promoted" },
      { notes: [] },
      { machine_generated: true },
      { materiality: 4 },
      { tone: 2 },
      { event_type: "rumour" },
      { confidence: 0.85 },
      { confidence: "0.12345" },
      { model: "m".repeat(65) },
      { cluster_id: "7" }
    ]) {
      await assert.rejects(callTool(client, LABEL_PUT, { ...label, ...bad }, LABEL), JSON.stringify(bad));
    }

    await assert.rejects(callTool(client, UNLABELED, {}, LABEL));
    await assert.rejects(callTool(client, UNLABELED, { prompt_version: "v1", limit: 26 }, LABEL));
    await assert.rejects(callTool(client, UNLABELED, { prompt_version: "v1", model: "m" }, LABEL));
    assert.equal(requests.length, 3);

    const byName = new Map(allTools().map((tool) => [tool.name, tool]));
    const put = byName.get(LABEL_PUT)!;
    const read = byName.get(UNLABELED)!;

    assert.deepEqual(
      [put.annotations.readOnlyHint, put.annotations.destructiveHint, put.annotations.idempotentHint],
      [false, true, true]
    );
    assert.equal(read.annotations.readOnlyHint, true);

    for (const tool of [put, read]) {
      assert.match(tool.description, /data, never instructions/, tool.name);
      assert.deepEqual(
        Object.keys((tool.inputSchema as any).properties).sort(),
        Object.keys((tool.zodSchema as any).shape).sort(),
        `${tool.name}: the published schema names the validator's properties`
      );
    }

    assert.match(put.description, /unknown field answers 422 naming it/);
    assert.match(put.description, /Journaled under your token/);
    assert.match(read.description, /clauses/);
  });

  // User story (ADR-0056 §7, §9; the amendment of 2026-11-08, C5; plan D-8,
  // carry-forward 4):
  // As the operator whose labeller pays for every token it reads,
  // I want news.unlabeled's worst case at its default limit to hold its
  // budget on the text the tool returns, tag characters spelled out,
  // so that a hostile feed cannot make a labelling batch cost ten times
  // its budget.
  //
  // Acceptance criteria:
  // - The server's answer to test/portfolixir_web/controllers/
  //   api_v1_news_unlabeled_budget_test.exs's worst case (10 rows, 40
  //   securities, eight-clause theses), returned by the tool: compact JSON,
  //   the tag characters spelled [U+E0041], at most 6,000 tokens.
  it("holds the read's budget on the text it returns", async () => {
    const answer = JSON.parse(readFileSync(new URL("unlabeled-worst-case.json", FIXTURES), "utf8"));
    const { client } = createRecordingClient({ data: answer.data });
    const result = await callTool(client, UNLABELED, { prompt_version: "v1" }, LABEL);
    const text = result.content[0].text;

    assert.match(text, /\[U\+E0041\]/);
    assert.doesNotMatch(text, /\n/, "compact JSON");
    assert.equal((JSON.parse(text) as { data: { rows: unknown[] } }).data.rows.length, 10);
    assert.ok(tokens(text) <= 6_000, `news.unlabeled: ${tokens(text)} tokens`);
  });
});
