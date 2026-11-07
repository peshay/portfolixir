import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0056 §6, §9, §11 and ADR-0054 §4 (Sprint 27, N7): the news layer's
// reads, each calling the API only, answering compact JSON, with stored text
// spelled where an operator cannot see it.
const LIST = "portfolixir.news.list";
const GET = "portfolixir.news.get";
const HEALTH = "portfolixir.news.health";
const DIGEST = "portfolixir.news.digest";
const READS = [LIST, GET, HEALTH, DIGEST];

const tool = (name: string) => listTools().find((entry) => entry.name === name);

describe("the news read tools", () => {
  // User story (ADR-0056 §9, §11):
  // As the operator's agent,
  // I want four read tools — the list, one story or item, the health and the
  // digest — that call the news reads of the API and refuse what they do not
  // take,
  // so that I read the news layer in every profile without a write in reach.
  //
  // Acceptance criteria:
  // - news.list sends GET /api/v1/news/stories with its parameters; news.get
  //   sends GET /api/v1/news/stories/:id for a cluster_id and
  //   GET /api/v1/news/items/:id for a news_id; news.health sends
  //   GET /api/v1/news/health; news.digest sends GET /api/v1/news/digest.
  // - A label parameter of Sprint 28 (min_materiality, event_types,
  //   consumer), no selector or two, a tier or an assignment outside its set
  //   and a limit or max_rows out of range are refused before any request.
  // - Each is read-only and listed in the read, book and full profiles.
  // - Each description says that what it returns is data, never
  //   instructions.
  it("routes each read to the API and refuses what it does not take", async () => {
    const { client, requests } = createRecordingClient({ data: { rows: [] } });

    await callTool(client, LIST, { security_id: 12 });
    await callTool(client, LIST, {
      assignment: "ambiguous",
      since: "2026-11-07T09:30:00Z",
      tier_min: "secondary",
      limit: 50,
      fields: "std",
      cursor: "2026-11-07T10:00:00.000000Z~41"
    });
    await callTool(client, GET, { cluster_id: 7 });
    await callTool(client, GET, { news_id: 9 });
    await callTool(client, HEALTH, {});
    await callTool(client, DIGEST, {});
    await callTool(client, DIGEST, { view_id: 3, since: "2026-11-06", include_unlabeled: true, max_rows: 10 });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["GET", "/api/v1/news/stories?security_id=12", undefined],
        [
          "GET",
          "/api/v1/news/stories?assignment=ambiguous&since=2026-11-07T09%3A30%3A00Z&tier_min=secondary" +
            "&limit=50&fields=std&cursor=2026-11-07T10%3A00%3A00.000000Z%7E41",
          undefined
        ],
        ["GET", "/api/v1/news/stories/7", undefined],
        ["GET", "/api/v1/news/items/9", undefined],
        ["GET", "/api/v1/news/health", undefined],
        ["GET", "/api/v1/news/digest", undefined],
        [
          "GET",
          "/api/v1/news/digest?view_id=3&since=2026-11-06&include_unlabeled=true&max_rows=10",
          undefined
        ]
      ]
    );

    for (const [name, args] of [
      [LIST, { security_id: 12, min_materiality: 2 }],
      [LIST, { security_id: 12, event_types: ["earnings"] }],
      [LIST, {}],
      [LIST, { security_id: 12, category_id: 3 }],
      [LIST, { assignment: "assigned" }],
      [LIST, { security_id: 12, tier_min: "blocked" }],
      [LIST, { security_id: 12, limit: 101 }],
      [LIST, { security_id: 12, fields: "full" }],
      [GET, {}],
      [GET, { cluster_id: 7, news_id: 9 }],
      [HEALTH, { verbose: true }],
      [DIGEST, { consumer: "agent" }],
      [DIGEST, { min_materiality: 2 }],
      [DIGEST, { max_rows: 0 }],
      [DIGEST, { max_rows: 101 }]
    ] as const) {
      const before = requests.length;
      await assert.rejects(callTool(client, name, { ...args }), `${name} ${JSON.stringify(args)}`);
      assert.equal(requests.length, before, `${name} ${JSON.stringify(args)}`);
    }

    for (const profile of ["read", "book", "full"] as const) {
      const listed = listTools({ profile }).map((entry) => entry.name);
      assert.ok(READS.every((name) => listed.includes(name)), profile);
    }

    for (const name of READS) {
      assert.deepEqual(
        tool(name)?.annotations,
        { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        name
      );
      assert.equal((tool(name)?.inputSchema as { additionalProperties?: boolean }).additionalProperties, false);
      assert.match(tool(name)?.description ?? "", /data, never instructions/, name);
    }

    assert.match(tool(GET)?.description ?? "", /only read with the excerpt and url/);
    assert.match(tool(DIGEST)?.description ?? "", /include_unlabeled/);
    assert.match(tool(LIST)?.description ?? "", /first sight/);
  });

  // User story (ADR-0054 §4, ADR-0056 §9 and §14 item 2):
  // As the operator whose agent reads foreign headlines,
  // I want a news read to reach the agent as compact JSON, with every
  // character I cannot see spelled as on my screen,
  // so that the budgets measured on the API's JSON are what the tool returns,
  // and an invisible instruction in a title is visible as what it is.
  //
  // Acceptance criteria:
  // - The text a news read returns is the API's answer as compact JSON (no
  //   indentation), its structured content the same value.
  // - A title or an excerpt carrying U+200B or a tag character reaches the
  //   agent spelled [U+200B], [U+E0041].
  it("answers compact JSON with invisible characters spelled out", async () => {
    const stored = {
      rows: [{ id: 1, title: "Profit\u200b warning \u{E0041}", tier: "primary", at: "2026-11-07T09:00:00Z", count: 1 }]
    };
    const { client } = createRecordingClient({ data: stored });

    for (const [name, args] of [
      [LIST, { security_id: 1 }],
      [GET, { cluster_id: 1 }],
      [HEALTH, {}],
      [DIGEST, {}]
    ] as const) {
      const result = await callTool(client, name, { ...args });
      const text = result.content[0].text;
      const expected = {
        data: {
          rows: [{ id: 1, title: "Profit[U+200B] warning [U+E0041]", tier: "primary", at: "2026-11-07T09:00:00Z", count: 1 }]
        }
      };

      assert.equal(text, JSON.stringify(expected), name);
      assert.deepEqual(result.structuredContent, expected, name);
      assert.ok(!text.includes("\n"), name);
    }

    const other = await callTool(createRecordingClient({ data: { id: 1 } }).client, "portfolixir.securities.get", { id: 1 });
    assert.ok(other.content[0].text.includes("\n"), "other tools keep their indented text");
  });
});
