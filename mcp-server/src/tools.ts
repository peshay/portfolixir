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
// A factory (not a shared instance): reusing one Zod instance across fields
// makes the generated JSON schema dedupe the repeats into a `$ref`, which some
// MCP clients mis-render. A fresh instance per field keeps each property inline.
const optionalString = () => z.string().optional();

const securityZ = z.object({
  security: z.object({
    name: z.string(),
    ticker_symbol: optionalString(),
    isin: optionalString(),
    wkn: optionalString(),
    currency_code: z.string(),
    exchange_code: optionalString(),
    asset_class: optionalString(),
    note: optionalString(),
    feed: optionalString(),
    feed_url: optionalString(),
    provider: optionalString(),
    online_id: optionalString(),
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
    notes: optionalString()
  })
});

const cashAccountZ = z.object({
  cash_account: z.object({
    portfolio_id: z.number().int().positive(),
    name: z.string(),
    currency_code: z.string(),
    notes: optionalString()
  })
});

const securitiesAccountZ = z.object({
  securities_account: z.object({
    portfolio_id: z.number().int().positive(),
    cash_account_id: z.number().int().positive(),
    name: z.string(),
    notes: optionalString()
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
    fees: optionalString(),
    taxes: optionalString(),
    currency_code: z.string(),
    notes: optionalString()
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

const classificationSchema = objectWith("classification", {
  type: "object",
  required: ["name"],
  properties: {
    name: { type: "string" },
    position: { type: "integer" },
    description: { type: "string" }
  }
});

const classificationZ = z.object({
  classification: z.object({
    name: z.string(),
    position: z.number().int().optional(),
    description: optionalString()
  })
});

const categorySchema = {
  type: "object",
  additionalProperties: false,
  required: ["classification_id", "category"],
  properties: {
    classification_id: { type: "integer", minimum: 1 },
    category: {
      type: "object",
      required: ["name"],
      properties: {
        name: { type: "string" },
        color: { type: "string" },
        description: { type: "string" },
        parent_id: { type: "integer", minimum: 1 },
        position: { type: "integer" }
      }
    }
  }
};

const categoryZ = z.object({
  classification_id: z.number().int().positive(),
  category: z.object({
    name: z.string(),
    color: optionalString(),
    description: optionalString(),
    parent_id: z.number().int().positive().optional(),
    position: z.number().int().optional()
  })
});

const assignSchema = {
  type: "object",
  additionalProperties: false,
  required: ["classification_id", "security_id", "category_id"],
  properties: {
    classification_id: { type: "integer", minimum: 1 },
    security_id: { type: "integer", minimum: 1 },
    category_id: { type: "integer", minimum: 1 }
  }
};

const assignZ = z.object({
  classification_id: z.number().int().positive(),
  security_id: z.number().int().positive(),
  category_id: z.number().int().positive()
});

const unassignSchema = {
  type: "object",
  additionalProperties: false,
  required: ["classification_id", "security_id"],
  properties: {
    classification_id: { type: "integer", minimum: 1 },
    security_id: { type: "integer", minimum: 1 }
  }
};

const unassignZ = z.object({
  classification_id: z.number().int().positive(),
  security_id: z.number().int().positive()
});

const classificationUpdateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id", "classification"],
  properties: {
    id: { type: "integer", minimum: 1 },
    classification: {
      type: "object",
      properties: {
        name: { type: "string" },
        position: { type: "integer" },
        description: { type: "string" }
      }
    }
  }
};

const classificationUpdateZ = z.object({
  id: z.number().int().positive(),
  classification: z.object({
    name: optionalString(),
    position: z.number().int().optional(),
    description: optionalString()
  })
});

const categoryUpdateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["classification_id", "id", "category"],
  properties: {
    classification_id: { type: "integer", minimum: 1 },
    id: { type: "integer", minimum: 1 },
    category: {
      type: "object",
      properties: {
        name: { type: "string" },
        color: { type: "string" },
        description: { type: "string" },
        parent_id: { type: "integer", minimum: 1 },
        position: { type: "integer" }
      }
    }
  }
};

const categoryUpdateZ = z.object({
  classification_id: z.number().int().positive(),
  id: z.number().int().positive(),
  category: z.object({
    name: optionalString(),
    color: optionalString(),
    description: optionalString(),
    parent_id: z.number().int().positive().optional(),
    position: z.number().int().optional()
  })
});

const categoryDeleteSchema = {
  type: "object",
  additionalProperties: false,
  required: ["classification_id", "id"],
  properties: {
    classification_id: { type: "integer", minimum: 1 },
    id: { type: "integer", minimum: 1 }
  }
};

const categoryDeleteZ = z.object({
  classification_id: z.number().int().positive(),
  id: z.number().int().positive()
});

const assignBulkSchema = {
  type: "object",
  additionalProperties: false,
  required: ["classification_id", "category_id", "security_ids"],
  properties: {
    classification_id: { type: "integer", minimum: 1 },
    category_id: { type: "integer", minimum: 1 },
    security_ids: { type: "array", items: { type: "integer", minimum: 1 }, minItems: 1 }
  }
};

const assignBulkZ = z.object({
  classification_id: z.number().int().positive(),
  category_id: z.number().int().positive(),
  security_ids: z.array(z.number().int().positive()).min(1)
});

const securityUpdateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id", "security"],
  properties: {
    id: { type: "integer", minimum: 1 },
    security: {
      type: "object",
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
    }
  }
};

const securityUpdateZ = z.object({
  id: z.number().int().positive(),
  security: z.object({
    name: optionalString(),
    ticker_symbol: optionalString(),
    isin: optionalString(),
    wkn: optionalString(),
    currency_code: optionalString(),
    exchange_code: optionalString(),
    asset_class: optionalString(),
    note: optionalString(),
    feed: optionalString(),
    feed_url: optionalString(),
    provider: optionalString(),
    online_id: optionalString(),
    attributes: z.record(z.unknown()).optional()
  })
});

const transactionUpdateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id", "transaction"],
  properties: {
    id: { type: "integer", minimum: 1 },
    transaction: {
      type: "object",
      properties: {
        portfolio_id: { type: "integer", minimum: 1 },
        securities_account_id: { type: "integer", minimum: 1 },
        cash_account_id: { type: "integer", minimum: 1 },
        counter_cash_account_id: { type: "integer", minimum: 1 },
        counter_securities_account_id: { type: "integer", minimum: 1 },
        security_id: { type: "integer", minimum: 1 },
        type: {
          type: "string",
          enum: [
            "buy",
            "sell",
            "dividend",
            "interest",
            "deposit",
            "removal",
            "fee",
            "tax",
            "tax_refund",
            "cash_transfer",
            "inbound_delivery",
            "outbound_delivery",
            "security_transfer"
          ]
        },
        date: { type: "string", format: "date" },
        quantity: { type: "string" },
        price: { type: "string" },
        gross_amount: { type: "string" },
        fees: { type: "string" },
        taxes: { type: "string" },
        currency_code: { type: "string" },
        notes: { type: "string" }
      }
    }
  }
};

