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
      "portfolixir.securities.update",
      "portfolixir.securities.delete",
      "portfolixir.securities.search_online",
      "portfolixir.quotes.sync",
      "portfolixir.quotes.list",
      "portfolixir.quotes.upsert",
      "portfolixir.portfolios.list",
      "portfolixir.portfolios.create",
      "portfolixir.cash_accounts.list",
      "portfolixir.cash_accounts.create",
      "portfolixir.cash_accounts.update",
      "portfolixir.cash_accounts.delete",
      "portfolixir.securities_accounts.list",
      "portfolixir.securities_accounts.create",
      "portfolixir.securities_accounts.update",
      "portfolixir.securities_accounts.delete",
      "portfolixir.transactions.list",
      "portfolixir.transactions.create",
      "portfolixir.transactions.update",
      "portfolixir.transactions.delete",
      "portfolixir.holdings.list",
      "portfolixir.portfolios.valuation",
      "portfolixir.exchange_rates.list",
      "portfolixir.exchange_rates.sync",
      "portfolixir.classifications.list",
      "portfolixir.classifications.create",
      "portfolixir.classifications.categories.create",
      "portfolixir.classifications.update",
      "portfolixir.classifications.delete",
      "portfolixir.classifications.categories.update",
      "portfolixir.classifications.categories.delete",
      "portfolixir.classifications.assign",
      "portfolixir.classifications.assign_bulk",
      "portfolixir.classifications.unassign",
      "portfolixir.trades.list",
      "portfolixir.targets.list",
      "portfolixir.targets.set",
      "portfolixir.targets.delete",
      "portfolixir.portfolios.allocation"
    ]);

    const transactionCreate = tools.find((tool) => tool.name === "portfolixir.transactions.create");
    assert.equal(
      transactionCreate?.inputSchema.properties.transaction.properties.quantity.type,
      "string"
    );
    assert.equal(transactionCreate?.inputSchema.properties.transaction.properties.price.type, "string");

    const securitiesList = tools.find((tool) => tool.name === "portfolixir.securities.list");
    assert.deepEqual(securitiesList?.inputSchema.properties.holding_status.enum, [
      "held",
      "not_held",
      "all"
    ]);

    const securitiesCreate = tools.find((tool) => tool.name === "portfolixir.securities.create");
    assert.equal(
      securitiesCreate?.inputSchema.properties.security.properties.asset_class.type,
      "string"
    );
    assert.doesNotThrow(() =>
      securitiesCreate?.zodSchema.parse({
        security: {
          name: "Synthetic Government Bond",
          currency_code: "EUR",
          asset_class: "government_bond"
        }
      })
    );
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
      direction: "asc",
      holding_status: "held"
    });

    assert.equal(requests[0].method, "GET");
    assert.equal(
      requests[0].path,
      "/api/v1/securities?query=syn&sort=name&direction=asc&holding_status=held"
    );
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

  it("issues a GET to /valuation for portfolixir.portfolios.valuation", async () => {
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
              portfolio_id: 3,
              total_value: "2000",
              unvalued_count: 0,
              positions: [{ security_id: 9, market_value: "1000", weight: "0.5", valued: true }]
            }
          }),
          { status: 200, headers: { "content-type": "application/json" } }
        );
      }
    });

    const result = await callTool(client, "portfolixir.portfolios.valuation", { portfolio_id: 3 });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/portfolios/3/valuation");
    assert.equal(requests[0].token, "Bearer api-token");
    assert.match(result.content[0].text, /0\.5/);
  });

  it("issues a POST to /exchange_rates/sync for portfolixir.exchange_rates.sync", async () => {
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

        return new Response(
          JSON.stringify({ data: { provider: "ecb", status: "ok", upserted: 25 } }),
          { status: 200, headers: { "content-type": "application/json" } }
        );
      }
    });

    const result = await callTool(client, "portfolixir.exchange_rates.sync", {});

    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].path, "/api/v1/exchange_rates/sync");
    assert.deepEqual(requests[0].body, {});
    assert.match(result.content[0].text, /ecb/);
  });

  it("routes classification assignment to PUT /assignments with the body", async () => {
    const requests: Array<{ method: string; path: string; body?: unknown }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({
          method: init?.method ?? "GET",
          path: `${parsed.pathname}${parsed.search}`,
          body: init?.body ? JSON.parse(String(init.body)) : undefined
        });

        return new Response(
          JSON.stringify({ data: { security_id: 7, classification_id: 3, category_id: 9 } }),
          { status: 200, headers: { "content-type": "application/json" } }
        );
      }
    });

    const result = await callTool(client, "portfolixir.classifications.assign", {
      classification_id: 3,
      security_id: 7,
      category_id: 9
    });

    assert.equal(requests[0].method, "PUT");
    assert.equal(requests[0].path, "/api/v1/classifications/3/assignments");
    assert.deepEqual(requests[0].body, { security_id: 7, category_id: 9 });
    assert.match(result.content[0].text, /category_id/);
  });

  it("passes richer quote sync status responses through unchanged", async () => {
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

        return new Response(
          JSON.stringify({ data: { status: "skipped", reason: "missing_ticker" } }),
          { status: 200, headers: { "content-type": "application/json" } }
        );
      }
    });

    const result = await callTool(client, "portfolixir.quotes.sync", { security_id: 42 });

    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].path, "/api/v1/securities/42/sync_quotes");
    assert.deepEqual(requests[0].body, {});
    assert.deepEqual(result.structuredContent, {
      data: { status: "skipped", reason: "missing_ticker" }
    });
    assert.match(result.content[0].text, /missing_ticker/);
  });

  it("pages securities.list via limit/offset query params", async () => {
    const requests: Array<{ method: string; path: string }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({ method: init?.method ?? "GET", path: `${parsed.pathname}${parsed.search}` });
        return new Response(JSON.stringify({ data: [] }), {
          status: 200,
          headers: { "content-type": "application/json" }
        });
      }
    });

    await callTool(client, "portfolixir.securities.list", { query: "etf", limit: 50, offset: 100 });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/securities?query=etf&limit=50&offset=100");
  });

  it("routes category update to PATCH /categories/:id with the body", async () => {
    const requests: Array<{ method: string; path: string; body?: unknown }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({
          method: init?.method ?? "GET",
          path: `${parsed.pathname}${parsed.search}`,
          body: init?.body ? JSON.parse(String(init.body)) : undefined
        });
        return new Response(JSON.stringify({ data: { id: 5 } }), {
          status: 200,
          headers: { "content-type": "application/json" }
        });
      }
    });

    await callTool(client, "portfolixir.classifications.categories.update", {
      classification_id: 3,
      id: 5,
      category: { description: "Core equity", color: "#2563eb" }
    });

    assert.equal(requests[0].method, "PATCH");
    assert.equal(requests[0].path, "/api/v1/classifications/3/categories/5");
    assert.deepEqual(requests[0].body, { category: { description: "Core equity", color: "#2563eb" } });
  });

  it("routes classification delete to DELETE /classifications/:id", async () => {
    const requests: Array<{ method: string; path: string }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({ method: init?.method ?? "GET", path: `${parsed.pathname}${parsed.search}` });
        return new Response(JSON.stringify({ data: { deleted: true } }), {
          status: 200,
          headers: { "content-type": "application/json" }
        });
      }
    });

    await callTool(client, "portfolixir.classifications.delete", { id: 4 });

    assert.equal(requests[0].method, "DELETE");
    assert.equal(requests[0].path, "/api/v1/classifications/4");
  });

  it("routes bulk assign to PUT /assignments/bulk with the body", async () => {
    const requests: Array<{ method: string; path: string; body?: unknown }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({
          method: init?.method ?? "GET",
          path: `${parsed.pathname}${parsed.search}`,
          body: init?.body ? JSON.parse(String(init.body)) : undefined
        });
        return new Response(JSON.stringify({ data: { assigned: 3 } }), {
          status: 200,
          headers: { "content-type": "application/json" }
        });
      }
    });

    await callTool(client, "portfolixir.classifications.assign_bulk", {
      classification_id: 3,
      category_id: 9,
      security_ids: [1, 2, 7]
    });

    assert.equal(requests[0].method, "PUT");
    assert.equal(requests[0].path, "/api/v1/classifications/3/assignments/bulk");
    assert.deepEqual(requests[0].body, { category_id: 9, security_ids: [1, 2, 7] });
  });

  it("routes update/delete tools to PATCH/DELETE on the right paths", async () => {
    const requests: Array<{ method: string; path: string; body?: unknown }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({
          method: init?.method ?? "GET",
          path: `${parsed.pathname}${parsed.search}`,
          body: init?.body ? JSON.parse(String(init.body)) : undefined
        });
        return new Response(JSON.stringify({ data: { id: 1 } }), {
          status: 200,
          headers: { "content-type": "application/json" }
        });
      }
    });

    await callTool(client, "portfolixir.transactions.update", {
      id: 7,
      transaction: { notes: "corrected" }
    });
    await callTool(client, "portfolixir.transactions.delete", { id: 7 });
    await callTool(client, "portfolixir.cash_accounts.update", {
      id: 3,
      cash_account: { name: "Renamed" }
    });
    await callTool(client, "portfolixir.securities_accounts.delete", { id: 4 });
    await callTool(client, "portfolixir.securities.update", { id: 9, security: { note: "x" } });

    assert.deepEqual(requests[0], {
      method: "PATCH",
      path: "/api/v1/transactions/7",
      body: { transaction: { notes: "corrected" } }
    });
    assert.deepEqual(requests[1], { method: "DELETE", path: "/api/v1/transactions/7", body: undefined });
    assert.deepEqual(requests[2], {
      method: "PATCH",
      path: "/api/v1/cash_accounts/3",
      body: { cash_account: { name: "Renamed" } }
    });
    assert.deepEqual(requests[3], {
      method: "DELETE",
      path: "/api/v1/securities_accounts/4",
      body: undefined
    });
    assert.equal(requests[4].method, "PATCH");
    assert.equal(requests[4].path, "/api/v1/securities/9");
  });

  it("passes list filters through as query params", async () => {
    const requests: Array<{ method: string; path: string }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({ method: init?.method ?? "GET", path: `${parsed.pathname}${parsed.search}` });
        return new Response(JSON.stringify({ data: [] }), {
          status: 200,
          headers: { "content-type": "application/json" }
        });
      }
    });

    await callTool(client, "portfolixir.transactions.list", {
      from: "2026-01-01",
      to: "2026-03-31",
      portfolio_id: 3,
      securities_account_id: 7
    });
    await callTool(client, "portfolixir.holdings.list", { portfolio_id: 3, security_id: 9 });
    await callTool(client, "portfolixir.trades.list", { security_id: 9, from: "2026-01-01" });

    assert.equal(
      requests[0].path,
      "/api/v1/transactions?from=2026-01-01&to=2026-03-31&portfolio_id=3&securities_account_id=7"
    );
    assert.equal(requests[1].path, "/api/v1/portfolios/3/holdings?security_id=9");
    assert.equal(requests[2].path, "/api/v1/securities/9/trades?from=2026-01-01");
  });

  it("routes target weight tools to the portfolio targets endpoints", async () => {
    const requests: Array<{ method: string; path: string; body?: unknown }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({
          method: init?.method ?? "GET",
          path: `${parsed.pathname}${parsed.search}`,
          body: init?.body ? JSON.parse(String(init.body)) : undefined
        });
        return new Response(JSON.stringify({ data: { targets: [] } }), {
          status: 200,
          headers: { "content-type": "application/json" }
        });
      }
    });

    await callTool(client, "portfolixir.targets.list", { portfolio_id: 3, classification_id: 5 });
    await callTool(client, "portfolixir.targets.set", {
      portfolio_id: 3,
      classification_id: 5,
      targets: [{ category_id: 9, target_weight: "0.25" }]
    });
    await callTool(client, "portfolixir.targets.delete", { portfolio_id: 3, category_id: 9 });

    assert.deepEqual(requests[0], {
      method: "GET",
      path: "/api/v1/portfolios/3/targets?classification_id=5",
      body: undefined
    });
    assert.deepEqual(requests[1], {
      method: "PUT",
      path: "/api/v1/portfolios/3/targets",
      body: { classification_id: 5, targets: [{ category_id: 9, target_weight: "0.25" }] }
    });
    assert.deepEqual(requests[2], {
      method: "DELETE",
      path: "/api/v1/portfolios/3/targets/9",
      body: undefined
    });
  });

  it("issues a GET to /allocation for portfolixir.portfolios.allocation", async () => {
    const requests: Array<{ method: string; path: string }> = [];
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async (url, init) => {
        const parsed = new URL(url);
        requests.push({ method: init?.method ?? "GET", path: `${parsed.pathname}${parsed.search}` });
        return new Response(
          JSON.stringify({
            data: {
              portfolio_id: 3,
              classification_id: 5,
              categories: [
                { category_id: 9, actual_weight: "0.4", target_weight: "0.25", drift_weight: "-0.15" }
              ]
            }
          }),
          { status: 200, headers: { "content-type": "application/json" } }
        );
      }
    });

    const result = await callTool(client, "portfolixir.portfolios.allocation", {
      portfolio_id: 3,
      classification_id: 5
    });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/portfolios/3/allocation?classification_id=5");
    assert.match(result.content[0].text, /-0\.15/);
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
