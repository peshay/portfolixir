# Sprint 9 Retrospective — the knowledge batch, and the debt the agent round left behind (2026-09-03)

**Status: written at close-out.** PR #754 was rebase-merged 2026-09-03
(20:24 UTC), 17 commits linear on `main`, head `6de32ff`. The annotated
`0.9.0` tag is **prepared as an owner action** — the session's git proxy
refused the tag push again, as it did for 0.8.0; command under "Close-out
ledger". Planned, built, reviewed and merged on the day ADR-0044 was signed.

## What shipped

One batch on one branch, one PR (#754), per the adopted plan
(sprint-plan-2026-09-03-sprint9.md, D-1 signed on adoption in #753). Ten
issues closed by the merge's keywords, verified against the post-merge
open-issue list: #747 #748 #749 #750 #751 #752 #740 #741 #738 #737. Nothing
in the shrink order was cut.

- **Lane A — E20, the knowledge batch (ADR-0044):** `security_notes` as an
  append-only log, refused UPDATE/DELETE/TRUNCATE at the database and
  journal-armed in its first migration (the signed §5 clause); the thesis
  state as a pure projection carried in the security read; append and the
  four reads of §7 over API and MCP with no update and no delete, by design;
  the Research tab on the security detail pane in the same batch (the signed
  §6 clause), superseded entries shown as superseded and retractions legible;
  the contract-version read with a meta-test that ties the router and the MCP
  tool inventory to the manifest in both directions.
- **Lane B — the agent-round debt:** #740 closed the FR-37 surface gap on the
  view valuation and the position-target listing through one parser and one
  predicate; #741 stated the re-import preservation guarantee (now covering
  the research log) where an agent and an operator read; #738 levelled the
  README with the product documentation.
- **Lane C — the historical FX gap (#737, D-1):** the historical ECB series
  as a one-shot backfill through the existing sync path, `scope=history` on
  endpoint and tool, and a live control inside all three Cash-flow exclusion
  notes. On the Sprint 8 D-1 fixture `excluded.count` went 1 → 0 with the
  exact Decimal; the basis statement did not move.
- **Lane M:** the three applicable Dependabot rows as their own commits and
  the bot PRs closed with pointers; `@types/node` declined major-wide in
  `dependabot.yml`; patch rows for phoenix_live_view, req, ecto, tsx, zod;
  #727 re-checked against excoveralls 0.18.5, Elixir 1.20.4 and ecto 3.14.2 —
  no trigger fired. `version-report-2026-09-03.md` written at lane time.
- **Lane Z:** E20 in the Tracker Index and `sprint-status.yaml` when the
  branch opened; the surface-check clause in AGENTS.md step 5 and its first
  use in the briefing; `Portfolixir.Knowledge` in the Active Architecture.

## Agentic review closing act — what it caught

The three parallel review agents (correctness, edge cases, risk-tier/docs)
were cut off by a session limit before reporting, so the pass ran as a
verified self-review against the rubric, section by section, and stated so
on the PR. Conditions per section G, stated in
`uat-sprint9-2026-09-03/walkthrough.md`: DE locale, one full pass at 390 px,
a synthetic seed that fired every touched alarm surface. Findings:

1. **`source_url` accepted any string** and is rendered as an anchor on the
   timeline and handed to an agent as a source. Fixed: http(s) only at the
   changeset, `javascript:`/`data:` are a 422; documented EN/DE.
2. **Patch coverage 81.7 % against the 90 % target** — the first CI run's
   only red check. Fixed with tests for the parameter edge cases, the
   retracted state and markers, the backfill that misses its date, the flows
   and costs controls, the ECB history fetch through Req's plug adapter and
   the sync endpoint's 502/422 contract; two dead clauses removed. 93.96 % on
   the merged head.
3. **Design critic, DE at 390 px:** the fact grids under a thesis and an
   entry overran with the long German label. Fixed: stacked below 480 px,
   labels wrap. Folded into the #751 commit.
4. A history-fetch option merge that would have dropped the longer timeout
   when a caller passed Req overrides. Fixed.

## What worked

- **The signed gate went first and stayed the ADR's scope.** Five issues cut
  against ADR-0044 the day it was signed, built in the ADR's own order, the
  contract read last so its first entry names the batch's additions. Nothing
  was re-litigated.
- **The codecov patch check did its job** — it is the one gate that can fail
  after every other gate is green, and it named the files. The tests it
  provoked found nothing wrong but pinned the edge cases that a later change
  would otherwise silently break.
- **Meta-tests as the contract:** the router/tool inventory test for the
  manifest, the docs test that names every route and tool, the armed-table
  set, the append-only unboxed test — each caught a surface addition before
  it was documented, which is exactly the failure ADR-0044 §8 was written
  against.

## What to carry forward

1. **Review agents need a budget check before they are spawned.** Three
   sub-agents started at once against a session limit and all three died
   before reporting. The rubric allows a self-review, and it was run and
   stated, but the multi-role review is the ADR-0026 default; a closing act
   should confirm headroom (or run the roles sequentially) before fanning
   out.
2. **The tag push is blocked for the session for the third sprint.** The
   prepared-command path works and the Lane Z guard reports a lightweight
   tag, so the mechanism holds; but three repetitions are a pattern, not an
   incident. A follow-up worth filing: allow the designated-branch proxy to
   push annotated tags on `main`'s head, or move the tag into the Release
   workflow behind an owner dispatch.
3. **The demo seed assumes a portfolio name.** `priv/demo/strategies_seed.exs`
   raises unless the portfolio is called "Demo Depot" — the import creates it
   under the export's name. Small, but it cost a walkthrough round; a
   follow-up to make the seed find the first portfolio.
4. **The branch name deviates from the epic-batch shape** (`claude/...`
   instead of `agent/claude/<slug>`), for the same session-proxy reason as
   #753. Harmless for a rebase-merge; worth settling once in AGENTS.md rather
   than explaining per PR.

## Close-out ledger

- Merge: PR #754, rebase-merge, `main` at `6de32ff` (17 commits linear on
  8771702), 2026-09-03 20:24 UTC.
- CI on the merge push: run 1467 (CI) and run 481 (Commit authorship) on
  `6de32ff` — verified before this entry was pushed.
- Issues: ten closed by keyword (list above); #747 (the E20 tracker) among
  them. Stays open with a reason: #727 (both toolchain halves blocked
  upstream; triggers re-checked this lane, none fired).
