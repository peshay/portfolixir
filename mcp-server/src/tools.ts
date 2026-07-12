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

// Mirrors Catalog.Quote @sources: a closed set, so the schema describes the
// accepted values instead of letting an LLM guess a free-form string (#508).
const quoteSources = ["auto", "manual", "coingecko", "portfolio_performance"] as const;

const quoteUpsertZ = z.object({
  security_id: z.number().int().positive(),
  quotes: z.array(
    z.object({
      date: z.string(),
      close: z.string(),
      source: z.enum(quoteSources)
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

const liquidityRoleZ = z.enum(["free_cash", "credit_line", "reserve"]);

const cashAccountZ = z.object({
  cash_account: z.object({
    // ADR-0024: optional — a missing portfolio_id binds the account to the
    // deterministic internal default portfolio.
    portfolio_id: z.number().int().positive().optional(),
    name: z.string(),
    currency_code: z.string(),
    notes: optionalString(),
    liquidity_role: liquidityRoleZ.optional()
  })
});

const securitiesAccountZ = z.object({
  securities_account: z.object({
    // ADR-0024: optional — a missing portfolio_id binds the depot to the
    // deterministic internal default portfolio.
    portfolio_id: z.number().int().positive().optional(),
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
    security_amount: optionalString(),
    settlement_amount: optionalString(),
    settlement_fx_rate: optionalString(),
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
          source: {
            type: "string",
            enum: [...quoteSources],
            description:
              "Quote origin. Use `manual` for user- or LLM-supplied quotes; `auto`, `coingecko` and `portfolio_performance` are reserved for the respective providers."
          }
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
  required: ["name", "currency_code"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    name: { type: "string" },
    currency_code: { type: "string" },
    notes: { type: "string" },
    liquidity_role: { type: "string", enum: ["free_cash", "credit_line", "reserve"] }
  }
});

const securitiesAccountSchema = objectWith("securities_account", {
  type: "object",
  required: ["cash_account_id", "name"],
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
    security_amount: { type: "string" },
    settlement_amount: { type: "string" },
    settlement_fx_rate: { type: "string" },
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
        security_amount: { type: "string" },
        settlement_amount: { type: "string" },
        settlement_fx_rate: { type: "string" },
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
    security_amount: optionalString(),
    settlement_amount: optionalString(),
    settlement_fx_rate: optionalString(),
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
        notes: { type: "string" },
        liquidity_role: { type: "string", enum: ["free_cash", "credit_line", "reserve"] }
      }
    }
  }
};

const cashAccountUpdateZ = z.object({
  id: z.number().int().positive(),
  cash_account: z.object({
    name: optionalString(),
    currency_code: optionalString(),
    notes: optionalString(),
    liquidity_role: liquidityRoleZ.optional()
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

// Since ADR-0020 a SOLL plan belongs to a view: the target read/write tools take
// an optional `view` (a view id). Omitting it addresses the portfolio-wide
// "Gesamt" plan, reproducing the behaviour before views existed.
const targetsListSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    classification_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 }
  }
};

const targetsListZ = z.object({
  portfolio_id: z.number().int().positive(),
  classification_id: z.number().int().positive().optional(),
  view: z.number().int().positive().optional()
});

const targetsSetSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id", "classification_id", "targets"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    classification_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 },
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
  view: z.number().int().positive().optional(),
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
    category_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 }
  }
};

const targetsDeleteZ = z.object({
  portfolio_id: z.number().int().positive(),
  category_id: z.number().int().positive(),
  view: z.number().int().positive().optional()
});

// A map of asset_class -> percentage cap string (e.g. {"equity": "50"}). Caps
// are opt-in (FR9): no defaults ship, so an absent map means no cap violations.
const decimalMapSchema = {
  type: "object",
  additionalProperties: { type: "string" }
};

const warnHardSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    warn: { type: "string" },
    hard: { type: "string" }
  }
};

const riskSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 },
    top_n: { type: "integer", minimum: 1 },
    asset_class_caps: decimalMapSchema,
    hhi_bands: {
      type: "object",
      additionalProperties: false,
      properties: {
        low: { type: "string" },
        high: { type: "string" }
      }
    },
    stock_thresholds: warnHardSchema,
    etf_thresholds: {
      type: "object",
      additionalProperties: false,
      properties: { warn: { type: "string" } }
    }
  }
};

