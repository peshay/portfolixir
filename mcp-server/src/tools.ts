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

// The 13 bookable PP kinds. `balance_adjustment` is deliberately absent:
// absolute balance anchors are owned by the dedicated `set_balance` tool.
const bookableKinds = [
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
] as const;

const transactionZ = z.object({
  transaction: z
    .object({
      portfolio_id: z.number().int().positive(),
      securities_account_id: z.number().int().positive().optional(),
      cash_account_id: z.number().int().positive().optional(),
      counter_cash_account_id: z.number().int().positive().optional(),
      counter_securities_account_id: z.number().int().positive().optional(),
      security_id: z.number().int().positive().optional(),
      type: z.enum(bookableKinds),
      date: z.string(),
      quantity: optionalString(),
      price: optionalString(),
      gross_amount: optionalString(),
      fees: optionalString(),
      taxes: optionalString(),
      currency_code: z.string(),
      security_amount: optionalString(),
      settlement_amount: optionalString(),
      settlement_fx_rate: optionalString(),
      notes: optionalString()
    })
    .superRefine((tx, ctx) => {
      // The backend validates per-kind required fields; these two guards are
      // deliberately client-side because the failure they prevent is silent:
      // an unpriced delivery is VALID for the API (PP-import compatibility)
      // but enters the cost basis at zero (FR-31 cost-basis guard).
      if (tx.type === "buy" || tx.type === "sell") {
        for (const field of ["quantity", "price"] as const) {
          if (!tx[field]) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              path: [field],
              message: `${field} is required for ${tx.type}`
            });
          }
        }
      }

      if (tx.type === "inbound_delivery" || tx.type === "outbound_delivery") {
        if (!tx.quantity) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ["quantity"],
            message: `quantity is required for ${tx.type}`
          });
        }
      }

      // Only INBOUND deliveries read the price (it sets the acquisition
      // cost); outbound deliveries remove cost at the position's running
      // average and ignore price entirely — forcing a fabricated value
      // there would persist a meaningless number.
      if (tx.type === "inbound_delivery" && !tx.price) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["price"],
          message:
            "price is required for inbound_delivery over MCP: an unpriced inbound delivery " +
            "enters the cost basis at zero — supply the acquisition price"
        });
      }
    })
});

const idSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id"],
  properties: { id: { type: "integer", minimum: 1 } }
};

// ISIN-change recording (ADR-0029 §3): the current ISIN moves into a journaled
// former-ISIN alias and the new ISIN is written onto the security.
const isinChangeSchema = {
  type: "object",
  additionalProperties: false,
  required: ["security_id", "new_isin"],
  properties: {
    security_id: { type: "integer", minimum: 1 },
    new_isin: {
      type: "string",
      minLength: 1,
      description: "The security's new ISIN (normalized to trimmed uppercase server-side)."
    },
    changed_on: {
      type: "string",
      format: "date",
      description: "Effective date of the ISIN change (YYYY-MM-DD); defaults to today."
    },
    note: { type: "string", description: "Optional note, e.g. the corporate action." }
  }
};

const isinChangeZ = z.object({
  security_id: z.number().int().positive(),
  new_isin: z.string().min(1),
  changed_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  note: optionalString()
});

const isinAliasDeleteSchema = {
  type: "object",
  additionalProperties: false,
  required: ["security_id", "alias_id"],
  properties: {
    security_id: { type: "integer", minimum: 1 },
    alias_id: { type: "integer", minimum: 1 }
  }
};

const isinAliasDeleteZ = z.object({
  security_id: z.number().int().positive(),
  alias_id: z.number().int().positive()
});

// The dedicated split booking flow (ADR-0028 §1): the ratio is a pair of
// positive INTEGERS (10:1 forward, 1:10 reverse) — integers keep a 1:3
// reverse split exact where a decimal ratio cannot, so these two fields are
// deliberately not Decimal strings. All returned quantities are strings.
// The parts persist into int4 columns, hence the 2147483647 cap (E17
// review, finding 4).
const INT4_MAX = 2147483647;

const splitRequestSchema = {
  type: "object",
  additionalProperties: false,
  required: ["security_id", "date", "ratio_numerator", "ratio_denominator"],
  properties: {
    security_id: { type: "integer", minimum: 1 },
    date: {
      type: "string",
      format: "date",
      description: "Effective date (YYYY-MM-DD), not in the future."
    },
    ratio_numerator: {
      type: "integer",
      minimum: 1,
      maximum: INT4_MAX,
      description: "New share count per ratio_denominator old shares (10 for a 10:1 forward split, 1 for a 1:10 reverse split)."
    },
    ratio_denominator: { type: "integer", minimum: 1, maximum: INT4_MAX }
  }
};

const splitRequestZ = () =>
  z.object({
    security_id: z.number().int().positive(),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    ratio_numerator: z.number().int().positive().max(INT4_MAX),
    ratio_denominator: z.number().int().positive().max(INT4_MAX)
  });

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
  required: ["portfolio_id", "type", "date", "currency_code"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    securities_account_id: { type: "integer", minimum: 1 },
    cash_account_id: { type: "integer", minimum: 1 },
    counter_cash_account_id: { type: "integer", minimum: 1 },
    counter_securities_account_id: { type: "integer", minimum: 1 },
    security_id: { type: "integer", minimum: 1 },
    type: { type: "string", enum: [...bookableKinds] },
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
        treat_quotes_as_raw: {
          type: "boolean",
          description:
            "ADR-0028 escape hatch: treat this security's provider-synced quote history as raw (as-traded). Set it when the provider never back-adjusts closes after a stock split, so the split-adjustment factors apply to its synced rows too. Default false (synced rows are trusted as an already-adjusted provider mirror)."
        },
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
    treat_quotes_as_raw: z.boolean().optional(),
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
        type: { type: "string", enum: [...bookableKinds] },
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
  transaction: z
    .object({
      portfolio_id: z.number().int().positive().optional(),
      securities_account_id: z.number().int().positive().optional(),
      cash_account_id: z.number().int().positive().optional(),
      counter_cash_account_id: z.number().int().positive().optional(),
      counter_securities_account_id: z.number().int().positive().optional(),
      security_id: z.number().int().positive().optional(),
      type: z.enum(bookableKinds).optional(),
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
    .superRefine((tx, ctx) => {
      // Closes the create-guard bypass: re-typing an existing booking into an
      // inbound delivery without supplying a price would leave a silent
      // zero-cost acquisition. Patches that don't change the type are
      // unaffected (the existing price stays in place).
      if (tx.type === "inbound_delivery" && !tx.price) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["price"],
          message:
            "price is required when changing a transaction's type to inbound_delivery: " +
            "an unpriced inbound delivery enters the cost basis at zero"
        });
      }
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

// A target entry sets a category weight (category_id only) or, since ADR-0030
// (#481), a position weight when it also carries a security_id — the security
// must sit under the named category.
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
          security_id: { type: "integer", minimum: 1 },
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
        security_id: z.number().int().positive().optional(),
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

// Position-level SOLL reads/deletes (ADR-0030, #481).
const positionTargetsListSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    classification_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 }
  }
};

