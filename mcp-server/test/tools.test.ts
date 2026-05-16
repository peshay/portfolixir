import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { createApiClient } from "../src/api-client.js";
import { callTool, listTools } from "../src/tools.js";

describe("Portfolixir MCP tools", () => {
  it("lists API-wrapper tools with string decimal schemas", () => {
    const tools = listTools();
    const names = tools.map((tool) => tool.name);

    assert.deepEqual(names, [
      "portfolixir.securities.list",
      "portfolixir.securities.create",
      "portfolixir.securities.search_online",
      "portfolixir.quotes.sync",
      "portfolixir.quotes.list",
      "portfolixir.quotes.upsert",
      "portfolixir.portfolios.list",
      "portfolixir.portfolios.create",
      "portfolixir.cash_accounts.list",
      "portfolixir.cash_accounts.create",
      "portfolixir.securities_accounts.list",
      "portfolixir.securities_accounts.create",
      "portfolixir.transactions.list",
      "portfolixir.transactions.create",
      "portfolixir.holdings.list",
      "portfolixir.trades.list"
    ]);

    const transactionCreate = tools.find((tool) => tool.name === "portfolixir.transactions.create");
    assert.equal(
      transactionCreate?.inputSchema.properties.transaction.properties.quantity.type,
      "string"
    );
    assert.equal(transactionCreate?.inputSchema.properties.transaction.properties.price.type, "string");
  });

  it("calls the Phoenix API with bearer auth and returns structured content", async () => {
    const requests: Array<{ method: string; path: string; body?: unknown; token: string }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({
          method: init?.method ?? "GET",
          path: `${parsed.pathname}${parsed.search}`,
          body: init?.body ? JSON.parse(String(init.body)) : undefined,
          token: String(init?.headers?.["authorization"])
        });

        return new Response(JSON.stringify({ data: [{ id: 7, name: "Synthetic" }] }), {
          status: 200,
          headers: { "content-type": "application/json" }
        });
      }
    });

    const result = await callTool(client, "portfolixir.securities.list", {
      query: "syn",
      sort: "name",
      direction: "asc"
    });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/securities?query=syn&sort=name&direction=asc");
    assert.equal(requests[0].token, "Bearer api-token");
    assert.deepEqual(result.structuredContent, { data: [{ id: 7, name: "Synthetic" }] });
    assert.match(result.content[0].text, /Synthetic/);
  });

  it("issues a GET to /trades for portfolixir.trades.list", async () => {
    const requests: Array<{ method: string; path: string; token: string }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({
          method: init?.method ?? "GET",
          path: `${parsed.pathname}${parsed.search}`,
          token: String(init?.headers?.["authorization"])
        });

        return new Response(
          JSON.stringify({
            data: {
              open_lots: [],
              closed_trades: [
                {
                  open_date: "2026-01-10",
                  close_date: "2026-04-10",
                  quantity: "10",
                  realized_pnl_abs: "500"
                }
              ],
              orphan_sells: []
            }
          }),
          { status: 200, headers: { "content-type": "application/json" } }
        );
      }
    });

    const result = await callTool(client, "portfolixir.trades.list", { security_id: 42 });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/securities/42/trades");
    assert.equal(requests[0].token, "Bearer api-token");
    assert.match(result.content[0].text, /500/);
  });

  it("maps invalid tool names and upstream API errors to clear failures", async () => {
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async () =>
        new Response(JSON.stringify({ errors: { name: ["can't be blank"] } }), {
          status: 422,
          headers: { "content-type": "application/json" }
        })
    });

    await assert.rejects(
      callTool(client, "portfolixir.unknown", {}),
      /Unknown Portfolixir MCP tool/
    );

    await assert.rejects(
      callTool(client, "portfolixir.securities.create", { security: { name: "" } }),
      /Portfolixir API request failed/
    );
  });
});
