import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0056 §7, §9 (Sprint 28, N2): the labels in the agent's news reads.
// news.list and news.digest take min_materiality and prompt_version,
// news.get a story's prompt_version; no read takes tone; each description
// says how a label acts.
const LIST = "portfolixir.news.list";
const GET = "portfolixir.news.get";
const HEALTH = "portfolixir.news.health";
const DIGEST = "portfolixir.news.digest";
const FIXTURES = new URL("./fixtures/news-budget/", import.meta.url);

const description = (name: string) => listTools().find((entry) => entry.name === name)?.description ?? "";

describe("the labels in the news read tools", () => {
  // User story (ADR-0056 §7, §9):
  // As the operator's agent,
  // I want the list and the digest to take a materiality threshold and a
  // prompt version, and get a story's prompt version, sent to the API as
  // given, and tone refused by every read,
  // so that a label sorts what I read and a model's tone never filters it.
  //
  // Acceptance criteria:
  // - news.list and news.digest send min_materiality and prompt_version as
  //   query parameters; news.get sends prompt_version for a cluster_id.
  // - min_materiality outside 0 to 3, prompt_version with a news_id, and
  //   tone, min_tone or sort on any news read are refused before a request.
  it("routes the label parameters and refuses tone before any request", async () => {
    const { client, requests } = createRecordingClient({ data: { rows: [] } });

    await callTool(client, LIST, { security_id: 12, min_materiality: 2, prompt_version: "v2" });
    await callTool(client, DIGEST, { min_materiality: 0, prompt_version: "v2" });
    await callTool(client, GET, { cluster_id: 7, prompt_version: "v2" });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path]),
      [
        ["GET", "/api/v1/news/stories?security_id=12&min_materiality=2&prompt_version=v2"],
        ["GET", "/api/v1/news/digest?min_materiality=0&prompt_version=v2"],
        ["GET", "/api/v1/news/stories/7?prompt_version=v2"]
      ]
    );

    for (const [name, args] of [
      [LIST, { security_id: 12, min_materiality: 4 }],
      [DIGEST, { min_materiality: -1 }],
      [GET, { news_id: 9, prompt_version: "v2" }],
      ...[LIST, GET, HEALTH, DIGEST].flatMap((tool) =>
        [{ tone: 1 }, { min_tone: 0 }, { sort: "tone" }].map((extra) => [
          tool,
          { ...(tool === LIST ? { security_id: 12 } : tool === GET ? { cluster_id: 7 } : {}), ...extra }
        ])
      )
    ] as const) {
      const before = requests.length;
      await assert.rejects(callTool(client, name, { ...args }), `${name} ${JSON.stringify(args)}`);
      assert.equal(requests.length, before, `${name} ${JSON.stringify(args)}`);
    }
  });

  // User story (ADR-0056 §7, NFR-10):
  // As the operator's agent reading the tool list once at connect time,
  // I want each news read to say how a label acts on it,
  // so that I know a label sorts aggregator and thematic stories, never an
  // issuer's, and that it is a model's proposal.
  //
  // Acceptance criteria:
  // - news.list names materiality, event_type, min_materiality and the
  //   prompt_version default; news.get a story's label, machine_generated;
  //   news.digest that rows come most material first, that issuer and
  //   regulatory stories show always, min_materiality (2), unlabeled and
  //   the 50-character title.
  it("says how a label acts on each read", () => {
    const list = description(LIST);
    assert.match(list, /materiality, event_type/);
    assert.match(list, /min_materiality aggregator and thematic stories below it or unlabeled/);
    assert.match(list, /prompt_version's, default newest/);

    assert.match(description(GET), /a story's label \(machine_generated\)/);

    const digest = description(DIGEST);
    assert.match(digest, /most material first/);
    assert.match(digest, /Issuer and regulatory stories always/);
    assert.match(digest, /labeled min_materiality \(2\) or more/);
    assert.match(digest, /unlabeled, unassigned, ambiguous/);
    assert.match(digest, /title \(45 chars\)/);
    assert.match(digest, /prompt_version's, default newest/);

    for (const name of [LIST, GET, HEALTH, DIGEST]) {
      assert.doesNotMatch(JSON.stringify(listTools().find((entry) => entry.name === name)?.inputSchema), /tone/, name);
    }
  });

  // User story (ADR-0056 §9, §14 item 2; plan D-8 carry-forward 4):
  // As the operator whose agent pays for every token it reads,
  // I want the budget fixtures to carry the widest label a read answers,
  // so that the budgets the companion measures hold with labels.
  //
  // Acceptance criteria:
  // - The digest's fixture rows carry materiality 3 and event_type, and
  //   the digest names its 64-character prompt_version; the list's rows
  //   carry materiality; both get fixtures carry a label naming a thesis's
  //   clause, machine_generated true (news-budget.test.ts measures them).
  it("measures the budgets with labels", () => {
    const fixture = (name: string) =>
      JSON.parse(readFileSync(new URL(`${name}.json`, FIXTURES), "utf8")).data;

    const digest = fixture("digest-soft-hyphens");
    assert.equal(digest.prompt_version.length, 64);
    assert.ok(digest.rows.every((row: any) => row.materiality === 3 && row.event_types.join() === "capital_measure,regulatory"));
    assert.ok(fixture("list-tag-characters").rows.every((row: any) => row.materiality === 3));

    for (const name of ["get-tag-characters", "get-worst-case"]) {
      assert.deepEqual(Object.keys(fixture(name).label).sort(), [
        "clause_idx",
        "confidence",
        "event_type",
        "machine_generated",
        "materiality",
        "thesis_note_id",
        "tone"
      ]);
    }
  });
});