const positionTargetsListZ = z.object({
  portfolio_id: z.number().int().positive(),
  classification_id: z.number().int().positive().optional(),
  view: z.number().int().positive().optional()
});

const positionTargetDeleteSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id", "category_id", "security_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    category_id: { type: "integer", minimum: 1 },
    security_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 }
  }
};

const positionTargetDeleteZ = z.object({
  portfolio_id: z.number().int().positive(),
  category_id: z.number().int().positive(),
  security_id: z.number().int().positive(),
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

// Period selection (#563): besides the fixed period strings, a single
// calendar year or a custom from/to date range (both dates required, from
// on or before to; the server clamps to the available history).
const performanceSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    view: { type: "integer", minimum: 1 },
    period: { type: "string", enum: ["ytd", "1y", "3y", "5y", "max"] },
    year: { type: "integer", minimum: 1970 },
    from: { type: "string", format: "date" },
    to: { type: "string", format: "date" },
    series: { type: "boolean" }
  }
};

const performanceZ = z.object({
  portfolio_id: z.number().int().positive(),
  view: z.number().int().positive().optional(),
  period: z.enum(["ytd", "1y", "3y", "5y", "max"]).optional(),
  year: z.number().int().min(1970).optional(),
  from: z.string().optional(),
  to: z.string().optional(),
  series: z.boolean().optional()
});

// Cross-portfolio view performance (#577): keyed by the view id.
const viewPerformanceSchema = {
  type: "object",
  additionalProperties: false,
  required: ["id"],
  properties: {
    id: { type: "integer", minimum: 1 },
    period: { type: "string", enum: ["ytd", "1y", "3y", "5y", "max"] },
    year: { type: "integer", minimum: 1970 },
    from: { type: "string", format: "date" },
    to: { type: "string", format: "date" },
    series: { type: "boolean" }
  }
};

const viewPerformanceZ = z.object({
  id: z.number().int().positive(),
  period: z.enum(["ytd", "1y", "3y", "5y", "max"]).optional(),
  year: z.number().int().min(1970).optional(),
  from: z.string().optional(),
  to: z.string().optional(),
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

// Plan versions & depot snapshots (ADR-0027).
const plansListSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    classification_id: { type: "integer", minimum: 1 }
  }
};

const plansListZ = z.object({
  portfolio_id: z.number().int().positive(),
  classification_id: z.number().int().positive().optional()
});

const planIdSchema = {
  type: "object",
  additionalProperties: false,
  required: ["plan_id"],
  properties: { plan_id: { type: "integer", minimum: 1 } }
};

const planIdZ = z.object({ plan_id: z.number().int().positive() });

const planDuplicateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["plan_id"],
  properties: {
    plan_id: { type: "integer", minimum: 1 },
    name: { type: "string", minLength: 1, maxLength: 120 }
  }
};

const planDuplicateZ = z.object({
  plan_id: z.number().int().positive(),
  name: z.string().min(1).max(120).optional()
});

const planRenameSchema = {
  type: "object",
  additionalProperties: false,
  required: ["plan_id", "name"],
  properties: {
    plan_id: { type: "integer", minimum: 1 },
    name: { type: "string", minLength: 1, maxLength: 120 }
  }
};

const planRenameZ = z.object({
  plan_id: z.number().int().positive(),
  name: z.string().min(1).max(120)
});

const snapshotsListSchema = {
  type: "object",
  additionalProperties: false,
  properties: {}
};

const snapshotsListZ = z.object({});

// -- tax (ADR-0031) ---------------------------------------------------------
// The pots are RECORDED, never derived. Not for want of FIFO - the ledger has
// a FIFO lot matcher - but because Teilfreistellung, Vorabpauschale,
// chronological allowance consumption and prior-year carry-forward are absent
// from transaction data, and the pots are per institution. Every money value is
// a Decimal string.

const taxMoney = {
  type: "string",
  description: "Decimal string, positive magnitude (e.g. \"1000.00\")"
} as const;

const taxParametersListSchema = {
  type: "object",
  additionalProperties: false,
  properties: { jurisdiction: { type: "string", enum: ["DE"] } }
};

const taxParametersListZ = z.object({ jurisdiction: z.enum(["DE"]).optional() });

const taxParametersUpsertSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "tax_year",
    "capital_gains_tax_rate",
    "solidarity_surcharge_rate",
    "saver_allowance_single",
    "saver_allowance_joint"
  ],
  properties: {
    jurisdiction: { type: "string", enum: ["DE"] },
    tax_year: { type: "integer", minimum: 1990, maximum: 2200 },
    capital_gains_tax_rate: {
      type: "string",
      description: "Decimal string fraction in [0,1) - \"0.25\", never \"25\""
    },
    solidarity_surcharge_rate: { type: "string", description: "Decimal string fraction in [0,1)" },
    saver_allowance_single: taxMoney,
    saver_allowance_joint: taxMoney,
    church_tax_rates: { type: "array", items: { type: "string" } }
  }
};

const taxParametersUpsertZ = z.object({
  jurisdiction: z.enum(["DE"]).optional(),
  tax_year: z.number().int().min(1990).max(2200),
  capital_gains_tax_rate: z.string(),
  solidarity_surcharge_rate: z.string(),
  saver_allowance_single: z.string(),
  saver_allowance_joint: z.string(),
  church_tax_rates: z.array(z.string()).optional()
});

const taxHolderSchema = {
  type: "object",
  additionalProperties: false,
  required: ["holder"],
  properties: { holder: { type: "string", minLength: 1 } }
};

const taxHolderZ = z.object({ holder: z.string().min(1) });

const taxProfileCreateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["holder", "valid_from"],
  properties: {
    holder: { type: "string", minLength: 1 },
    valid_from: { type: "string", description: "ISO date (YYYY-MM-DD)" },
    church_tax_liable: { type: "boolean" },
    church_tax_rate: { type: "string", description: "Decimal string fraction; 0 when not liable" },
    assessment_type: { type: "string", enum: ["single", "joint"] },
    note: { type: "string" }
  }
};

const taxProfileCreateZ = z.object({
  holder: z.string().min(1),
  valid_from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  church_tax_liable: z.boolean().optional(),
  church_tax_rate: z.string().optional(),
  assessment_type: z.enum(["single", "joint"]).optional(),
  note: z.string().optional()
});

const taxProfileUpdateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["profile_id"],
  properties: {
    profile_id: { type: "integer", minimum: 1 },
    valid_from: { type: "string", description: "ISO date (YYYY-MM-DD)" },
    church_tax_liable: { type: "boolean" },
    church_tax_rate: { type: "string" },
    assessment_type: { type: "string", enum: ["single", "joint"] },
    note: { type: "string" }
  }
};

const taxProfileUpdateZ = z.object({
  profile_id: z.number().int().positive(),
  valid_from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  church_tax_liable: z.boolean().optional(),
  church_tax_rate: z.string().optional(),
  assessment_type: z.enum(["single", "joint"]).optional(),
  note: z.string().optional()
});

const taxProfileIdSchema = {
  type: "object",
  additionalProperties: false,
  required: ["profile_id"],
  properties: { profile_id: { type: "integer", minimum: 1 } }
};

const taxProfileIdZ = z.object({ profile_id: z.number().int().positive() });

const allowanceOrdersListSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    holder: { type: "string" },
    institution: { type: "string" },
    tax_year: { type: "integer", minimum: 1990, maximum: 2200 }
  }
};

const allowanceOrdersListZ = z.object({
  holder: z.string().optional(),
  institution: z.string().optional(),
  tax_year: z.number().int().min(1990).max(2200).optional()
});

const allowanceOrderPutSchema = {
  type: "object",
  additionalProperties: false,
  required: ["holder", "institution", "tax_year", "amount_granted"],
  properties: {
    holder: { type: "string", minLength: 1 },
    institution: { type: "string", minLength: 1 },
    tax_year: { type: "integer", minimum: 1990, maximum: 2200 },
    amount_granted: taxMoney,
    note: { type: "string" }
  }
};

const allowanceOrderPutZ = z.object({
  holder: z.string().min(1),
  institution: z.string().min(1),
  tax_year: z.number().int().min(1990).max(2200),
  amount_granted: z.string(),
  note: z.string().optional()
});

const allowanceOrderIdSchema = {
  type: "object",
  additionalProperties: false,
  required: ["allowance_order_id"],
  properties: { allowance_order_id: { type: "integer", minimum: 1 } }
};

const allowanceOrderIdZ = z.object({ allowance_order_id: z.number().int().positive() });

const taxSnapshotMoneyProperties = {
  taxable_income: taxMoney,
  allowance_granted: taxMoney,
  allowance_used: taxMoney,
  loss_pot_equities: taxMoney,
  loss_pot_other: taxMoney,
  loss_carryforward_prior_years: taxMoney,
  withholding_tax_pot: taxMoney,
  withholding_tax_credited: taxMoney,
  capital_gains_tax_withheld: taxMoney,
  solidarity_surcharge_withheld: taxMoney,
  church_tax_withheld: taxMoney
};

const taxSnapshotMoneyZ = {
  taxable_income: z.string().optional(),
  allowance_granted: z.string().optional(),
  allowance_used: z.string().optional(),
  loss_pot_equities: z.string().optional(),
  loss_pot_other: z.string().optional(),
  loss_carryforward_prior_years: z.string().optional(),
  withholding_tax_pot: z.string().optional(),
  withholding_tax_credited: z.string().optional(),
  capital_gains_tax_withheld: z.string().optional(),
  solidarity_surcharge_withheld: z.string().optional(),
  church_tax_withheld: z.string().optional()
};

const taxSnapshotsListSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    holder: { type: "string" },
    institution: { type: "string" },
    tax_year: { type: "integer", minimum: 1990, maximum: 2200 }
  }
};

const taxSnapshotsListZ = z.object({
  holder: z.string().optional(),
  institution: z.string().optional(),
  tax_year: z.number().int().min(1990).max(2200).optional()
});

const taxSnapshotIdSchema = {
  type: "object",
  additionalProperties: false,
  required: ["snapshot_id"],
  properties: { snapshot_id: { type: "integer", minimum: 1 } }
};

const taxSnapshotIdZ = z.object({ snapshot_id: z.number().int().positive() });

const taxSnapshotCreateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["institution", "holder", "tax_year", "as_of"],
  properties: {
    institution: { type: "string", minLength: 1 },
    holder: { type: "string", minLength: 1 },
    tax_year: { type: "integer", minimum: 1990, maximum: 2200 },
    as_of: { type: "string", description: "ISO date (YYYY-MM-DD), not in the future" },
    source: { type: "string", enum: ["manual", "pdf_import"] },
    church_tax_rate: {
      type: "string",
      description: "Decimal string fraction; omit to take the holder's profile in force at as_of"
    },
    note: { type: "string" },
    ...taxSnapshotMoneyProperties
  }
};

const taxSnapshotCreateZ = z.object({
  institution: z.string().min(1),
  holder: z.string().min(1),
  tax_year: z.number().int().min(1990).max(2200),
  as_of: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  source: z.enum(["manual", "pdf_import"]).optional(),
  church_tax_rate: z.string().optional(),
  note: z.string().optional(),
  ...taxSnapshotMoneyZ
});

const taxSnapshotUpdateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["snapshot_id"],
  properties: {
    snapshot_id: { type: "integer", minimum: 1 },
    source: { type: "string", enum: ["manual", "pdf_import"] },
    church_tax_rate: { type: "string" },
    note: { type: "string" },
    ...taxSnapshotMoneyProperties
  }
};

const taxSnapshotUpdateZ = z.object({
  snapshot_id: z.number().int().positive(),
  source: z.enum(["manual", "pdf_import"]).optional(),
  church_tax_rate: z.string().optional(),
  note: z.string().optional(),
  ...taxSnapshotMoneyZ
});

const taxTrimBudgetSchema = {
  type: "object",
  additionalProperties: false,
  required: ["holder", "tax_year"],
  properties: {
    holder: { type: "string", minLength: 1 },
    tax_year: { type: "integer", minimum: 1990, maximum: 2200 }
  }
};

const taxTrimBudgetZ = z.object({
  holder: z.string().min(1),
  tax_year: z.number().int().min(1990).max(2200)
});

const snapshotCreateSchema = {
  type: "object",
  additionalProperties: false,
  required: ["name", "as_of"],
  properties: {
    name: { type: "string", minLength: 1, maxLength: 120 },
    as_of: { type: "string", description: "ISO date (YYYY-MM-DD), not in the future" },
    view_id: { type: "integer", minimum: 1 }
  }
};

const snapshotCreateZ = z.object({
  name: z.string().min(1).max(120),
  as_of: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  view_id: z.number().int().positive().optional()
});

const snapshotIdSchema = {
  type: "object",
  additionalProperties: false,
  required: ["snapshot_id"],
  properties: { snapshot_id: { type: "integer", minimum: 1 } }
};

const snapshotIdZ = z.object({ snapshot_id: z.number().int().positive() });

const snapshotComparisonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["portfolio_id", "snapshot_id"],
  properties: {
    portfolio_id: { type: "integer", minimum: 1 },
    snapshot_id: { type: "integer", minimum: 1 }
  }
};

const snapshotComparisonZ = z.object({
  portfolio_id: z.number().int().positive(),
  snapshot_id: z.number().int().positive()
});

// FR-35 / ADR-0029 §6 read-only holdings reconcile: the external list arrives
// ONLY in the request body (paste/file content parsed client-side into rows);
// quantities are canonical dot-decimal strings — locale parsing happens on the
// client, so the strict pattern rejects comma decimals before any API call.
const reconcileQuantityPattern = /^-?\d+(\.\d+)?$/;