const riskZ = z.object({
  portfolio_id: z.number().int().positive(),
  view: z.number().int().positive().optional(),
  top_n: z.number().int().positive().optional(),
  asset_class_caps: z.record(z.string()).optional(),
  hhi_bands: z
    .object({ low: optionalString(), high: optionalString() })
    .optional(),
  stock_thresholds: z
    .object({ warn: optionalString(), hard: optionalString() })
    .optional(),
  etf_thresholds: z.object({ warn: optionalString() }).optional()
});

const allocationSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id", "classification_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    classification_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 }
  }
};

const allocationZ = z.object({
  portfolio_id: z.number().int().positive(),
  classification_id: z.number().int().positive(),
  view: z.number().int().positive().optional()
});

// The cash target is the SOLL cash share of the allocation's 100% basis
// (securities + counting cash, issue #335): a string fraction in [0, 1], or
// null to stop steering a cash quote. Since ADR-0020 it belongs to a plan, so
// these tools take an optional `view` (omitted = the Gesamt plan, which is also
// what the legacy portfolio `cash_target_weight` field reads/writes).
const cashTargetGetSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 }
  }
};

const cashTargetGetZ = z.object({
  portfolio_id: z.number().int().positive(),
  view: z.number().int().positive().optional()
});

const cashTargetSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 },
    cash_target_weight: { type: ["string", "null"] }
  }
};

const cashTargetZ = z.object({
  portfolio_id: z.number().int().positive(),
  view: z.number().int().positive().optional(),
  cash_target_weight: z.union([z.string(), z.null()]).optional()
});

const cashBalanceSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id", "date", "amount"],
  properties: {
    id: { type: "integer", minimum: 1 },
    date: { type: "string", format: "date" },
    amount: { type: "string" },
    notes: { type: "string" }
  }
};

const cashBalanceZ = z.object({
  id: z.number().int().positive(),
  date: z.string(),
  amount: z.string(),
  notes: optionalString()
});

const incomeSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 }
  }
};

const incomeZ = z.object({
  portfolio_id: z.number().int().positive()
});

const performanceSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 },
    period: { type: "string", enum: ["ytd", "1y", "3y", "5y", "max"] },
    series: { type: "boolean" }
  }
};

const performanceZ = z.object({
  portfolio_id: z.number().int().positive(),
  view: z.number().int().positive().optional(),
  period: z.enum(["ytd", "1y", "3y", "5y", "max"]).optional(),
  series: z.boolean().optional()
});

// -- buckets & views (ADR-0018) --------------------------------------------

const bucketSchema = objectWith("bucket", {
  type: "object",
  required: ["name"],
  properties: {
    name: { type: "string" },
    color: { type: "string" },
    dimension: { type: "string", enum: ["tag", "scope"] }
  }
});

const bucketZ = z.object({
  bucket: z.object({
    name: z.string(),
    color: optionalString(),
    dimension: z.enum(["tag", "scope"]).optional()
  })
});

const bucketUpdateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id", "bucket"],
  properties: {
    id: { type: "integer", minimum: 1 },
    bucket: {
      type: "object",
      properties: {
        name: { type: "string" },
        color: { type: "string" }
      }
    }
  }
};

const bucketUpdateZ = z.object({
  id: z.number().int().positive(),
  bucket: z.object({
    name: optionalString(),
    color: optionalString()
  })
});

const viewSchema = objectWith("view", {
  type: "object",
  required: ["name"],
  properties: {
    name: { type: "string" },
    include_all: { type: "boolean" }
  }
});

const viewZ = z.object({
  view: z.object({
    name: z.string(),
    include_all: z.boolean().optional()
  })
});

const viewUpdateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id", "view"],
  properties: {
    id: { type: "integer", minimum: 1 },
    view: {
      type: "object",
      properties: {
        name: { type: "string" },
        include_all: { type: "boolean" }
      }
    }
  }
};

