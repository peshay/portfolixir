import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ADMIN_TOOLS } from "../src/profiles.js";
import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// Sprint 32 T2 (I59; ADR-0062's amendment of 2026-11-25, point 6): the
// operator's own periods over the companion. The list rides on
// dashboards.list's answer; the writes are one tool, periods.put, calling
// the public JSON API only (ADR-0002). Every name is synthetic.
const LIST = "portfolixir.dashboards.list";
const PUT = "portfolixir.periods.put";

const tool = (name: string) => listTools().find((entry) => entry.name === name);
const listed = (profile: "read" | "book" | "full") => listTools({ profile }).map((entry) => entry.name);

describe("the period tools", () => {
  // User story (T2):
  // As the agent the operator runs,
  // I want the stored periods with the dashboards, and one write that
  // creates, replaces and deletes one,
  // so that „leg mir einen Zeitraum ‚Sommer 2026‘ an“ is one call and every
  // widget pinned to it follows a change.
  //
  // Acceptance criteria:
  // - dashboards.list also reads GET /api/v1/periods and answers it as
  //   data.periods.
  // - periods.put without id POSTs {period: {name, from, to?}}; with id it
  //   PUTs {period: {name, from, to, lock_version}}; with id and delete:
  //   true it DELETEs /api/v1/periods/:id and sends no body.
  // - A delete without an id, a period beside delete, a write with neither,
  //   a name over 40 characters, a malformed date and a key the tool does
  //   not take never leave the companion.
  it("routes the list and each write to the API", async () => {
    const { client, requests } = createRecordingClient({ data: [{ id: 1 }] });

    const listing = await callTool(client, LIST, {});
    await callTool(client, PUT, { period: { name: "Sommer 2026", from: "2026-06-01", to: "2026-08-31" } });
    await callTool(client, PUT, { period: { name: "Seit Umschichtung", from: "2025-03-01" } });
    await callTool(client, PUT, {
      id: 7,
      period: { name: "Seit Umschichtung", from: "2025-04-01", to: null, lock_version: 2 }
    });
    await callTool(client, PUT, { id: 7, delete: true });

    assert.deepEqual((listing.structuredContent as any).data.periods, [{ id: 1 }]);

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["GET", "/api/v1/dashboards", undefined],
        ["GET", "/api/v1/widgets", undefined],
        ["GET", "/api/v1/periods", undefined],
        ["GET", "/api/v1/periods/quick", undefined],
        ["POST", "/api/v1/periods", { period: { name: "Sommer 2026", from: "2026-06-01", to: "2026-08-31" } }],
        ["POST", "/api/v1/periods", { period: { name: "Seit Umschichtung", from: "2025-03-01" } }],
        [
          "PUT",
          "/api/v1/periods/7",
          { period: { name: "Seit Umschichtung", from: "2025-04-01", to: null, lock_version: 2 } }
        ],
        ["DELETE", "/api/v1/periods/7", undefined]
      ]
    );

    for (const refused of [
      { delete: true },
      { id: 7, delete: true, period: { name: "X", from: "2025-01-01" } },
      { id: 7 },
      {},
      { period: { name: "x".repeat(41), from: "2025-01-01" } },
      { period: { name: "X", from: "01.03.2025" } },
      { period: { name: "X", from: "2025-01-01", color: "red" } },
      { id: 7, delete: false }
    ]) {
      await assert.rejects(callTool(client, PUT, refused), undefined, JSON.stringify(refused));
    }

    assert.equal(requests.length, 8, "a refused call sends nothing");
  });

  // User story (T3):
  // As the agent the operator runs,
  // I want the quick choice with the dashboards and set by the same write,
  // so that „leg Vorquartal in die Schnellwahl“ is one call.
  //
  // Acceptance criteria:
  // - dashboards.list also reads GET /api/v1/periods/quick and answers it
  //   as data.quick.
  // - periods.put with quick: [keys] PUTs {quick: {keys}} to
  //   /api/v1/periods/quick; up to six keys, each a period key in shape
  //   (saved:<id> among them), alone: beside id, delete or period, a
  //   seventh key or a key that is none it never leaves the companion.
  it("reads and writes the quick choice", async () => {
    const { client, requests } = createRecordingClient({ data: { keys: ["1w"] } });

    const listing = await callTool(client, LIST, {});
    await callTool(client, PUT, { quick: ["1w", "mtd", "saved:7", "year:2025"] });

    assert.deepEqual((listing.structuredContent as any).data.quick, { keys: ["1w"] });
    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["GET", "/api/v1/dashboards", undefined],
        ["GET", "/api/v1/widgets", undefined],
        ["GET", "/api/v1/periods", undefined],
        ["GET", "/api/v1/periods/quick", undefined],
        ["PUT", "/api/v1/periods/quick", { quick: { keys: ["1w", "mtd", "saved:7", "year:2025"] } }]
      ]
    );

    for (const refused of [
      { quick: ["1d", "1w", "1m", "3m", "6m", "1y", "3y"] },
      { quick: ["fortnight"] },
      { quick: ["1w"], id: 7 },
      { quick: ["1w"], period: { name: "X", from: "2025-01-01" } }
    ]) {
      await assert.rejects(callTool(client, PUT, refused), undefined, JSON.stringify(refused));
    }

    assert.equal(requests.length, 5, "a refused call sends nothing");
  });

  // Acceptance criteria (the profiles' rule, D-5 of Sprint 17):
  // - periods.put removes a stored period with delete: true, so it is
  //   admin, listed in full only, with its reason; it is hinted
  //   destructive and not idempotent (a create adds another).
  // - Its description names the key saved:<id>, the 409 with the stored
  //   period, the 50 limit and the journal, and says its answer is data.
  it("is admin, hinted destructive, and described well enough to write one", () => {
    assert.ok(ADMIN_TOOLS.has(PUT));
    assert.ok(!listed("read").includes(PUT));
    assert.ok(!listed("book").includes(PUT));
    assert.ok(listed("full").includes(PUT));

    assert.deepEqual(tool(PUT)?.annotations, {
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    });

    const description = tool(PUT)?.description ?? "";

    for (const part of ["saved:<id>", "lock_version", "409", "50", "delete", "quick", "Journaled", "never instructions"]) {
      assert.ok(description.includes(part), `put names ${part}`);
    }

    assert.match(tool(LIST)?.description ?? "", /data\.periods/);
    assert.match(tool(LIST)?.description ?? "", /data\.quick/);
  });
});
