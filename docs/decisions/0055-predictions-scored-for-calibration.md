---
layout: docs
title: "ADR-0055: Predictions — permanent records of a stated call, resolved against stored quotes and scored for calibration"
description: "Decision for gate B4.2 (FR-46, FR-47; idea F1). A prediction is a permanent record of one call: a security outperforms or underperforms a benchmark by a date, with a stated probability, an author and the model an agent names. Nothing edits, withdraws or deletes one, and nothing can date one in the past. It is resolved at read against stored closes in EUR, never guessed, and the calibration report scores every resolved call with a Brier score and its uncertainty, shows sharpness beside it, and shows a probability band only above a minimum count. Ladder (c): it scores what was recorded before the outcome was known. Agent first; the human view is the next sprint's."
---

# ADR-0055: Predictions — permanent records of a stated call, resolved against stored quotes and scored for calibration

- **Status:** Accepted. Adopted by the merge of the Sprint 25 planning PR
  (ADR-0026 step 1, as amended on 2026-10-08: the merge is the signature).
  The owner's question was answered on 2026-11-05 ("ja f1", the Sprint 24
  plan's D-10): "measure the agent" at the small shape, with the four
  conditions, which opened gate B4.2. Amended on 2026-11-05 by the Sprint
  25 closing act, adopted by the merge of the Sprint 25 PR: the start close
  is the last close on or before the day made, a resolution waits for its
  end close, and a fixed-rate benchmark of a prediction is a fraction up to
  1 (see "Amendment of 2026-11-05 (the Sprint 25 closing act)" below).
- **Date:** 2026-11-05
- **Answers:** gate B4.2; FR-46 and FR-47 (`epics.md`), narrowed here;
  idea F1 (`_bmad-output/planning-artifacts/ideas.md`).
- **Builds on:** ADR-0044 (the research log a prediction may point at),
  ADR-0046 (the two benchmark kinds and their price rules), ADR-0050 §9
  (what a merge and a delete do with a reference), ADR-0054 (the author is
  derived from the credential).
- **Ladder:** level (c), evaluation of decisions. It scores calls recorded
  before their outcome was known; it replays no rule against past prices,
  so it is not level (d). Following
  [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html), §9 lists each
  ask as answered or deferred.

## Context

**The use case is to measure the agent, not to trade better.** The owner
runs an LLM agent that reads Portfolixir and states views on securities.
LLMs are weak forecasters of prices and tend to state more confidence than
their hit rate earns, so the question worth answering is how much weight
the agent's calls deserve, in figures rather than memory, with the owner's
own calls beside them. Portfolixir stores, resolves and scores; the agent
judges. Nothing in the app calls a model.

