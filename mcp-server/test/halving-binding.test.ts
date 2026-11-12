import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0059 §4, §11 (Sprint 29 H1, FR-58): a security's halving_chain on
// portfolixir.securities.update, calling the API only.
const tool = (name: string) => listTools().find((entry) => entry.name === name);

describe("the halving chain binding", () => {
  // --- S29 H1 begin ---
  // User story (ADR-0059 §4, §11):
  // As the agent that knows which chain a coin lives on,
  // I want securities.update to take halving_chain, a registered chain or
  // null, and securities.list to select it,
  // so that I can bind and unbind a security without the operator's hands.
  //
  // Acceptance criteria:
  // - securities.update forwards halving_chain "bitcoin", "bitcoin_cash",
  //   "litecoin" or null unchanged.
  // - Any other value ("zcash", a number) is refused before any request.
  // - The schema names the three chains and null, and its description says
  //   that unbinding or rebinding deletes its halving events, counted.
  // - securities.list's fields enum offers halving_chain.
  it("forwards a registered chain or null and refuses any other", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 7 } });

    for (const chain of ["bitcoin", "bitcoin_cash", "litecoin", null]) {
      await callTool(client, "portfolixir.securities.update", { id: 7, security: { halving_chain: chain } });
    }

    assert.deepEqual(
      requests.map((request) => request.body),
      ["bitcoin", "bitcoin_cash", "litecoin", null].map((chain) => ({ security: { halving_chain: chain } }))
    );

    for (const bad of ["zcash", "Bitcoin", 7]) {
      const before = requests.length;
      await assert.rejects(callTool(client, "portfolixir.securities.update", { id: 7, security: { halving_chain: bad } }));
      assert.equal(requests.length, before, JSON.stringify(bad));
    }

    const properties = (tool("portfolixir.securities.update")?.inputSchema as any).properties.security.properties;
    assert.deepEqual(properties.halving_chain.enum, ["bitcoin", "bitcoin_cash", "litecoin", null]);
    assert.match(properties.halving_chain.description, /deletes its halving events/);
    assert.match(properties.halving_chain.description, /halving_events_deleted/);

    const fields = (tool("portfolixir.securities.list")?.inputSchema as any).properties.fields.items.enum;
    assert.ok(fields.includes("halving_chain"));
  });

  // User story (ADR-0048's amendment of 2026-11-12, items 1 to 4, 6, 8):
  // As the agent recording a Litecoin halving or reading the calendar,
  // I want the events tools to take the kind halving with its chain_height
  // and to say when the chain alone writes it,
  // so that I bind first, give the height, and leave Bitcoin to the chain.
  //
  // Acceptance criteria:
  // - events.create and events.update take kind "halving" and chain_height
  //   (an integer, at least 1) and forward them unchanged; a chain_height
  //   of 0 or a string is refused before any request.
  // - The kind filters of upcoming, unconfirmed and stale offer halving.
  // - events.create names no_halving_chain and halving_from_chain; events.stale
  //   says confirmed halvings are left out; securities.merge_preview names
  //   the dropped halvings.
  it("takes the kind halving with its chain height and names its refusals", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 9 } });
    const event = {
      kind: "halving",
      chain_height: 840_000,
      date: "2019-08-05",
      timing: "exact",
      source_quality: "primary"
    };

    await callTool(client, "portfolixir.events.create", { security_id: 4, event });
    await callTool(client, "portfolixir.events.update", { id: 9, event: { chain_height: 1_680_000 } });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["POST", "/api/v1/securities/4/events", { event }],
        ["PATCH", "/api/v1/security_events/9", { event: { chain_height: 1_680_000 } }]
      ]
    );

    for (const chain_height of [0, "840000"]) {
      const before = requests.length;
      await assert.rejects(
        callTool(client, "portfolixir.events.create", { security_id: 4, event: { ...event, chain_height } })
      );
      assert.equal(requests.length, before, JSON.stringify(chain_height));
    }

    for (const name of ["portfolixir.events.upcoming", "portfolixir.events.unconfirmed", "portfolixir.events.stale"]) {
      assert.ok((tool(name)?.inputSchema as any).properties.kind.enum.includes("halving"), name);
    }

    const create = tool("portfolixir.events.create")?.description ?? "";
    assert.match(create, /no_halving_chain/);
    assert.match(create, /halving_from_chain/);
    assert.match(tool("portfolixir.events.stale")?.description ?? "", /confirmed halving/);
    assert.match(tool("portfolixir.securities.merge_preview")?.description ?? "", /dropped/);
  });
  // --- S29 H1 end ---
});
