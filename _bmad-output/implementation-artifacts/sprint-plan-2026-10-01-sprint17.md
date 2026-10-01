# Sprint 17 — the agent's first contact, the trades the owner could not find, and two debts with a deadline

**Status: ADOPTED by the merge of the Sprint 17 planning PR.**
The merge is the signature (ADR-0026 step 1 as amended on PR #780). This
planning PR **signs one decision gate**:
[ADR-0051](../../docs/decisions/0051-contribution-analysis.md), the design
gate for FR-41, written in Sprint 16 (its plan's D-7) and moved into the
decision records as this PR's opening commit. The merge also adopts:

- the lane cut, the three lane PRs and **D-1** to **D-15**;
- the owner feedback triage of 2026-10-01
  (`planning-artifacts/feedback-triage-2026-10-01.md`): its launch path, its
  four filed items, and an answer to each of its open questions OQ-1 to OQ-6
  (**D-1**, **D-2**, **D-5** to **D-8**);
- the design picks of **D-9**, on the boards of
  `planning-artifacts/ux-design-2026-10-01-sprint17.md`;
- answers to the two process questions the Sprint 16 close-out put to this
  planning: commit authorship (**D-10**) and versioning (**D-11**).

Nothing here is `DRAFT` or `Proposed`. A decision the owner rejects is
removed on the PR before the merge. A closure the owner rejects is undone by
a comment naming its issue.

**This PR also carries two repairs that could not wait for a batch**, each as
its own commit: `main` is red (see the verification basis), and the session
trailer every cloud session is told to add and must refuse is switched off
at its source (**D-10**).

**Verification basis:**

- **`main` and CI:** `main` at `dda28888` (the triage of 2026-10-01). **CI
  1630 on it is red**: pre-commit's end-of-file-fixer rewrites two drafts of
  the 2026-09-30 competitive research (`drafts/claims.json` has no final
  newline, `drafts/header.md` a trailing blank line), so the test and quality
  jobs were skipped. The last green CI on `main` is **1628** on `4c376c22`.
  This PR's second commit is the fixer's own output, nothing else.
- **The open-issue list of 2026-10-01:** 95 open (five of them trackers), and
  four open pull requests, all Dependabot's (#881, #975, #976, #977).
- **The published releases:** latest **0.14.0** (2026-09-23). `0.15.0`,
  `0.15.1` and `0.16.0` are unpublished (D-11).
- **The code, read for every claim this plan makes about it:** the trade
  matcher and its two reads (D-7), the MCP companion's tool registry, its
  read-only switch and its hint counts (D-5, D-6), and the import path's API
  coverage (D-1). The figures are named where they are used.
- **The design pass this PR carries:** three boards, rendered with the real
  `priv/static/app.css` (D-9).

## State of play, in five lines

1. **Sprint 16 merged, and nothing was shrunk.** PR #914 was fast-forwarded
   onto `main` on 2026-09-29: E25 done, ADR-0050 L1–L5 shipped, NFR-9 built,
   twenty-two issues closed by keyword. Its retrospective asks four things of
   this planning: cut a big batch into lane PRs, turn two recurring review
   catches into gates, plan against a token budget, and answer two process
   questions.
2. **The owner stated a new direction on 2026-10-01: polish, then launch.**
   The runway of the 2026-09-23 triage (three sprints of product work, then
   maintenance mode) is superseded. What comes next is a launch to a small
   group of self-hosters who run LLM agents, and the agent is that group's
   first contact.
3. **The triage's governing finding applies to itself.** It says "before
   building a peer's feature, check whether the figure exists and is merely
   unreachable", and then files #984 as "there is no portfolio-wide list of
   trades". **There is one.** Cash-flow → Realized (`/cashflow?tab=realized`,
   #807, Sprint 13) lists every closed round-trip across all portfolios, with
   `GET /api/v1/realized_gains` and `portfolixir.cashflow.realized_gains`
   beside it. The owner did not find it. #984 shrinks to reach, one column,
   and naming the sells the list silently leaves out (D-7).
4. **The agent's first contact has three gaps, all cheap, none built:** the
   companion registers 139 tools and no prompt, it has one profile switch
   (read-only, by hint), and nothing agent-readable says what Portfolixir is.
   The three valuation, performance and benchmark tools exist twice, at two
   scopes, and only one side of each pair says when to use the other.
5. **Two debts carry a deadline into this sprint**: the merge-record list
   view and the release of manual quotes, both shipped agent-first in
   Sprint 16 and due their human view by its end.

## Why this cut

- **Sprint 17 is the agent's sprint; Sprint 18 is the operator's** (D-2). The
  launch path's agent-facing half (MCP surface, prompts, the LLM-facing
  entry, the README that points at them) has no rendered output and few
  dependencies, and the launch test (D-1) can only run once it exists. The
  operator's half (the UI polish lane, FR-41's calculation breakdown, the
  human documentation and its screenshots) comes after, because what it shows
  depends on what this sprint ships.
