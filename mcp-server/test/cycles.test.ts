import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { ADMIN_TOOLS, BOOK_KEPT_DESTRUCTIVE } from "../src/profiles.js";
import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0059 §11 and ADR-0060 §11 (Sprint 29, H6; FR-58, #1450): the chain
// tools and the cycles read, each calling the public JSON API only
// (ADR-0002), and the dossier's cycles line, measured on the text the tool
// returns. The fixture is the server's line from
// test/portfolixir_web/controllers/api_v1_security_cycles_test.exs, its id
// normalized; that test fails when it no longer matches.
const LIST = "portfolixir.chains.list";
const REFRESH = "portfolixir.chains.refresh";
const CYCLES = "portfolixir.securities.cycles";
const DOSSIER = "portfolixir.securities.dossier";
const H6_TOOLS = [LIST, REFRESH, CYCLES];
const FIXTURE = new URL("./fixtures/cycles/dossier-cycles.json", import.meta.url);

const tool = (name: string) => listTools().find((entry) => entry.name === name);
const listed = (profile: "read" | "book" | "full") => listTools({ profile }).map((entry) => entry.name);

// Characters / 4, counted in code points, of the text the agent receives.
const tokens = (text: string) => Array.from(text).length / 4;

describe("the chain and cycles tools", () => {
  // User story (ADR-0059 §11, ADR-0060 §11):
  // As the agent the operator runs,
  // I want the chains, an on-demand chain read and a security's cycles as
  // tools, each calling the API,
  // so that I read the same health, halvings and bands the operator sees.
  //
  // Acceptance criteria:
  // - chains.list sends GET /api/v1/chains; chains.refresh sends POST
  //   /api/v1/chains/:chain/refresh without a body; securities.cycles sends
  //   GET /api/v1/securities/:security_id/cycles, with include=aligned when
  //   asked.
  // - A chain outside the registry, include other than aligned, as_of and
  //   any field a tool does not take are refused before any request.
  it("routes each tool to the API and refuses what it does not take", async () => {
    const { client, requests } = createRecordingClient({ data: { chain: "bitcoin" } });

    await callTool(client, LIST, {});
    await callTool(client, REFRESH, { chain: "bitcoin" });
    await callTool(client, REFRESH, { chain: "litecoin" });
    await callTool(client, CYCLES, { security_id: 7 });
    await callTool(client, CYCLES, { security_id: 7, include: "aligned" });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["GET", "/api/v1/chains", undefined],
        ["POST", "/api/v1/chains/bitcoin/refresh", undefined],
        ["POST", "/api/v1/chains/litecoin/refresh", undefined],
        ["GET", "/api/v1/securities/7/cycles", undefined],
        ["GET", "/api/v1/securities/7/cycles?include=aligned", undefined]
      ]
    );

    for (const [name, args] of [
      [LIST, { chain: "bitcoin" }],
      [REFRESH, {}],
      [REFRESH, { chain: "dogecoin" }],
      [REFRESH, { chain: "bitcoin/../../securities" }],
      [REFRESH, { chain: "bitcoin", force: true }],
      [CYCLES, {}],
      [CYCLES, { security_id: 0 }],
      [CYCLES, { security_id: 7, as_of: "2024-01-01" }],
      [CYCLES, { security_id: 7, include: "bands" }],
      [CYCLES, { security_id: 7, window: "1y" }]
    ] as const) {
      const before = requests.length;
      await assert.rejects(callTool(client, name, { ...args }), `${name} ${JSON.stringify(args)}`);
      assert.equal(requests.length, before, `${name} ${JSON.stringify(args)}`);
    }
  });

  // User story (ADR-0059 §11, ADR-0060 §8, §11; the "no advice" non-goal):
  // As the operator whose agent reads a coin's cycles,
  // I want each tool to say it returns data, the cycles read to say that the
  // band is not a forecast and that n and both ends belong with every
  // figure, and the refresh to say how often it runs,
  // so that a band is never passed on as a price target or a tip.
  //
  // Acceptance criteria:
  // - Each tool says it returns data, never instructions or advice, and
  //   takes no field it does not name.
  // - securities.cycles says not a forecast, n and both ends, that the parts
  //   share their data, that there is no as_of, and include=aligned.
  // - chains.refresh says once per 10 minutes, 429 with retry_after and
  //   no_source; chains.list says stale after 24 hours.
  // - chains.list and securities.cycles are reads in every profile;
  //   chains.refresh is a write that reaches an outside host (openWorldHint),
  //   neither destructive nor idempotent, in book and full, not read, and in
  //   neither the admin set nor the kept overwrites.
  it("says each returns data, and places each by its hints", () => {
    for (const name of H6_TOOLS) {
      const definition = tool(name);
      assert.match(definition?.description ?? "", /[Dd]ata, never instructions or advice/, name);
      assert.equal(
        (definition?.inputSchema as { additionalProperties?: boolean }).additionalProperties,
        false,
        name
      );
    }

    const cycles = tool(CYCLES)?.description ?? "";
    assert.match(cycles, /not a forecast/);
    assert.match(cycles, /n and both ends/);
    assert.match(cycles, /parts share their data/);
    assert.match(cycles, /no as_of/);
    assert.match(cycles, /include=aligned/);
    assert.match(cycles, /computation_basis/);

    const refresh = tool(REFRESH)?.description ?? "";
    assert.match(refresh, /once per 10 minutes/);
    assert.match(refresh, /429 with retry_after/);
    assert.match(refresh, /no_source/);
    assert.match(tool(LIST)?.description ?? "", /stale after 24 hours/);

    const read = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
    assert.deepEqual(tool(LIST)?.annotations, read);
    assert.deepEqual(tool(CYCLES)?.annotations, read);
    assert.deepEqual(tool(REFRESH)?.annotations, {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: true
    });

    for (const profile of ["read", "book", "full"] as const) {
      assert.ok(listed(profile).includes(LIST), profile);
      assert.ok(listed(profile).includes(CYCLES), profile);
    }

    assert.ok(!listed("read").includes(REFRESH));
    assert.ok(listed("book").includes(REFRESH));
    assert.ok(listed("full").includes(REFRESH));
    assert.ok(!ADMIN_TOOLS.has(REFRESH));
    assert.ok(!BOOK_KEPT_DESTRUCTIVE.has(REFRESH));
  });

  // User story (ADR-0060 §11; plan row H6, "about 40 tokens, measured on the
  // companion's text"):
  // As the operator whose agent starts a research run from the dossier,
  // I want its cycles line to cost about 40 tokens on the text my agent
  // receives, with every price at its widest,
  // so that the dossier says where the coin stands in its cycle without
  // spending the read's budget on it.
  //
  // Acceptance criteria:
  // - The dossier answers compact JSON, its structured content the same.
  // - The cycles line of the fixture (7- and 8-digit prices at 6 decimals)
  //   is at most 40 tokens with its n at the widest a small count is.
  // - The description names the line's two arrays and their order.
  it("holds the dossier's cycles line to about 40 tokens on the returned text", async () => {
    const answer = JSON.parse(readFileSync(FIXTURE, "utf8"));
    const { client } = createRecordingClient({ data: answer.data });

    const result = await callTool(client, DOSSIER, { id: 1 });
    const text = result.content[0].text;

    assert.doesNotMatch(text, /\n/, "compact JSON");

    const line = text.slice(text.indexOf('"cycles":') + '"cycles":'.length, text.indexOf(',"security_id"'));
    assert.deepEqual(JSON.parse(line), (result.structuredContent as any).data.cycles);
    assert.ok(tokens(line) <= 40, `cycles line: ${tokens(line)} tokens`);

    const description = tool(DOSSIER)?.description ?? "";
    assert.match(description, /cycles: low and top, each \[from, to, price from, price to, state, n\]/);
    assert.match(description, /not a forecast/);
  });
});
