# Contributing to Portfolixir

Portfolixir is built story-by-story with tests first.

## Local setup

After the Phoenix app has been bootstrapped:

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

## Development workflow

1. Pick one user story.
2. Write acceptance tests first.
3. Implement the smallest possible change.
4. Run the quality gate.
5. Open a PR with a short story summary.

## Branch naming

```text
story/PFX-004-category-descriptions
fix/PFX-007-symbol-search-provider
chore/quality-gate
```

## PR checklist

- [ ] Tests were written before implementation.
- [ ] No real financial data was added.
- [ ] No external network calls are used in tests.
- [ ] Financial values use `Decimal`.
- [ ] No atoms are created from external input.
- [ ] The story scope was not exceeded.
- [ ] Commands run are listed in the PR.

## Commit style

Use concise conventional commits:

```text
feat(taxonomies): add category descriptions
feat(ledger): record buy transactions
fix(market-data): avoid atom creation from symbols
chore(ci): add coverage threshold
```