- Registry: `epics.md` FR Coverage Map (FR-37 row: #740 shipped; FR-45 row:
  shipped, E20), a dated reconciliation section, the E20 Tracker Index line
  (opened with the branch); `sprint-status.yaml` epic-20 done, this entry.
- Two-way coverage check: every agent-visible capability of this batch (the
  research log and its reads, the contract read, the backfill scope, the two
  parameters) shipped with its human view in the same batch. The ledger stays
  empty.
- Surface check (AGENTS.md step 5, first use): `include_positions` is carried
  by `GET /portfolios/:id/valuation`, `GET /portfolios/:id/allocation`,
  `GET /views/:id/valuation`; `min_drift` by `GET /portfolios/:id/allocation`
  and `GET /portfolios/:id/position_targets`; `fields=` by transactions,
  holdings, securities; `since=` by transactions, securities and the contract
  read. Every read of these families carries its parameter.
- Tag: **`0.9.0` is an OPEN OWNER ITEM.** Created locally as an annotated
  tag on `6de32ff`; the push was refused by the session's git proxy. The
  prepared command, to run on a checkout of `main`:

  ```bash
  git fetch origin main
  git tag -a 0.9.0 6de32ff134fc36fc6bbd9766332c2dd4425da907 -m "0.9.0 — Sprint 9: the knowledge batch (ADR-0044, E20), the agent-round debt, the historical FX backfill"
  git push origin 0.9.0
  ```

  The tag push triggers the Release workflow, which creates release 0.9.0
  with generated notes and reports the tag's object type in the body.
- Version report: `version-report-2026-09-03.md` (written at lane time).
