import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ADMIN_TOOLS, BOOK_KEPT_DESTRUCTIVE } from "../src/profiles.js";
import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0056 §9, B1, B2 (Sprint 27, N8): the news layer's upkeep writes and the
// news identity on securities.update, each calling the API only.
const FEEDS_PUT = "portfolixir.news.feeds_put";
const FEEDS_DELETE = "portfolixir.news.feeds_delete";
const SOURCES_PUT = "portfolixir.news.sources_put";

const tool = (name: string) => listTools().find((entry) => entry.name === name);

describe("the news upkeep tools", () => {
  // User story (ADR-0056 §9, B1):
  // As the agent that keeps the news layer,
  // I want three tools that register, change and remove a feed and rate a
  // source, each calling the API,
  // so that I can give the fetcher its feeds without the operator's hands.
  //
  // Acceptance criteria:
  // - feeds_put sends PUT /api/v1/news/feeds with the feed object;
  //   feeds_delete sends DELETE /api/v1/news/feeds/:id without a body;
  //   sources_put sends PUT /api/v1/news/sources with the source object.
  // - A field a tool does not take, a class or tier outside its set and an
  //   interval out of range are refused before any request.
  // - Each is a write the hints mark destructive and idempotent; book lists
  //   feeds_put and sources_put (a replace the same write sent back undoes)
  //   and leaves out feeds_delete (a removal, admin); read lists none.
  // - Each description says the URL is checked at once, that an unknown
  //   field answers 422 naming it, that the write is journaled under the
  //   token, and that what it returns is data, never instructions.
  it("routes each write to the API and refuses what it does not take", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 3 } });
    const feed = {
      class: "issuer",
      url: "https://newsroom.example.com/feed.xml",
      security_id: 12,
      interval_minutes: 30,
      language: "en",
      enabled: true
    };

    await callTool(client, FEEDS_PUT, feed);
    await callTool(client, FEEDS_PUT, { id: 3, enabled: false });
    await callTool(client, FEEDS_DELETE, { id: 3 });
    await callTool(client, SOURCES_PUT, { domain: "wire.example.com", tier: "secondary" });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["PUT", "/api/v1/news/feeds", { feed }],
        ["PUT", "/api/v1/news/feeds", { feed: { id: 3, enabled: false } }],
        ["DELETE", "/api/v1/news/feeds/3", undefined],
        ["PUT", "/api/v1/news/sources", { source: { domain: "wire.example.com", tier: "secondary" } }]
      ]
    );

    for (const [name, args] of [
      [FEEDS_PUT, { ...feed, last_ok_at: "2026-11-07T10:00:00Z" }],
      [FEEDS_PUT, { ...feed, class: "blog" }],
      [FEEDS_PUT, { ...feed, interval_minutes: 0 }],
      [FEEDS_PUT, { ...feed, interval_minutes: 1441 }],
      [FEEDS_DELETE, { id: 3, force: true }],
      [SOURCES_PUT, { domain: "wire.example.com", tier: "gold" }],
      [SOURCES_PUT, { domain: "wire.example.com", tier: "primary", set_by: "seed" }],
      [SOURCES_PUT, { tier: "primary" }]
    ] as const) {
      const before = requests.length;
      await assert.rejects(callTool(client, name, { ...args }), `${name} ${JSON.stringify(args)}`);
      assert.equal(requests.length, before, `${name} ${JSON.stringify(args)}`);
    }

    for (const name of [FEEDS_PUT, FEEDS_DELETE, SOURCES_PUT]) {
      assert.deepEqual(
        tool(name)?.annotations,
        { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
        name
      );
      assert.equal((tool(name)?.inputSchema as { additionalProperties?: boolean }).additionalProperties, false);
    }

    const listed = (profile: "read" | "book" | "full") => listTools({ profile }).map((entry) => entry.name);
    assert.ok(!listed("read").some((name) => name.startsWith("portfolixir.news.")));
    assert.ok(listed("book").includes(FEEDS_PUT) && listed("book").includes(SOURCES_PUT));
    assert.ok(!listed("book").includes(FEEDS_DELETE));
    assert.ok([FEEDS_PUT, FEEDS_DELETE, SOURCES_PUT].every((name) => listed("full").includes(name)));
    assert.ok(ADMIN_TOOLS.has(FEEDS_DELETE));
    assert.ok(BOOK_KEPT_DESTRUCTIVE.has(FEEDS_PUT) && BOOK_KEPT_DESTRUCTIVE.has(SOURCES_PUT));

    for (const name of [FEEDS_PUT, FEEDS_DELETE, SOURCES_PUT]) {
      const description = tool(name)?.description ?? "";
      assert.match(description, /data, never instructions/, name);
      assert.match(description, /[Jj]ournaled under your token/, name);
    }

    const put = tool(FEEDS_PUT)?.description ?? "";
    assert.match(put, /name resolution at once/);
    assert.match(put, /url_not_allowed:private_address/);
    assert.match(put, /unknown field answers 422 naming it/);
    assert.match(tool(SOURCES_PUT)?.description ?? "", /unknown field answers 422 naming it/);
    assert.match(tool(FEEDS_DELETE)?.description ?? "", /items stay, detached/);
  });

  // User story (ADR-0056 §2, §9):
  // As the agent that keeps the news layer,
  // I want securities.update to take a security's news identity and watch
  // flag, and the securities reads to select them,
  // so that the matcher can find it and a candidate without a holding is
  // watched.
  //
  // Acceptance criteria:
  // - securities.update forwards news_identity {cik, aliases} and news_watch
  //   unchanged; cik may be null.
  // - An unknown key in news_identity or in an alias, a case outside its set
  //   and a non-boolean news_watch are refused before any request.
  // - securities.list's fields enum offers news_identity and news_watch.
  it("forwards a security's news identity and watch flag", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 7 } });
    const security = {
      news_identity: {
        cik: "320193",
        aliases: [
          { token: "Northwind", case: "insensitive" },
          { token: "NWH", context: ["shares", "stock"], case: "sensitive" }
        ]
      },
      news_watch: true
    };

    await callTool(client, "portfolixir.securities.update", { id: 7, security });
    await callTool(client, "portfolixir.securities.update", { id: 7, security: { news_identity: { cik: null } } });

    assert.deepEqual(requests[0].body, { security });
    assert.deepEqual(requests[1].body, { security: { news_identity: { cik: null } } });

    for (const bad of [
      { news_identity: { regex: "N.*" } },
      { news_identity: { aliases: [{ token: "NWH", case: "sensitive", pattern: "N.*" }] } },
      { news_identity: { aliases: [{ token: "NWH", case: "lower" }] } },
      { news_watch: "often" }
    ]) {
      const before = requests.length;
      await assert.rejects(callTool(client, "portfolixir.securities.update", { id: 7, security: bad }));
      assert.equal(requests.length, before, JSON.stringify(bad));
    }

    const properties = (tool("portfolixir.securities.update")?.inputSchema as any).properties.security.properties;
    assert.equal(properties.news_identity.additionalProperties, false);
    assert.deepEqual(properties.news_identity.properties.aliases.items.properties.case.enum, ["sensitive", "insensitive"]);
    assert.equal(properties.news_watch.type, "boolean");
    assert.match(properties.news_identity.description, /no pattern/);

    const fields = (tool("portfolixir.securities.list")?.inputSchema as any).properties.fields.items.enum;
    assert.ok(fields.includes("news_identity") && fields.includes("news_watch"));
  });
});