const transactionUpdateZ = z.object({
  id: z.number().int().positive(),
  transaction: z.object({
    portfolio_id: z.number().int().positive().optional(),
    securities_account_id: z.number().int().positive().optional(),
    cash_account_id: z.number().int().positive().optional(),
    counter_cash_account_id: z.number().int().positive().optional(),
    counter_securities_account_id: z.number().int().positive().optional(),
    security_id: z.number().int().positive().optional(),
    type: z
      .enum([
        "buy",
        "sell",
        "dividend",
        "interest",
        "deposit",
        "removal",
        "fee",
        "tax",
        "tax_refund",
        "cash_transfer",
        "inbound_delivery",
        "outbound_delivery",
        "security_transfer"
      ])
      .optional(),
    date: optionalString(),
    quantity: optionalString(),
    price: optionalString(),
    gross_amount: optionalString(),
    fees: optionalString(),
    taxes: optionalString(),
    currency_code: optionalString(),
    notes: optionalString()
  })
});

const cashAccountUpdateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id", "cash_account"],
  properties: {
    id: { type: "integer", minimum: 1 },
    cash_account: {
      type: "object",
      properties: {
        name: { type: "string" },
        currency_code: { type: "string" },
        notes: { type: "string" }
      }
    }
  }
};

const cashAccountUpdateZ = z.object({
  id: z.number().int().positive(),
  cash_account: z.object({
    name: optionalString(),
    currency_code: optionalString(),
    notes: optionalString()
  })
});

const securitiesAccountUpdateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id", "securities_account"],
  properties: {
    id: { type: "integer", minimum: 1 },
    securities_account: {
      type: "object",
      properties: {
        cash_account_id: { type: "integer", minimum: 1 },
        name: { type: "string" },
        notes: { type: "string" }
      }
    }
  }
};

const securitiesAccountUpdateZ = z.object({
  id: z.number().int().positive(),
  securities_account: z.object({
    cash_account_id: z.number().int().positive().optional(),
    name: optionalString(),
    notes: optionalString()
  })
});

const targetsListSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    classification_id: { type: "integer", minimum: 1 }
  }
};

const targetsListZ = z.object({
  portfolio_id: z.number().int().positive(),
  classification_id: z.number().int().positive().optional()
});

const targetsSetSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id", "classification_id", "targets"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    classification_id: { type: "integer", minimum: 1 },
    targets: {
      type: "array",
      items: {
        type: "object",
        required: ["category_id", "target_weight"],
        properties: {
          category_id: { type: "integer", minimum: 1 },
          target_weight: { type: "string" }
        },
        additionalProperties: false
      }
    }
  }
};

const targetsSetZ = z.object({
  portfolio_id: z.number().int().positive(),
  classification_id: z.number().int().positive(),
  targets: z
    .array(
      z.object({
        category_id: z.number().int().positive(),
        target_weight: z.string()
      })
    )
    .min(1)
});

const targetsDeleteSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id", "category_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    category_id: { type: "integer", minimum: 1 }
  }
};

const targetsDeleteZ = z.object({
  portfolio_id: z.number().int().positive(),
  category_id: z.number().int().positive()
});

const allocationSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id", "classification_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    classification_id: { type: "integer", minimum: 1 }
  }
};

const allocationZ = z.object({
  portfolio_id: z.number().int().positive(),
  classification_id: z.number().int().positive()
});

