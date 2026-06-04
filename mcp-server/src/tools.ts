import type { ApiClient } from "./api-client.js";
import { z, type ZodTypeAny } from "zod";

type JsonSchema = Record<string, any>;

export interface ToolDefinition {
  name: string;
  title: string;
  description: string;
  inputSchema: JsonSchema;
  zodSchema: ZodTypeAny;
}

export interface ToolResult {
  content: Array<{ type: "text"; text: string }>;
  structuredContent: unknown;
}

const emptyObjectSchema = {
  type: "object",
  additionalProperties: false,
  properties: {}
};

const emptyObjectZ = z.object({});
const idZ = z.object({ id: z.number().int().positive() });
const optionalString = z.string().optional();

const securityZ = z.object({
  security: z.object({
    name: z.string(),
    ticker_symbol: optionalString,
    isin: optionalString,
    wkn: optionalString,
    currency_code: z.string(),
    exchange_code: optionalString,
    asset_class: optionalString,
    note: optionalString,
    feed: optionalString,
    feed_url: optionalString,
    provider: optionalString,
    online_id: optionalString,
    attributes: z.record(z.unknown()).optional()
  })
});

const quoteUpsertZ = z.object({
  security_id: z.number().int().positive(),
  quotes: z.array(
    z.object({
      date: z.string(),
      close: z.string(),
      source: z.string()
    })
  )
});

const portfolioZ = z.object({
  portfolio: z.object({
    name: z.string(),
    base_currency_code: z.string(),
    notes: optionalString
  })
});

const cashAccountZ = z.object({
  cash_account: z.object({
    portfolio_id: z.number().int().positive(),
    name: z.string(),
    currency_code: z.string(),
    notes: optionalString
  })
});

const securitiesAccountZ = z.object({
  securities_account: z.object({
    portfolio_id: z.number().int().positive(),
    cash_account_id: z.number().int().positive(),
    name: z.string(),
    notes: optionalString
  })
});

const transactionZ = z.object({
  transaction: z.object({
    portfolio_id: z.number().int().positive(),
    securities_account_id: z.number().int().positive(),
    security_id: z.number().int().positive(),
    type: z.enum(["buy", "sell"]),
    date: z.string(),
    quantity: z.string(),
    price: z.string(),
    fees: optionalString,
    taxes: optionalString,
    currency_code: z.string(),
    notes: optionalString
  })
});

const idSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id"],
  properties: { id: { type: "integer", minimum: 1 } }
};

const securitySchema = objectWith("security", {
  type: "object",
  required: ["name", "currency_code"],
  properties: {
    name: { type: "string" },
    ticker_symbol: { type: "string" },
    isin: { type: "string" },
    wkn: { type: "string" },
    currency_code: { type: "string" },
    exchange_code: { type: "string" },
    asset_class: { type: "string" },
    note: { type: "string" },
    feed: { type: "string" },
    feed_url: { type: "string" },
    provider: { type: "string" },
    online_id: { type: "string" },
    attributes: { type: "object", additionalProperties: true }
  }
});

const quoteUpsertSchema = {
  type: "object",
  additionalProperties: false,
  required: ["security_id", "quotes"],
  properties: {
    security_id: { type: "integer", minimum: 1 },
    quotes: {
      type: "array",
      items: {
        type: "object",
        required: ["date", "close", "source"],
        properties: {
          date: { type: "string", format: "date" },
          close: { type: "string" },
          source: { type: "string" }
        },
        additionalProperties: false
      }
    }
  }
};

const portfolioSchema = objectWith("portfolio", {
  type: "object",
  required: ["name", "base_currency_code"],
  properties: {
    name: { type: "string" },
    base_currency_code: { type: "string" },
    notes: { type: "string" }
  }
});

const cashAccountSchema = objectWith("cash_account", {
  type: "object",
  required: ["portfolio_id", "name", "currency_code"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    name: { type: "string" },
    currency_code: { type: "string" },
    notes: { type: "string" }
  }
});

const securitiesAccountSchema = objectWith("securities_account", {
  type: "object",
  required: ["portfolio_id", "cash_account_id", "name"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    cash_account_id: { type: "integer", minimum: 1 },
    name: { type: "string" },
    notes: { type: "string" }
  }
});