const reconcileSchema = {
  type: "object",
  additionalProperties: false,
  required: ["rows"],
  properties: {
    rows: {
      type: "array",
      minItems: 1,
      maxItems: 10000,
      description:
        "The external position list, one row per line of the source document. " +
        "Parse locale formats client-side: quantity must be a canonical dot-decimal string. " +
        "At most 10000 rows per request.",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["identifier", "quantity"],
        properties: {
          identifier: {
            type: "string",
            minLength: 1,
            description:
              "The row's security identifier as the external document shows it: an ISIN, " +
              "WKN, ticker or name. ISIN-shaped strings match via the ISIN tier only " +
              "(recorded former ISINs included)."
          },
          quantity: {
            type: "string",
            pattern: "^-?\\d+(\\.\\d+)?$",
            description: 'External quantity as a canonical dot-decimal string (e.g. "12.5").'
          },
          currency: {
            type: "string",
            description:
              "The row's currency (e.g. EUR). Required for ticker/name matching — a " +
              "currency-less row can only match by ISIN or WKN and is otherwise unmatched."
          },
          security_id: {
            type: "integer",
            minimum: 1,
            description: "Optional pin: match this row to the given security, bypassing the ladder."
          }
        }
      }
    },
    portfolio_id: {
      type: "integer",
      minimum: 1,
      description: "Optional scope: compare against this portfolio's ledger quantities only."
    },
    view: {
      type: "integer",
      minimum: 1,
      description:
        "Optional scope: compare against the holdings matching this bucket view. " +
        "Mutually exclusive with portfolio_id."
    }
  }
};

const reconcileZ = z.object({
  rows: z
    .array(
      z.object({
        identifier: z.string().min(1),
        quantity: z.string().regex(reconcileQuantityPattern, {
          message:
            "quantity must be a canonical dot-decimal string (parse locale formats client-side)"
        }),
        currency: optionalString(),
        security_id: z.number().int().positive().optional()
      })
    )
    .min(1)
    .max(10000),
  portfolio_id: z.number().int().positive().optional(),
  view: z.number().int().positive().optional()
});

