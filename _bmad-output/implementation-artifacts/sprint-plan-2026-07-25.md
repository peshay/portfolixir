# Sprint Plan — 2026-07-25

Companion to `sprint-status.yaml`. That file tracks epic/story state; this one
sequences the open GitHub issues, which is where the actual work lives for
epics 1–5 and 7–16 (they carry no story breakdown — their unit is the issue,
per the FR Coverage Map in `epics.md`).

Ground truth: `main` at `ff4d809`. Status was verified against code, not taken
from issue labels.

> **Revised the same day.** The first cut of this plan was written against
> `224f442` and led with `#545`. Two merges landed within the hour and changed
> the sprint: `#611` fixed `#545` (with the ADR-0010 amendment), and `#612` was
> signed off, unblocking Epic 19. The earlier finding that "`#545` is unfixed
> and `#610` rests on a premise that does not hold" was **wrong** — it came from
> checking issues and locally-fetched branches without checking open pull
> requests, where `#611` was already sitting. Both are corrected below.

## Where the project actually stands

**Done and merged:** E5 (analytics engine), E6 (LLM/MCP surface — the DX batch
`#581`–`#585`), E12 (localization/docs), E13 (buckets & views), E14 (CSS/design
system), E15 (view-bound SOLL plans), E16 (plan versions & depot snapshots),
E17 (corporate actions — `#588`–`#591`), E18 (stable identities & re-import
survival — `#600`–`#602`, `#605`).

**Just landed (2026-07-25):**

- `#611` → **`#545` fixed**. Trade-price basis steps no longer enter the return
  base: `r_d = V_d / (V_{d−1} + F_d + B_d) − 1`, with `B_d` gated on price
  provenance and measured by replaying the day. ADR-0010 gained the
  *Amendment (2026-07-24): trade-price basis steps are not return*. The
  synthetic four-year fixture that chained to **+2,567.5 %** is now the
  regression guard.
- `#613` → **ADR-0031 merged** (`629b222`), and **`#612` signed off**. Epic 19
  stories 19.2–19.6 are unblocked. Note the ADR document itself still reads
  `Status: Proposed`; flipping it to `Accepted` belongs in the first
  implementation PR, together with the `AGENTS.md` Active-Architecture
  amendment for the `Portfolixir.Tax` context.

**Open with real remaining work:** E1 (`#314` coverage ratchet), E2 (`#354`
pg_dump backup), E3 (`#328` merge/rename accounts), E7 (ranked both-direction
cash guidance), E11 (UX/a11y — the largest unattached pile), E19 (now open for
implementation).

**Gated by design, do not "fix":** E4 (`#333` PP XML), E8 (`#320` sync), E9
(`#330`/`#340` product types, discovery-first), E10 (`#332` what-if simulator).

## Constraint that shapes this sprint

One reviewer. ADR-0026 makes that explicit ("the owner is one person"), and
risk-tier changes — ledger/money math, security, dependencies, import
idempotency, projection semantics — ship as **dedicated small PRs with real
human review**, never inside a batch. Three merges landed today; the reviewer
queue, not the implementation queue, is the binding constraint.

## Sprint 1 — "Build the tax epic, pay off the review debt"

### Lane A — Epic 19, one epic branch (the sprint's centre of gravity)

The gate is signed off and the design is settled, so this runs as a normal epic
batch under ADR-0026, in dependency order:

1. **19.2** — `tax_parameters` (year-scoped statutory data), `tax_profiles`
   (effective-dated, church tax defaulting to not liable), `allowance_orders`.
   Everything downstream reads these, so they go first.
2. **19.3** — record a `tax_statement_snapshot`: eleven Decimal money columns,
   positive-magnitude sign convention, journaled writes, the profile-resolved
   church-tax rate frozen on the row.
3. **19.4** — the consistency engine: two hard changeset rules, six advisories,
   the `max(1.00, 0.05 %)` band, pure engine per AR-2.
4. **19.5** — JSON API + MCP parity for all four resources (AR-11).
5. **19.6** — entry surface, EN/DE documentation.

The first PR of the batch also carries the `AGENTS.md` amendment and flips
ADR-0031 to `Accepted`.

**19.7 stays out** — forward projection and `tax_bucket` are behind their own
decision gate, by design.

### Lane B — E17/E18 review debt, one small batch

- **`#609`** — polish bundle from the E17/E18 reviews (local date boundary,
  reconcile response cosmetics, remaining confirmed findings).
- **`#607`** — scope the imports untouched-config panel so incremental imports
  do not drown the signal.

Cheapest now, while that code is still fresh. Small enough to ride alongside
Lane A without competing for review attention.

### Lane C — one dedicated PR

- **`#562`** — cache the daily TTWROR walk (currently recomputed on every
  mount). Pure performance, not risk-tier, but it must be **output-identical** —
  and it now has exactly the right proof available: the fixtures `#611` just
  added, including the `+2,567.5 %` regression case. This is the moment to do
  it, before that context goes cold.

## Decisions needed, not code

- **`#610`** — the documented residual of the `#611` fix, and its premise now
  holds. The `B_d` gate emits a basis step only for a security carrying **no
  quote from any earlier day**; that is what keeps quoted portfolios
  byte-identical, but it means a security that *was* quoted and later loses its
  feed (delisting, provider drop, ticker change) keeps booking its trade-price
  re-pricings as return. Closing it needs a **staleness rule** ("a quote older
  than N days with no newer row is not a measurement") and risks re-classifying
  legitimate off-quote days. The issue itself says it is worth doing only if
  delisted or feed-dropped holdings actually occur in practice — that is an
  owner call before any code, and it is risk-tier when it happens.
- **Close `#338` and `#603`** — E17/E18 trackers whose children are all closed
  and merged.
- **UAT pile** (`needs-uat`): `#328`, `#330`, `#332`, `#333`, `#354`, `#412`,
  `#564`. Owner time, not development capacity; listed so the sprint is honest
  about what is actually waiting.

## Explicitly out of this sprint

- **`#606`** (microcopy voice sweep) — genuinely large and cross-cutting; it
  deserves its own epic batch.
- **19.7** and everything under E4/E8/E9/E10 — gated by design.

## Sprint 2 preview

1. **`#606` microcopy sweep** as its own batch.
2. **Analytics wishlist triage** — `#563`, `#564`, `#568`, `#572`, `#577` have
   accumulated without an owning epic and need one prioritisation pass before
   any of them starts.
3. **`#610`**, if the owner decides the delisted-holdings case is real.

## Standing findings

1. **Two parallel epic structures have drifted apart.** `epics.md` defines
   E1–E19; GitHub carries a separate tracker set (`#416`–`#420`, `#470`, `#398`,
   `#356`). Roughly 20 of the open issues hang off neither. One reconciliation
   pass would make future sprint planning mechanical instead of archaeological.
2. **`#321` (roadmap index) is stale** — it indexes ~35 issues, most now closed.
   Either refresh it or retire it in favour of the epic trackers.
3. **Planning inputs must include open pull requests, not just issues.** This
   plan's first cut called `#545` unfixed while `#611` was open with the fix in
   it. An issue's state lags its PR, and `git branch -r` only shows what the
   local clone has fetched.
