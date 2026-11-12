---
layout: docs
title: "ADR-0058: Crash windows — detected by one rule on one benchmark, named by hand, ranked by price"
description: "Decision for I24 (FR-54). A crash window is a peak-to-trough decline of 10 % or more in the stored closes of one benchmark security the operator chooses; the rule fixes its dates, derived at read and never stored, so every agent gets the same windows, and the operator only names them. A manual window is stored, marked manual and may overlap. Per window, three ranked lists over the catalogue or a view's holdings: losers and winners by the EUR price return from peak to trough, rebounders by the rise from each security's own low to the end of a three-month span. Price only, survivorship named, no verdict."
---

# ADR-0058: Crash windows — detected by one rule on one benchmark, named by hand, ranked by price

- **Status:** Accepted. Adopted by the merge of the Sprint 28 planning PR
  (ADR-0026 step 1, as amended on 2026-10-08: the merge is the signature).
  **Built in Sprint 29**, not 28 (the Sprint 28 plan, D-2). Amended on
  2026-11-12 by the merge of the Sprint 29 planning PR (see "Amendment of
  2026-11-12" at the end).
- **Date:** 2026-11-08
- **Answers:** FR-54 (`epics.md`); idea I24
  (`_bmad-output/planning-artifacts/ideas.md`), as the owner narrowed it on
  2026-11-07 and drew it on idea board
  [03](../../_bmad-output/planning-artifacts/design-language/mockups/ux-design-2026-11-06-ideas-i23-i24/03-crash-rankings--light.png);
  the Sprint 27 plan's D-9, which owes this record to the Sprint 28
  planning PR and leaves it four points (the benchmark the rule reads,
  overlapping manual windows, the recovery span, a fixed 10 %).
- **Builds on:** `Portfolixir.Portfolios.Performance.WindowReturn`, the one
  window-return function sale hindsight and the prediction resolution share
  (its close lookup, its split adjustment, its EUR conversion);
  [ADR-0046's amendment of 2026-11-07](0046-benchmark-comparison.html)
  (any security with stored quotes may be a benchmark); ADR-0047's max
  drawdown, the same notion on one security; ADR-0003 (decimals).
- **Ladder:** levels (a) and (b): a derived move per security and a
  comparison against a benchmark. §8 says why the detection is not (d).
- **The Sprint 26 retrospective's first carry-forward** asks a rule that
  reads several records to be attacked for order at planning time: §7 is
  that pass. Following [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html),
  §10 lists each ask as answered or deferred.

## Context

The owner wants, for one market crash, the securities that fell furthest,
those that rose, and those that recovered best afterwards, as ranked lists
(I24, 2026-11-07). The catalogue already stores full daily history for
every security, held or not, so nothing new is fetched. What does not
exist is the window itself: no object says "the crash of spring 2020 ran
from this day to that day". If the operator or an agent drew each window
by hand, two agents asking about "the 2022 crash" would get different
dates, and a window could be drawn after the fact to make a holding look
good. The owner settled it: a window is **detected** by a rule from one
benchmark's stored closes and only **named** by the operator; a window the
rule does not give (the outbreak of a war inside a longer bear market, a
two-day sell-off) is made by hand and **marked manual**.

The record left four points open, and one premise of the idea row does not
hold: it recommends "the benchmark flagged as the default comparison", and
no such flag exists. A comparison takes its benchmark per request
(ADR-0046 §4); `is_benchmark` marks reference-only instruments, of which
an instance may hold several.

## Decision

### 1. The crash benchmark: one setting, chosen by the operator or an agent

A single instance setting, `crash_benchmark_security_id`, names the
security whose closes the rule reads. Any security with at least one stored
quote may be named (ADR-0046's amendment of 2026-11-07), flagged or not, held
or not; a merged-away one is refused with 422 naming `merged_into`. It is
set through the API and its MCP tool with the caller's token and journaled
(ADR-0054 §3), like every write. **Unset, the rule detects nothing**: the
read answers `detected: []` with `reason: "no_crash_benchmark"`, the screen
says so in one line with a link to choose one, and manual windows work
regardless. *Why one setting and not a parameter:* a parameter would let
two agents read two sets of windows and name the same crash twice; the
point of the rule is that everyone gets the same dates. *Why no default:*
the app cannot know which index stands for "the market" on an instance,
and guessing one from the flagged securities would pick by id or name.
**To flip:** "Crash-Benchmark je Anfrage" (a parameter, names keyed per
benchmark as below).

### 2. The detection rule

Over the benchmark's stored closes **in its own currency**, read in the
current display basis (`Quotes.adjust_rows/2`, so a split is not a fall),
positive closes only, days without a close skipped (no interpolation):

1. Walk the closes in date order and keep the **running peak**, the
   highest close so far. When several days share the highest close, the
   peak is the **latest** of them: the decline starts on the last day at
   the high.
2. A window **opens** on the first close for which
   `(peak − close) / peak ≥ 0.10`, compared exactly in `Decimal`. Its
   `start` is the peak's date.
3. Its **trough** is the lowest close after `start` and before the series
   first closes at or above the peak close again; among equal lows, the
   **earliest**. The window's decline is `start → trough`.
4. The window **closes** on the first close at or above the peak close
   (`recovered_on`). The walk then continues from there with that close
   as the new running peak, so windows never overlap each other.
5. A window not yet recovered at the series' last close is **ongoing**: its
   trough is the lowest close so far and is marked `provisional: true`;
   it moves while prices fall further.

A decline in several legs with no recovery in between is **one** window
(the owner's board names the consequence: the outbreak of the war folds into
the 2022 bear market). The threshold is **fixed at 10 %** (one constant,
stated in the basis as `threshold: "0.10"`); "Crash-Schwelle als Einstellung"
makes it a setting. *Why the latest peak and the earliest trough:* the
window is then the tightest span that contains the whole fall, and both
ties are decided by dates and values alone, never by an id or a read order.

**Detected windows are derived at read and never stored.** The same closes
give the same windows; there is nothing to keep in step. A detected window's
**key** is `d:<benchmark_security_id>:<start>` (its peak date), stable as
long as the benchmark's closes before the fall are.

### 3. Names, and what happens when the closes change

The operator or an agent names a detected window by its key. The name is
stored with the key (benchmark and start date), the write journaled. A
name never moves the window's dates, which stay the rule's.

**When the closes change** (a re-sync, a manual quote, a split booked
later) the rule may give a window another start date, or no window. A
name whose key no longer matches a detected window is **not re-attached by
a guess**: the read lists it under `unmatched_names` with its stored key, and
the screen shows it in the disclosure as "Name ohne Fenster", with the
choice to delete it or to make a manual window from its dates. *Why not
match the nearest window:* a nearest match picks between candidates by a
distance the operator never saw. Names are keyed per benchmark, so
switching the benchmark (§1) hides the old names under `unmatched_names`
with their benchmark named, and switching back restores them.

### 4. Manual windows

A manual window is stored: `name` (required, at most 80 characters, ADR-0054
§4's text rules), `start`, `trough` (the end of the decline; after `start`,
neither in the future), the creating token, `created_at`; `kind: manual`
on every read and on the screen ("manuell"). **It may overlap a detected
window or another manual one** (the owner's answer of 2026-11-07,
recommended: the point of a manual window is a span the rule folds into a
longer one). It is edited and deleted through the API, journaled. Its
recovery span and rankings follow §5 exactly as for a detected window. *Why
the marker matters:* a manual window's dates were chosen by a person, who
may have chosen them knowing the outcome; the marker lets every reader
weigh that.

### 5. The rankings

Per window, over a **universe** and with a **list**:

- **Universe:** `catalogue` (default), every security not merged away and
  not flagged `is_benchmark`, minus the crash benchmark itself; or
  `view:<id>`, the securities the view holds **today** (the owner's
  answer: "today's holdings in that crash" is this filter, not a
  calculation of its own). Flagged securities are left out because they are
  reference instruments, not choices; the benchmark is the reference line.
- **Losers and winners:** each security's **EUR price return from `start`
  to `trough`** by `WindowReturn.price_return/3`: its close lookup (the last
  close on or before the date, at most 7 days old), its split adjustment,
  its conversion at each close's own EUR-hub rate, one division. Losers are
  the lowest returns, winners the highest; the winners list can hold
  negative returns when few securities rose, and says so by its signs.
  Beside each: the benchmark's EUR return over the same dates, and the
  difference in percentage points.
- **Rebounders:** each security's **own low**, its lowest close (display
  basis) on a day from `start` to `trough`; its **rise** from that low to
  its close at the **end of the recovery span**, `trough` plus **three
  calendar months** (the last day of the month when the day does not exist;
  one setting for all windows, fixed first), in EUR by `WindowReturn` from
  the low's date to the span's end. Beside it: the days from its own low
  until its first close at or above its close at `start` (`days_back`), or
  `null` with `not_yet` when that has not happened by its last close.
  While the span has not ended, the list answers with `provisional: true`
  and the date it completes; a rebound is never ranked over a span shorter
  than the one it names without saying so.
- **Ties** within a list: by the figure, then by the security's name
  (case-folded), then its ISIN, never by an id.
- **Eight** per list on the screen, `limit` up to 50 in the API.
- **No answer** for a security, never a zero: `no_close_at_start`,
  `no_close_at_end` (none within 7 days, or a security younger than the
  window), `no_fx_rate`; counted per reason in the answer, listed by
  `include_unanswered=true`.

### 6. The computation basis, in every payload

The benchmark (id, name, flagged or not), the rule (`peak_trough_v1`,
threshold `0.10`, the tie rules of §2), the window's dates and kind, the
universe, the list's figure and its dates, the currency (the benchmark's
own for detection, EUR for the lists), the close lookup (7 days), the
split adjustment, the recovery span (3 months), the treatment of gaps (a
missing close is skipped by the rule and answered as `no_close_*` in the
lists), and **survivorship**: the catalogue holds what is still tracked,
so a security that failed and was removed is in no list, and the
rebounder list in particular reads better than the market did.

### 7. The adversarial pass: order, ties and after-the-fact choice

Run at planning time, as the Sprint 26 retrospective asks:

1. *Can the read order change a window?* No: the walk is by date over one
   series; equal highs and equal lows are decided by date (§2).
2. *Can two securities swap places by id?* No: ties by value, name, ISIN
   (§5).
3. *Can a window be chosen after the outcome is known?* A detected window
   cannot: its dates are the rule's, and naming does not move them. A
   manual window can, and is marked manual on every surface (§4).
4. *Can a correction of one close make a window appear or vanish?* Yes, and
   it should: the window is a property of the closes. What must not happen
   silently is a name sliding onto another window; §3 forbids it.
5. *Can an ongoing crash's trough move?* Yes, and it is marked
   `provisional`; its rankings carry the flag too.
6. *Can a benchmark switch rewrite history?* It changes the detected set,
   and names stay with the benchmark they were given for (§3).
7. *Can the threshold flap?* A decline of exactly 10.00 % opens a window
   (`≥`); 9.99 % does not. Exact `Decimal`, no float, no rounding before the
   comparison.
8. *Can a gap in the benchmark hide a fall?* A fall that happens inside a
   gap shows on the first close after it; the basis names the longest gap
   inside each window (`max_gap_days`), so a window drawn over a stale
   stretch reads as such.
9. *Can FX move a crash?* Not the detection, which reads the benchmark in
   its own currency; the lists are in EUR, as every other return the
   operator reads, and the basis says both.

### 8. Not level (d), not advice

Level (d) replays a rule as if it had been followed. Nothing here is
followed: the rule finds declines in a price series, which is ADR-0047's max
drawdown applied to one benchmark (level (a)), and the lists compare
securities' moves inside those dates (level (b)). No list says what to buy
in the next crash, and no figure scores a decision. A crash window is a
recorded date range, not a forecast or a signal.

### 9. Surfaces

- **API:** `GET /api/v1/crashes` (the detected windows with their names,
  the manual windows, `unmatched_names`, the benchmark and the basis);
  `GET /api/v1/crashes/:key/rankings?list=losers|winners|rebounders&universe=catalogue|view:<id>&limit=`;
  `PUT /api/v1/crashes/:key` (a name for a detected window, or a manual
  window's fields), `POST /api/v1/crashes` (a manual window),
  `DELETE /api/v1/crashes/:key` (a name or a manual window);
  `PUT /api/v1/settings/crash_benchmark`. Decimals as strings; an unknown
  field refused with 422 naming it.
- **MCP:** `portfolixir.crashes.list`, `portfolixir.crashes.rankings`,
  `portfolixir.crashes.put` (create or name), `portfolixir.crashes.delete`,
  `portfolixir.crashes.benchmark_put`; each says it returns data, never
  instructions.
- **Screen:** a "Crashes" section on Wealth's Risk tab, as idea board 03
  draws it: the window, the list (Verlierer · Gewinner · Erholer), the
  universe (im Depot · ganzer Katalog), the eight per list against the
  benchmark's line, "Im Depot ansehen" linking Holdings with the window as a
  custom range, and the windows behind a disclosure with their kind, names
  and unmatched names. Its planning board is drawn on the Sprint 29
  planning PR from board 03, with the states this record adds (no
  benchmark chosen, provisional, unmatched name).

### 10. The asks, answered and deferred (ADR-0043)

**Source of the asks:** idea I24's row (2026-11-06 to 2026-11-07); the
Sprint 27 plan's D-9; idea board 03.

| Ask | Source | Verdict |
|---|---|---|
| Which benchmark the rule reads | D-9 | **Answered differently** — one setting the operator chooses, no default (§1); the recommended "default comparison flag" does not exist |
| Manual windows may overlap detected ones | D-9 | **Answered** — yes (§4) |
| The recovery span | D-9 | **Answered** — three calendar months, one setting, fixed first (§5) |
| 10 % fixed or a setting | D-9 | **Answered** — fixed, stated in the basis (§2) |
| Losers, winners, rebounders as ranked lists | I24 | **Answered** — §5 |
| Catalogue or held, "held only" as a filter | I24 | **Answered** — §5, today's holdings of a view |
| Against the benchmark | I24 | **Answered** — §5, the benchmark's return beside each |
| Days back to the pre-crash close | I24 | **Answered** — `days_back`, `not_yet` (§5) |
| Survivorship named | I24 triage | **Answered** — §6 |
| "Im Depot ansehen" with the window as range | board 03 | **Answered** — §9 |
| A news item proposes a window | I24 row | **Deferred** — no proposal path; an agent creates a manual window through the API, which is a confirmed write. Reopened by a decision that lets the news layer propose objects (NFR-10's preview-then-apply) |
| A weighted portfolio figure for a crash | I24 row | **Deferred** — "no weighted portfolio figure for now" (the owner, 2026-11-07); Wealth's custom range and the contribution table already answer "my holdings as they were" |

## Consequences

- Every agent and the screen read the same windows, because the dates come
  from one rule over one series; the operator decides only which series
  and what to call a window.
- Nothing about a detected window is stored but its name, so there is no
  stored window to correct when the closes change; the cost is that a name
  can lose its window, which §3 makes visible instead of guessing.
- A manual window is the one place a person chooses dates, and it says so.
- The lists inherit `WindowReturn`'s rules, so a crash return and a sale's
  hindsight return of the same dates agree to the last digit.
- The rebounder list flatters by construction (survivorship), and says so.
- The setting is one more instance write; until it is made, only manual
  windows exist.

## Choices and how to flip them

| Choice | Flip by comment |
|---|---|
| One instance setting for the benchmark, no default | "Crash-Benchmark je Anfrage" |
| Detection in the benchmark's own currency | "Crashes in EUR erkennen" |
| Lists in EUR | "Crashes in Landeswährung" |
| Threshold fixed at 10 % | "Crash-Schwelle als Einstellung" |
| Recovery span three calendar months, one for all | a number by comment |
| A rebounder's low within `start`–`trough` | "Erholer-Tief bis Spannenende" (the low may fall after the market's trough) |
| Flagged benchmarks left out of the lists | "Crashes mit Benchmarks" |
| Detected windows derived, never stored | none: storing them would need a rule to keep them in step with the closes, which is the problem §3 avoids |

## Amendment of 2026-11-12: what drawing the screen found

**Adopted by the merge of the Sprint 29 planning PR**, before the build.
Drawing §9's planning board
([01](../../_bmad-output/planning-artifacts/design-language/mockups/ux-design-2026-11-12-sprint29/01-crash-section--light.png))
found five places where this record says less than a build needs, or
something the code does not do. None books or corrects a stored money
figure; each is decided here with its reason and flips by a comment.

### F1. A name without a window becomes a manual window only with its trough

§3 offers to "make a manual window from its dates", but a name stores only
its key, the benchmark and the start (§2, §3): the trough was never
stored. **The form takes the stored start and asks for the trough**,
under §4's rules (after the start, not in the future); nothing is
guessed from the closes. *Why not the trough the rule would give today:*
the name lost its window because the closes changed, so today's closes
are exactly what can no longer be trusted to give the old dates.

### F2. Without a crash benchmark, a manual window's lists carry no reference

§1 says manual windows work without a crash benchmark, and §5 puts the
benchmark's EUR return and the difference in points beside each security.
**With no crash benchmark set, a manual window's lists answer without
both**: no reference line, no `vs_benchmark_pp`, and the basis says
`benchmark: null` with `reason: "no_crash_benchmark"`. The ranking is
unchanged. *Why not refuse the lists:* a manual window is the operator's
own span, and ranking the securities inside it needs no market line.
**To flip:** "Ohne Crash-Benchmark keine Listen".

### F3. `days_back` counts calendar days

§5 names `days_back` without a unit. **It counts calendar days** from a
security's own low to its first close at or above its close at `start`,
stated in the basis as `days_back_unit: "calendar_days"`. *Why:* trading
days differ per venue, and a list that mixes venues would compare
different clocks; calendar days are the same for every row. **To flip:**
"Erholer-Tage als Handelstage".

### F4. „Im Depot ansehen“ only for a window the view can show

§9 links Holdings with the window as a custom range. Holdings replaces a
range that ends before the view's first day with one year and a line
that the period does not fit the data (`portfolio_live.ex`, the range
check). **For a window that ends before the view's first booking, the
section shows no link and one line saying why** ("Das Fenster liegt vor
der ersten Buchung dieser Ansicht"); a window that overlaps the view's
history links with its range as stated. *Why:* a link that opens a
different period than it names misleads. **To flip:** "Depot-Link immer".

### F5. Lane B's rule reaches the screens' resolvers too

ADR-0046's amendment of 2026-11-07 (any security with a stored quote may
be a benchmark), on which §1 builds, was filed as #1416 naming the API's
`BenchmarkParam` and `Predictions`. Two screens resolve a benchmark by the
flag as well: Holdings' benchmark choice (`resolve_benchmark_security/1`
in `portfolio_live.ex`) and the sale-hindsight section's select
(`sale_hindsight_section.ex`), which looks the id up in the flagged list
only. **Both take the same rule as the API**, so a security picked in the
new picker is never dropped silently to "not selected". This states what
the amendment already meant; it changes no reading of it.

### F6. The asks of the board (ADR-0043)

| Ask | Source | Verdict |
|---|---|---|
| A name without a window made manual | §3 | **Answered** — F1 |
| The lists without a crash benchmark | §1, §5 | **Answered** — F2 |
| The unit of `days_back` | §5 | **Answered** — F3 |
| „Im Depot ansehen“ before the view's history | §9 | **Answered** — F4 |
| The screens' benchmark resolvers | #1416 | **Answered** — F5 |

The screen's own choices (where the section sits, the window as a select,
the opening universe and window, the phone's rows, the „im Depot“ mark in
the catalogue, where the crash benchmark is chosen) are the board's, and
the Sprint 29 plan's D-5 names each with its flip.