const toolDefinitions: ToolDefinition[] = [
  tool("portfolixir.securities.list", "List securities", "List local securities. Rows default to a slim projection (id, name, ticker_symbol, isin, wkn, currency_code, asset_class) to keep responses small; pass projection=full only when you need notes, feed config, attributes or timestamps. Use limit/offset to page large catalogs.", {
    type: "object",
    additionalProperties: false,
    properties: {
      query: { type: "string" },
      sort: { type: "string" },
      direction: { type: "string", enum: ["asc", "desc"] },
      holding_status: { type: "string", enum: ["held", "not_held", "all"] },
      projection: { type: "string", enum: ["slim", "full"] },
      limit: { type: "integer", minimum: 0 },
      offset: { type: "integer", minimum: 0 }
    }
  }, z.object({
    query: optionalString(),
    sort: optionalString(),
    direction: z.enum(["asc", "desc"]).optional(),
    holding_status: z.enum(["held", "not_held", "all"]).optional(),
    projection: z.enum(["slim", "full"]).optional(),
    limit: z.number().int().min(0).optional(),
    offset: z.number().int().min(0).optional()
  })),
  tool("portfolixir.securities.get", "Get security", "Read one security's full record, including its identifier_aliases — the former ISINs recorded via portfolixir.securities.isin_change that keep old exports matching this security.", idSchema, idZ),
  tool("portfolixir.securities.create", "Create security", "Create a local security. To keep a position (e.g. Bitcoin) in the totals and performance but out of the allocation steering basis (the 100%) and drift, tag it with a bucket and exclude that bucket from the active view.", securitySchema, securityZ),
  tool("portfolixir.securities.update", "Update security", "Patch a local security's master data. To keep a position visible in totals/performance but out of the allocation steering basis and drift, tag it with a bucket and exclude that bucket from the active view. Do NOT use this to change an ISIN after a corporate action — use portfolixir.securities.isin_change instead, which keeps the former ISIN as an import-matching alias; a plain rename is just a name edit here.", securityUpdateSchema, securityUpdateZ),
  tool("portfolixir.securities.delete", "Delete security", "Delete a local security when no transactions or quotes reference it.", idSchema, idZ),
  tool("portfolixir.securities.isin_change", "Record ISIN change", "Record a corporate-action ISIN change (merger rename, re-domiciliation): the current ISIN becomes a journaled former-ISIN alias and new_isin is written onto the same security, so re-imports of OLD exports (former ISIN) and NEW exports (new ISIN) both keep matching this security instead of duplicating it. Use this whenever a broker/PP export starts carrying a new ISIN for an existing position; a plain rename needs no ISIN change — edit the name via portfolixir.securities.update. Rejected with a named conflict when new_isin equals the current ISIN, is live on another security, or is aliased to another security; recording a change back to one of this security's own former ISINs consumes that alias (revert).", isinChangeSchema, isinChangeZ),
  tool("portfolixir.securities.delete_isin_alias", "Delete ISIN alias", "Delete one recorded former-ISIN alias of a security (journaled) — use when an ISIN change was recorded by mistake. After deletion, imports no longer match the security via that former ISIN.", isinAliasDeleteSchema, isinAliasDeleteZ),
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
  tool("portfolixir.quotes.list", "List quotes", "List quote history for one security. Each row is self-describing about stock splits (ADR-0028): close is the STORED value (never mutated), adjusted_close is the split-adjusted display value (Decimal string), basis states the row's storage basis (raw = as-traded manual rows, provider_mirror = back-adjusted sync rows) and adjusted whether a split factor applied. Chart or value with adjusted_close; audit with close.", {
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
  tool("portfolixir.transactions.create", "Create transaction", "Create a transaction of any bookable kind: buy, sell, dividend, interest, deposit, removal, fee, tax, tax_refund, cash_transfer, inbound_delivery, outbound_delivery, security_transfer (absolute balance anchors are set via set_balance instead). Required fields depend on the kind: buy/sell need securities_account_id, security_id, quantity and price; dividend needs security_id, cash_account_id and gross_amount; interest/deposit/removal/fee/tax/tax_refund need cash_account_id and gross_amount; cash_transfer needs cash_account_id, counter_cash_account_id and gross_amount; deliveries need securities_account_id, security_id and quantity — inbound_delivery additionally REQUIRES price (an unpriced inbound delivery enters the cost basis at zero), while outbound_delivery removes cost at the position's running average and treats price as informational; security_transfer needs securities_account_id, counter_securities_account_id, security_id and quantity. For buy/sell, omit cash_account_id — it is derived from the depot's linked account. Amounts are positive magnitudes; the kind implies the direction (removal/fee/tax debit, deposit/dividend/interest credit) — never send negative values (set_balance is the only negative-capable amount). Semantics: for dividend/interest/tax_refund bookings, gross_amount is the NET cash credited to the account — record withheld taxes in the taxes field; the income report reconstructs gross as net plus withheld tax. For a security settled through a different-currency cash account (e.g. a USD security via a EUR account), book it in the security currency and supply the cross-currency settlement fields: security_amount (trade amount in the security currency), settlement_amount (cash amount in the account currency) and settlement_fx_rate (account units per 1 security unit; derived from the two amounts when omitted). All Decimal strings.", transactionSchema, transactionZ),
  tool("portfolixir.transactions.update", "Update transaction", "Patch a transaction (e.g. fix a mis-imported booking). Semantics as on create: a dividend's gross_amount is the NET cash credited (withheld taxes ride in the taxes field), and an unpriced inbound delivery enters the cost basis at zero (changing a type to inbound_delivery therefore requires a price).", transactionUpdateSchema, transactionUpdateZ),
  tool("portfolixir.transactions.delete", "Delete transaction", "Delete a transaction.", idSchema, idZ),
  tool(
    "portfolixir.splits.preview",
    "Preview stock split",
    "Read-only preview of a stock split booking (ADR-0028): shows, per portfolio holding the security, the quantity immediately before and after the effective date and the resulting current position, plus warnings — nothing is written. ALWAYS call this before portfolixir.splits.create and read the numbers: the effective_date_before_history warning means the effective date predates the security's earliest recorded transaction, so the stored quantities may already be post-split (Portfolio Performance's split wizard rewrites history destructively before export) — booking the split then would double-adjust; do not book when before/after are 0 and the current position already looks post-split. The preview also renders the stored closes around the effective date (quotes_around) and a quote_basis_check comparing the observed jump against each row's basis classification: a quote_basis_contradiction warning means the stored series contradicts its source classification (e.g. a synced series that never back-adjusted) — resolve it (for never-adjusting providers set the security's treat_quotes_as_raw flag via portfolixir.securities.update) instead of booking blindly; insufficient_quotes_to_verify_basis means too few closes existed to verify. Each portfolio row carries a bookable flag: false means the portfolio held nothing at the effective date, so booking would create no row for it — when NO row is bookable the preview warns no_position_at_effective_date and splits.create would fail with a no-position error. The ratio is a pair of positive integers (10:1 forward, 1:10 reverse), normalized to lowest terms; all quantities in the response are Decimal strings.",
    splitRequestSchema,
    splitRequestZ()
  ),
  tool(
    "portfolixir.splits.create",
    "Book stock split",
    "Book a stock split as a first-class ledger event (ADR-0028): ONE call fans the split out across all portfolios holding a position in the security at the effective date — one journaled split row per portfolio, inserted atomically; do not call once per portfolio. A second same-day split for the same security is rejected with the existing event named (write idempotency — a retried timeout cannot compound the split), so a 422 naming an existing transaction means the split is already booked. A future-dated effective date is rejected, and a security nobody held at the effective date returns a no-position error. Check portfolixir.splits.preview first — especially its effective_date_before_history warning, which signals quantities that may already be post-split. The ratio parts are positive integers (never Decimal strings); the response returns the created transactions with all financial values as strings.",
    splitRequestSchema,
    splitRequestZ()
  ),
  tool("portfolixir.holdings.list", "List holdings", "Per-portfolio derived holdings in each security's own currency (no FX conversion), with moving-average cost basis, latest price, market value and unrealized P&L. Each row carries the security's stable identifiers isin and wkn (null when absent), so reconciling against broker data needs no join over securities.list. For FX-converted base-currency totals and the cash quote use portfolixir.portfolios.valuation; for a global per-security EUR view across all portfolios use portfolixir.holdings.by_security. Optional filters: security_id, securities_account_id.", {
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
  tool("portfolixir.holdings.by_security", "Holdings by security (global EUR)", "Global per-security valuation across ALL portfolios: each held security's total quantity and current market value converted to the EUR hub, with a valued flag (false when a quote, trade price or EUR rate path is missing) and an unvalued_reason (no_price: nothing resolves at all; missing_fx: latest_price/price_currency are known but no stored rate path reaches EUR; null when valued). Each row also carries latest_price, price_currency and price_source. Self-describing: currency EUR, an as_of read date and a note; financial values are Decimal strings. Differs from portfolixir.holdings.list (per-portfolio holdings in the security's own currency, no FX) and from portfolixir.portfolios.valuation (one portfolio's totals/weights in its base currency).", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.holdings.negative", "Negative holdings (data quality)", "Data-quality report of impossible negative holdings (#570): every (depot, security) position whose derived quantity is below zero — import debris from unmodeled corporate actions or rename chains, listed per depot with depot/security names plus each listed security's total quantity across ALL depots (so transfer debris, negative in one depot but positive in another, is distinguishable from a truly negative total). Quantities are Decimal strings. Self-describing: an as_of read date and a note. Repair the security's transaction history via portfolixir.transactions.*; there is no repair wizard beyond splits and nothing is changed automatically.", emptyObjectSchema, emptyObjectZ),
  tool("portfolixir.holdings.reconcile", "Reconcile external position list (read-only)", "Compare a user-supplied external position list (broker statement, depot overview) against the ledger-derived holdings — strictly read-only, nothing is stored. Each row's identifier is matched through the stable-identity ladder (ISIN incl. recorded former ISINs, then WKN / ticker+currency / name+currency with an exactly-one rule across those tiers); the response reports per matched security the matched_via tier, the exact ledger quantity, external quantity and delta as Decimal strings, plus ambiguous rows with candidates, unmatched rows, and held ledger positions absent from the list. Rows resolving to the same security are aggregated so there is never more than one delta per position. Resolve a difference by booking the missing transaction of the correct kind (buy, sell, delivery with price, transfer, dividend, ...) via portfolixir.transactions.create — balance snapshots (set_balance) and unpriced deliveries are last resorts that distort cost basis; do NOT reach for them just to make numbers match. Weak (ticker/name) matches carry a caveat: confirm the security before booking anything. Quantities must be canonical dot-decimal strings — parse locale formats (comma decimals, thousands separators) client-side before calling. Optional scope: portfolio_id or view (mutually exclusive); default is the whole instance, and the response states its basis (as_of, scope).", reconcileSchema, reconcileZ),
  tool("portfolixir.portfolios.valuation", "Value portfolio", "Live valuation of a portfolio: market values, actual weights per position, plus the base-currency portfolio total, cash balances and the cash quote (use this, not holdings.list, for base-currency totals). The valued/price_source flags mark stale or unpriceable positions, and unvalued_reason distinguishes no_price (nothing resolves) from missing_fx (a native latest_price/price_currency is known but no stored FX path reaches the base currency). Pass an optional view (a view id) to scope the result to the holdings matching that bucket view; the response then echoes the active view.", {
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
    "Upsert target weights for one portfolio and classification. Each target_weight is a string fraction in [0,1]. A target entry with only a category_id sets that category's weight; adding a security_id (ADR-0030, #481) sets a position-level weight on that security under the category (the security must sit under it). Category and position rows coexist; a category's effective target rolls up from its positions. A plan carries at most one position row per security (filing it under a second category, or twice in one batch, is rejected). Weight sums are NOT enforced in this slice — neither per category nor per level (the 100%-per-level check is a later slice), so verify sums yourself if they matter.",
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
    "portfolixir.targets.list_positions",
    "List position targets",
    "List a portfolio's position-level SOLL targets (ADR-0030, #481): a target_weight (string fraction in [0,1]) per individual security under a category, plus each affected category's effective roll-up (explicit weight, position sum, effective steering weight and a conflict flag surfacing an explicit/position mismatch). Sums are NOT enforced in this slice (the 100%-per-level check is a later slice), so a category's position sum may not match its explicit weight or 1. Each position row carries security_id, security_name and a stale flag — true when its security no longer sits under the stored category (reclassified or unassigned); the row still counts where it was filed, so react to stale rows by re-filing them (delete_position + set under the current category). The roll-up carries has_stale per category. Optional classification_id scopes to one tree; optional view (a view id) selects that view's plan.",
    positionTargetsListSchema,
    positionTargetsListZ
  ),
  tool(
    "portfolixir.targets.delete_position",
    "Delete position target",
    "Remove a portfolio's position-level SOLL target for one security under a category (ADR-0030, #481). The category target and the category's other positions are left in place.",
    positionTargetDeleteSchema,
    positionTargetDeleteZ
  ),
  tool(
    "portfolixir.portfolios.allocation",
    "Portfolio allocation drift",
    "SOLL/IST allocation breakdown for a portfolio against one classification: market value, actual weight, target weight and drift per category plus a cash row, in one call. Drift is actual - target (positive = overweight, i.e. reduce to reach the target; ADR-0023), as a weight and restated in base currency. Category targets are the EFFECTIVE targets (ADR-0030): when the plan carries position-level SOLL rows their sum steers the category — conflict flags a diverging explicit category weight, has_stale a stale position row. Each category's positions are the union of its held positions and the plan's position SOLL rows: each row carries quantity, target_weight (its position SOLL, null when none), drift_weight (actual - target), held, drift_value and rebalance_quantity (indicative units to sell (positive) or buy (negative)) — display-only hints, never an order. A position with SOLL > 0 that is not yet held appears with IST 0 (held=false) and its hint priced at the latest stored quote (null without a price); quote_date names that quote's date (null when the hint is not quote-based), and held means holdings presence — an unpriceable held security is never reported as unheld. A row is hidden only when its SOLL is 0/absent and holdings are zero; stale=true marks a row whose SOLL row no longer matches the security's current category (it keeps counting where it was filed). Unassigned entries attach their position SOLL too, and deep_target_sum reports the effective targets steered below an untargeted top level. Rows without their own SOLL keep the category-share drift_value/rebalance_quantity at the valuation's implied unit price. The 100% basis is securities + counting cash. Pass an optional view (a view id) to scope the breakdown to the holdings matching that bucket view; the response then echoes the active view. For the raw position-target rows and per-category roll-up (the maintenance view) use portfolixir.targets.list_positions.",
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
    "Record an absolute cash-balance snapshot for one account (the current balance as of a date), instead of mirroring every booking. amount is a Decimal string and may be negative. When a reconciliation shows a difference, prefer booking the missing transaction of the correct kind — balance snapshots (and unpriced inbound deliveries) are last resorts: they make the balance look right while hiding what actually happened and distorting cost basis.",
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
    "Time-weighted (ttwror) and money-weighted (irr) rate of return for a portfolio over a period (ytd, 1y, 3y, 5y, max — default max; or year=YYYY for one calendar year, or from/to ISO dates for a custom range clamped to the available history). TTWROR neutralises external cash flows the Portfolio Performance way; IRR is the annualised money-weighted return solved from the same dated flows and is a Decimal string or null when no rate exists (no sign change / no convergence). Set series=true to include the daily valuation series. Pass an optional view (a view id) to scope the series to the holdings matching that bucket view; the response then echoes the active view.",
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
    "Live valuation of a bucket view across ALL portfolios (id is the view id): the deduplicated union of every depot, position and cash account matching the view — an account tagged into several included buckets counts exactly once. Totals, weights, cash balances and the cash quote are in EUR (converted via the EUR hub); the valued/price_source flags mark stale or unpriceable positions and unvalued_reason distinguishes no_price from missing_fx, exactly as in portfolixir.portfolios.valuation. The overlap object lists the depots/cash accounts carrying more than one included bucket (badge data — the totals are already deduplicated). matches_no_accounts is true when the view's resolution matches no account at all (an empty include set or orphaned buckets), explaining a 0 total. All financial values are Decimal strings. Use this, not a client-side sum of portfolio valuations, for a view's total wealth.",
    idSchema,
    idZ
  ),
  tool(
    "portfolixir.views.performance",
    "View performance (cross-portfolio TTWROR + IRR)",
    "True time-weighted return (TTWROR) and money-weighted IRR of a bucket view across ALL portfolios (id is the view id): the same deduplicated account scope as portfolixir.views.valuation, so the view's total and its return always cover the same accounts. Money crossing the view boundary counts as an external flow (a deposit/withdrawal to the slice); money moving between two in-scope accounts nets out. period is ytd|1y|3y|5y|max (default max), or year=YYYY for one calendar year, or from/to ISO dates for a custom range; series=true adds the daily points. All financial values are Decimal strings.",
    viewPerformanceSchema,
    viewPerformanceZ
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
  ),
  tool(
    "portfolixir.plans.list",
    "List plan versions",
    "List a portfolio's SOLL plan versions (ADR-0027): active first, then drafts and archived plans, each with name, status, scope (view_id, classification_id) and the cash target weight as a string fraction. Optional classification_id scopes to one tree. Use this before duplicating or activating a plan.",
    plansListSchema,
    plansListZ
  ),
  tool(
    "portfolixir.plans.duplicate",
    "Duplicate a plan into a draft",
    "Copy a plan version (its category target weights and cash target) into a new DRAFT of the same scope. Optional name (default: '<source> (copy)'). The active plan keeps steering the allocation until the draft is activated - use this to prepare a restructured plan next to the current one.",
    planDuplicateSchema,
    planDuplicateZ
  ),
  tool(
    "portfolixir.plans.activate",
    "Activate a plan version",
    "Make a draft or archived plan version the ACTIVE plan of its scope; the previously active plan is archived in the same transaction, so a scope always has at most one active plan. Activating the already-active plan is a no-op.",
    planIdSchema,
    planIdZ
  ),
  tool(
    "portfolixir.plans.rename",
    "Rename a plan version",
    "Rename one plan version (any status). Names are free text up to 120 characters.",
    planRenameSchema,
    planRenameZ
  ),
  tool(
    "portfolixir.plans.delete",
    "Delete a plan version",
    "Delete one plan version by id (any status) including its category targets - the cleanup path for drafts and archived plans. Deleting the active plan leaves its scope without a plan (the allocation falls back to actual-only).",
    planIdSchema,
    planIdZ
  ),
  tool(
    "portfolixir.snapshots.list",
    "List depot snapshots",
    "List depot snapshot markers (ADR-0027): each is a name, a view scope (view_id null = everything) and an as-of date. A snapshot copies no data - the holdings it represents derive from the transaction ledger on demand.",
    snapshotsListSchema,
    snapshotsListZ
  ),
  tool(
    "portfolixir.snapshots.create",
    "Create a depot snapshot",
    "Freeze 'the holdings of a scope as of a date' as a named marker (no data copied; the ledger stays the single source). as_of is an ISO date not in the future; names are unique per scope. Create one before restructuring a strategy, then compare later with portfolixir.snapshots.comparison.",
    snapshotCreateSchema,
    snapshotCreateZ
  ),
  tool(
    "portfolixir.snapshots.delete",
    "Delete a depot snapshot",
    "Delete one snapshot marker. No transactions or holdings are affected - the marker only referenced them.",
    snapshotIdSchema,
    snapshotIdZ
  ),
  tool(
    "portfolixir.snapshots.comparison",
    "Snapshot counterfactual comparison",
    "Answer 'would I have done better keeping what I had?': values the snapshot's frozen holdings buy-and-hold over the real stored quote history (daily, EUR-hub FX) and compares against the scope's real TTWROR since the as-of date. Gross, price-return only (v1); all financial values are Decimal strings; the response is self-describing (basis, base_currency) and lists securities excluded for missing quotes/FX under gaps.",
    snapshotComparisonSchema,
    snapshotComparisonZ  ),
  tool(
    "portfolixir.tax_parameters.list",
    "List statutory tax parameters",
    "List the year-scoped German statutory tax parameters (ADR-0031): capital-gains and solidarity rates, and the Sparer-Pauschbetrag ceilings for single and joint assessment. Rates are Decimal string FRACTIONS ('0.25', not '25'). Seeded 2009-2026; a year with no row is absent rather than approximated - never substitute a neighbouring year's ceiling.",
    taxParametersListSchema,
    taxParametersListZ
  ),
  tool(
    "portfolixir.tax_parameters.upsert",
    "Record statutory tax parameters for a year",
    "Insert or replace the statutory parameters of one tax year. Use this only when the law for a year is known and missing (e.g. a newly legislated year); the built-in German history is already seeded. Rates are Decimal string fractions in [0,1).",
    taxParametersUpsertSchema,
    taxParametersUpsertZ
  ),
  tool(
    "portfolixir.tax_profiles.list",
    "List taxpayer profiles",
    "List a holder's effective-dated tax profiles, newest valid_from first. The profile in force for a date is the one with the greatest valid_from at or before it - never an exact match. Church-tax liability defaults to NOT liable with rate 0.",
    taxHolderSchema,
    taxHolderZ
  ),
  tool(
    "portfolixir.tax_profiles.create",
    "Record a taxpayer profile from a date",
    "Record the taxpayer situation in force from valid_from: church-tax liability and rate, and single/joint assessment (which selects the Sparer-Pauschbetrag ceiling). Effective-dated on purpose - a new row never rewrites what an already-recorded statement reconstructs to. A non-zero church_tax_rate on a not-liable profile is rejected.",
    taxProfileCreateSchema,
    taxProfileCreateZ
  ),
  tool(
    "portfolixir.tax_profiles.update",
    "Correct a taxpayer profile",
    "Correct one profile row. To record a CHANGE in the taxpayer's situation, create a new row with a later valid_from instead - editing rewrites history, adding does not.",
    taxProfileUpdateSchema,
    taxProfileUpdateZ
  ),
  tool(
    "portfolixir.tax_profiles.delete",
    "Delete a taxpayer profile",
    "Delete one profile row by id. Snapshots already recorded keep the church-tax rate frozen on them and are unaffected.",
    taxProfileIdSchema,
    taxProfileIdZ
  ),
  tool(
    "portfolixir.allowance_orders.list",
    "List configured Freistellungsauftraege",
    "List the Freistellungsauftraege the taxpayer INSTRUCTED, per holder, institution and tax year. This is the instruction side; what the bank actually applied is recorded on the statement snapshot. Filters fold case, so 'comdirect' and 'Comdirect' are the same institution.",
    allowanceOrdersListSchema,
    allowanceOrdersListZ
  ),
  tool(
    "portfolixir.allowance_orders.put",
    "Record a configured Freistellungsauftrag",
    "Record or replace the instructed allowance for one (holder, institution, tax_year). amount_granted is a non-negative Decimal string. Recording the same triple again updates it - identity folds case, so it never silently becomes a second order.",
    allowanceOrderPutSchema,
    allowanceOrderPutZ
  ),
  tool(
    "portfolixir.allowance_orders.delete",
    "Delete a configured Freistellungsauftrag",
    "Delete one configured allowance order by id.",
    allowanceOrderIdSchema,
    allowanceOrderIdZ
  ),
  tool(
    "portfolixir.tax_snapshots.list",
    "List recorded tax statements",
    "List recorded broker tax statements (Verlustverrechnungstoepfe / Freistellungsauftrag block), newest as-of first. THESE POTS ARE RECORDED, NOT DERIVED. Note carefully WHY, because the obvious objection is wrong: Portfolixir DOES match lots FIFO (see portfolixir.trades.list), so the missing piece is not the cost method. It is that Teilfreistellung, Vorabpauschale, chronological allowance consumption and certified prior-year carry-forward are not in the transaction data at all, and that the pots are kept per tax-reporting institution, which Portfolixir does not model. FIFO gives you a GROSS GAIN; a gross gain is not a tax pot. So do NOT try to compute these from holdings or from trades - read the recorded statement. Each row carries allowance_remaining, tax_free_trim_budget, its as_of basis, a stale flag and the advisory consistency findings. All money values are Decimal strings.",
    taxSnapshotsListSchema,
    taxSnapshotsListZ
  ),
  tool(
    "portfolixir.tax_snapshots.get",
    "Read one recorded tax statement",
    "Read one recorded statement by id with its derived figures (allowance_remaining, tax_free_trim_budget), its as_of basis, staleness, and the advisory findings. A finding names the recorded and the expected number and the gap; it never proposes a corrected value.",
    taxSnapshotIdSchema,
    taxSnapshotIdZ
  ),
  tool(
    "portfolixir.tax_snapshots.create",
    "Record a tax statement",
    "Transcribe the tax block of a broker statement for one (institution, holder, tax_year, as_of). Every money field is a POSITIVE MAGNITUDE Decimal string - a loss pot is the volume of loss available for offsetting, NOT the negative number the statement prints; a negative input is rejected rather than silently flipped. as_of must not be in the future. Omit church_tax_rate to take the holder's profile in force at as_of, which is then frozen on the row. Arithmetic advisories come back in the response and never block the write.",
    taxSnapshotCreateSchema,
    taxSnapshotCreateZ
  ),
  tool(
    "portfolixir.tax_snapshots.update",
    "Correct a recorded tax statement",
    "Correct a recorded statement in place - the case of a re-issued statement for the same position date. Same magnitude rules as create.",
    taxSnapshotUpdateSchema,
    taxSnapshotUpdateZ
  ),
  tool(
    "portfolixir.tax_snapshots.delete",
    "Delete a recorded tax statement",
    "Delete one recorded statement by id.",
    taxSnapshotIdSchema,
    taxSnapshotIdZ
  ),
  tool(
    "portfolixir.tax_snapshots.trim_budget",
    "Tax-free trim budget for a holder and year",
    "The volume of realised EQUITY gain still free of Kapitalertragsteuer, rolled up across institutions for one holder and tax year: the latest statement per institution, its equity loss pot plus its remaining allowance. Always read the as_of and the coverage before acting on it - the figure decays without any action by the maintainer (dividends and interest consume the allowance chronologically), and complete=false with missing_institutions lists banks that have a configured allowance order but no recorded statement, so the total is a partial picture. This is a DECISION INPUT, never an instruction: nothing here creates, stores or transmits an order.",
    taxTrimBudgetSchema,
    taxTrimBudgetZ
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
  // Validate here, not only in the SDK layer: guards like the delivery-price
  // rule must hold for every caller of callTool, and a zod failure must
  // surface BEFORE any API request is made.
  const definition = toolDefinitions.find((tool) => tool.name === name);
  const parsedArgs = definition
    ? (definition.zodSchema.parse(args ?? {}) as Record<string, any>)
    : (args ?? {});
  const payload = await apiCall(client, name, parsedArgs);

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
          "projection",
          "limit",
          "offset"
        ])
      );
    case "portfolixir.securities.get":
      return client.request("GET", `/api/v1/securities/${args.id}`);
    case "portfolixir.securities.create":
      return client.request("POST", "/api/v1/securities", { security: args.security });
    case "portfolixir.securities.isin_change":
      return client.request("POST", `/api/v1/securities/${args.security_id}/isin-change`, {
        isin_change: isinChangeBody(args)
      });
    case "portfolixir.securities.delete_isin_alias":
      return client.request(
        "DELETE",
        `/api/v1/securities/${args.security_id}/identifier_aliases/${args.alias_id}`
      );
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
    case "portfolixir.splits.preview":
      return client.request("POST", "/api/v1/splits/preview", splitRequestBody(args));
    case "portfolixir.splits.create":
      return client.request("POST", "/api/v1/splits", splitRequestBody(args));
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
    case "portfolixir.holdings.negative":
      return client.request("GET", "/api/v1/holdings/negative");
    case "portfolixir.holdings.reconcile":
      return client.request("POST", "/api/v1/holdings/reconcile", reconcileBody(args));
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
    case "portfolixir.targets.list_positions":
      return client.request(
        "GET",
        withQuery(`/api/v1/portfolios/${args.portfolio_id}/position_targets`, args, [
          "classification_id",
          "view"
        ])
      );
    case "portfolixir.targets.delete_position":
      return client.request(
        "DELETE",
        withQuery(
          `/api/v1/portfolios/${args.portfolio_id}/position_targets/${args.category_id}/${args.security_id}`,
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
          "year",
          "from",
          "to",
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
    case "portfolixir.views.performance":
      return client.request(
        "GET",
        withQuery(`/api/v1/views/${args.id}/performance`, args, [
          "period",
          "year",
          "from",
          "to",
          "series"
        ])
      );
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
    case "portfolixir.plans.list":
      return client.request(
        "GET",
        withQuery(`/api/v1/portfolios/${args.portfolio_id}/plans`, args, ["classification_id"])
      );
    case "portfolixir.plans.duplicate":
      return client.request(
        "POST",
        `/api/v1/plans/${args.plan_id}/duplicate`,
        args.name !== undefined ? { name: args.name } : {}
      );
    case "portfolixir.plans.activate":
      return client.request("POST", `/api/v1/plans/${args.plan_id}/activate`, {});
    case "portfolixir.plans.rename":
      return client.request("PATCH", `/api/v1/plans/${args.plan_id}`, { name: args.name });
    case "portfolixir.plans.delete":
      return client.request("DELETE", `/api/v1/plans/${args.plan_id}`);
    case "portfolixir.snapshots.list":
      return client.request("GET", "/api/v1/snapshots");
    case "portfolixir.snapshots.create":
      return client.request("POST", "/api/v1/snapshots", {
        name: args.name,
        as_of: args.as_of,
        ...(args.view_id !== undefined ? { view_id: args.view_id } : {})
      });
    case "portfolixir.snapshots.delete":
      return client.request("DELETE", `/api/v1/snapshots/${args.snapshot_id}`);
    case "portfolixir.snapshots.comparison":
      return client.request(
        "GET",
        `/api/v1/portfolios/${args.portfolio_id}/snapshots/${args.snapshot_id}/comparison`
      );
    case "portfolixir.tax_parameters.list":
      return client.request(
        "GET",
        withQuery("/api/v1/tax/parameters", args, ["jurisdiction"])
      );
    case "portfolixir.tax_parameters.upsert":
      return client.request("PUT", "/api/v1/tax/parameters", {
        parameters: { jurisdiction: "DE", ...args }
      });
    case "portfolixir.tax_profiles.list":
      return client.request("GET", withQuery("/api/v1/tax/profiles", args, ["holder"]));
    case "portfolixir.tax_profiles.create":
      return client.request("POST", "/api/v1/tax/profiles", { profile: args });
    case "portfolixir.tax_profiles.update":
      return client.request("PATCH", `/api/v1/tax/profiles/${args.profile_id}`, {
        profile: withoutKeys(args, ["profile_id"])
      });
    case "portfolixir.tax_profiles.delete":
      return client.request("DELETE", `/api/v1/tax/profiles/${args.profile_id}`);
    case "portfolixir.allowance_orders.list":
      return client.request(
        "GET",
        withQuery("/api/v1/tax/allowance_orders", args, ["holder", "institution", "tax_year"])
      );
    case "portfolixir.allowance_orders.put":
      return client.request("PUT", "/api/v1/tax/allowance_orders", { allowance_order: args });
    case "portfolixir.allowance_orders.delete":
      return client.request(
        "DELETE",
        `/api/v1/tax/allowance_orders/${args.allowance_order_id}`
      );
    case "portfolixir.tax_snapshots.list":
      return client.request(
        "GET",
        withQuery("/api/v1/tax/statement_snapshots", args, [
          "holder",
          "institution",
          "tax_year"
        ])
      );
    case "portfolixir.tax_snapshots.get":
      return client.request("GET", `/api/v1/tax/statement_snapshots/${args.snapshot_id}`);
    case "portfolixir.tax_snapshots.create":
      return client.request("POST", "/api/v1/tax/statement_snapshots", {
        statement_snapshot: args
      });
    case "portfolixir.tax_snapshots.update":
      return client.request("PATCH", `/api/v1/tax/statement_snapshots/${args.snapshot_id}`, {
        statement_snapshot: withoutKeys(args, ["snapshot_id"])
      });
    case "portfolixir.tax_snapshots.delete":
      return client.request("DELETE", `/api/v1/tax/statement_snapshots/${args.snapshot_id}`);
    case "portfolixir.tax_snapshots.trim_budget":
      return client.request(
        "GET",
        withQuery("/api/v1/tax/trim_budget", args, ["holder", "tax_year"])
      );
    default:
      throw new Error(`Unknown Portfolixir MCP tool: ${name}`);
  }
}

function withoutKeys(
  args: Record<string, any>,
  keys: string[]
): Record<string, unknown> {
  const rest: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(args)) {
    if (!keys.includes(key)) rest[key] = value;
  }
  return rest;
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

function isinChangeBody(args: Record<string, any>): Record<string, unknown> {
  const body: Record<string, unknown> = { new_isin: args.new_isin };
  if (args.changed_on !== undefined) body.changed_on = args.changed_on;
  if (args.note !== undefined) body.note = args.note;
  return body;
}

function reconcileBody(args: Record<string, any>): Record<string, unknown> {
  const body: Record<string, unknown> = { rows: args.rows };
  if (args.portfolio_id !== undefined) body.portfolio_id = args.portfolio_id;
  if (args.view !== undefined) body.view = args.view;
  return body;
}

function splitRequestBody(args: Record<string, any>): Record<string, unknown> {
  return {
    security_id: args.security_id,
    date: args.date,
    ratio_numerator: args.ratio_numerator,
    ratio_denominator: args.ratio_denominator
  };
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
