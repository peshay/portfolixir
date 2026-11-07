# Agent Report Triage — 2026-11-07 (data quality and logos)

Source: a findings report written by the operator's agent for the PM on
2026-11-07. It followed a read-only audit of every `data_quality` set and the
other consistency reads on the operator's instance. This document is the PM
triage per ADR-0038 and the sprint workflow's "Issues and the registry" (a
third party's report is triaged into a triage document). Every claim was
checked against the code on `main` at `d6df259`. Nothing here is a decision
record: the owner answers Part 3 before any of it becomes a plan.

**Privacy note.** The report named securities by their instance ids, gave
counts from the instance and gave performance figures before and after its
corrections. None of that is reproduced here. Only the product shape of each
point is kept.

Status: **answered.** On 2026-11-07 the owner accepted every recommendation
of this document ("ja alles was du empfiehlst"). Every item now has an issue
(Part 5). The four questions of Part 3 are answered with their
recommendations, and OQ-3 is written into ADR-0046 as its amendment of
2026-11-07. Two items stay rows in the idea list (I25, I26), because they
are not worked out.

---

## Part 0 — What governs the rest

1. **Two findings are S1 and were filed at once**, as the sprint workflow
   requires: the sync writes provider rows behind a feed that the screen
   calls "Manual" (#1410), and it stores closes in a foreign currency without
   comparing them (#1411). In both, a stored series, and every figure on it,
   can be wrong while nothing names it.
2. **Three premises in the report do not hold**, and their wishes change
   with them:
   - The scoped-token route for logo writes was **decided against** (#999,
     closed `not_planned` by the Sprint 20 decision pass; ADR-0056 §7 kept
     ADR-0054 for the news labeller). It is not an open story to start with.
     The gap is MCP coverage, not token scope (B1 below).
   - Logo discovery **does** search Wikipedia: page titles, a validated name
     search and issuer titles for funds (`catalog/logo_lookup.ex`).
     companieslogo and CoinGecko are fallbacks, not the only sources. What is
     missing is a lookup by ISIN (B3).
   - The bookkeeping stores **no source URL** for a discovered logo. It
     stores the adapter name and the host (`logo_source`,
     `logo_source_host`). "Reload from the stored URL" cannot work as asked
     (B2).
3. **One premise is stronger than the report states.** Flagging a held
   security `is_benchmark` hides it from the booking form *and* from every
   data-quality set (`data_quality.ex` `list_opts/1`). The workaround the
   report rejects would also have silenced the checks on that position (B8).

---

## Part 1 — Item by item

Severity follows the sprint workflow's closing-act scale (S1 to S3); "idea"
means the item is not worked out and goes into the idea list.

| # | Claim | Verified | Class | Recorded as | Recommendation |
|---|---|---|---|---|---|
| B1 | No MCP tool for `PUT`/`DELETE /securities/:id/logo` and `POST …/logo/discover`; the companion token gets a bare 401 on `/api/v1` | **Yes.** `mcp-server/src/tools.ts` has no logo tool; the API routes exist (`router.ex`). The coverage rule ("both ways") was not met and no PR said why | S2 (a flow the agent cannot complete) | plan candidate (Part 2); the 401 wording as a line on "Polish: API and MCP" (#1356) | Three tools in the book profile, routed to the existing endpoints and journaled under the calling token like every write. `logo_put` and `logo_discover` carry `openWorldHint`, since the server fetches the URL. Not a scoped token (#999) |
| B2 | Logos lost on a redeploy; the reconciliation marks but does not reload | **Partly.** (a) The volume is documented (`docker-compose.yml`, `docs/home-deployment.md` table and backup/restore), and an empty directory already marks every logo, which the Overview raises. (b) No source URL is stored, so nothing can be reloaded from one. Marked, unlocked rows go back to discovery already | (a) built; (b) a premise error | no record | Nothing to build for (a). For (b) the real gap is that re-discovery found fewer logos than the first run did. That is B3's problem, not the reconciliation's. **[unchecked]** Wikimedia's API refuses clients whose User-Agent names no contact. The adapter's UA should be checked in B3's story before any new source is added |
| B3 | Discovery finds too little; Wikidata by ISIN (P946 → P154) would find most shares, issuer logos most funds | **Partly** (see Part 0). No ISIN lookup exists | idea | **I26** | Wikidata by ISIN is a deterministic, keyless source on hosts the instance already reaches for logos, so it is not new acquisition (B3.3 covers data beyond quotes and FX; logos are an existing enrichment). The acceptance figure the report proposes is instance data; a synthetic fixture set replaces it |
| B4 | `quotes_sync` ignores `is_retired` and `feed=MANUAL` | **Yes.** `sync_all/1` dispatches on `provider` only; imports set `provider` whatever the PP feed was | **S1** | **#1410** (`needs-decision`, answer recommended) | Skip `MANUAL`/`NONE` feeds and retired securities in the full run; name the stop in the tool description |
| B5 | `implausible_quote` checks only held securities; unit errors in sold securities' series reach snapshots, sale hindsight and the long-window TTWROR | **Yes.** `list_opts("implausible_quote")` is `holding_status: :held` (#1101, Sprint 20 D-7) | S2, and it changes an adopted set definition | **OQ-1** | Run the same guard over every security with a priced booking, held or not; each finding carries `held`. Naming the findings in the `computation_basis` of the three reads is a second, separate step |
| B6 | Provider currency ≠ security currency not checked | **Yes.** `yahoo.ex` `decode/1` drops `meta.currency` | **S1** | **#1411** (`agentic`) | Refuse the rows on mismatch. A `currency_mismatch` set for series already stored, and ISIN matching before the first sync, stay open (**OQ-2**) |
| B7 | A held, delisted security stays in `stale_quote` for good; `is_retired` is the only exit and is wrong for a held one | **Yes** | idea | **I25** (with B9) | One mechanism with B9: an acknowledgement per security and set, journaled, that lapses when the finding's evidence changes (for `stale_quote`: a newer quote). No `quote_frozen_at` field of its own |
| B8 | `is_benchmark` makes a security unbookable, so a held fund cannot be the benchmark | **Yes**, and broader (Part 0.3). ADR-0046 §1 says a benchmark "may also be held … then it is simply both", while the booking form excludes it (`transaction_management_live.ex`); the API does not | S2: the ADR contradicts itself | **OQ-3** (an ADR-0046 amendment) | Accept `benchmark=security:<id>` for any security with stored quotes. `is_benchmark` keeps its meaning (a reference-only instrument: not bookable, out of the checks) and curates the picker |
| B9 | Overview counts and hints include sold, unretired securities; hints cannot be acknowledged | **Yes.** The sets exclude benchmarks and retired securities, not sold ones. The counts are catalog-wide **by decision**: Sprint 19 D-3, J1.2, "stale in the catalog", so the count matches the list it opens (#1081) | changes an owner decision | **OQ-4**; the acknowledgement half in **I25** | Count held first, with "in the catalog" as the secondary figure and the link carrying `holding_status=held`. The API already combines `holding_status` with `data_quality` |

The report's "no open findings" paragraph (trim budget, cash mismatch,
split completeness, rate-only, missing FX, two scales, negative holdings,
events, policy findings) needs no action. Its two corrections are on the
instance's side.

---

## Part 2 — Plan candidates (no decision needed)

- **B1, the logo tools.** One story: the three MCP tools with their schemas,
  the companion tests against a fake API, and the contract entry. It fills a
  coverage gap the rule already demands, adds no endpoint and no semantics.
  The 401 wording (say which token `/api/v1` expects) is one line on #1356.
- **#1411**, the currency refusal: test-first, one adapter, fake answers
  only.

---

## Part 3 — The owner's questions (all answered 2026-11-07 with the recommendation)

- **OQ-1 — `implausible_quote` beyond held securities (B5).** The Sprint 20
  answer limited the guard to held securities. Widening it adds sold
  securities to a set the Overview counts, so it interacts with OQ-4.
  Recommended: widen the guard, count it under OQ-4's held-first rule.
- **OQ-2 — Stored series in the wrong currency (B6).** #1411 stops new
  ones. For those already stored: a `currency_mismatch` set needs the
  provider currency stored per quote row or per security, which is a schema
  change. Recommended: store the provider's currency on the security at
  each sync (one column), and derive the set from it.
- **OQ-3 — A held security as a benchmark (B8).** Amend ADR-0046 §1 so that
  `benchmark=security:<id>` accepts any security with stored quotes, or keep
  the flag as the gate and make the booking form and the checks exclude only
  *unheld* benchmarks. Recommended: the first; it leaves the flag one
  meaning.
- **OQ-4 — What the Overview counts (B9).** Reverses Sprint 19 D-3 J1.2.
  Recommended: held first, the catalog count beside it. Needs a board.

---

## Part 4 — What the report does not change

- No token scope (#999 stands; reopened only by an agent on another host
  with a token of its own).
- No reload from a stored URL (none is stored; B2).
- `is_retired` keeps its #610 side effect; I25 is the exit for a held
  security, not a change to retiring.

---

## Part 5 — Where each item went (2026-11-07)

| Item | Record | Label |
|---|---|---|
| B1, the logo tools | #1413 (under #419) | `agentic` |
| B1, the 401 wording | a line on #1356 ("Polish: API and MCP") | — |
| B3, logo discovery by ISIN | idea I26 (`triaged`) | — |
| B4, the sync behind a "Manual" feed and retired securities | #1410, answer recorded on the issue | `agentic` |
| B5 / OQ-1, `implausible_quote` beyond held securities | #1414 (under #416) | `agentic` |
| B6, the currency refusal | #1411 (under #416) | `agentic` |
| B6 / OQ-2, the `currency_mismatch` set | #1415 (under #416), after #1411 | `agentic` |
| B7 and B9's acknowledgement | idea I25 (`triaged`) | — |
| B8 / OQ-3, any security with quotes as the benchmark | ADR-0046 amendment of 2026-11-07; #1416 (under #418), after its merge | `agentic` |
| B9 / OQ-4, the Overview counts held first | #1417 (under #418), board first | `agentic` |

The ADR amendment is signed by the merge of the PR that carries it
(ADR-0026 step 1); #1416 waits for that merge. #1417 and the picker half of
#1416 are UI changes and get a board before they are built. The next
planning session takes these as candidates. Nothing here is built in this
session.