**A private investor's sample is small.** FR-47's acceptance ("after ten
resolved predictions") would put two predictions in each of five
probability bands, and a hit rate of two is not a calibration. The Sprint
24 plan's D-10 therefore added four conditions, which the owner accepted
with the shape:

1. the headline is one score over all predictions, with its uncertainty,
   and a band is shown only above a minimum count the payload states;
2. the author is the actor plus the model the agent states at write time,
   because models change under one token;
3. sharpness is shown beside calibration, because saying 50 % to every
   question is perfectly calibrated and says nothing;
4. a prediction whose security or benchmark has no quote at its resolution
   is named unresolved, never guessed.

**What exists already.** The quote sync keeps fetching closes for every
catalogue security with an adapter and a ticker, held or not (Sprint 24
plan, verified on `1c2d8e1`), so a sold position still resolves.
ADR-0046's benchmark comparison already prices a flagged benchmark
security and a fixed rate in EUR, and `Benchmark.daily_rate_factor/1`
compounds a fixed rate daily.

## Decision

### 1. A prediction is one call on one security

A row in a new table `predictions`:

| Field | Meaning |
|---|---|
| `security_id` | the security the call is about |
| `direction` | `outperform` or `underperform`: the security's price return against the benchmark's over the prediction's window |
| `probability` | the stated probability that the direction holds, a `Decimal` from `0.50` to `0.99` in steps of `0.01`; a string in the API and the MCP schema |
| `benchmark` | ADR-0046's two kinds, as `benchmark=` spells them: `security:<id>` (a catalogue security flagged `is_benchmark`) or `rate:<decimal>` (a fixed annual rate; `rate:0` makes the call absolute: the price rises or falls). *(Amendment of 2026-11-05: the rate is a fraction from -0.999999 to 1; `rate:0.02` is 2 % a year.)* |
| `resolves_on` | the date the call is about, at least 7 and at most 1,830 days after the day it was made |
| `made_at` | the server's clock at the write, never the caller's |
| `author`, `actor` | derived from the credential, as the research log does (ADR-0054 §1): `operator` or `agent`, and the token's name |
| `model` | the model the agent states it runs on, free text up to 100 characters; required when the author is `agent`, refused when it is `operator` |
| `note_id` | optional: the research-log entry of the same security the call belongs to (its thesis, its decision, its news item) |
| `rationale` | optional text up to 4,000 characters |

**Why a probability from 0.50:** a call below 50 % is the opposite call
above it. One spelling per belief keeps the bands and sharpness
unambiguous; the API refuses `0.49` and names the other direction.

**Why the server's clock:** a prediction dated in the past is a prediction
made with its outcome in view, which is level (d) by another door. Nothing
accepts a caller's `made_at`.

**Hold decisions and news assessments are predictions too**, recorded in
the same shape: "I keep it" is `outperform` against the benchmark the
money would otherwise sit in; a news item read as positive is `outperform`
with its probability and a `note_id` pointing at the item. That is what
makes the sample grow faster than the trades.

### 2. Permanent: nothing edits, withdraws or deletes a prediction

The table is append-only in the same way `security_notes` is: a statement
trigger refuses `UPDATE` and `DELETE`. There is no withdrawal and no void.
A mistaken prediction stays and counts; a corrected one is a new
prediction, and both count.

**Why no withdrawal at all:** any path that removes a call before it
resolves is a path that removes the losing calls, and the report then
measures what its author chose to keep. The cost of a typo is one bad
score. The tool descriptions say so before the first write.

**References** (ADR-0050 §9, `Lifecycle.ForeignKeys`): the security and a
benchmark security are `merge: :refuse` and `delete: :restrict`, as the
research log's are, because a scored record can neither move nor vanish.
A delete answers 409 naming the predictions.

### 3. Resolution happens at read, from stored closes, in EUR

A prediction is `open` until `resolves_on` has passed, then `resolved` or
`unresolved`. *(Amendment of 2026-11-05: after it, open until its end
close is in, at most 7 days.)* Nothing stores the outcome; every read
derives it, and the payload names the closes it used, so a quote corrected
later changes the outcome visibly rather than silently.

- **Start:** the security's last close **strictly before** the day of
  `made_at` (UTC), so a call made during a trading day is never measured
  from a close it could have seen coming. The same day for the benchmark.
  *(Amendment of 2026-11-05: the last close **on or before** the day made.)*
- **End:** the last close on or before `resolves_on`.
- **Staleness:** a close more than 7 calendar days before the date it
  stands for is no close. Then the prediction is `unresolved` with its
  reason (`no_start_close`, `no_end_close`, `no_benchmark_close`,
  `no_fx_rate`), never estimated.
- **Currency:** both closes are converted to EUR at the stored EUR-hub
  rates of their dates, as valuation does, so a USD security against a EUR
  benchmark compares what the operator holds.
- **Benchmark return:** a security benchmark by the same rule; a fixed rate
  by `Benchmark.daily_rate_factor/1` raised to the calendar days between
  the two dates the security's closes stand for.
- **Outcome:** with `excess = security return − benchmark return`, an
  `outperform` call hits when `excess > 0`, an `underperform` call when
  `excess < 0`; `excess = 0` is a miss for both.
- **Price only:** distributions are not counted on either side, and the
  basis says so. A security with manual quotes only has no closes after
  the operator stops entering them and resolves `unresolved`.

### 4. The calibration report

`GET /api/v1/predictions/calibration`, filtered by `author`, `model` and a
`resolves_on` range, answers:

- **counts:** open, resolved, and unresolved by reason;
- **the headline**, over every resolved prediction: the **Brier score**
  (the mean of `(probability − outcome)²`, outcome 1 for a hit and 0 for a
  miss), its **standard error** (the sample standard deviation of the
  squared errors over √n), and the **reference** `0.25`, the score of
  saying 50 % to everything;
- **sharpness:** the mean of `probability − 0.50`, beside the score;
- **the hit rate** over all resolved predictions with its standard error,
  beside the mean stated probability;
- **five bands** (0.50–0.59, 0.60–0.69, 0.70–0.79, 0.80–0.89, 0.90–0.99),
  each with its count, mean stated probability and hit rate; a band with
  fewer than **20** resolved predictions shows its count and `too_few`
  instead of a hit rate;
- **groups:** the same block per `author` and `model`;
- **`computation_basis`:** the resolution rule of §3, the formulas, the
  minimum band count, that unresolved predictions are excluded and counted,
  and that no distribution is counted.

Every figure is a `Decimal` and a string in the payload; the square root
is `Decimal.sqrt/1`. **Expect the first year to read mostly `too_few`.**
That is the honest answer for a small sample, not a defect; the headline
with its standard error is meaningful from the first resolutions on.

### 5. Surfaces, agent first

- **API:** `POST /api/v1/predictions`; `GET /api/v1/predictions`, filtered
  by `security_id`, `status`, `author`, `model` and `due_before` (open
  predictions whose `resolves_on` is on or before the date: the due query);
  `GET /api/v1/predictions/:id`; the calibration read of §4. Each read
  carries the derived status, the outcome and the closes used. The write
  is journaled under the token. The contract manifest gains its entry.
- **MCP:** `portfolixir.predictions.create` (a write, not destructive, in
  the `book` and `full` profiles, as `notes.append` is), and
  `portfolixir.predictions.list`, `.get` and `.calibration` (read-only,
  every profile). The schema ceilings rise by the new tools' own bytes.
- **The recording workflow:** one MCP prompt, `position_review`, walks the
  agent through a position (the dossier, open theses, invalidation
  conditions, upcoming events) and ends by asking for predictions with
  direction, probability, date and benchmark, or for none where the agent
  has no view. It frames the result as a recorded call, never as a trade.
  This is the first prompt of idea F32; without it the table stays empty.
- **The human view comes in the next sprint:** the security page lists a
  security's predictions, and the report has its block, each on a board in
  the next planning PR. Agent first because predictions only score once
  they have been recorded for months: every week without the write path is
  a week of calls lost, while the view can only show what exists.

### 6. What it does not do

- **No model in the app.** The agent outside judges; the app stores,
  resolves and scores (`AGENTS.md`, permanent non-goals).
- **No advice and no trade.** The report scores calls and makes none; no
  field holds an order, a size or a limit, and no read proposes one.
- **No backdating, no withdrawal, no stored outcome** (§§1–3).
- **No level (d).** Nothing replays a rule or a strategy over past prices;
  a prediction is scored only against prices that came after it.

### 7. The amended requirements

FR-46 becomes: *a prediction as a permanent record of one call on one
security against a benchmark, with a stated probability, a resolution
date, its author and the model an agent names, optionally linked to a
research-log entry; resolved at read from stored closes; with a query for
due predictions.* FR-47 becomes: *a calibration report with a Brier score
and its standard error over all resolved predictions, sharpness beside it,
and a hit rate per probability band shown above a minimum count, split by
author and model.*

### 8. Gate

**B4.2 is closed by this record.** Per-source calibration (§9) and the
human view (§5) are the only named follow-ups.

### 9. The asks, answered and deferred (ADR-0043)

**Source of the asks:** FR-46 and FR-47 as written in `epics.md`, F1's row
in the idea list (2026-11-01 to 2026-11-05), and the Sprint 24 plan's D-10.

| Ask | Source | Verdict |
|---|---|---|
| Thesis | FR-46 | **Answered** — `note_id` points at the thesis entry in the research log (§1); the thesis stays in the log, which is its home (ADR-0044) |
| Stated probability | FR-46 | **Answered** — §1, from 0.50 to 0.99 |
| Check date | FR-46 | **Answered** — `resolves_on` (§1) |
| Invalidation | FR-46 | **Answered by the link** — the thesis entry's `invalidation_condition` (ADR-0044) holds it; a second copy on the prediction would drift from it |
| Action if right, action if wrong | FR-46 | **Deferred** — an action plan is a `decision` entry in the research log, where it is permanent too; on a scored object it would sit one field away from an order, which §6 keeps out |
| Outcome, resolved-at | FR-46 | **Answered** — derived at read with the closes and dates used (§3) |
| Resolution note | FR-46 | **Deferred** — the agent appends an `event_result` entry to the research log; the prediction itself stays as made |
| A query for due check dates | FR-46 | **Answered** — `due_before` (§5) |
| Hit rate per stated-probability band | FR-47 | **Answered** — §4, shown above 20 per band |
| Available after ten resolved predictions | FR-47 | **Answered differently** — the headline with its standard error from the first resolution; a band needs 20, because ten over five bands is two per band (condition 1) |
| Author including the model | D-10, condition 2 | **Answered** — §1 |
| Sharpness beside calibration | D-10, condition 3 | **Answered** — §4 |
| Unresolved, never guessed | D-10, condition 4 | **Answered** — §3, with four named reasons |
| Hold decisions and news assessments count | F1's row, 2026-11-03 | **Answered** — §1 |
| Relative to a benchmark | F1's row, 2026-11-03 | **Answered** — every prediction names one; `rate:0` is the absolute call |
| The decision it belongs to | F1's row | **Answered** — `note_id` (§1) |
| Per-source calibration (how right a source's interpretations were) | F1's row, via I13 (2026-11-01) | **Deferred** — a source is not an author, and splitting an already small sample by source shows `too_few` everywhere; filed as an issue in the planning session's registry pass |
| A recurring workflow that asks for predictions | F1's row, F32 | **Answered** — the `position_review` prompt (§5) |
| The human view | the two-way coverage rule | **Deferred to the next sprint**, with the reason in §5 |

## Consequences

- An agent can record a call in one tool call and read, at any later time,
  how its calls have scored, split by the model it runs on.
- A security with predictions can be neither merged away nor deleted, as a
  security with research notes cannot.
- A mistaken prediction cannot be removed. That is the price of a report
  nobody can tidy, and the tool descriptions say it before the first write.
- The report will mostly say `too_few` for a long time. The headline
  score with its standard error is what carries meaning early, and the
  payload says so.
- The resolution rule of §3 (a window's return in EUR from stored closes,
  with a staleness bound) is the same computation idea I18 needs for what a
  sale missed; one function serves both.

## Amendment of 2026-11-05 (the Sprint 25 closing act)

**Status:** adopted by the merge of the Sprint 25 PR. The closing act's
lenses reproduced three defects in the rules above before any prediction
was recorded on an instance; each change below is flippable by a comment
naming it. Nothing is stored (§3), so every prediction re-resolves under
these rules at its next read.

### 1. The start close is the last close on or before the day made

**Was:** the last close strictly before the UTC day of `made_at`.
**Now:** the security's last close **on or before** the UTC day of
`made_at`, within the 7-day staleness bound, and the same date for a
benchmark security.

**Why** (the money lens, reproduced): a window that starts at a close dated
before the call includes the move from that close to the moment of the
call, which the caller already knows. The quote sync stores the day's close
the same evening, so an agent writing at 22:00 UTC sees today's close and
the jump since yesterday, and a call measured from yesterday's close scores
a move it had seen. Reproduced: closes Monday 100 and Tuesday 110, a call
made Tuesday at 22:00 UTC, `outperform` against `rate:0`: measured from 100
it is a hit, from 110 a miss. From the day made's close, a call made before
that close is measured from a close that comes after it, and a call made
after the close starts from a price it knew with no move in between: no
call scores a move it saw. The old rule contradicted §6 ("scored only
against prices that came after it").

**To flip:** a comment naming "ADR-0055 start before".

### 2. A resolution waits for its end close

**Now:** after `resolves_on` has passed, a prediction stays `open` until
each priced side (the security, and a security benchmark) has a stored
positive close dated **on or after** `resolves_on`, or until 7 days after
`resolves_on` have passed (the staleness bound). That close is the evidence
that the day's data is in; it is never used in the measurement, whose end
close stays the last close on or before `resolves_on`. After the 7 days, a
prediction resolves with what is stored, or reads `unresolved` with its
reason. The due query (§5) follows: a call waiting for its end close is
open, so it is due. A later correction of a stored quote still changes the
outcome visibly, as §3 says.

**Why** (the UAT persona, reproduced): a call read the day after
`resolves_on`, measured from an older close standing for `resolves_on`
(within 7 days), read `resolved hit`; when the close of `resolves_on`
arrived late (the sync runs every 6 hours, a US close is published after
the instance's day starts, manual quotes arrive late), the same call read
`resolved miss`, and the Brier score moved. A resolved call that changes
without any correction is a score nobody can quote.

**To flip:** a comment naming "ADR-0055 finality".

### 3. A fixed-rate benchmark of a prediction is a fraction up to 1

**Now:** `rate:<decimal>` on a prediction is a fraction from -0.999999 to
1: `rate:0.02` is 2 % a year. A rate above 1 is refused with a message
naming the fraction form, by the changeset and by a database CHECK added
in a new migration. The lower bound is the engine's, unchanged; the
benchmark comparison's own wider range (ADR-0046, up to 10) is unchanged.

**Why** (the UAT persona, reproduced): `rate:5`, meant as 5 %, was accepted
as 500 % a year on a record that can never be corrected (§2), and the
descriptions said only "a fixed annual rate". A rate above 100 % a year is
not a benchmark anyone makes a call against; refusing it turns the likeliest
typo into an answer before the write.

**To flip:** a comment naming "ADR-0055 rate cap".
