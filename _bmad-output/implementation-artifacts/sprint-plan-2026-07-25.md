# Sprint Plan — 2026-07-25

Companion to `sprint-status.yaml`. That file tracks epic/story state; this one
sequences the **48 open GitHub issues**, which is where the actual work lives
for epics 1–5 and 7–16 (they carry no story breakdown — their unit is the issue,
per the FR Coverage Map in `epics.md`).

Ground truth: `main` at `224f442`. Status was **verified against code**, not
taken from issue labels — see Findings for two places where the two disagree.

## Where the project actually stands

**Done and merged:** E5 (analytics engine), E6 (LLM/MCP surface — the DX batch
`#581`–`#585` is fully in `mcp-server/src/tools.ts`), E12 (localization/docs),
E13 (buckets & views), E14 (CSS/design system), E15 (view-bound SOLL plans),
E16 (plan versions & depot snapshots), **E17** (corporate actions — `#588`–`#591`
merged), **E18** (stable identities & re-import survival — `#600`–`#602`, `#605`
merged).

**Open with real remaining work:** E1 (`#314` coverage ratchet), E2 (`#354`
pg_dump backup), E3 (`#328` merge/rename accounts), E7 (ranked both-direction
cash guidance), E11 (UX/a11y — the largest unattached pile), E19 (gated).

**Gated by design, do not "fix":** E4 (`#333` PP XML), E8 (`#320` sync), E9
(`#330`/`#340` product types, discovery-first), E10 (`#332` what-if simulator).

Two epics landed back to back. The cheapest work available right now is their
review debt, while the code is still fresh.

## Constraint that shapes this sprint

One reviewer. ADR-0026 makes that explicit ("the owner is one person"), and
risk-tier changes — ledger/money math, security, dependencies, import
idempotency, projection semantics — must ship as **dedicated small PRs with real
human review**, never inside a batch. So the sprint runs two lanes at different
cadences, not one queue.

## Sprint 1 — "Truthful returns, then the debt from the last two epics"

### Lane A — risk-tier, dedicated PRs, strictly sequential

**A1 · `#545` — trade-price re-pricing inflates long-period TTWROR.**
The headline wrong number in the app: a `max`-period TTWROR can read in the
thousands of percent. Verified still present — `Performance.day_factor/2`
(`lib/portfolixir/portfolios/performance.ex:761`) neutralises a day only when
`prev + flow <= 0`, so the day a new trade re-prices an entire long-held
unquoted position, that basis step enters the chain as a one-day market return
and compounds.

This needs a **decision before code**: what counts as return versus a change of
valuation basis. That is an ADR-0010 amendment, and it rides in the same PR as
the fix (the repo's ADR-with-the-change convention). Binding acceptance
criterion from the issue: **quoted-only portfolios stay byte-identical**, guarded
by a regression fixture.

**A2 · `#562` — cache the daily TTWROR walk.**
Same module, immediately after A1 while the context is loaded. Pure performance,
not risk-tier, but it must be output-identical — so it reuses A1's regression
fixtures as its own proof. Doing it before A1 would mean caching a wrong series.

### Lane B — epic batch, one branch, agentic review

**B1 · `#609` — polish bundle from the E17/E18 reviews.**
Local date boundary, reconcile response cosmetics, and the rest of the confirmed
findings that were deliberately deferred out of those PRs. Freshest possible
context; the cost only goes up from here.

**B2 · `#607` — scope the imports untouched-config panel.**
Incremental imports currently drown the signal in unchanged-config noise. Small,
self-contained, same subsystem as E18's work.

### Lane C — owner-blocked, zero dev capacity, unblocks Sprint 2

- **`#612` sign-off** (ADR-0031 on PR `#613`, CI green) → unblocks E19 stories
  19.2–19.6. This is the single highest-leverage item on the list because it
  gates a whole epic.
- **Close `#338` and `#603`** — both are E17/E18 trackers whose children are all
  closed and merged.
- **UAT pile** (`needs-uat`): `#328`, `#330`, `#332`, `#333`, `#354`, `#412`,
  `#564`. These consume owner time, not dev time; they are listed so the sprint
  is honest about what is actually waiting.

## Explicitly out of this sprint

- **`#610`** (feed-dropped securities still book trade-price steps) — its
  premise does not hold yet, see Findings. Re-scope it *after* A1 lands. The
  issue itself says it is worth doing only if delisted or feed-dropped holdings
  actually occur in practice, which is an owner call, not an automatic backlog
  item.
- **`#606`** (microcopy voice sweep) — genuinely large and cross-cutting.
  It deserves its own epic batch, not a slot at the end of this one.
- **E19 implementation** — gated on `#612`.
- Everything under E4/E8/E9/E10 — gated by design.

## Sprint 2 preview

1. **E19 batch** (19.2–19.6) on one epic branch, assuming `#612` signs off:
   configuration layer → snapshot recording → consistency engine → API/MCP →
   entry surface and EN/DE docs.
2. **`#606` microcopy sweep** as its own batch.
3. Analytics wishlist triage: `#563`, `#564`, `#568`, `#572`, `#577` — these
   have accumulated without an owning epic and need one prioritisation pass
   before any of them starts.

## Findings — things that need a decision, not code

1. **`#610` is built on a fix that is not in `main`.** It states it is a "known
   residual of the #545 fix (ADR-0010, amendment 2026-07-24)". Verified: ADR-0010
   has no 2026-07-24 amendment (the last is 2026-06-13, IRR), there is no
   basis-step logic in `performance.ex`, and no remote branch carries one. Either
   that work was designed and never landed, or the issue was filed from a design
   session as though it had. `#545` is therefore real, open, unfixed work — which
   is why it heads Lane A.

2. **Two parallel epic structures have drifted apart.** `epics.md` defines E1–E19;
   GitHub carries a separate tracker set (`#416`–`#420`, `#470`, `#398`, `#356`).
   Roughly 20 of the 48 open issues hang off neither. One reconciliation pass
   would make future sprint planning mechanical instead of archaeological.

3. **`#321` (roadmap index) is stale** — it indexes ~35 issues, most now closed.
   Either refresh it or retire it in favour of the epic trackers.