- **Surface before text.** The LLM-facing entry and the prompts name tools and
  a profile variable. They are written after the surface they describe stops
  moving, inside the same lane PR, so nothing is written twice.
- **FR-41's record is signed; its build moves to Sprint 18** (D-4). It is the
  most expensive item on the old runway (risk-tier money math inside the
  performance walk, nine identities to pin and mutation-verify), its surface
  is the operator's, and it is the peer feature the research ranks first
  ("a calculation breakdown from initial to final value"). It belongs in the
  operator's sprint, where the human documentation can show it.
- **No batch over a hundred commits.** The work is cut into three lane PRs,
  merged in order (D-12), each with a closing act sized to its risk (D-14).
- **The retrospective's two harnesses ride the first PR**, so the later two
  are already protected by them.

## Lanes

### Lane A — the agent's first contact (PR β)

Six items, in this order, because each later one names what the earlier
ones build:

- **A1, MCP tool profiles (OQ-3; D-5).** `PORTFOLIXIR_MCP_PROFILE` with three
  values, `read`, `book` and `full`, default `full`. The existing
  `PORTFOLIXIR_MCP_READ_ONLY=true` keeps working as `read`; a conflicting pair
  stops the companion at boot, like an invalid value does today. `book` is
  `read` plus the creates plus every write an ordinary inverse write can
  undo; the **admin set** it leaves out is an explicit list in the companion
  (every delete, every merge, the former-name and ISIN-alias removals, the
  ISIN change, rule retirement and the manual-quote release, among others).
  A meta-test fails any tool that carries `destructiveHint` and sits in
  neither set, so a new tool forces the choice. The refusal at call time stays,
  as the read-only switch does it today. The docs say in one sentence that a
  profile narrows the companion and **not** the API token.
- **A2, the duplicate scope tools (OQ-4; D-6).** The three pairs
  (`portfolios.valuation` / `views.valuation`, `portfolios.performance` /
  `views.performance`, `portfolios.benchmark` / `views.benchmark`) each name
  the other in both descriptions, with the scope difference in one line: one
  portfolio, its base currency, a `view` that narrows **within** it, against
  every portfolio, deduplicated, in EUR. A companion test pins that each pair
  names its twin. No tool is removed or renamed in this sprint.
- **A3, the schema budget.** A companion test measures the serialized tool
  schemas per profile and fails above a ceiling set at the measured figure on
  the day it lands. It only ever moves down. The figure per profile goes into
  the LLM-facing entry, because "how much context does connecting cost" is
  the first thing a careful agent asks.
