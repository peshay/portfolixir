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
5. Run public artifact guard checks.
6. Open a PR with a short story summary.

## Public artifact guard

This repository enforces a local and CI guard for GitHub-visible text artifacts.

```bash
pre-commit install --install-hooks
pre-commit run --all-files
```

If the guard fails:

1. Remove internal paths/metadata, leaked prompt/process text, or obvious secrets from the flagged files.
2. Replace literal escaped backslash-n sequences with real line breaks in public-facing text/templates/scripts.
3. Rerun `pre-commit run --all-files` until it passes.

## Public commit and merge metadata

GitHub-visible commit and merge metadata must stay repo-facing. Before opening or merging a PR:

- Use public-safe author and co-author identities. Do not use local-only email domains.
- Keep commit bodies and merge messages to the story summary, constraints respected, tests run, and follow-up tasks.
- Do not include private agent identity, model/runtime identifiers, hostnames, workspace paths, prompt/process text, or board-only metadata in commit messages, merge messages, PR bodies, or release notes.
- If GitHub suggests a merge message containing private metadata, rewrite it before merge. If an already-published commit needs history rewriting or branch deletion to hide metadata, stop and get explicit maintainer approval first.

The CI public artifact guard scans PR commit metadata as well as repository files. It allows only `Worker-Model` and `Worker-Thinking` worker traceability footers, and fails unsafe author/co-author data or any other private metadata before merge.

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
- [ ] Commit, co-author, and merge-message text are public-safe.

## Commit style

Use concise conventional commits:

```text
feat(taxonomies): add category descriptions
feat(ledger): record buy transactions
fix(market-data): avoid atom creation from symbols
chore(ci): add coverage threshold
```
