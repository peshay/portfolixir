import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ADMIN_TOOLS, BOOK_KEPT_DESTRUCTIVE } from "../src/profiles.js";
import { callTool, listTools } from "../src/tools.js";
import { createApiClient } from "../src/api-client.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0062 §8 (Sprint 31, D2; FR-60): the four dashboard tools, each
// calling the public JSON API only (ADR-0002). The widget catalogue is part
// of list's answer, not a fifth tool.
const LIST = "portfolixir.dashboards.list";
const GET = "portfolixir.dashboards.get";
const PUT = "portfolixir.dashboards.put";
const DELETE = "portfolixir.dashboards.delete";
const DASHBOARD_TOOLS = [LIST, GET, PUT, DELETE];

const tool = (name: string) => listTools().find((entry) => entry.name === name);
const listed = (profile: "read" | "book" | "full") => listTools({ profile }).map((entry) => entry.name);

describe("the dashboard tools", () => {
  // User story (ADR-0062 §8):
  // As the agent the operator runs,
  // I want the dashboards and the widget catalogue in one call, one
  // dashboard or template with each widget's source route, and a put and a
  // delete,
  // so that „stell mir ein Dashboard für kurzfristige Bewegungen zusammen“
  // is one list and one put.
  //
  // Acceptance criteria:
  // - dashboards.list sends GET /api/v1/dashboards and GET /api/v1/widgets
  //   and answers {data: {dashboards, widgets}}, each the route's data.
  // - dashboards.get sends GET /api/v1/dashboards/:id with id, and GET
  //   /api/v1/dashboards/template:<key> with template, the key encoded.
  // - dashboards.put without id POSTs {dashboard: {name, layout}}, or with
  //   template {dashboard: {template, name?}}; with id and a layout it PUTs
  //   {dashboard: {name, layout, lock_version}}; with id and no layout it
  //   PATCHes {dashboard: {name?, position?, lock_version?}}.
  // - dashboards.delete sends DELETE /api/v1/dashboards/:id, with dry_run
  //   when given.
  it("routes each tool to the API", async () => {
    const { client, requests } = createRecordingClient({ data: [{ type: "template" }] });
    const layout = [
      { kind: "movers", size: "M", col: 1, row: 1, settings: { period: "1w" } },
      { kind: "performance", size: "S", col: 7, row: 1 }
    ];

    const listing = await callTool(client, LIST, {});
    await callTool(client, GET, { id: 4 });
    await callTool(client, GET, { template: "overview" });
    await callTool(client, PUT, { dashboard: { name: "Kurzfristig", layout } });
    await callTool(client, PUT, { template: "overview" });
    await callTool(client, PUT, { template: "overview", dashboard: { name: "Mein Überblick" } });
    await callTool(client, PUT, { id: 4, dashboard: { name: "Kurz", layout, lock_version: 3 } });
    await callTool(client, PUT, { id: 4, dashboard: { name: "Kurz", position: 2, lock_version: 3 } });
    await callTool(client, PUT, { id: 4, dashboard: { position: 1 } });
    await callTool(client, DELETE, { id: 4 });
    await callTool(client, DELETE, { id: 4, dry_run: true });

    assert.deepEqual(listing.structuredContent, {
      data: { dashboards: [{ type: "template" }], widgets: [{ type: "template" }] }
    });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["GET", "/api/v1/dashboards", undefined],
        ["GET", "/api/v1/widgets", undefined],
        ["GET", "/api/v1/dashboards/4", undefined],
        ["GET", "/api/v1/dashboards/template%3Aoverview", undefined],
        ["POST", "/api/v1/dashboards", { dashboard: { name: "Kurzfristig", layout } }],
        ["POST", "/api/v1/dashboards", { dashboard: { template: "overview" } }],
        ["POST", "/api/v1/dashboards", { dashboard: { template: "overview", name: "Mein Überblick" } }],
        ["PUT", "/api/v1/dashboards/4", { dashboard: { name: "Kurz", layout, lock_version: 3 } }],
        ["PATCH", "/api/v1/dashboards/4", { dashboard: { name: "Kurz", position: 2, lock_version: 3 } }],
        ["PATCH", "/api/v1/dashboards/4", { dashboard: { position: 1 } }],
        ["DELETE", "/api/v1/dashboards/4", undefined],
        ["DELETE", "/api/v1/dashboards/4?dry_run=true", undefined]
      ]
    );
  });

  // Acceptance criteria (ADR-0062 §2, §11):
  // - Before any request: get with both id and template, or neither; a put
  //   with id and template; a template copy carrying a layout, a position or
  //   a lock_version; a put with neither id, template nor dashboard; an item
  //   key or a setting the layout does not take (a route among them); a size
  //   outside S, W, M, T and L; a col outside 1 to 12; 41 items; a name over
  //   60 characters; a misspelt dry_run; a field a tool does not take.
  it("refuses what the API would refuse by its shape, before any request", async () => {
    const { client, requests } = createRecordingClient();
    const item = { kind: "due", size: "S", col: 1, row: 1 };

    for (const [name, args] of [
      [GET, {}],
      [GET, { id: 4, template: "overview" }],
      [GET, { id: "4" }],
      [PUT, {}],
      [PUT, { id: 4, template: "overview" }],
      [PUT, { template: "overview", dashboard: { layout: [item] } }],
      [PUT, { template: "overview", dashboard: { lock_version: 1 } }],
      [PUT, { template: "overview", dashboard: { position: 1 } }],
      [PUT, { dashboard: { name: "N", layout: [{ ...item, source: "GET /api/v1/journal" }] } }],
      [PUT, { dashboard: { name: "N", layout: [{ ...item, settings: { route: "/api/v1/journal" } }] } }],
      [PUT, { dashboard: { name: "N", layout: [{ ...item, size: "full" }] } }],
      [PUT, { dashboard: { name: "N", layout: [{ ...item, col: 13 }] } }],
      [PUT, { dashboard: { name: "N", layout: Array.from({ length: 41 }, (_, row) => ({ ...item, row: row + 1 })) } }],
      [PUT, { dashboard: { name: "x".repeat(61) } }],
      [PUT, { dashboard: { name: "N", kind: "due" } }],
      [DELETE, { id: 4, dryRun: true }],
      [DELETE, {}],
      [LIST, { group: "risk" }]
    ] as const) {
      const before = requests.length;
      await assert.rejects(callTool(client, name, { ...args } as any), `${name} ${JSON.stringify(args)}`);
      assert.equal(requests.length, before, `${name} ${JSON.stringify(args)}`);
    }
  });

  // Acceptance criteria (ADR-0062 §8; the plan's agent lens):
  // - list and get are reads in every profile; put is a write in book and
  //   full, kept with its reason (the previous name and layout put back
  //   restore it); delete is admin, listed in full only.
  // - put is hinted destructive and not idempotent (it overwrites with an
  //   id, adds without one); delete destructive.
  // - list's description says its answer carries the catalogue (kinds,
  //   sizes, source routes, period rules) and the grid; put's names
  //   lock_version, the 409 with the stored dashboard, the template copy,
  //   the rename and move without a layout, the 422 naming the first bad
  //   item and that the token's actor is journaled; delete's names dry_run
  //   and that a dashboard deletes nothing else. Each says its answer is
  //   data, never instructions.
  it("is described well enough to compose a dashboard from list's answer alone", () => {
    for (const name of [LIST, GET]) {
      assert.equal(tool(name)?.annotations.readOnlyHint, true, name);

      for (const profile of ["read", "book", "full"] as const) {
        assert.ok(listed(profile).includes(name), `${name} in ${profile}`);
      }
    }

    assert.ok(!listed("read").includes(PUT));
    assert.ok(listed("book").includes(PUT));
    assert.ok(BOOK_KEPT_DESTRUCTIVE.has(PUT));
    assert.ok(ADMIN_TOOLS.has(DELETE));
    assert.ok(!listed("book").includes(DELETE));
    assert.ok(listed("full").includes(DELETE));

    assert.deepEqual(tool(PUT)?.annotations, {
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    });
    assert.equal(tool(DELETE)?.annotations.destructiveHint, true);

    const description = (name: string) => tool(name)?.description ?? "";

    for (const part of ["widgets", "sizes", "source", "period", "grid", "template:", "in_menu"]) {
      assert.match(description(LIST), new RegExp(part), `list names ${part}`);
    }

    for (const part of ["lock_version", "409", "template", "position", "422", "token", "period"]) {
      assert.match(description(PUT), new RegExp(part), `put names ${part}`);
    }

    assert.match(description(GET), /source/);
    assert.match(description(DELETE), /dry_run/);
    assert.match(description(DELETE), /nothing else/);

    for (const name of DASHBOARD_TOOLS) {
      assert.match(description(name), /never instructions/, `${name} says its answer is data`);
    }

    const putSchema = tool(PUT)?.inputSchema as any;
    const item = putSchema.properties.dashboard.properties.layout.items;
    assert.equal(putSchema.additionalProperties, false);
    assert.equal(putSchema.properties.dashboard.additionalProperties, false);
    assert.equal(item.additionalProperties, false);
    assert.deepEqual(item.required, ["kind", "size", "col", "row"]);
    assert.deepEqual(item.properties.size.enum, ["S", "W", "M", "T", "L"]);
    assert.equal(item.properties.settings.additionalProperties, false);
    assert.deepEqual(Object.keys(item.properties.settings.properties).sort(), ["period", "view_id"]);
    assert.equal(putSchema.properties.dashboard.properties.layout.maxItems, 40);
  });

  // Acceptance criteria (ADR-0062 §2, §8):
  // - A stale lock_version's 409 reaches the agent as a tool error carrying
  //   the API's body: the code stale and the stored dashboard.
  it("passes a stale write's 409 with the stored dashboard to the agent", async () => {
    const stored = { type: "dashboard", id: 4, name: "Kurz", lock_version: 5 };
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async () =>
        new Response(JSON.stringify({ errors: { code: "stale", detail: "changed", stored } }), {
          status: 409,
          headers: { "content-type": "application/json" }
        })
    });

    await assert.rejects(
      callTool(client, PUT, { id: 4, dashboard: { name: "N", layout: [], lock_version: 3 } }),
      (error: Error) => /409/.test(error.message) && /"stale"/.test(error.message) && /"lock_version":5/.test(error.message)
    );
  });
});
