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
      { kind: "movers", size: "L", col: 1, row: 1, settings: { period: "1w" } },
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
      data: {
        dashboards: [{ type: "template" }],
        widgets: [{ type: "template" }],
        periods: [{ type: "template" }],
        quick: [{ type: "template" }]
      }
    });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["GET", "/api/v1/dashboards", undefined],
        ["GET", "/api/v1/widgets", undefined],
        // Sprint 32 T2: the own periods ride on list's answer.
        ["GET", "/api/v1/periods", undefined],
        // Sprint 32 T3: and the quick choice.
        ["GET", "/api/v1/periods/quick", undefined],
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
  //   outside S, M, L and XL (Sprint 31's W and T among them); a kind over 40 characters (SE2: every other
  //   text field is capped); a col outside 1 to 12; 41 items; a name over
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
      [PUT, { dashboard: { name: "N", layout: [{ ...item, route: "GET /api/v1/journal" }] } }],
      [PUT, { dashboard: { name: "N", layout: [{ ...item, settings: { route: "/api/v1/journal" } }] } }],
      [PUT, { dashboard: { name: "N", layout: [{ ...item, size: "full" }] } }],
      [PUT, { dashboard: { name: "N", layout: [{ ...item, size: "W" }] } }],
      [PUT, { dashboard: { name: "N", layout: [{ ...item, size: "T" }] } }],
      [PUT, { dashboard: { name: "N", layout: [{ ...item, kind: "k".repeat(41) }] } }],
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

  // User story (ADR-0062 §8, §11; Sprint 31 closing act, C3 and A2):
  // As the agent the operator runs,
  // I want to put back a layout as get (or a 409's stored dashboard)
  // answered it, with only my change made,
  // so that get, modify and put is one round trip.
  //
  // Acceptance criteria:
  // - put takes an item's title and source as get answers them (a string
  //   or null, an object or null) and does not send them: both are
  //   read-only, the registry's, ignored on write.
  // - get's and put's descriptions say so; the schema names both.
  it("takes a layout as get answered it, its title and source not sent", async () => {
    const { client, requests } = createRecordingClient();
    const source = { routes: ["GET /api/v1/movers"], function: "M.read/3", note: null };
    const read = [
      { kind: "movers", size: "L", col: 1, row: 2, settings: {}, title: "Tops and flops", source },
      { kind: "gone_kind", size: "S", col: 7, row: 1, settings: {}, title: null, source: null }
    ];

    await callTool(client, PUT, { id: 4, dashboard: { name: "Kurz", layout: read, lock_version: 3 } });
    await callTool(client, PUT, { dashboard: { name: "Kopie", layout: read } });

    const sent = [
      { kind: "movers", size: "L", col: 1, row: 2, settings: {} },
      { kind: "gone_kind", size: "S", col: 7, row: 1, settings: {} }
    ];

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["PUT", "/api/v1/dashboards/4", { dashboard: { name: "Kurz", layout: sent, lock_version: 3 } }],
        ["POST", "/api/v1/dashboards", { dashboard: { name: "Kopie", layout: sent } }]
      ]
    );

    const item = (tool(PUT)?.inputSchema as any).properties.dashboard.properties.layout.items;
    assert.ok("title" in item.properties && "source" in item.properties);

    for (const name of [GET, PUT]) {
      assert.match(tool(name)?.description ?? "", /title and source .*read-only/, name);
    }
  });

  // User story (Sprint 32 E3; ADR-0062's amendment of 2026-11-25, point 2):
  // As the agent the operator runs,
  // I want put to ask the server to make room for the item I changed,
  // so that I resize or move one widget without placing every other one.
  //
  // Acceptance criteria:
  // - put with id, a layout, arrange "push" and arranged_index PUTs both
  //   inside dashboard, as the API takes them.
  // - Before any request: arrange other than "push", arrange without
  //   arranged_index or the other way round, an arranged_index that is no
  //   whole number from 0 to 39, either without a layout (a rename or a
  //   move, which arranges nothing) or on a create or a copy.
  // - put's schema names both, and its description says the others make
  //   room and that without them an overlap is refused.
  it("asks the server to arrange around the item changed, and only on a replace", async () => {
    const { client, requests } = createRecordingClient();
    const layout = [
      { kind: "snapshots", size: "M", col: 1, row: 3 },
      { kind: "movers", size: "L", col: 1, row: 3 }
    ];

    await callTool(client, PUT, {
      id: 4,
      dashboard: { name: "Kurz", layout, lock_version: 3, arrange: "push", arranged_index: 0 }
    });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        [
          "PUT",
          "/api/v1/dashboards/4",
          { dashboard: { name: "Kurz", layout, lock_version: 3, arrange: "push", arranged_index: 0 } }
        ]
      ]
    );

    for (const args of [
      { id: 4, dashboard: { name: "N", layout, lock_version: 3, arrange: "always", arranged_index: 0 } },
      { id: 4, dashboard: { name: "N", layout, lock_version: 3, arrange: "push" } },
      { id: 4, dashboard: { name: "N", layout, lock_version: 3, arranged_index: 0 } },
      { id: 4, dashboard: { name: "N", layout, lock_version: 3, arrange: "push", arranged_index: -1 } },
      { id: 4, dashboard: { name: "N", layout, lock_version: 3, arrange: "push", arranged_index: 40 } },
      { id: 4, dashboard: { name: "N", layout, lock_version: 3, arrange: "push", arranged_index: 0.5 } },
      { id: 4, dashboard: { name: "N", position: 2, arrange: "push", arranged_index: 0 } },
      { dashboard: { name: "N", layout, arrange: "push", arranged_index: 0 } },
      { template: "overview", dashboard: { arrange: "push", arranged_index: 0 } }
    ]) {
      const before = requests.length;
      await assert.rejects(callTool(client, PUT, args as any), JSON.stringify(args));
      assert.equal(requests.length, before, JSON.stringify(args));
    }

    const fields = (tool(PUT)?.inputSchema as any).properties.dashboard.properties;
    assert.deepEqual(fields.arrange, { type: "string", enum: ["push"] });
    assert.deepEqual(fields.arranged_index, { type: "integer" });
    assert.match(tool(PUT)?.description ?? "", /arrange "push" \+ arranged_index/);
    assert.match(tool(PUT)?.description ?? "", /others make room; else an overlap is 422/);
  });

  // Acceptance criteria (ADR-0062 §8; the plan's agent lens):
  // - list and get are reads in every profile; put is a write in book and
  //   full, kept with its reason (the previous name and layout put back
  //   restore it); delete is admin, listed in full only.
  // - put is hinted destructive and not idempotent (it overwrites with an
  //   id, adds without one); delete destructive.
  // - list's description says its answer carries the catalogue (kinds,
  //   sizes, source routes, period rules) and the grid, says get takes a
  //   template's bare key and that data.widgets is the catalogue object,
  //   its kinds under widgets (A4); put's names
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

    for (const part of ["widgets", "sizes", "source", "period", "grid", "in_menu"]) {
      assert.match(description(LIST), new RegExp(part), `list names ${part}`);
    }

    // A4: get takes a template's bare key (template), and data.widgets is
    // the catalogue object, its kinds under widgets beside groups, grid and
    // periods.
    assert.match(description(LIST), /get takes a template's key as template/);
    assert.doesNotMatch(description(LIST), /template:</);
    assert.match(description(LIST), /data\.widgets, the catalogue: widgets, each kind's key/);
    assert.match(description(LIST), /groups; grid \(.*\); periods; limits/);

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
    // Apple's families since Sprint 32 E4; list names them with their grid.
    assert.deepEqual(item.properties.size.enum, ["S", "M", "L", "XL", "row"]);
    assert.match(description(LIST), /families S 3x2, M 6x2, L 6x4, XL 12x4; row 12x1, content height/);
    assert.equal(item.properties.kind.maxLength, 40);
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

// --- S32 S1 begin ---
describe("a dashboard's own view (Sprint 32 S1)", () => {
  // User story (ADR-0062's amendment of 2026-11-25, point 4):
  // As the agent composing a dashboard for one part of the operator's
  // holdings,
  // I want put to give it a view of its own on a create, a template's copy
  // and a rename, and to clear it with null,
  // so that I compose what the operator's gallery composes.
  //
  // Acceptance criteria:
  // - put sends view_id inside dashboard on POST (a create, a copy) and on
  //   PATCH (no layout), null as null.
  // - Before any request: view_id beside a layout on a replace (the PUT
  //   takes none), a view_id that is no positive whole number.
  // - put's description names view_id.
  it("sends view_id on a create, a copy and a rename, and refuses it on a replace", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await callTool(client, PUT, { dashboard: { name: "Krypto", layout: [], view_id: 7 } });
    await callTool(client, PUT, { template: "overview", dashboard: { view_id: 7 } });
    await callTool(client, PUT, { id: 4, dashboard: { view_id: 8 } });
    await callTool(client, PUT, { id: 4, dashboard: { view_id: null } });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["POST", "/api/v1/dashboards", { dashboard: { name: "Krypto", layout: [], view_id: 7 } }],
        ["POST", "/api/v1/dashboards", { dashboard: { template: "overview", view_id: 7 } }],
        ["PATCH", "/api/v1/dashboards/4", { dashboard: { view_id: 8 } }],
        ["PATCH", "/api/v1/dashboards/4", { dashboard: { view_id: null } }]
      ]
    );

    for (const args of [
      { id: 4, dashboard: { name: "N", layout: [], lock_version: 1, view_id: 7 } },
      { dashboard: { name: "N", layout: [], view_id: 0 } },
      { dashboard: { name: "N", layout: [], view_id: "7" } }
    ]) {
      const before = requests.length;
      await assert.rejects(callTool(client, PUT, args as any), JSON.stringify(args));
      assert.equal(requests.length, before, JSON.stringify(args));
    }

    assert.match(tool(PUT)?.description ?? "", /view_id/);
  });
});
// --- S32 S1 end ---