const viewUpdateZ = z.object({
  id: z.number().int().positive(),
  view: z.object({
    name: optionalString(),
    include_all: z.boolean().optional()
  })
});

const bucketIdArraySchema = {
  type: "array",
  items: { type: "integer", minimum: 1 }
};
const bucketIdArrayZ = z.array(z.number().int().positive());

const viewBucketsSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id"],
  properties: {
    id: { type: "integer", minimum: 1 },
    include: bucketIdArraySchema,
    exclude: bucketIdArraySchema
  }
};

const viewBucketsZ = z.object({
  id: z.number().int().positive(),
  include: bucketIdArrayZ.optional(),
  exclude: bucketIdArrayZ.optional()
});

const depotBucketsSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id"],
  properties: {
    id: { type: "integer", minimum: 1 },
    bucket_ids: bucketIdArraySchema
  }
};

const depotBucketsZ = z.object({
  id: z.number().int().positive(),
  bucket_ids: bucketIdArrayZ.optional()
});

const positionBucketsSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id", "security_id"],
  properties: {
    id: { type: "integer", minimum: 1 },
    security_id: { type: "integer", minimum: 1 },
    bucket_ids: bucketIdArraySchema
  }
};

const positionBucketsZ = z.object({
  id: z.number().int().positive(),
  security_id: z.number().int().positive(),
  bucket_ids: bucketIdArrayZ.optional()
});

const clearPositionBucketsSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id", "security_id"],
  properties: {
    id: { type: "integer", minimum: 1 },
    security_id: { type: "integer", minimum: 1 }
  }
};

const clearPositionBucketsZ = z.object({
  id: z.number().int().positive(),
  security_id: z.number().int().positive()
});

// The default-view preference (ADR-0024): a view id, or null/omitted for the
// built-in Everything scope. Not a financial value, so no Decimal strings.
const defaultViewSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    view_id: { type: ["integer", "null"], minimum: 1 }
  }
};

const defaultViewZ = z.object({
  view_id: z.number().int().positive().nullable().optional()
});

const journalActorTypes = [
  "owner_ui",
  "api_token_rw",
  "api_token_ro",
  "import_session",
  "system_job"
] as const;
const journalOperations = ["create", "update", "delete", "upsert"] as const;

const journalListSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    resource_type: { type: "string" },
    resource_id: { type: "string" },
    actor_type: { type: "string", enum: [...journalActorTypes] },
    operation: { type: "string", enum: [...journalOperations] },
    include_scenarios: { type: "boolean" },
    limit: { type: "integer", minimum: 1 }
  }
};