- **A4, MCP prompts (#983).** The companion gains the `prompts` capability and
  two prompts: `first_setup` (check the instance and the profile, read what
  exists, propose a structure of cash accounts and depots, explain how data
  gets in, and write nothing without the user's confirmation) and
  `import_converter` (turn a user-supplied bank or broker export into
  Portfolio Performance CSV v1 with a converter the agent writes and runs on
  the user's machine). The constraints the triage carried stay binding: no
  broker sync, no network call and no model call from the app, synthetic
  examples only, and **the output is a file the operator drops into the
  Imports view**. The prompt says plainly that booking the converted rows one
  by one through `transactions.create` is not a substitute, because it skips
  the preview and the content-hash idempotency. Each prompt carries the
  no-advice framing in its own text.
- **A5, the LLM-facing entry (#982).** `docs/llms.txt`, served at the docs
  site's root: what Portfolixir is, who it is for, **when not to recommend
  it** (no broker sync, no phone app, no hosted service, no advice), how to
  install it, how to connect the companion and pick a profile, the two
  prompts, the schema cost per profile, and links into
  `docs/integration/api-and-mcp.md`. Beside it, a "Connect an agent" page in
  English and German with copy-paste client configurations, which no page
  has today. A docs test pins that the entry exists, names every prompt and
  the profile variable, and links only to pages that exist.
- **A6, the README (#981).** The first screen answers two questions: what this
  is, and how the user's data gets in (Portfolio Performance CSV/JSON, the
  broker-PDF importer, an agent-written converter through `import_converter`,
  manual booking). Badges, the support link and the philosophy paragraph
  follow. One line says how the project is built (D-10). #935 (the Docker
  minimum version) rides along. No screenshot in this sprint: the screenshots
  belong to Sprint 18's human documentation and come from the synthetic seed.

**Coverage:** A1–A4 change the MCP surface and carry the PR's contract entry.
A1 and A2 change no API route. A4's prompts are MCP only and say why in the
entry: a prompt is an instruction to the user's agent, and the API has
nothing to serve it to.

### Lane T — trades, reached and annualized (PR γ; #984 rescoped)

- **T1, the annualized return per trade (API and MCP; risk-tier: money
  math).** Every closed round-trip in `GET /api/v1/realized_gains` and
  `GET /api/v1/securities/:security_id/trades` gains `annualized_return` (a
  decimal string, or `null`) with its reason, and the payload's
  `computation_basis` states the rule (D-7). The figure is the round-trip's
  money-weighted return: the existing XIRR solver over the trade's own flows
  (each consumed lot's buy at its date and prorated cost, the sell at its
  proceeds), in the trade's own currency like the percent it annualizes,
  inside ADR-0034 §2's float exception, which this does not widen. It is `null` for a holding period under 365 days, as ADR-0034 §2
  already rules for the MWR. The trade matcher exposes the consumed lots it
  already computes internally; every existing field stays byte-identical.
  The two MCP tools' descriptions follow. Contract entry for PR γ.
- **T1b, the sells nobody matched (API, MCP, UI).** `RealizedGains.report/1`
  drops the matcher's `orphan_sells` without a word: a sell of shares that
  arrived by an inbound delivery has no lot, because deliveries open none, so
  its round-trip is missing from the list and from every total above it. A
  currency exclusion is already named; this one is not, against UX-DR25 ("an
  excluded row is named where the total is read"). The read gains an
  `unmatched_sells` block (count, and per sell the security, date and
  quantity), the basis says why, and the screen names them beside the
  summary (board G1). An imported history with deliveries is exactly the
  owner's case, so this is part of "was the trade worth it", not a side
  repair.
- **T2, the reach (UI; pick G1).** The figure moves to where the owner looks,
  on the pick of D-9: the facet's tab label, the p.a. column, the basis line,
  and the placement the board recommends. The picked anatomy goes into
  `DESIGN.md`.
- **T3, income inside a trade (OQ-6; D-7).** Not in v1. The basis says
  "income received while the trade was open is not included", and the
  attribution rule a variant needs (dividends of a security split across the
  lots open on the ex-date, by quantity) is filed for a decision.

**Identities the lane pins, TDD first with exact expectations:** a single-lot
trade held N ≥ 365 days returns `(proceeds ÷ basis)^(365/N) − 1` to the
solver's stated scale; under 365 days the field is `null` with its reason; a
loss stays above −100 %; every field the reads return today is unchanged for
every fixture in the existing suites; the payload carries no signal, rating
or verdict key.

### Lane V — the two human views due by this sprint's end (PR γ)

- **V1, the merge-record list (ADR-0050 §12; pick G2).** Read-only, newest
  first, every kind; no undo, because ADR-0050 §12 rules there is none, and
  the view must not suggest one. The board found two things the story
  settles: every `manifest_summary` key needs a fixed German label, pinned
  by a meta-test over the keys the three merge writers emit; and the
  payload counts every removed booking as one number, so the row says
  "N entfernt" unless the story groups the count by reason (both users would
  read the grouped form; it is a payload change, so the contract entry
  names it).
- **V2, releasing manual quotes (T-9; pick G3).** The page's first quote
  write. A confirm that names the range and what happens to it. **No read
  exists today that says which dates are manual** outside the chart's range,
  so the story adds one (count, first and last date, the stretches of manual
  quotes) and a public check of whether the security's provider can refill
  the days; the dialog warns when it cannot. Whether API and MCP gain the
  same summary is the story's call under the two-way rule, and a `source=`
  filter on the quotes read would be a read-ergonomics parameter for the
  close-out's surface check.

If either does not land, the close-out records it as a finding under the
two-way rule; neither is on the shrink order.

### Lane G — the two harnesses the retrospective asked for (PR α)

- **G-1, the seeded-upgrade harness.** A test helper that migrates a fresh
  database to a named earlier version, inserts synthetic legacy rows with
  plain SQL, migrates to head, and hands the test the result. It runs in the
  existing `migration-roundtrip` job. Its first cases reproduce Sprint 16's
  two upgrade-path catches that would have stopped the release from booting
  (the import hash-kind CHECK, CR-1's author backfill) as seeded cases that
  pass on the shipped migrations and are mutation-verified: putting the
  defect back makes them fail, which is the only proof a harness catches
  what it was built for. A meta-test
  then requires a seeded case for every **new** migration that adds a CHECK,
  a NOT NULL or a backfill; the existing ones are not grandfathered into an
  ignore list, they are simply older than the rule.
- **G-2, the two-connection lock-order harness.** Two real connections
  outside the SQL sandbox, a barrier that interleaves two writers, and a
  deadlock (`40P01`) read as a failure. Its first cases are Sprint 16's lock
  pairs (the importer against a rename, the ISIN writers, a delete against an
  override). **The lane's shrinkable half** (shrink order, step 1).

### Lane P — process: versioning, and the authorship friction (PR α)

- **P1, calendar versions made by a workflow (D-11).** The Release workflow
  gains a job on pushes to `main` that touch shipped paths: it computes the
  next `YYYY.M.N`, creates an **annotated** tag through the API, and creates
  the GitHub Release in the same job, with generated notes and the API
  contract version named in them. A tag pushed with the workflow token
  triggers no other workflow, which is why the release is made in the same
  job. The tag-push trigger stays for hand-made tags. `AGENTS.md` step 5 and
  ADR-0026 gain the amendment; `ci_test.exs` pins the new wording.
- **P2, the git identity (D-10), an owner action.** Four environment variables
  in the cloud environment's settings (below), after which no session commits
  as the agent by default.

### Lane D — first-run debt with no rendered difference (PR α)

What a stranger meets when they install, plus the gate hygiene the batch
records named, none of it changing a pixel: #961 (`config/dev.exs` ignores
`DATABASE_PORT`), #932 (dev and prod Compose share a database volume), #963
(the dev seed makes outbound logo calls), #924 (stale gettext catalogs, and an
extraction check in CI), #947 (order-dependent flaky tests), #978 (merge
refusal details print ids as a charlist), and the test-hygiene four #916,
#927, #934, #936. If a story finds that one of them does change rendered
output after all, it stops and gets a before/after board before its code.

### Lane M — maintenance (always present; PR α)

- **Take:** #975 (phoenix 1.8.15) and #976 (`@types/node` 24.19.0), each its
  own commit through the gates, the Dependabot PR closed with the commit
  named.
- **Decline, recorded:** #977 (Node 26), because Node 26 becomes LTS on
  2026-10-28 and the companion pins an LTS line. #881 stays the
  maintainer's, as the Sprint 16 report recorded.
- **Re-check:** #727's two triggers; the BMAD modules for a release since
  6.12.0.
- **The version report** before PR α's closing act. An advisory bump in the
  transport stack gets its changelog read and a real-transport test (the
  Sprint 16 retrospective's mint lesson).

### Lane Z — registry (small)

- **Right after the merge:** #849 closed by hand (D-13); ADR-0051's four
  deferrals filed, as its asks table requires at the signature (percentage
  points linked to the TTWROR, percentage points of invested capital, the
  currency split, grouping by today's classification).
- **At each lane PR's branch opening:** the E26 tracker (PR α), and under it
  the issues for A1, A2, A3, G-1, G-2, P1 and the launch test (D-1); the
  follow-ups the decisions name (scoped API tokens, D-5; income inside a
  trade and the matcher's depot scope, D-7; the Sprint 18 candidates of
  D-8), and the Scope Lock observations of the design pass's Part 4 (PR γ).
  #981–#984 move under E26. Every number lands on its registry row the
  same day.
- **Registry edits already on this PR:** FR-41's row (ADR-0051 signed, the
  build in Sprint 18), and the Tracker Index's new **E26** line.

## Decisions

### D-1: the launch test is the exit criterion, and it runs in this sprint (OQ-2; recommended)

"When the owner is satisfied" stays the owner's call, but it gets a measure
under it. **The launch test**, run by a fresh agent with no repository
context:

1. **Setup:** a clean container with Docker and an MCP-capable agent client.
   The agent gets the repository URL and one sentence from a stand-in user:
   "I track my investments in a spreadsheet and my bank gives me this CSV;
   set me up." It is told to rely on the README and `llms.txt` only.
2. **Input:** a synthetic bank-and-broker export in an invented format,
   committed as a fixture with its expected ledger, so the answers are known
   to the cent. It spans two depots that belong in two portfolios and
   carries at least one closed round-trip.
3. **What the agent must do:** install and boot an instance; connect the
   companion with the `book` profile; use `first_setup` and
   `import_converter`; produce a CSV that the Imports preview accepts with no
   error. The stand-in user drops the file and applies it, because the import
   stays an operator action (ADR-0029: there is no import route under
   `/api/v1`, by design).
4. **Three questions with known answers:** the total value across both
   portfolios (which only the view scope answers in one call, so it tests
   D-6's steering), this year's realized result of closed trades (D-7), and
   the balance of a named cash account.
5. **Pass:** all three exact, with nothing from the stand-in user beyond the
   sentence and the drop.

It runs at PR β's closing act, as that PR's UAT persona, and again at the
close-out against `main`. A failure is a finding with the step it failed at.
**Passing it is necessary for the announcement and not sufficient**: the
owner still decides.

**To flip by comment:** name a different measure, or "no measure".

### D-2: the order of the launch path (OQ-1; recommended)

**The PM order is adopted over the owner's, with one refinement.** The
owner's order puts the README first. The risk is concrete: the README's first screen
describes the agent path (how data gets in, how an agent connects), and that
path changes in this sprint (profiles, prompts, an entry point). Written
first, it is written twice. So:

| Sprint | Content |
|---|---|
| **17** | the agent's first contact: MCP surface (A1–A3), prompts (A4), the LLM-facing entry (A5), the README (A6); the trades' reach (T); the two due views (V); the harnesses (G); versioning (P); first-run debt (D); the launch test (D-1) |
| **18** | the operator's first look: FR-41 as the calculation breakdown (D-4), the UI polish lane (the design debt #908–#913, #918, #920, #921, #969, and #912's missing delete), the human documentation that shows what is better here, its screenshots from the synthetic seed, the Sprint 18 candidates of D-8, the launch test again |
| **then** | the owner's announcement decision; widening (phone access, D-8) after it |

The launch path replaces the 2026-09-23 runway, so "maintenance mode after
Sprint 18" (Sprint 16's D-12) no longer holds. Maintenance mode returns when
the owner decides the widening phase is over.

**To flip by comment:** "owner order" puts A6 first inside PR β; nothing
else moves.

### D-3: ADR-0051 is signed (recommended)

The record is unchanged except for two edits named in its commit (§12 names
its board's path; the registry consequence no longer names a sprint). Its
board's pick, **A** (a contribution table under the Wealth performance chart),
is adopted with it. Its four deferrals are filed right after the merge.

### D-4: FR-41's build moves to Sprint 18 (recommended)

Sprint 16's D-12 put it here. Three reasons to move it, in order of weight:

1. **Capacity.** It is risk-tier money math in the walk, with nine
   identities, and the retrospective's budget lesson is fresh: Sprint 16 ran
   into the weekly usage limit for about 36 hours.
2. **It is the operator's surface**, and the operator's sprint is the next one
   (D-2).
3. **It is the research's top-ranked parity item**, a calculation breakdown,
   and Sprint 18's human documentation can then show it.

#900 and #901 move with it (ADR-0051 §6, §9).

**To flip by comment:** "FR-41 in 17" adds it to PR γ as Lane F, and the
shrink order gains it at the bottom.

### D-5: MCP tool profiles, one server, three levels (OQ-3; recommended)

The owner rejected separate servers; one switch with three levels is the
whole change (A1). The **admin set's principle** is written down so the list
can be argued with: a write belongs to `admin` when nothing in the `book`
profile can undo it. A delete, a merge, an identity change, a retirement and
a release qualify. An activated plan does not, because activating the
previous one undoes it.

**What it is not:** a security boundary. The bearer token still reaches every
route, and an agent with a shell can call the API directly. The boundary the
peers ship, tokens scoped to what they may write (the research's
"drafting versus committing"), is filed as its own decision. The launch does
not wait for it, because the target group runs its own agent on its own
machine.

**To flip by comment:** a different default (`book` instead of `full`) is one
word. It changes what an existing setup can do after upgrading, which is why
it is not the recommendation.

### D-6: the duplicate scope tools are steered, not merged, in this sprint (OQ-4; recommended)

The pairs are not duplicates: `portfolios.*` answers for one portfolio in its
base currency, with a `view` that narrows within it, and `views.*` answers for
every portfolio, deduplicated, in EUR. The wrong figure came from choosing
without guidance, and only the `views.*` side gives any. A2 gives it on both
sides. The launch test asks a question only the view scope answers, so it
measures whether steering is enough. **A merge with a deprecation path is
decided only if that question fails**, and then before the announcement,
because a surface that changes after strangers learn it costs more than one
that changes before.

### D-7: trades — reach and one column; the figure already exists (recommended)

The facts, read from the code:

- `TradeMatcher.match/1` returns, per closed round-trip: open and close date,
  quantity, average buy and sell price, buy and sell fees and taxes, basis,
  proceeds, realized result in absolute and percent terms, and a
  quantity-weighted holding period.
- `RealizedGains.report/1` lists these across all portfolios, converts the
  result to the base currency on the close date, and summarises them (total,
  hit rate, average holding period). It is shown as Cash-flow → Realized, and
  served by `GET /api/v1/realized_gains` and `portfolixir.cashflow.realized_gains`.

So #984 is rescoped: **reach** (T2), **an annualized figure** (T1), and
**the sells the list leaves out, named** (T1b). The issue is closed by the
keyword of PR γ, with its rescope stated there.

**The annualization rule.** "So a two-week trade and a three-year trade with
the same percentage look different" is the owner's reason for the column. A
plain annualization does the opposite of what is meant for short trades: 5 %
in 14 days annualizes to roughly 257 % a year, so short trades would look
brilliant. ADR-0034 §2 already refuses to annualize a window under a year for
the MWR, and the GIPS convention is the same. So the column is `null` under
365 days, and the holding period beside the period return carries the
comparison there. Above a year it is the round-trip's own XIRR, which keeps
the float inside the exception ADR-0034 already grants.

**Two facts the basis states and v1 does not change**, each filed for a
decision:

- the matcher keeps **one FIFO queue per security across every depot**, and
  deliveries and transfers neither open nor close lots. A transfer between
  one's own depots therefore leaves the lots where they were, which is
  right; but it is not a per-depot FIFO, which some tax regimes require, and
  a delivered-in position's sells have no lot at all (T1b names them);
- **income received while a trade was open is not included** (OQ-6).

**Not recommended for v1: an excess return against a benchmark over the same
holding window**, the strongest answer to "was the trade worth it". The
benchmark series builder is private to `Benchmark` today and the comparison
needs a picker on the page. It is a Sprint 18 candidate (D-8).

### D-8: peer features — none in this sprint (OQ-5; recommended)

| Candidate | Verdict |
|---|---|
| Privacy / presenter mode | **Not now.** The triage's reason was screenshots for the announcement, but every public screenshot comes from the synthetic seed under the privacy rule, so no screenshot needs masking. Its real use, a user sharing their screen, is a Sprint 18 candidate with a board. |
| Calculation breakdown, initial to final value | **Sprint 18, as FR-41** (D-4). ADR-0051 §3's sum and its three remainder lines are that breakdown, per position. |
| Returns heatmap, monthly and yearly | **Sprint 18 candidate**, boarded at that planning. A level-(a) metric with its computation basis. |
| Excess return per trade against a benchmark | **Sprint 18 candidate** (D-7). |
| Phone access (PWA plus a documented Tailscale Serve recipe) | **Widening phase**, as the triage already ruled; the research's half-hour hands-on test comes first. |
| Weighted multi-category assignment | **Stays out**: the advanced-classifications hard rule. |
| A complete Portfolio Performance file import | **Stays gated**: the owner ruled the migration path not a priority. |

### D-9: the design picks (recommended; silence adopts them)

Three boards, under
`planning-artifacts/design-language/mockups/ux-design-2026-10-01/`, argued in
`planning-artifacts/ux-design-2026-10-01-sprint17.md`:

| Pick | Item | Board | Variants | Recommended |
|---|---|---|---|---|
| **G1** | Trades: reach, the p.a. column and the unmatched sells (#984 rescoped, Lane T) | `01-trades-reach` | the facet renamed "Trades" plus an Overview card with the last five closed trades · a top-level nav entry and route `/trades`, the facet removed and redirected | **A** |
| **G2** | The merge-record list (ADR-0050 §12, two-way deadline, Lane V1) | `02-merge-records` | a collapsed section at the end of Accounts & depots, all three kinds in one list · the same section on the Imports page · no list, a disclosure per survivor | **A** |
| **G3** | Releasing manual quotes (T-9, two-way deadline, Lane V2) | `03-quote-release` | a data note on the Quotes tab with the count and span of manual quotes, its remedy opening a range dialog · an item in the securities row menu, same dialog · a selection on the quote table's manual rows | **A** |

**Items with no board:** everything in Lanes A, G, P, D and M changes no
rendered output (A6 is the repository's README, not the app). T1 changes the
payload only; its column is G1's.

### D-10: commit authorship — the rule stays, and the friction goes (recommended)

The owner asked whether the human-author rule still fits fully agent-written
work. **The cost the question was raised over is friction, and the friction
has two sources, both removable without touching the rule:**

1. **The trailer instruction.** Claude Code's `attribution` setting governs
   it; the repository only set the deprecated `includeCoAuthoredBy`, which
   never covered the session link. This PR sets `attribution.commit` to an
   empty string and `attribution.sessionUrl` to `false` (both per the
   setting's published schema). The effect was visible inside the session
   that wrote this plan: the instruction to add the trailer disappeared from
   the next commit on.
2. **The container's git identity**, which is the agent's
   (`Claude <noreply@anthropic.com>`) in every new session. **Owner action:**
   in the cloud environment's settings, add `GIT_AUTHOR_NAME`,
   `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME` and `GIT_COMMITTER_EMAIL` with the
   owner's name and an allowlisted address. Git reads these before its
   configuration, so every session commits as the owner from its first
   command.

**Why not move accountability to merge control.** It is a coherent model
(the agent drafts, the owner merges, as "machine-extracted data is a proposal
until confirmed" already works), but it costs three things this rule does not:
the hook, the workflow and the allowlist are reworked; the public history
changes author in the weeks before a public launch; and merge control is a
habit rather than a gate (the last batch reached `main` by a manual
fast-forward push, so the model would need a branch ruleset first).
Honesty about how the code is written does not need per-commit authorship:
the README says it in one line (A6), and the PR description is where
`AGENTS.md` records the model.

**To flip by comment:** "agent authorship" files the switch as its own
decision record for Sprint 18, with a branch ruleset as its precondition.

### D-11: calendar versions, made by a workflow (recommended)

`0.<sprint>.0` couples the number to the sprint, never leaves 0.x, and
depends on an owner action the agent's credential cannot perform: three tags
are outstanding right now. **Adopted: `YYYY.M.N`**, created by the Release
workflow on every push to `main` that touches shipped code (P1), annotated,
with the release in the same job and the API contract version named in the
notes. Docs-only and planning pushes make no release. A lane PR's merge is a
release, which is the rollback granularity a self-hoster wants.

**The three outstanding tags:** not created (recommended). The first calendar
release's notes start from `0.14.0`, so nothing is lost from the changelog,
and `0.15.1`'s runtime fix is inside it.

**What remains uncertain:** that the workflow token may push tags. The block
recorded so far is the agent session's git proxy, not a rule on the
repository; P1's first run on PR α's merge proves it, and a failure there is
reported on the PR with the owner's fallback (the three commands in the
Sprint 16 close-out still work under the old scheme).

**To flip by comment:** "keep 0.x" leaves P1 out and the three commands with
the owner; "tag the three" means the owner runs them before PR α merges.

### D-12: three lane PRs, merged in order (standing, from the Sprint 16 retrospective)

| PR | Lanes | Merged | Why this order |
|---|---|---|---|
| **α** — engineering | G, P, D, M | first | the harnesses protect β and γ; P1 makes their merges releases |
| **β** — the agent's first contact | A | second | the launch test (D-1) runs in its closing act |
| **γ** — the operator's due surfaces | T, V | third | `mcp-server/src/tools.ts` and the contract manifest are shared with β; γ rebases onto `main` after β merges |

Each PR opens as a draft with its first commit, carries its own reviewer
briefing, is promoted by the agent under `AGENTS.md`'s four conditions, and is
merged by the owner (rebase-merge; each stays well under GitHub's
hundred-commit limit). A lane PR that changes the API or MCP surface opens
its own contract entry, because each merge is a release (D-11).

### D-13: what is decided, and what stays open on purpose (recommended)

| Issue | Action | Reason |
|---|---|---|
| **#849** | close as not planned | deferred twice for an agent report on polling cost that never came; the cost the launch path is actually measuring is schema load (A3), not re-reads. Reopened by an agent report that shows the re-read cost |
| **B4.2** (predictions, FR-46/47) | stays parked | its condition, the agent confirming it will record predictions, has not been met since 2026-09-23 |
| **#330** (bonds) | waits on one word | the owner answers "hundredth", "face" or "mixed": does the Portfolio Performance export book a bond's quantity as a hundredth of the face amount or as the face amount? The answer decides between a small story and a risk-tier record |
| **#899** (Idempotency-Key) | Sprint 18 | Sprint 16 filed it "for Sprint 17"; the outcome-unknown error (G31) already tells an agent not to retry blindly, and the key competes with the launch path for this sprint's budget |
| **#328**, **#354** | stay open | the owner's runs on real data |
| **#727** | stays open | re-checked in Lane M |
| **#894–#898**, **#902–#907**, **#866**, the other `needs-decision` issues | stay open | each needs a decision nobody has asked for yet; none blocks the launch path |

**To flip by comment:** name the issue number.

### D-14: the closing act, one lens per risk class (standing, amended)

The Sprint 16 retrospective measured where reviews paid (only where no gate
can see) and where they did not (overlapping lenses, verifier fleets,
review-of-review layers). So each lane PR gets the lenses its risk classes
need, one each, and a cascade stops when a layer yields no major finding:

| PR | Lenses |
|---|---|
| **α** | correctness hunter; the seeded-upgrade lens (G-1 run against the batch's own migrations); dependency chokepoint for Lane M |
| **β** | correctness hunter; **the launch test as the UAT persona** (D-1); security reviewer on the profile switch's call-time refusal |
| **γ** | correctness hunter; edge-case hunter; money-identity lens on T1's identities; UAT persona on the synthetic seed; design critic against G1–G3, in German at 390 px, light and dark |

Every finding carries its reach label (Sprint 15's D-9). The patch-coverage
listing is read from the last pre-promotion CI run. Scope-lock triage runs as
one agent with a `git log --grep` pre-filter, and the implementers'
out-of-scope notes reach the fixer whole.

### D-15: the budget (standing)

Each lane PR reserves its closing act and its briefing before its first
story starts. If the weekly usage limit comes into view, the shrink order
applies from its first step, and the closing acts are not what is cut. A
workflow phase that returns nothing reports failed, and a closing keyword is
checked against the diff before a PR body names it.

## Sequencing

```text
after the merge ── Lane Z: #849 closed, ADR-0051's four deferrals filed
PR α opens ─────▶ Lane Z: E26 tracker and its issues
                   Lane M: #975, #976; version report
                   Lane G: G-1 (with Sprint 16's two seeded cases), then G-2
                   Lane P: P1, the AGENTS.md step-5 amendment
                   Lane D: the first-run items
                   closing act (D-14) ─▶ merge = the first calendar release
PR β opens ─────▶ A1 profiles ─▶ A2 descriptions ─▶ A3 budget ─▶ A4 prompts
                   ─▶ A5 llms.txt + "Connect an agent" ─▶ A6 README
                   closing act with the launch test ─▶ merge
PR γ opens ─────▶ (from main after β, or rebased onto it)
                   T1 the payload ─▶ T2 the reach on G1
                   V1 the merge list on G2, V2 the release on G3
                   closing act ─▶ merge
close-out ─────── the launch test against main; the two-way check;
                   the surface check; the release list
```

## Shrink order (cut from the top, name the cut in the briefing)

1. **G-2**, the lock-order harness, moves to Sprint 18.
2. **Lane D's test hygiene** (#916, #927, #934, #936) moves to Sprint 18.
3. **A3**, the schema budget gate, moves to Sprint 18; the figure is then
   measured once by hand for `llms.txt`.
4. **#924**'s CI extraction check moves to Sprint 18; the catalogs are still
   regenerated.
5. **P1** moves to Sprint 18. D-11 stands, and the owner tags by hand until
   it lands.

**What does not shrink:** V1 and V2 (the two-way deadline); A1, A2, A4, A5 and
A6 (without them the launch test cannot run); T1 and T2 (the owner's own
finding); G-1 (it protects every later migration a stranger will run).

## What is deliberately not in this sprint

- **FR-41's build**, #900 and #901: Sprint 18 (D-4).
- **The UI polish lane** (#908–#913, #918, #920, #921, #969, and #912's
  missing delete): Sprint 18, boarded at its planning.
- **The human documentation that shows features**, and screenshots: Sprint 18.
- **Peer features** (D-8), **#899** (D-13), **scoped API tokens** (D-5).
- **An import route under `/api/v1`**: the import stays an operator action
  (ADR-0029). If the launch test fails at the drop, that is the evidence to
  reopen it, as a decision record.
- **B3.3, B3.5, B3.7, B3.8** and ladder level (d): shut.
- **Node 26** until its LTS date, the Elixir/OTP moves (#727), PostgreSQL 19.

## What "done" means for this sprint

1. **PR α, β and γ are merged in order**, each green on its head, each with
   its closing act under D-14 and its briefing.
2. **The launch test ran** at PR β's closing act and at the close-out, and its
   result is recorded step by step. A pass is recorded as a pass; a failure
   names its step.
3. **#981, #982 and #983 are closed by keyword**, and **#984 is closed by
   PR γ's keyword** with its rescope stated.
4. **The merge-record list and the manual-quote release have their human
   views**, or the close-out records the miss as a two-way finding.
5. **G-1 is green** with Sprint 16's two seeded cases, and its meta-test
   guards every new migration.
6. **Each merge produced a calendar release**, or P1 is named as cut and the
   owner's fallback is recorded.
7. **ADR-0051's four deferrals and every follow-up this plan names are
   filed**, each on its registry row.
8. **The close-out's surface check** names `annualized_return`'s family (the
   two trade reads), `unmatched_sells`' (the realized read, and whether the
   per-security trades read carries it too), and the profile variable's
   reach (every tool).
