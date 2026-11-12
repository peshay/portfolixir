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
  // - The schema names the three chains and null.
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

    const fields = (tool("portfolixir.securities.list")?.inputSchema as any).properties.fields.items.enum;
    assert.ok(fields.includes("halving_chain"));
  });
  // --- S29 H1 end ---
});
