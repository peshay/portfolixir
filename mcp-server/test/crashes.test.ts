import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ADMIN_TOOLS, BOOK_KEPT_DESTRUCTIVE } from "../src/profiles.js";
import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0058 §9 (Sprint 29, C5; FR-54, #1421): the five crash tools, each
// calling the public JSON API only (ADR-0002).
const LIST = "portfolixir.crashes.list";
const RANKINGS = "portfolixir.crashes.rankings";
const PUT = "portfolixir.crashes.put";
const DELETE = "portfolixir.crashes.delete";
const BENCHMARK_PUT = "portfolixir.crashes.benchmark_put";
const CRASH_TOOLS = [LIST, RANKINGS, PUT, DELETE, BENCHMARK_PUT];

const tool = (name: string) => listTools().find((entry) => entry.name === name);
const listed = (profile: "read" | "book" | "full") => listTools({ profile }).map((entry) => entry.name);

describe("the crash tools", () => {
  // User story (ADR-0058 §9):
  // As the agent the operator runs,
  // I want the crash windows, a window's lists and the crash writes as
  // tools, each calling the API,
  // so that I read the same windows the operator sees and name, draw and
  // delete them with my own token.
  //
  // Acceptance criteria:
  // - crashes.list sends GET /api/v1/crashes; crashes.rankings sends GET
  //   /api/v1/crashes/:key/rankings with list, universe, limit and
  //   include_unanswered as given, the key encoded.
  // - crashes.put sends PUT /api/v1/crashes/:key with the window when a key
  //   is given, else POST /api/v1/crashes (a manual window, or from_name);
  //   crashes.delete sends DELETE /api/v1/crashes/:key without a body;
  //   crashes.benchmark_put sends PUT /api/v1/settings/crash_benchmark with
  //   security_id, null to clear.
  // - A field a tool does not take, a key in neither spelling, a list or
  //   universe outside its set and a limit over 50 are refused before any
  //   request.
  it("routes each tool to the API and refuses what it does not take", async () => {
    const { client, requests } = createRecordingClient({ data: { key: "m:4" } });

    await callTool(client, LIST, {});
    await callTool(client, RANKINGS, { key: "d:12:2020-02-19" });
    await callTool(client, RANKINGS, {
      key: "m:4",
      list: "rebounders",
      universe: "view:3",
      limit: 20,
      include_unanswered: true
    });
    await callTool(client, PUT, { key: "d:12:2020-02-19", window: { name: "Spring fall" } });
    await callTool(client, PUT, { key: "m:4", window: { trough: "2020-03-16" } });
    await callTool(client, PUT, {
      window: { name: "War leg", start: "2022-02-23", trough: "2022-03-07" }
    });
    await callTool(client, PUT, { window: { from_name: "d:12:2018-01-26", trough: "2018-02-08" } });
    await callTool(client, DELETE, { key: "m:4" });
    await callTool(client, BENCHMARK_PUT, { security_id: 12 });
    await callTool(client, BENCHMARK_PUT, { security_id: null });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["GET", "/api/v1/crashes", undefined],
        ["GET", "/api/v1/crashes/d%3A12%3A2020-02-19/rankings", undefined],
        [
          "GET",
          "/api/v1/crashes/m%3A4/rankings?list=rebounders&universe=view%3A3&limit=20&include_unanswered=true",
          undefined
        ],
        ["PUT", "/api/v1/crashes/d%3A12%3A2020-02-19", { window: { name: "Spring fall" } }],
        ["PUT", "/api/v1/crashes/m%3A4", { window: { trough: "2020-03-16" } }],
        [
          "POST",
          "/api/v1/crashes",
          { window: { name: "War leg", start: "2022-02-23", trough: "2022-03-07" } }
        ],
        [
          "POST",
          "/api/v1/crashes",
          { window: { from_name: "d:12:2018-01-26", trough: "2018-02-08" } }
        ],
        ["DELETE", "/api/v1/crashes/m%3A4", undefined],
        ["PUT", "/api/v1/settings/crash_benchmark", { security_id: 12 }],
        ["PUT", "/api/v1/settings/crash_benchmark", { security_id: null }]
      ]
    );

    for (const [name, args] of [
      [LIST, { benchmark: "security:12" }],
      [RANKINGS, {}],
      [RANKINGS, { key: "d:12:2020-02-19", list: "fallers" }],
      [RANKINGS, { key: "d:12:2020-02-19", universe: "held" }],
      [RANKINGS, { key: "d:12:2020-02-19", limit: 51 }],
      [RANKINGS, { key: "d:12:2020-02-19", order: "asc" }],
      [RANKINGS, { key: "12:2020-02-19" }],
      [RANKINGS, { key: "m:4/../../securities/1" }],
      [PUT, { key: "m:4" }],
      [PUT, { key: "m:4", window: { name: "x", kind: "detected" } }],
      [PUT, { key: "x:4", window: { name: "x" } }],
      [PUT, { window: { name: "x" }, provisional: true }],
      [DELETE, {}],
      [DELETE, { key: "m:4", force: true }],
      [BENCHMARK_PUT, {}],
      [BENCHMARK_PUT, { security_id: 0 }],
      [BENCHMARK_PUT, { security_id: 12, threshold: "0.2" }]
    ] as const) {
      const before = requests.length;
      await assert.rejects(callTool(client, name, { ...args }), `${name} ${JSON.stringify(args)}`);
      assert.equal(requests.length, before, `${name} ${JSON.stringify(args)}`);
    }
  });

  // User story (ADR-0058 §8, §9; the "no advice" non-goal):
  // As the operator whose agent reads crash lists,
  // I want each crash tool to say it returns data, and the writes to say
  // they are journaled under the agent's token,
  // so that a list of who fell and who rose is never read as a tip.
  //
  // Acceptance criteria:
  // - Every crash tool's description says it returns data, never advice or
  //   instructions; the writes say they are journaled under the token and
  //   that an unknown field answers 422 naming it.
  // - The reads are read-only in every profile; crashes.put is destructive
  //   and not idempotent (a key overwrites, no key adds a window), so it
  //   says a timeout's outcome is unknown; crashes.delete and
  //   crashes.benchmark_put are destructive and idempotent.
  // - book lists the reads, crashes.put and crashes.benchmark_put (a
  //   replace the same write sent back undoes) and leaves out
  //   crashes.delete (a removal, admin); read lists the two reads only.
  it("says each returns data, and places each by its hints", () => {
    for (const name of CRASH_TOOLS) {
      const description = tool(name)?.description ?? "";
      assert.match(description, /[Dd]ata, never (advice|instructions)/, name);
      assert.equal(
        (tool(name)?.inputSchema as { additionalProperties?: boolean }).additionalProperties,
        false,
        name
      );
    }

    for (const name of [PUT, DELETE, BENCHMARK_PUT]) {
      assert.match(tool(name)?.description ?? "", /[Jj]ournaled under your token/, name);
    }

    assert.match(tool(PUT)?.description ?? "", /unknown field answers 422 naming it/);
    assert.match(tool(RANKINGS)?.description ?? "", /[Ss]urvivorship/);
    assert.match(tool(RANKINGS)?.description ?? "", /computation_basis/);
    assert.match(tool(LIST)?.description ?? "", /computation_basis/);

    const hints = (name: string) => tool(name)?.annotations;
    const read = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
    assert.deepEqual(hints(LIST), read);
    assert.deepEqual(hints(RANKINGS), read);
    assert.deepEqual(hints(PUT), {
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    });
    assert.match(tool(PUT)?.description ?? "", /outcome unknown/);

    for (const name of [DELETE, BENCHMARK_PUT]) {
      assert.deepEqual(hints(name), {
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: true,
        openWorldHint: false
      }, name);
    }

    assert.deepEqual(
      CRASH_TOOLS.filter((name) => listed("read").includes(name)),
      [LIST, RANKINGS]
    );
    assert.deepEqual(
      CRASH_TOOLS.filter((name) => listed("book").includes(name)),
      [LIST, RANKINGS, PUT, BENCHMARK_PUT]
    );
    assert.deepEqual(CRASH_TOOLS.filter((name) => listed("full").includes(name)), CRASH_TOOLS);
    assert.ok(ADMIN_TOOLS.has(DELETE));
    assert.ok(BOOK_KEPT_DESTRUCTIVE.has(PUT) && BOOK_KEPT_DESTRUCTIVE.has(BENCHMARK_PUT));
  });
});
