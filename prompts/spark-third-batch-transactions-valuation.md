# Prompt for ChatGPT 5.3 Codex Spark — Third Batch

Use this only after PFX-000 through PFX-009 are green.

You are working on Portfolixir.

Read first:

- AGENTS.md
- docs/product/initial-user-stories.md
- docs/adr/0002-domain-model.md

Goal:
Implement exactly this batch, in order:

1. PFX-010 — Latest quote provider behaviour
2. PFX-011 — Store latest quotes
3. PFX-012 — Record buy transactions
4. PFX-013 — Position calculation from buy history
5. PFX-014 — Portfolio valuation from latest quotes

Scope lock:

- Do not implement sell transactions yet.
- Do not implement FX conversion except returning explicit missing-FX for mismatched currencies.
- Do not implement dashboard UI unless tests require it.
- Do not make real HTTP calls.
- Do not implement TTWROR or IRR.
- Do not implement MCP/LLM features.

TDD requirements:

For each story:

1. Write tests first.
2. Show the failing test.
3. Implement minimal code.
4. Show passing tests.

Financial rules:

- Use `Decimal` for quantity, price, amount, fees and taxes.
- Persist financial values as decimal fields.
- Do not use floats for persisted values.
- Tests must assert exact Decimal values where practical.

Commands:

```bash
mix format
mix test
```

Final response must include completed stories, tests, commands and files changed.
