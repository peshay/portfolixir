# Prompt for ChatGPT 5.3 Codex Spark — Second Batch

Use this only after PFX-000 through PFX-004 are green.

You are working on Portfolixir.

Read first:

- AGENTS.md
- docs/product/initial-user-stories.md
- docs/adr/0002-domain-model.md
- docs/adr/0003-market-data-strategy.md

Goal:
Implement exactly this batch, in order:

1. PFX-006 — Securities with symbol and currency
2. PFX-007 — Assign categories to securities
3. PFX-008 — Symbol search provider behaviour
4. PFX-009 — Store symbol candidates

Scope lock:

- Do not implement latest quotes yet.
- Do not implement buy transactions yet.
- Do not implement valuation yet.
- Do not make real HTTP calls.
- Use a fake market-data provider only.
- Do not add provider API keys.
- Do not implement MCP/LLM features.

TDD requirements:

For each story:

1. Write tests first.
2. Show the failing test.
3. Implement minimal code.
4. Show passing tests.

Technical requirements:

- Use `Portfolixir.Catalog` for securities.
- Use `Portfolixir.Taxonomies` for assignments.
- Use `Portfolixir.MarketData` for provider behaviour and symbol candidates.
- Do not create atoms from provider/user input.
- Currency must reference existing currency codes.

Expected fake provider result for `AAPL`:

```text
AAPL     Apple Inc.        NASDAQ     USD
AAPL.F   Apple Inc.        Frankfurt  EUR
AAPL.SG  Apple Inc.        Stuttgart  EUR
```

Commands:

```bash
mix format
mix test
```

Final response must include completed stories, tests, commands and files changed.