const journalListZ = z.object({
  resource_type: optionalString(),
  resource_id: optionalString(),
  actor_type: z.enum(journalActorTypes).optional(),
  operation: z.enum(journalOperations).optional(),
  include_scenarios: z.boolean().optional(),
  limit: z.number().int().min(1).optional()
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
  tool("portfolixir.securities.create", "Create security", "Create a local security. To keep a position (e.g. Bitcoin) in the totals and performance but out of the allocation steering basis (the 100%) and drift, tag it with a bucket and exclude that bucket from the active view.", securitySchema, securityZ),
  tool("portfolixir.securities.update", "Update security", "Patch a local security's master data. To keep a position visible in totals/performance but out of the allocation steering basis and drift, tag it with a bucket and exclude that bucket from the active view.", securityUpdateSchema, securityUpdateZ),
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
  tool("portfolixir.portfolios.list", "List portfolios", "List local portfolios. Deprecated (ADR-0024): portfolios are internal compatibility records, not the user-facing grouping — use portfolixir.buckets.list and portfolixir.views.list to group and scope holdings.", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.portfolios.create", "Create portfolio", "Create a portfolio. Deprecated (ADR-0024, compatibility only — the API answers with a Deprecation header): grouping happens through buckets and views, so prefer portfolixir.buckets.create and portfolixir.views.create; depots and cash accounts no longer need a portfolio_id (a deterministic internal default is bound automatically).", portfolioSchema, portfolioZ),
  tool("portfolixir.cash_accounts.list", "List cash accounts", "List cash accounts with their current balance.", emptyObjectSchema, emptyObjectZ),
  tool(
    "portfolixir.cash_accounts.create",
    "Create cash account",
    "Create a cash account. liquidity_role is free_cash (default, deployable cash), credit_line (overdraft/Lombard, never deployable), or reserve (visible but excluded from the cash quote).",
    cashAccountSchema,
    cashAccountZ
  ),
  tool(
    "portfolixir.cash_accounts.update",
    "Update cash account",
    "Patch a cash account's name, currency, notes or liquidity_role (free_cash, credit_line, reserve).",
    cashAccountUpdateSchema,
    cashAccountUpdateZ
  ),
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
  tool("portfolixir.transactions.create", "Create transaction", "Create a manual buy or sell transaction. For a security settled through a different-currency cash account (e.g. a USD security via a EUR account), book it in the security currency and supply the cross-currency settlement fields: security_amount (trade amount in the security currency), settlement_amount (cash amount in the account currency) and settlement_fx_rate (account units per 1 security unit; derived from the two amounts when omitted). All Decimal strings.", transactionSchema, transactionZ),
  tool("portfolixir.transactions.update", "Update transaction", "Patch a transaction (e.g. fix a mis-imported booking).", transactionUpdateSchema, transactionUpdateZ),
  tool("portfolixir.transactions.delete", "Delete transaction", "Delete a transaction.", idSchema, idZ),
  tool("portfolixir.holdings.list", "List holdings", "Per-portfolio derived holdings in each security's own currency (no FX conversion), with moving-average cost basis, latest price, market value and unrealized P&L. For FX-converted base-currency totals and the cash quote use portfolixir.portfolios.valuation; for a global per-security EUR view across all portfolios use portfolixir.holdings.by_security. Optional filters: security_id, securities_account_id.", {
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
  tool("portfolixir.holdings.by_security", "Holdings by security (global EUR)", "Global per-security valuation across ALL portfolios: each held security's total quantity and current market value converted to the EUR hub, with a valued flag (false when a quote, trade price or EUR rate path is missing). Self-describing: currency EUR, an as_of read date and a note; market_value is a Decimal string. Differs from portfolixir.holdings.list (per-portfolio holdings in the security's own currency, no FX) and from portfolixir.portfolios.valuation (one portfolio's totals/weights in its base currency).", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.portfolios.valuation", "Value portfolio", "Live valuation of a portfolio: market values, actual weights per position, plus the base-currency portfolio total, cash balances and the cash quote (use this, not holdings.list, for base-currency totals). The valued/price_source flags mark stale or unpriceable positions. Pass an optional view (a view id) to scope the result to the holdings matching that bucket view; the response then echoes the active view.", {
    type: "object",
    additionalProperties: false,
    required: ["portfolio_id"],
    properties: {
      portfolio_id: { type: "integer", minimum: 1 },
      view: { type: "integer", minimum: 1 }
    }
  }, z.object({ portfolio_id: z.number().int().positive(), view: z.number().int().positive().optional() })),
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
    "List FIFO-matched trades for a security: open lots, closed round-trips and orphan sells, with realized P&L per FIFO-matched round-trip. For unrealized P&L on current positions use portfolixir.holdings.list. Optional from/to (ISO dates) filter each leg by its own date.",
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
    "SOLL/IST allocation breakdown for a portfolio against one classification: market value, actual weight, target weight and drift per category plus a cash row, in one call. Drift is actual - target (positive = overweight, i.e. reduce to reach the target; ADR-0023), as a weight and restated in base currency. Each category's positions carry quantity, drift_value (the position's share of the category drift) and rebalance_quantity (indicative units to sell (positive) or buy (negative) at the valuation's implied unit price) — display-only hints, never an order. The 100% basis is securities + counting cash. Pass an optional view (a view id) to scope the breakdown to the holdings matching that bucket view; the response then echoes the active view.",
    allocationSchema,
    allocationZ
  ),
  tool(
    "portfolixir.portfolios.risk",
    "Portfolio risk/concentration lens",
    "Risk/concentration lens for a portfolio over the steerable basis (the valued positions, scoped by the active view): single-name Top-N (default 10, override top_n) with a severity (ok/warn/hard) per instrument type (stock warn>7/hard>10, ETF warn>25), the Herfindahl-Hirschman Index (hhi) on the 0-10000 scale with a band (low<1500, moderate, concentrated>2500), and opt-in asset-class cap violations (asset_class_caps, e.g. {\"equity\":\"50\"}) returning only classes over cap with the overage in percentage points. Weights, caps and HHI are 0-100 percentage Decimal strings. Thresholds and bands are overridable per call. Pass an optional view (a view id) to scope the lens to the holdings matching that bucket view; the response then echoes the active view.",
    riskSchema,
    riskZ
  ),
  tool(
    "portfolixir.portfolios.cash_target",
    "Read cash target weight",
    "Read a plan's cash target weight, the SOLL cash share of the allocation's 100% basis (securities + counting cash), as a string fraction in [0,1] (or null when none is steered). Pass an optional view (a view id) to read that view's plan; omitting it reads the portfolio-wide Gesamt plan, the same value the portfolio's legacy cash_target_weight field reports.",
    cashTargetGetSchema,
    cashTargetGetZ
  ),
  tool(
    "portfolixir.portfolios.set_cash_target",
    "Set cash target weight",
    "Set (or clear with null) a plan's cash target weight, the SOLL cash share of the allocation's 100% basis (securities + counting cash). A string fraction in [0,1]. Pass an optional view (a view id) to steer that view's plan; omitting it steers the portfolio-wide Gesamt plan (equivalent to the legacy portfolio cash_target_weight).",
    cashTargetSchema,
    cashTargetZ
  ),
  tool(
    "portfolixir.cash_accounts.set_balance",
    "Set cash balance",
    "Record an absolute cash-balance snapshot for one account (the current balance as of a date), instead of mirroring every booking. amount is a Decimal string and may be negative.",
    cashBalanceSchema,
    cashBalanceZ
  ),
  tool(
    "portfolixir.portfolios.income",
    "Portfolio income (dividends + interest)",
    "Retrospective income report for a portfolio from booked dividend and interest transactions (no forecast): an annual year x month matrix split into dividends and interest with a yearly total, a per-position table (security, gross, withheld tax, net, payment count, last payment) and the per-transaction detail for a year drilldown. Gross is net plus the dividend's withheld tax; all amounts are Decimal strings in the portfolio base currency, converted via the EUR hub at each booking date's stored rate, with the original currency retained.",
    incomeSchema,
    incomeZ
  ),
  tool(
    "portfolixir.portfolios.performance",
    "Portfolio performance (TTWROR + IRR)",
    "Time-weighted (ttwror) and money-weighted (irr) rate of return for a portfolio over a period (ytd, 1y, 3y, 5y, max — default max). TTWROR neutralises external cash flows the Portfolio Performance way; IRR is the annualised money-weighted return solved from the same dated flows and is a Decimal string or null when no rate exists (no sign change / no convergence). Set series=true to include the daily valuation series. Pass an optional view (a view id) to scope the series to the holdings matching that bucket view; the response then echoes the active view.",
    performanceSchema,
    performanceZ
  ),
  tool(
    "portfolixir.journal.list",
    "List audit journal",
    "List append-only audit-journal entries (FR-28), newest first: who (actor_type/label), what (operation on resource_type/resource_id) and the before/after snapshots of every financial write, including deletions. Optional filters: resource_type, resource_id, actor_type, operation, limit. Real writes only unless include_scenarios=true. The response echoes as_of, the filters applied and the ordering.",
    journalListSchema,
    journalListZ
  ),
  tool(
    "portfolixir.buckets.list",
    "List buckets",
    "List the buckets (tags applied to holdings for wealth scoping). Each bucket carries its dimension: \"tag\" (free overlapping tag) or \"scope\" (the exclusive dimension — at most one per depot/cash account, ADR-0024).",
    emptyObjectSchema,
    emptyObjectZ
  ),
  tool(
    "portfolixir.buckets.get",
    "Get bucket",
    "Get one bucket by id.",
    idSchema,
    idZ
  ),
  tool(
    "portfolixir.buckets.create",
    "Create bucket",
    "Create a bucket. name is required; color is an optional hex string. dimension is optional: \"tag\" (default, a free overlapping tag) or \"scope\" (the exclusive dimension — a depot/cash account carries at most one scope bucket, ADR-0024); the dimension is fixed at creation.",
    bucketSchema,
    bucketZ
  ),
  tool(
    "portfolixir.buckets.update",
    "Update bucket",
    "Patch a bucket's name or color. The dimension is fixed at creation and cannot be patched.",
    bucketUpdateSchema,
    bucketUpdateZ
  ),
  tool(
    "portfolixir.buckets.delete",
    "Delete bucket",
    "Delete a bucket. The deletion cascades: the bucket is removed from every assignment and view set.",
    idSchema,
    idZ
  ),
  tool(
    "portfolixir.views.list",
    "List views",
    "List the views (named global filters over buckets). Each view carries its resolved include/exclude bucket sets; include is \"all\" under include_all, otherwise a list of bucket ids. Exclude always wins.",
    emptyObjectSchema,
    emptyObjectZ
  ),
  tool(
    "portfolixir.views.get",
    "Get view",
    "Get one view by id, with its resolved include/exclude bucket sets.",
    idSchema,
    idZ
  ),
  tool(
    "portfolixir.views.create",
    "Create view",
    "Create a view (a named bucket filter). name is required; include_all defaults to true (every bucket is in scope until you narrow it with set_buckets).",
    viewSchema,
    viewZ
  ),
  tool(
    "portfolixir.views.update",
    "Update view",
    "Patch a view's name or include_all flag.",
    viewUpdateSchema,
    viewUpdateZ
  ),
  tool(
    "portfolixir.views.delete",
    "Delete view",
    "Delete a view and its include/exclude bucket sets.",
    idSchema,
    idZ
  ),
  tool(
    "portfolixir.views.set_buckets",
    "Set view buckets",
    "Replace a view's include and exclude bucket sets in one call. include and exclude are arrays of bucket ids (default empty). A holding matches when it is included (always under include_all, otherwise carries an included bucket) and carries no excluded bucket; exclude always wins.",
    viewBucketsSchema,
    viewBucketsZ
  ),
  tool(
    "portfolixir.views.valuation",
    "Value view (cross-portfolio)",
    "Live valuation of a bucket view across ALL portfolios (id is the view id): the deduplicated union of every depot, position and cash account matching the view — an account tagged into several included buckets counts exactly once. Totals, weights, cash balances and the cash quote are in EUR (converted via the EUR hub); the valued/price_source flags mark stale or unpriceable positions, exactly as in portfolixir.portfolios.valuation. The overlap object lists the depots/cash accounts carrying more than one included bucket (badge data — the totals are already deduplicated). matches_no_accounts is true when the view's resolution matches no account at all (an empty include set or orphaned buckets), explaining a 0 total. All financial values are Decimal strings. Use this, not a client-side sum of portfolio valuations, for a view's total wealth.",
    idSchema,
    idZ
  ),
  tool(
    "portfolixir.securities_accounts.set_buckets",
    "Set depot default buckets",
    "Replace a depot/securities account's default bucket set (the buckets every position inherits unless overridden). bucket_ids is an array of bucket ids (default empty); at most one may be a scope-dimension bucket (ADR-0024) — a violating set is rejected with 422.",
    depotBucketsSchema,
    depotBucketsZ
  ),
  tool(
    "portfolixir.cash_accounts.set_buckets",
    "Set cash account buckets",
    "Replace a cash account's bucket set. bucket_ids is an array of bucket ids (default empty); at most one may be a scope-dimension bucket (ADR-0024) — a violating set is rejected with 422.",
    depotBucketsSchema,
    depotBucketsZ
  ),
  tool(
    "portfolixir.securities_accounts.set_position_buckets",
    "Set position bucket override",
    "Set the per-position bucket override for one security in one depot (id is the securities account id, security_id the security). bucket_ids is an array of bucket ids; an empty array records the explicit-empty state (deliberately no buckets), distinct from inheriting the depot default. Override wins over the depot default. Like the account assignments, an override carries at most one scope-dimension bucket (ADR-0024); a second scope bucket is rejected with a 422.",
    positionBucketsSchema,
    positionBucketsZ
  ),
  tool(
    "portfolixir.securities_accounts.clear_position_buckets",
    "Clear position bucket override",
    "Clear the per-position bucket override, returning the position to inherit the depot default (id is the securities account id, security_id the security).",
    clearPositionBucketsSchema,
    clearPositionBucketsZ
  ),
  tool(
    "portfolixir.settings.get_default_view",
    "Get default view",
    "Read the user's default view preference (ADR-0024): the view the Wealth page and dashboard open on. view_id is null when the built-in Everything scope is the default. No financial values are involved.",
    emptyObjectSchema,
    emptyObjectZ
  ),
  tool(
    "portfolixir.settings.set_default_view",
    "Set default view",
    "Set the user's default view preference (ADR-0024). Pass a view id to make it the default scope of the Wealth page and dashboard; pass null (or omit view_id) to clear back to the built-in Everything scope. An unknown view id is rejected with 404.",
    defaultViewSchema,
    defaultViewZ
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
    case "portfolixir.holdings.by_security":
      return client.request("GET", "/api/v1/holdings/by_security");
    case "portfolixir.portfolios.valuation":
      return client.request(
        "GET",
        withQuery(`/api/v1/portfolios/${args.portfolio_id}/valuation`, args, ["view"])
      );
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
        withQuery(`/api/v1/portfolios/${args.portfolio_id}/targets`, args, [
          "classification_id",
          "view"
        ])
      );
    case "portfolixir.targets.set":
      return client.request("PUT", `/api/v1/portfolios/${args.portfolio_id}/targets`, {
        classification_id: args.classification_id,
        ...(args.view !== undefined && args.view !== null ? { view: args.view } : {}),
        targets: args.targets
      });
    case "portfolixir.targets.delete":
      return client.request(
        "DELETE",
        withQuery(
          `/api/v1/portfolios/${args.portfolio_id}/targets/${args.category_id}`,
          args,
          ["view"]
        )
      );
    case "portfolixir.portfolios.allocation":
      return client.request(
        "GET",
        withQuery(`/api/v1/portfolios/${args.portfolio_id}/allocation`, args, [
          "classification_id",
          "view"
        ])
      );
    case "portfolixir.portfolios.risk":
      return client.request("GET", riskPath(args));
    case "portfolixir.portfolios.cash_target":
      return client.request(
        "GET",
        withQuery(`/api/v1/portfolios/${args.portfolio_id}/cash_target`, args, ["view"])
      );
    case "portfolixir.portfolios.set_cash_target":
      return client.request("PUT", `/api/v1/portfolios/${args.portfolio_id}/cash_target`, {
        ...(args.view !== undefined && args.view !== null ? { view: args.view } : {}),
        cash_target_weight: args.cash_target_weight ?? null
      });
    case "portfolixir.cash_accounts.set_balance":
      return client.request("POST", `/api/v1/cash_accounts/${args.id}/balance`, {
        date: args.date,
        amount: args.amount,
        notes: args.notes
      });
    case "portfolixir.portfolios.income":
      return client.request("GET", `/api/v1/portfolios/${args.portfolio_id}/income`);
    case "portfolixir.portfolios.performance":
      return client.request(
        "GET",
        withQuery(`/api/v1/portfolios/${args.portfolio_id}/performance`, args, [
          "period",
          "series",
          "view"
        ])
      );
    case "portfolixir.journal.list":
      return client.request(
        "GET",
        withQuery("/api/v1/journal", args, [
          "resource_type",
          "resource_id",
          "actor_type",
          "operation",
          "include_scenarios",
          "limit"
        ])
      );
    case "portfolixir.buckets.list":
      return client.request("GET", "/api/v1/buckets");
    case "portfolixir.buckets.get":
      return client.request("GET", `/api/v1/buckets/${args.id}`);
    case "portfolixir.buckets.create":
      return client.request("POST", "/api/v1/buckets", { bucket: args.bucket });
    case "portfolixir.buckets.update":
      return client.request("PATCH", `/api/v1/buckets/${args.id}`, { bucket: args.bucket });
    case "portfolixir.buckets.delete":
      return client.request("DELETE", `/api/v1/buckets/${args.id}`);
    case "portfolixir.views.list":
      return client.request("GET", "/api/v1/views");
    case "portfolixir.views.get":
      return client.request("GET", `/api/v1/views/${args.id}`);
    case "portfolixir.views.create":
      return client.request("POST", "/api/v1/views", { view: args.view });
    case "portfolixir.views.update":
      return client.request("PATCH", `/api/v1/views/${args.id}`, { view: args.view });
    case "portfolixir.views.delete":
      return client.request("DELETE", `/api/v1/views/${args.id}`);
    case "portfolixir.views.valuation":
      return client.request("GET", `/api/v1/views/${args.id}/valuation`);
    case "portfolixir.views.set_buckets":
      return client.request("PUT", `/api/v1/views/${args.id}/buckets`, {
        include: args.include ?? [],
        exclude: args.exclude ?? []
      });
    case "portfolixir.securities_accounts.set_buckets":
      return client.request("PUT", `/api/v1/securities_accounts/${args.id}/buckets`, {
        bucket_ids: args.bucket_ids ?? []
      });
    case "portfolixir.cash_accounts.set_buckets":
      return client.request("PUT", `/api/v1/cash_accounts/${args.id}/buckets`, {
        bucket_ids: args.bucket_ids ?? []
      });
    case "portfolixir.securities_accounts.set_position_buckets":
      return client.request(
        "PUT",
        `/api/v1/securities_accounts/${args.id}/positions/${args.security_id}/buckets`,
        { bucket_ids: args.bucket_ids ?? [] }
      );
    case "portfolixir.securities_accounts.clear_position_buckets":
      return client.request(
        "DELETE",
        `/api/v1/securities_accounts/${args.id}/positions/${args.security_id}/buckets`
      );
    case "portfolixir.settings.get_default_view":
      return client.request("GET", "/api/v1/settings/default_view");
    case "portfolixir.settings.set_default_view":
      return client.request("PUT", "/api/v1/settings/default_view", {
        view_id: args.view_id ?? null
      });
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

// Encodes the risk lens overrides as a query string. Phoenix decodes
// bracketed params (`asset_class_caps[equity]=50`, `hhi_bands[low]=1500`) into
// nested maps, which is what the RiskController reads; the scalar `top_n` stays
// flat. Absent overrides are simply omitted so the shipped defaults apply.
function riskPath(args: Record<string, any>): string {
  const params = new URLSearchParams();

  if (args.view !== undefined && args.view !== null) {
    params.set("view", String(args.view));
  }

  if (args.top_n !== undefined && args.top_n !== null) {
    params.set("top_n", String(args.top_n));
  }

  appendNested(params, "asset_class_caps", args.asset_class_caps);
  appendNested(params, "hhi_bands", args.hhi_bands);
  appendNested(params, "stock_thresholds", args.stock_thresholds);
  appendNested(params, "etf_thresholds", args.etf_thresholds);

  const query = params.toString();
  const path = `/api/v1/portfolios/${args.portfolio_id}/risk`;
  return query === "" ? path : `${path}?${query}`;
}

function appendNested(
  params: URLSearchParams,
  key: string,
  value: Record<string, any> | undefined | null
): void {
  if (value === undefined || value === null) {
    return;
  }

  for (const [inner, raw] of Object.entries(value)) {
    if (raw !== undefined && raw !== null && raw !== "") {
      params.set(`${key}[${inner}]`, String(raw));
    }
  }
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
