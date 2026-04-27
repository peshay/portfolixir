# Prompt for ChatGPT 5.3 Codex Spark — First Batch

You are working on Portfolixir.

Read these files first:

- README.md
- AGENTS.md
- CONTRIBUTING.md
- docs/adr/0001-tech-stack.md
- docs/adr/0002-domain-model.md
- docs/adr/0003-market-data-strategy.md
- docs/adr/0004-testing-and-coverage.md
- docs/process/tdd-policy.md
- docs/process/definition-of-done.md
- docs/product/initial-user-stories.md

Goal:
Implement exactly this first batch, in order:

1. PFX-000 — Bootstrap Phoenix app
2. PFX-001 — Health endpoint
3. PFX-002 — Currency catalogue
4. PFX-003 — Portfolio with base currency
5. PFX-004 — Category taxonomies and category descriptions

Scope lock:

- Do not implement securities yet.
- Do not implement market data yet.
- Do not implement buy transactions yet.
- Do not implement valuation yet.
- Do not implement MCP/LLM features.
- Do not add TimescaleDB or InfluxDB.
- Do not add external provider calls.
- Do not add real financial data.
- Do not build more UI than necessary.

TDD requirements:

For each story:

1. Write the test first.
2. Run the test and show that it fails for the expected reason.
3. Implement the smallest possible change.
4. Run the test and show that it passes.
5. Move to the next story only after the previous story is green.

Technical requirements:

- Use Elixir/Phoenix and PostgreSQL/Ecto.
- Use `Decimal` where financial values appear.
- Use string codes for currencies.
- Do not create atoms from external input.
- Keep contexts clean:
  - `Portfolixir.Catalog` for currencies
  - `Portfolixir.Portfolios` for portfolios
  - `Portfolixir.Taxonomies` for taxonomies/categories
- Prefer generated Phoenix context code only if it stays clean and testable.
- Keep the app as a modular monolith.

Expected output:

- Working Phoenix app.
- `GET /health` endpoint.
- Currency schema/context/tests.
- Portfolio schema/context/tests.
- Taxonomy/category schema/context/tests.
- All tests passing.

Commands to run if available:

```bash
mix format
mix test
```

Final response must include:

- stories completed
- tests added
- commands run
- files changed
- any follow-up issues

Do not claim production readiness.