const toolDefinitions: ToolDefinition[] = [
  tool("portfolixir.securities.list", "List securities", "List local securities. Use limit/offset to page large catalogs and keep responses small.", {
    type: "object",
    additionalProperties: false,
    properties: {
      query: { type: "string" },
      sort: { type: "string" },
      direction: { type: "string", enum: ["asc", "desc"] },
      holding_status: { type: "string", enum: ["held", "not_held", "all"] },
      limit: { type: "integer", minimum: 0 },
      offset: { type: "integer", minimum: 0 }
    }
  }, z.object({
    query: optionalString(),
    sort: optionalString(),
    direction: z.enum(["asc", "desc"]).optional(),
    holding_status: z.enum(["held", "not_held", "all"]).optional(),
    limit: z.number().int().min(0).optional(),
    offset: z.number().int().min(0).optional()
  })),
  tool("portfolixir.securities.create", "Create security", "Create a local security.", securitySchema, securityZ),
  tool("portfolixir.securities.update", "Update security", "Patch a local security's master data.", securityUpdateSchema, securityUpdateZ),
  tool("portfolixir.securities.delete", "Delete security", "Delete a local security when no transactions or quotes reference it.", idSchema, idZ),
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
  }, z.object({ security_id: z.number().int().positive(), from: optionalString(), to: optionalString() })),
  tool("portfolixir.quotes.upsert", "Upsert quotes", "Upsert manual quote history.", quoteUpsertSchema, quoteUpsertZ),
  tool("portfolixir.portfolios.list", "List portfolios", "List local portfolios.", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.portfolios.create", "Create portfolio", "Create a portfolio.", portfolioSchema, portfolioZ),
  tool("portfolixir.cash_accounts.list", "List cash accounts", "List cash accounts with their current balance.", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.cash_accounts.create", "Create cash account", "Create a cash account.", cashAccountSchema, cashAccountZ),
  tool("portfolixir.cash_accounts.update", "Update cash account", "Patch a cash account's name, currency or notes.", cashAccountUpdateSchema, cashAccountUpdateZ),
  tool("portfolixir.cash_accounts.delete", "Delete cash account", "Delete a cash account when no transactions or depots reference it.", idSchema, idZ),
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
  tool(
    "portfolixir.securities_accounts.update",
    "Update securities account",
    "Patch a depot/securities account's name, notes or linked cash account.",
    securitiesAccountUpdateSchema,
    securitiesAccountUpdateZ
  ),
  tool(
    "portfolixir.securities_accounts.delete",
    "Delete securities account",
    "Delete a depot/securities account when no transactions reference it.",
    idSchema,
    idZ
  ),
  tool("portfolixir.transactions.list", "List transactions", "List transactions. Optional filters: from/to (ISO dates), portfolio_id, security_id, securities_account_id.", {
    type: "object",
    additionalProperties: false,
    properties: {
      from: { type: "string", format: "date" },
      to: { type: "string", format: "date" },
      portfolio_id: { type: "integer", minimum: 1 },
      security_id: { type: "integer", minimum: 1 },
      securities_account_id: { type: "integer", minimum: 1 }
    }
  }, z.object({
    from: optionalString(),
    to: optionalString(),
    portfolio_id: z.number().int().positive().optional(),
    security_id: z.number().int().positive().optional(),
    securities_account_id: z.number().int().positive().optional()
  })),
  tool("portfolixir.transactions.create", "Create transaction", "Create a manual buy or sell transaction.", transactionSchema, transactionZ),
  tool("portfolixir.transactions.update", "Update transaction", "Patch a transaction (e.g. fix a mis-imported booking).", transactionUpdateSchema, transactionUpdateZ),
  tool("portfolixir.transactions.delete", "Delete transaction", "Delete a transaction.", idSchema, idZ),
  tool("portfolixir.holdings.list", "List holdings", "List derived holdings for a portfolio, each with moving-average cost basis, latest price, market value and unrealized P&L (in the security's currency). Optional filters: security_id, securities_account_id.", {
    type: "object",
    additionalProperties: false,
    required: ["portfolio_id"],
    properties: {
      portfolio_id: { type: "integer", minimum: 1 },
      security_id: { type: "integer", minimum: 1 },
      securities_account_id: { type: "integer", minimum: 1 }
    }
  }, z.object({
    portfolio_id: z.number().int().positive(),
    security_id: z.number().int().positive().optional(),
    securities_account_id: z.number().int().positive().optional()
  })),
  tool("portfolixir.portfolios.valuation", "Value portfolio", "Live valuation of a portfolio: market values, total, and actual weights per position.", {
    type: "object",
    additionalProperties: false,
    required: ["portfolio_id"],
    properties: { portfolio_id: { type: "integer", minimum: 1 } }
  }, z.object({ portfolio_id: z.number().int().positive() })),
  tool("portfolixir.exchange_rates.list", "List exchange rates", "List stored EUR-hub exchange rates.", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.exchange_rates.sync", "Sync exchange rates", "Fetch and store the latest exchange rates from the configured provider.", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.classifications.list", "List classifications", "List classification trees with categories and security assignments.", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.classifications.create", "Create classification", "Create a custom classification tree.", classificationSchema, classificationZ),
  tool("portfolixir.classifications.categories.create", "Create category", "Create a category in a custom classification.", categorySchema, categoryZ),
  tool("portfolixir.classifications.update", "Update classification", "Update a custom classification's name, description or position.", classificationUpdateSchema, classificationUpdateZ),
  tool("portfolixir.classifications.delete", "Delete classification", "Delete a custom classification and all its categories.", idSchema, idZ),
  tool("portfolixir.classifications.categories.update", "Update category", "Patch a category's name, color, description, position or parent_id.", categoryUpdateSchema, categoryUpdateZ),
  tool("portfolixir.classifications.categories.delete", "Delete category", "Delete a category from a custom classification.", categoryDeleteSchema, categoryDeleteZ),
  tool("portfolixir.classifications.assign", "Assign security", "Assign a security to a category of a custom classification.", assignSchema, assignZ),
  tool("portfolixir.classifications.assign_bulk", "Assign securities (bulk)", "Assign many securities to one category in a single call.", assignBulkSchema, assignBulkZ),
  tool("portfolixir.classifications.unassign", "Unassign security", "Remove a security's assignment from a classification.", unassignSchema, unassignZ),
  tool(
    "portfolixir.trades.list",
    "List trades",
    "List FIFO-matched trades for a security: open lots, closed round-trips and orphan sells. Optional from/to (ISO dates) filter each leg by its own date.",
    {
      type: "object",
      additionalProperties: false,
      required: ["security_id"],
      properties: {
        security_id: { type: "integer", minimum: 1 },
        from: { type: "string", format: "date" },
        to: { type: "string", format: "date" }
      }
    },
    z.object({
      security_id: z.number().int().positive(),
      from: optionalString(),
      to: optionalString()
    })
  ),
  tool(
    "portfolixir.targets.list",
    "List target weights",
    "List a portfolio's stored target weights (SOLL). Optional classification_id scopes to one tree.",
    targetsListSchema,
    targetsListZ
  ),
  tool(
    "portfolixir.targets.set",
    "Set target weights",
    "Upsert target weights for one portfolio and classification. Each target_weight is a string fraction in [0,1].",
    targetsSetSchema,
    targetsSetZ
  ),
  tool(
    "portfolixir.targets.delete",
    "Delete target weight",
    "Remove a portfolio's target weight for one category.",
    targetsDeleteSchema,
    targetsDeleteZ
  ),
  tool(
    "portfolixir.portfolios.allocation",
    "Portfolio allocation drift",
    "SOLL/IST allocation breakdown for a portfolio against one classification: market value, actual weight, target weight and drift per category, in one call.",
    allocationSchema,
    allocationZ
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
        withQuery("/api/v1/securities", args, [
          "query",
          "sort",
          "direction",
          "holding_status",
          "limit",
          "offset"
        ])
      );
    case "portfolixir.securities.create":
      return client.request("POST", "/api/v1/securities", { security: args.security });
    case "portfolixir.securities.update":
      return client.request("PATCH", `/api/v1/securities/${args.id}`, { security: args.security });
    case "portfolixir.securities.delete":
      return client.request("DELETE", `/api/v1/securities/${args.id}`);
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
    case "portfolixir.cash_accounts.update":
      return client.request("PATCH", `/api/v1/cash_accounts/${args.id}`, {
        cash_account: args.cash_account
      });
    case "portfolixir.cash_accounts.delete":
      return client.request("DELETE", `/api/v1/cash_accounts/${args.id}`);
    case "portfolixir.securities_accounts.list":
      return client.request("GET", "/api/v1/securities_accounts");
    case "portfolixir.securities_accounts.create":
      return client.request("POST", "/api/v1/securities_accounts", {
        securities_account: args.securities_account
      });
    case "portfolixir.securities_accounts.update":
      return client.request("PATCH", `/api/v1/securities_accounts/${args.id}`, {
        securities_account: args.securities_account
      });
    case "portfolixir.securities_accounts.delete":
      return client.request("DELETE", `/api/v1/securities_accounts/${args.id}`);
    case "portfolixir.transactions.list":
      return client.request(
        "GET",
        withQuery("/api/v1/transactions", args, [
          "from",
          "to",
          "portfolio_id",
          "security_id",
          "securities_account_id"
        ])
      );
    case "portfolixir.transactions.create":
      return client.request("POST", "/api/v1/transactions", { transaction: args.transaction });
    case "portfolixir.transactions.update":
      return client.request("PATCH", `/api/v1/transactions/${args.id}`, {
        transaction: args.transaction
      });
    case "portfolixir.transactions.delete":
      return client.request("DELETE", `/api/v1/transactions/${args.id}`);
    case "portfolixir.holdings.list":
      return client.request(
        "GET",
        withQuery(`/api/v1/portfolios/${args.portfolio_id}/holdings`, args, [
          "security_id",
          "securities_account_id"
        ])
      );
    case "portfolixir.portfolios.valuation":
      return client.request("GET", `/api/v1/portfolios/${args.portfolio_id}/valuation`);
    case "portfolixir.exchange_rates.list":
      return client.request("GET", "/api/v1/exchange_rates");
    case "portfolixir.exchange_rates.sync":
      return client.request("POST", "/api/v1/exchange_rates/sync", {});
    case "portfolixir.classifications.list":
      return client.request("GET", "/api/v1/classifications");
    case "portfolixir.classifications.create":
      return client.request("POST", "/api/v1/classifications", {
        classification: args.classification
      });
    case "portfolixir.classifications.categories.create":
      return client.request(
        "POST",
        `/api/v1/classifications/${args.classification_id}/categories`,
        { category: args.category }
      );
    case "portfolixir.classifications.update":
      return client.request("PATCH", `/api/v1/classifications/${args.id}`, {
        classification: args.classification
      });
    case "portfolixir.classifications.delete":
      return client.request("DELETE", `/api/v1/classifications/${args.id}`);
    case "portfolixir.classifications.categories.update":
      return client.request(
        "PATCH",
        `/api/v1/classifications/${args.classification_id}/categories/${args.id}`,
        { category: args.category }
      );
    case "portfolixir.classifications.categories.delete":
      return client.request(
        "DELETE",
        `/api/v1/classifications/${args.classification_id}/categories/${args.id}`
      );
    case "portfolixir.classifications.assign":
      return client.request(
        "PUT",
        `/api/v1/classifications/${args.classification_id}/assignments`,
        { security_id: args.security_id, category_id: args.category_id }
      );
    case "portfolixir.classifications.assign_bulk":
      return client.request(
        "PUT",
        `/api/v1/classifications/${args.classification_id}/assignments/bulk`,
        { category_id: args.category_id, security_ids: args.security_ids }
      );
    case "portfolixir.classifications.unassign":
      return client.request(
        "DELETE",
        `/api/v1/classifications/${args.classification_id}/assignments/${args.security_id}`
      );
    case "portfolixir.trades.list":
      return client.request(
        "GET",
        withQuery(`/api/v1/securities/${args.security_id}/trades`, args, ["from", "to"])
      );
    case "portfolixir.targets.list":
      return client.request(
        "GET",
        withQuery(`/api/v1/portfolios/${args.portfolio_id}/targets`, args, ["classification_id"])
      );
    case "portfolixir.targets.set":
      return client.request("PUT", `/api/v1/portfolios/${args.portfolio_id}/targets`, {
        classification_id: args.classification_id,
        targets: args.targets
      });
    case "portfolixir.targets.delete":
      return client.request(
        "DELETE",
        `/api/v1/portfolios/${args.portfolio_id}/targets/${args.category_id}`
      );
    case "portfolixir.portfolios.allocation":
      return client.request(
        "GET",
        withQuery(`/api/v1/portfolios/${args.portfolio_id}/allocation`, args, ["classification_id"])
      );
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