const transactionSchema = objectWith("transaction", {
  type: "object",
  required: [
    "portfolio_id",
    "securities_account_id",
    "security_id",
    "type",
    "date",
    "quantity",
    "price",
    "currency_code"
  ],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    securities_account_id: { type: "integer", minimum: 1 },
    security_id: { type: "integer", minimum: 1 },
    type: { type: "string", enum: ["buy", "sell"] },
    date: { type: "string", format: "date" },
    quantity: { type: "string" },
    price: { type: "string" },
    fees: { type: "string" },
    taxes: { type: "string" },
    currency_code: { type: "string" },
    notes: { type: "string" }
  }
});

const toolDefinitions: ToolDefinition[] = [
  tool("portfolixir.securities.list", "List securities", "List local securities.", {
    type: "object",
    additionalProperties: false,
    properties: {
      query: { type: "string" },
      sort: { type: "string" },
      direction: { type: "string", enum: ["asc", "desc"] },
      holding_status: { type: "string", enum: ["held", "not_held", "all"] }
    }
  }, z.object({
    query: optionalString,
    sort: optionalString,
    direction: z.enum(["asc", "desc"]).optional(),
    holding_status: z.enum(["held", "not_held", "all"]).optional()
  })),
  tool("portfolixir.securities.create", "Create security", "Create a local security.", securitySchema, securityZ),
  tool("portfolixir.securities.search_online", "Search online securities", "Search configured online security providers.", {
    type: "object",
    additionalProperties: false,
    required: ["query"],
    properties: {
      query: { type: "string" },
      type: { type: "string", enum: ["security", "crypto"] }
    }
  }, z.object({ query: z.string(), type: z.enum(["security", "crypto"]).optional() })),
  tool("portfolixir.quotes.sync", "Sync quotes", "Sync quote history for one security.", {
    type: "object",
    additionalProperties: false,
    required: ["security_id"],
    properties: { security_id: { type: "integer", minimum: 1 } }
  }, z.object({ security_id: z.number().int().positive() })),
  tool("portfolixir.quotes.list", "List quotes", "List quote history for one security.", {
    type: "object",
    additionalProperties: false,
    required: ["security_id"],
    properties: {
      security_id: { type: "integer", minimum: 1 },
      from: { type: "string", format: "date" },
      to: { type: "string", format: "date" }
    }
  }, z.object({ security_id: z.number().int().positive(), from: optionalString, to: optionalString })),
  tool("portfolixir.quotes.upsert", "Upsert quotes", "Upsert manual quote history.", quoteUpsertSchema, quoteUpsertZ),
  tool("portfolixir.portfolios.list", "List portfolios", "List local portfolios.", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.portfolios.create", "Create portfolio", "Create a portfolio.", portfolioSchema, portfolioZ),
  tool("portfolixir.cash_accounts.list", "List cash accounts", "List cash accounts.", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.cash_accounts.create", "Create cash account", "Create a cash account.", cashAccountSchema, cashAccountZ),
  tool(
    "portfolixir.securities_accounts.list",
    "List securities accounts",
    "List depot/securities accounts.",
    emptyObjectSchema,
    emptyObjectZ
  ),
  tool(
    "portfolixir.securities_accounts.create",
    "Create securities account",
    "Create a depot/securities account linked to a cash account.",
    securitiesAccountSchema,
    securitiesAccountZ
  ),
  tool("portfolixir.transactions.list", "List transactions", "List manual transactions.", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.transactions.create", "Create transaction", "Create a manual buy or sell transaction.", transactionSchema, transactionZ),
  tool("portfolixir.holdings.list", "List holdings", "List derived holdings for a portfolio.", {
    type: "object",
    additionalProperties: false,
    required: ["portfolio_id"],
    properties: { portfolio_id: { type: "integer", minimum: 1 } }
  }, z.object({ portfolio_id: z.number().int().positive() })),
  tool("portfolixir.portfolios.valuation", "Value portfolio", "Live valuation of a portfolio: market values, total, and actual weights per position.", {
    type: "object",
    additionalProperties: false,
    required: ["portfolio_id"],
    properties: { portfolio_id: { type: "integer", minimum: 1 } }
  }, z.object({ portfolio_id: z.number().int().positive() })),
  tool(
    "portfolixir.trades.list",
    "List trades",
    "List FIFO-matched trades for a security: open lots, closed round-trips and orphan sells.",
    {
      type: "object",
      additionalProperties: false,
      required: ["security_id"],
      properties: { security_id: { type: "integer", minimum: 1 } }
    },
    z.object({ security_id: z.number().int().positive() })
  )
];

export function listTools(): ToolDefinition[] {
  return toolDefinitions;
}

export async function callTool(
  client: ApiClient,
  name: string,
  args: Record<string, any>
): Promise<ToolResult> {
  const payload = await apiCall(client, name, args ?? {});

  return {
    content: [{ type: "text", text: JSON.stringify(payload, null, 2) }],
    structuredContent: payload
  };
}

async function apiCall(client: ApiClient, name: string, args: Record<string, any>): Promise<unknown> {
  switch (name) {
    case "portfolixir.securities.list":
      return client.request(
        "GET",
        withQuery("/api/v1/securities", args, ["query", "sort", "direction", "holding_status"])
      );
    case "portfolixir.securities.create":
      return client.request("POST", "/api/v1/securities", { security: args.security });
    case "portfolixir.securities.search_online":
      return client.request(
        "GET",
        withQuery("/api/v1/securities/search", args, ["query", "type"])
      );
    case "portfolixir.quotes.sync":
      return client.request("POST", `/api/v1/securities/${args.security_id}/sync_quotes`, {});
    case "portfolixir.quotes.list":
      return client.request(
        "GET",
        withQuery(`/api/v1/securities/${args.security_id}/quotes`, args, ["from", "to"])
      );
    case "portfolixir.quotes.upsert":
      return client.request("PUT", `/api/v1/securities/${args.security_id}/quotes`, {
        quotes: args.quotes
      });
    case "portfolixir.portfolios.list":
      return client.request("GET", "/api/v1/portfolios");
    case "portfolixir.portfolios.create":
      return client.request("POST", "/api/v1/portfolios", { portfolio: args.portfolio });
    case "portfolixir.cash_accounts.list":
      return client.request("GET", "/api/v1/cash_accounts");
    case "portfolixir.cash_accounts.create":
      return client.request("POST", "/api/v1/cash_accounts", { cash_account: args.cash_account });
    case "portfolixir.securities_accounts.list":
      return client.request("GET", "/api/v1/securities_accounts");
    case "portfolixir.securities_accounts.create":
      return client.request("POST", "/api/v1/securities_accounts", {
        securities_account: args.securities_account
      });
    case "portfolixir.transactions.list":
      return client.request("GET", "/api/v1/transactions");
    case "portfolixir.transactions.create":
      return client.request("POST", "/api/v1/transactions", { transaction: args.transaction });
    case "portfolixir.holdings.list":
      return client.request("GET", `/api/v1/portfolios/${args.portfolio_id}/holdings`);
    case "portfolixir.portfolios.valuation":
      return client.request("GET", `/api/v1/portfolios/${args.portfolio_id}/valuation`);
    case "portfolixir.trades.list":
      return client.request("GET", `/api/v1/securities/${args.security_id}/trades`);
    default:
      throw new Error(`Unknown Portfolixir MCP tool: ${name}`);
  }
}

function tool(
  name: string,
  title: string,
  description: string,
  inputSchema: JsonSchema,
  zodSchema: ZodTypeAny
): ToolDefinition {
  return { name, title, description, inputSchema, zodSchema };
}

function objectWith(property: string, schema: JsonSchema): JsonSchema {
  return {
    type: "object",
    additionalProperties: false,
    required: [property],
    properties: { [property]: schema }
  };
}

function withQuery(path: string, args: Record<string, any>, keys: string[]): string {
  const params = new URLSearchParams();

  for (const key of keys) {
    const value = args[key];
    if (value !== undefined && value !== null && value !== "") {
      params.set(key, String(value));
    }
  }

  const query = params.toString();
  return query === "" ? path : `${path}?${query}`;
}
