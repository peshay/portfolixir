---
layout: docs
title: "ADR-0060: Halving cycles — tops and lows by each window's maximum drawdown, the next ones as an analog band, never a point"
description: "Decision for idea I12 (FR-58) and the scope ladder's analog-band entry. Between two halvings, a security's top and low are the peak and the trough of the window's maximum drawdown in its stored closes, not the highest close. The intervals between halvings, tops and lows are ladder (b). The next low and the next top are each one analog band: per relation, in time the minimum to the maximum of the past cycles' intervals and in price the last cycle's factor to that factor shrunk once more at its last rate on the logarithm, applied to the current anchors; the event's band is the hull of its parts, with the range where they overlap marked. No point forecast and no fit; n and both ends always shown. A band's state is read from the stored closes. Computed at every read, never stored, the computation basis in every payload. Scoring the band rule on past cycles stays level (d)."
---

# ADR-0060: Halving cycles — tops and lows by each window's maximum drawdown, the next ones as an analog band, never a point

- **Status:** Accepted. Adopted by the merge of the Sprint 29 planning PR
  (ADR-0026 step 1, as amended on 2026-10-08: the merge is the signature).
  **Built in Sprint 29** as its third stacked sprint PR (the Sprint 29 plan,
  D-2, as the owner decided on 2026-11-12), together with
  [ADR-0059](0059-chain-source-block-heights-and-times-for-halvings.html).
  The merge also adopts §8's amendment of the scope ladder, which lands in
  `AGENTS.md` and PRD §4 as §8 says.
- **Date:** 2026-11-12
- **Answers:** FR-58 (`epics.md`, the cycle half); idea I12
  (`_bmad-output/planning-artifacts/ideas.md`) as the owner worked it out on
  2026-11-10 over six rounds. The owner adopted every recommendation of the
  three idea boards in
  [`ux-design-2026-11-10-idea-i12`](../../_bmad-output/planning-artifacts/design-language/mockups/ux-design-2026-11-10-idea-i12/README.md):
  the "Zyklen" toggle with its dashboard card (board 01), the analog band,
  the lines between tops and lows (board 02), the lines continuing as cones,
  the "Zyklus" range, the corrected band rule (board 03), and one combined
  band per event. The row's last sentence names this record "the ladder
  entry for the projection".
- **Builds on:** ADR-0059 and
  [ADR-0048's amendment of 2026-11-12](0048-security-events-as-first-class-objects.html#amendment-of-2026-11-12-a-halving-is-an-event-and-the-chain-writes-it)
  (the halvings this record reads); [ADR-0047](0047-derived-metrics-per-security-and-per-view.html)
  (a price metric reads the security's own split-adjusted closes in its own
  currency; maximum drawdown; a gap is no observation; the float island
  and its boundary; no verdict in the payload);
  [ADR-0058](0058-crash-windows-detected-by-rule-ranked-by-price.html)'s
  tie rules for a peak and a trough; [ADR-0055](0055-predictions-scored-for-calibration.html)
  (a caller who stands behind one figure records a prediction);
  [ADR-0004](0004-holdings-derived-from-transactions.html) (what can be
  derived is not stored); ADR-0003 (decimals as strings).
- **Ladder:** levels (a) and (b) for the tops, lows and intervals: a
  derived figure per security, and a comparison of the current cycle with
  the past ones. **The analog band is none of (a) to (d)**, so §8 gives it
  its own entry, which this record adds. Scoring the band rule on past
  cycles is (d) and stays out (§8).
- Following [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html), §14
  lists each ask as answered or deferred. §13 is the adversarial pass the
  Sprint 26 retrospective asks of a rule that reads several records.

## Context

The owner wants Bitcoin's chart aligned on its halvings. Between two
halvings he wants the cycle's top and low with their dates and prices, the
days and the change from low to low, top to top, low to top and top to
low, and from these a projection of the next top and the next low (I12,
2026-11-10). ADR-0059 supplies the halvings. This record decides what is
computed from them and the stored closes, and where the projection sits on
the scope ladder.

Three things came out of drawing the boards, and each one is decided here.

**The obvious rule for a top is wrong.** "The highest close between two
halvings" picks the wrong top for 2020–2024. Inside that window, the rally
of March 2024 closed at about 73 thousand USD, above the November 2021 top
of about 68 thousand, a month before the next halving. The highest close
therefore falls *after* the window's low (November 2022) and is not the top
of the cycle anyone means. The board took the peak and the trough of the
window's maximum drawdown instead, and its README leaves "the rule the app
adopts" to this record.

**Min to max of the past cycles puts the band in the wrong place.** Every
price factor has shrunk from cycle to cycle: the drawdowns were −87, −84
and −78 %, low to low ×21 then ×5, top to top ×3.5 then ×1.8. The next
value therefore fell outside the old range every time. Min to max assumes
that the next cycle lies between the old ones, so it pushed the top → low
band too low and the low → low band too high, until the two excluded each
other. The owner noticed this on board 03 ("der rote Balken ist viel
weiter oben als das graue Tief-Band"), and the band rule was corrected.

**Two relations aim at one event.** Top → low and low → low both aim at the
next low, and halving → top and top → top both aim at the next top. They
are read from the same few lows and tops (the 2018 and 2022 lows are in
both), so they are two views of one sample, not two samples. Combining them
narrows nothing. The owner adopted one band per event, the hull of its
parts, with their overlap shaded as "both ways agree".

And one question was open in the row from the start: a projection is none
of the ladder's levels, and it sits next to the permanent non-goal "no
advice". It therefore needs a decision of its own, not a citation of the
ladder.

## Decision

### 1. The input: stored closes, halving windows, nothing else

- **The series:** the security's stored daily closes **in its own quote
  currency**, in the current display basis (split-adjusted, ADR-0028 §2,
  `Catalog.Quotes.adjusted_range/3`), positive closes only. **A day without
  a close is skipped, never filled.** The reason is ADR-0047 §1's: a price
  figure describes the instrument, and converting it would fold an FX path
  into it. A Bitcoin listing in EUR therefore has EUR cycles, and the basis
  names the currency. **To flip:** "Zyklen in EUR".
- **The halvings:** the security's `halving` events (ADR-0048's amendment).
  Windows are formed from the **confirmed** ones; the first unconfirmed one
  is the next halving.
- **A halving window** runs from one confirmed halving's date up to the
  next one's, excluding the later date. **The close dated on a halving day
  belongs to the window that starts there.** A daily close is struck at the
  end of the UTC day, which is after any block mined that day, and halving
  dates are UTC dates (ADR-0059 §5). The last window, from the last
  confirmed halving to the newest close, is **open**.
- **Complete, partial, open.** A window is **complete** when it is closed
  and the series holds a close within 7 days after its start. It is
  **partial** when it is closed but starts more than 7 days before the
  first stored close. The 2012–2016 window is partial for a series that
  begins in September 2014 (§12).
- **The view exists** for a security with **at least two confirmed halving
  events** and closes inside at least one window. Otherwise the read
  answers with `cycles: []` and a reason (`no_halving_chain`,
  `too_few_halvings`, `no_closes`), and the chart shows no toggle.

### 2. A window's top and low: the peak and the trough of its maximum drawdown

Over the window's closes in date order:

1. Keep the **running peak**, the highest close so far. Among equal
   highest closes, the peak is the **latest**.
2. At each close, its drawdown is `close / running peak − 1`, compared
   exactly in `Decimal`.
3. The window's **maximum drawdown** is the most negative drawdown. Its
   **trough** is the window's **low**, and the running peak at that
   moment is the window's **top**. Among equal maximum drawdowns, the
   **earliest** trough wins, together with its peak.

The tie rules are ADR-0058 §2's (the latest peak, the earliest trough).
They make the window the tightest span that contains the whole fall, and
both ties are decided by dates and values, never by an id or a read order.
**Why this rule:** a cycle's top is the high from which its bear market
fell, and its low is where that fall ended. The maximum drawdown is
exactly that pair, and it is ADR-0047's own figure, applied to one window.
The highest close does not care about order, so it can pick a late rally
above the old top. That is what happens in 2020–2024, as the Context
says. **To flip:** none offered. The highest close gives a top after the low.

- **A partial window** has no top (`top: null`, `reason: before_first_close`).
  Its low is the trough of the stored part's maximum drawdown, marked
  `partial: true`. A lower close before the first stored one cannot be
  excluded, and the basis says so. It enters the relations that need a low
  (§3), each marked `partial`. **To flip:** "Teilzyklen ohne Tief" (a partial
  window gives nothing; low → low then has n = 1 and no band).
- **An open window's** top and low are the same rule over its closes so
  far, and both are `final: false` until the window closes at the next
  confirmed halving.
  - **Its top is an anchor** (§4) once a close after it has been **at
    least 20 % below it**, that is, once the window's maximum drawdown so
    far reaches 20 % (`anchor_threshold: "0.20"`, stated in the basis). A
    later recovery does not undo it; only a replaced top does. Until
    then the relations that need it answer `reason: no_top_yet`. *Why a
    threshold:* without one, a dip in the first week after a halving would
    anchor a band a year away. *Why 20 %:* it is the conventional
    bear-market line, a figure every reader knows. It is not fitted to
    Bitcoin. §13 item 4 names the case it does not catch. **To flip:** a
    number by comment.
  - **Its low is an anchor only when final**, that is, when the window has
    closed. *Why waiting costs nothing:* the two relations that start from
    a low, low → low and low → top, aim at events after the next halving, by
    which time the low is final. Before that, a low that every lower close
    can still move would drag its band along. The open window's low is
    shown as `low_so_far`.

### 3. The intervals: ladder (b)

Per window and relation, with the days and the change of the closes at its
two ends:

| Relation | From → to | Change |
|---|---|---|
| `halving_to_top` | a window's halving → its top | days only |
| `top_to_low` | a window's top → its low | `low / top − 1` |
| `low_to_top` | a window's low → the next window's top | factor `top / low` |
| `top_to_top` | a window's top → the next window's top | factor |
| `low_to_low` | a window's low → the next window's low | factor |
| `low_to_next_halving` | a window's low → the next halving | days only |

An observation exists when both its ends do. An end may be a final point
or the open window's anchored top (§2). An observation with an end that is
not final is marked `provisional`, and one with a partial end is marked
`partial`. **Each relation reports `n`, its minimum and its maximum.**
This is level (b): the current cycle compared with the past ones, with its
basis. Nothing is averaged and nothing is fitted.

### 4. The analog band: one part per relation

A **part** is a rectangle in time and price for one coming event, read from
one relation alone and applied to the current anchor of that relation:

- **Time:** anchor date + the **minimum to the maximum** of the relation's
  past observations in days. *Why min to max:* the intervals show no trend
  from cycle to cycle (halving → top ran 526, 546 and 534 days; top → low
  363 and 378), so the past range is the honest range.
- **Price:** the anchor's close × the factors from the **last cycle's
  factor** ("the shrinking stops") to **that factor shrunk once more at
  its last rate, on the logarithm** ("it goes on as last time"). With the
  last two factors *f*₁ and *f*₂, oldest first, and *a* = ln *f*₁,
  *b* = ln *f*₂, the two ends are *f*₂ and *f*₂^(*b*/*a*), in either order.
  One step, no curve and no fit. Only the last two factors enter the price
  side, and the basis says so. A `top_to_low` part uses the factor
  `1 + change`.
  - *Why this rule:* the correction the Context describes. Every price
    factor has shrunk from each cycle to the next, so a band that runs
    from "stops shrinking" to
    "shrinks as it did last time" brackets the two simplest continuations
    of what the data did. Min to max of the past assumes a reversal that
    never happened.
  - **When no step is defined** (*a* or *b* is 0, or *a* and *b* have
    different signs, so the factor crossed 1 or the relation flipped
    direction), the price side falls back to the **minimum to the
    maximum** of the stored factors, with `price_rule: "min_max"` and
    `reason: "no_log_step"` in the part's basis. A step that would grow the
    factor (|*b*| > |*a*|) is taken as it comes ("as last time"), with no
    special case.
  - **To flip:** "Band nach Min/Max" (the first draw's rule for the price
    side too).
- **Minimum data:** a part needs **at least two observations** for its time
  side and two factors for its price side. Otherwise it is absent, with
  `reason: too_few_observations` and its `n`. *Why:* with one observation
  a band is a point, and a point is the forecast §8 rules out.
- **`halving_to_top`** has no price relation of its own. Its price side is
  `top_to_top`'s, and the part says `price_from: "top_to_top"`. Its time
  side starts from the next halving's window (ADR-0059 §6): from the window's
  first day + the minimum to its last day + the maximum. In this way the top
  band inherits the halving estimate's uncertainty (board 02). **When
  `top_to_top` is absent** (too few observations), `halving_to_top` is
  absent too: a borrowed side cannot outlive the part it is borrowed from
  (board 07, Sprint 29 planning).
- **The float island widens by one named operation, `:math.log/1`.** The
  step back uses `:math.pow/2`, which is already named. Decimals go in;
  on the way out come `Decimal.from_float/1` then `Decimal.round/2` at
  scale 6, for factors and prices. Nothing float is persisted. AR-3 in
  `epics.md` is amended by the same PR that adopts this record, as ADR-0047
  §4 did when it added `:math.sqrt/1`.

**The parts of each event:**

| Event | Parts | Anchors today (Bitcoin, November 2026) |
|---|---|---|
| **next low** (the low of the first window whose low is not final) | `top_to_low` (from that window's anchored top), `low_to_low` (from the last final low) | the October 2025 top; the November 2022 low |
| **next top** (the top of the first window without an anchored top) | `halving_to_top` (from that window's halving), `top_to_top` (from the last anchored top), `low_to_top` (from the last final low that has no top after it, once it is final) | the 2028 halving's window; the October 2025 top; `low_to_top` waits for the 2024–2028 window's low to be final (§2) |

### 5. One band per event: the hull of its parts, and where they agree

- **The event's band** is the **hull** of its parts: in time, from the
  earliest start to the latest end; in price, from the lowest lower end to
  the highest upper end.
- **`agree`** is the price range where **every part with a price side of
  its own** overlaps: from the highest lower end to the lowest upper end,
  when that range is not empty. Otherwise it is `null` with
  `reason: "parts_disjoint"`. The screen shades it as "beide Wege". For the
  next top, `halving_to_top` borrows its price side (§4), so until
  `low_to_top` joins there is one price relation. **For either event,
  when fewer than two parts have a price side of their own**, `agree` is
  `null` with `reason: "one_price_relation"`. A shade there would claim two
  ways where there is one.
- **No average and no intersection as the band.** The parts are read from
  the same lows and tops, so together they are no more evidence than either
  alone. An intersection is narrow by the coincidence of two rules, not by
  evidence, and in time it can be empty: top → low and low → low give
  windows in October 2026 that need not overlap. The hull shows the whole
  disagreement. **To flip:** "Band als Schnittmenge" (the band is `agree`,
  and an empty `agree` gives no band).
- **The parts stay visible:** every payload carries each part with its
  relation, anchor, window, price range, `n_time`, `n_price` and
  `price_rule`, so the combined band can be traced to what made it.

### 6. Lines and cones: from the last anchor, never past it as a line

- **Three line switches** in the cycle bar: **"Top ↔ Tief"** is on when
  cycles are on; **"Top – Top"** and **"Tief – Tief"** are off and can be
  switched on one by one. Each segment carries its days and its change, the
  figures of §3.
- **No line runs past the last anchor.** A line extended by a ruler would
  be a projection without a basis, and the band is the projection.
- **Each switched-on line continues as a cone** from its last anchor into
  the part of its own relation: two dashed edges to the part's corners, the
  area between them faintly filled. "Top ↔ Tief" goes into `top_to_low`
  after a top and into `low_to_top` after a final low; "Top – Top" goes
  into `top_to_top`; "Tief – Tief" into `low_to_low`. **It is a cone, never
  a single line,** because a band has no target point. A line would point at
  one, and that is the single figure the owner turned down for the band.
  `halving_to_top` has no line and no cone: it appears only in the combined
  band.
- **The default view** shows one filled band per event, with `agree`
  shaded. With any line switch on, the combined band is drawn as an outline
  and the cones show its parts (board 03, as adopted).
- **Low → top has no cone until its low is final** (§2). Until then the
  table shows its spread with its n (board 03: about ×8 to ×129, n = 3).

### 7. A band's state, read from the stored closes

For each combined band and each part: **`open`** before its window starts;
**`reached`** as soon as a close inside its window lies within its price
range, inclusive; **`running`** while its window has started and no such
close exists yet; **`missed`** when its window has ended without one. Each
state carries `window_ended`, and for the next low, `low_so_far`.

- **It is read, never written.** The same closes give the same state.
- **It describes the band as it now stands.** When the open window's top
  is replaced (§13 item 4), the bands move and so do their states. The
  payload's `final: false` on the anchor says that this can happen.
- **Every input of a band predates its window.** The read checks it, and
  answers `state: null, reason: "input_after_window"` otherwise. So a state
  never compares a band with closes that went into it.
- **It is not a score.** Nothing counts states, aggregates them over
  cycles, or turns them into a hit rate. That would be §8's level (d) when
  done over past cycles, and the calibration of a recorded statement
  (ADR-0055) when done over predictions.

### 8. Not a forecast, not advice, not level (d): the ladder's entry

**What the band is.** It is arithmetic on the stored cycles: their
intervals and factors, applied to the current anchors by one stated rule,
with its n and both ends. It names no single date and no single price,
fits nothing, and carries `not_a_forecast: true`. *Why no point
forecast:* with n = 2 or 3, any single figure is a curve through two or
three points. The timing has been regular, the size has not, and a fitted
decay is a model fitted to three points. A band shows how little the data
supports. A point would hide it.

**"No advice" does not block it.** The non-goal is about telling the
operator what to do with their money (PRD §4, "On 'no advice'"). A band with
its basis stated tells nothing to do: no field says buy, sell, wait or
hold, and the payload joins `metrics_carry_no_verdict_test.exs`'s key
walk, so no key contains signal, recommend, rating, score, action, alert,
verdict or advice. The row's earlier "near no advice" overstated the
problem, as the row itself says.

**A caller who wants to stand behind one figure records it.** The app
prepares and the caller calls: an operator or an agent who wants to commit
to a date records an ADR-0055 prediction, which is permanent and scored for
calibration. ADR-0055 §1 records a *direction* against a benchmark by a
date, so the nearest call is `underperform` against `rate:0` by a date (the
price will be lower then than now). A price level or the date of an
extreme cannot be recorded today, and §14 defers that.

**Scoring the band rule on past cycles is level (d).** "What the band
would have said in 2020 about the 2022 low" applies the rule to a history
in which it was not there. That is the ladder's own test for (d), and it
stays out. **The read takes no `as_of`**: a caller cannot compute a past
cycle's band from that cycle's data. An unknown parameter is refused with
422, and a test pins it. §7's state is the current band against closes
that came after its inputs, and it scores nothing.

**The scope-ladder amendment**, adopted by this record's merge. *Why:* a
projection is none of (a) to (d). It is not a derived figure of the past,
not a comparison, not a score of a recorded decision and not a replay, so
it needs an entry of its own and not an exception. A band that shows its n
and both ends is the form that says how little two or three cycles support.

- **`AGENTS.md`, the bullet "Analytics scope follows the scope ladder":**
  after the item "(d) backtesting rules against stored price history:
  forbidden, behind its own decision gate.", a fifth item:

  > - **an analog band** for a coming event — the range that the stored
  >   past cycles' intervals and factors give when applied to the current
  >   anchors, with n and both ends shown, never a single date or price
  >   and never fitted: **allowed** (ADR-0060). A caller who wants a single
  >   figure records an ADR-0055 prediction.

  The sentence after the list, "Level (c) scores what was recorded before
  its outcome was known; level (d) replays a counterfactual.", gains
  "Scoring an analog band's rule on past cycles is such a replay, so it is
  (d)." The bullet's *Why* gains, before its sources: "; the analog band
  has its own entry because a projection is none of (a)–(d), and a band
  that shows its n and both ends says how little two or three cycles
  support, where a single figure would hide it", with "ADR-0060 §8" added
  to the sources. The next bullet, "Every metric in (a)–(c) must state its
  **computation basis**", becomes "Every metric in (a)–(c), and every
  analog band, must state …".
- **PRD §4, "Scope ladder":** after the (d) item, a new item: "**Analog
  bands — in scope** (ADR-0060, 2026-11-12). A range for a coming event,
  read from the stored past cycles' intervals and factors and applied to the
  current anchors, with n and both ends shown; never a single date or
  price, never fitted. It scores nothing and replays nothing, so it is not a
  rung between (c) and (d). A caller who wants to stand behind one figure
  records an ADR-0055 prediction." "Where (c) ends and (d) begins" gains:
  "Scoring an analog band's rule on past cycles (what the band would have
  said in 2020 about 2022) is level (d): it invents a history in which the
  rule was already there." The quality bar's "every metric in (a)–(c)"
  becomes "every metric in (a)–(c) and every analog band".
- **The B7 gate registry is untouched.** The new sentences contain none of
  the words its prohibition check reads (`forbidden`, `gated`, a non-goal,
  "Do not implement"), and the (d) marker it pins is unchanged. *Why no
  new gate for point forecasts:* the entry permits a shape, and a point
  forecast is simply outside it, as any unlisted analytic is. A
  mechanical ban would need a vocabulary entry in B4 and a registry entry
  of its own, which this record does not ask for.
- **When it lands:** in the Sprint 29 planning PR, with this record (the
  Sprint 29 plan, D-11). The
  ladder text permits rather than gates, and the registry does not pin it,
  so it can stand before the code without misstating anything. That
  differs from ADR-0059 §12's gate sentence, which follows the code.

### 9. The computation basis, in every payload

The basis is review-blocking (`AGENTS.md`), so it travels with every
payload:

- **the series:** security id, currency, the display basis, positive
  closes only, the first and the last stored close, gaps skipped, never
  filled, and `max_gap_days` per window;
- **the halvings:** each with chain, height, date, `confirmed`,
  `source_quality`; the next one with its window and ADR-0059 §6's inputs;
  and `chain_source` (host, `last_ok_at`, `stale`);
- **the rules:** `window: halving_to_halving_v1` (the halving day's close
  belongs to the new window); `extremes: max_drawdown_v1` with its tie
  rules; `anchor_threshold: "0.20"`, with lows anchoring when final; the
  7-day rule for complete and partial windows;
- **the counts:** `cycles_complete`, `cycles_partial`, `cycle_open`;
- **per relation:** `n`, min, max, and which observations are
  `provisional` or `partial`;
- **per part:** `time_rule: min_max`, `price_rule: log_step_v1` or
  `min_max` with its reason, the two factors used, `n_time`, `n_price`,
  `price_from` where borrowed;
- **per band:** `hull`, `agree` or its reason, `state` and how it is read;
- **what is not computed:** `not_a_forecast: true`, no point, no fit, and
  no past cycle's band (§8).

### 10. Computed at every read, never stored

The cycles read runs the engine over the stored closes and events at every
request, and is registered at `:none` under the security basis, as
`security_metrics` is (ADR-0039). *Why:* a stored figure drifts from the
closes it came from (ADR-0004), and the input changes daily anyway (the
next halving's window, a new close, a band's state). **What a projection
said on an earlier day is kept only where someone recorded it** as an
ADR-0055 prediction. There is no history of bands, because a band history
read back over the cycles would be the replay §8 keeps out. **To flip:**
none offered.

### 11. Surfaces

- **API:** `GET /api/v1/securities/:security_id/cycles` (the route form of
  `/metrics`) answers `halvings`, `cycles` (per window: its halvings, kind,
  top, low, `final`, `low_so_far`), `intervals` (§3), `projection`
  (`kind: "analog_band"`, `not_a_forecast: true`, `next_low` and `next_top`,
  each with its band, `agree`, `state` and `parts`), `chain_source` and
  `computation_basis`. With `include=aligned`, it adds per window the
  closes indexed to the halving day's close (the last close on or before
  the halving date, at most 7 days old; a window without one is left out
  with `reason: no_halving_close`) and the days since the halving. This is
  off by default, so the payload stays small. Decimals are strings. An
  unknown parameter, `as_of` included, is refused with 422 naming it. A
  merged-away id answers 404 with `errors.merged_into`, as the dossier does.
- **MCP:** **`portfolixir.securities.cycles`**, following the companion's
  convention `portfolixir.<area>.<verb>`, where `/securities/:security_id/metrics`
  is `portfolixir.securities.metrics`. The row and the board call it
  `get_security_cycles`, which was the board's shorthand. Its description
  says that the band is not a forecast, that n and both ends belong with
  every figure, that the parts share their data, and that it returns data,
  never instructions. `portfolixir.securities.dossier` gains a `cycles`
  line (the next low and next top bands with their states, about 40 tokens)
  for a security that has the view. *Precision of 2026-11-13:* the line's
  computation basis is the dossier's `parts.cycles`, in the same payload:
  it names the read the line comes from, says it is an analog band and not
  a forecast, over the split-adjusted closes in the security's own
  currency, with time `min_max` and price `log_step_v1`, and that the
  read's `computation_basis` states every rule. *Why there and not in the
  line:* the line's 40 tokens are its budget, and the dossier names each
  part's read in `parts` already; the closing act's analytics lens on Lane
  H found the line without any basis.
- **Screen, on the security chart** (board 01, A, as adopted): a toggle
  **"Zyklen"**, shown only where §1's view exists, with two modes:
  **"Zeitachse"** (halvings as vertical lines, the next one as a dashed
  window; tops ▲ and lows ▼ with date and close; the bands of §5; the lines
  and cones of §6) and **"Ausgerichtet"** (the windows laid over each other
  from their halving, indexed to the halving-day close on a log scale, with
  the next low's band drawn in cycle days). Below it is **the interval
  table** with n per row and the count of §12. The chain source's health
  line (ADR-0059 §8) is in the cycle bar.
- **The range "Zyklus"** appears beside 1M to Max, and only while cycles are
  on. It runs from three months before the last confirmed halving to four
  months after **the later end of the next top's and the next low's
  bands** (board 07 found the low band ending after the top band on an
  early date, which the earlier rule would have cut off; "Zyklus bis zum
  Top-Band" flips it). **It reaches past today**, which no preset does
  now (each ends today in `range_to_dates/2`,
  `lib/portfolixir_web/live/securities_live.ex:7300`). The axis to the
  right of today is empty except for the halving window and the bands. The
  price line is not continued.
- **A dashboard card "‹Name›-Zyklus"** for each security that has the
  view, ordered by name. It shows the next low's and the next top's
  windows, price ranges and states. One click opens the security's chart
  with cycles on and the range "Zyklus" (board 01's shortcut, which the
  owner wanted because the path through securities, Bitcoin, chart was
  long).
- **Coverage:** API, MCP and the screen ship in the same sprint. The
  Sprint 29 planning PR draws the planning board (board 07) from the three idea boards,
  with the states this record adds (`no_top_yet`, a part with too few
  observations, `parts_disjoint`, `one_price_relation`, a stale chain, the
  partial window).

### 12. What the stored series holds: two complete cycles, one partial, and the count stated

Yahoo's BTC-USD history begins in September 2014 (ADR-0005's provider for
crypto history). The 2012 halving and the December 2013 top therefore lie
before the stored series. From stored quotes alone the view has **two
complete windows (2016–2020, 2020–2024), one partial (2012–2016, with its
January 2015 low and no top) and the open one (since 2024)**. The view
says so in one line ("2 vollständige Zyklen, 1 unvollständiger; Kurse ab
09/2014"), and the payload carries the three counts. Manually entered
closes before September 2014 (`quotes.manual`) would complete the 2012
window, and the rule would then read them like any other close. Nothing
here fetches older history. Today's n is therefore 2 for top → low,
low → low and top → top, and 3 for halving → top and low → top. The band
is drawn from that, and says so.

**Other bound securities** (ADR-0059 §4) get the same read over their own
closes and their own halvings. Triage point 6 warned that Litecoin's and
Bitcoin Cash's tops and lows have followed Bitcoin's cycle rather than
their own halvings. The view states facts (their halvings, their
drawdowns), and its n and parts say how little stands behind a band. It
does not claim a pattern. Aligning such a security on *Bitcoin's* halvings
is deferred (§14).

### 13. The adversarial pass: order, ties and after-the-fact choice

1. *Can the read order change a top or a low?* No. The walk goes by date
   over one series, and ties are decided by date (§2).
2. *Can one bad close become a top?* Yes. The rule takes the closes as
   stored, and one wrong tick at a peak moves the top and every band that
   anchors on it. The basis names every date it used, so the close can be
   checked and corrected (`quotes.manual`), and the next read follows the
   correction. No outlier filter is added, because a filter is a rule that
   chooses which closes count.
3. *Does the drawdown rule fail where the highest close did?* It cannot
   pick a top after the low, because the top is the running peak at the
   trough. It can pick an earlier high whose fall was deeper, which is the
   cycle top as the rule defines it.
4. *Can the open window's top be replaced?* Yes. In 2021 the April top
   fell 53 % by July and then a higher November top fell further. With the
   20 % threshold, the April top would have anchored bands from May 2021
   that moved in November. Every threshold has such a case. The anchor
   carries `final: false`, the bands move with it, and the record shows it
   instead of hiding it.
5. *Can a band be tuned after the fact?* The read takes no parameter that
   changes a figure. The constants (20 %, 7 days, the two rules) are fixed
   and named in the basis. Flipping one is a comment on this record.
6. *Can the partial window's low be wrong?* It can be higher than the true
   low if a lower close lies before the series. It is marked `partial`, and
   so is everything built on it.
7. *Can the log step divide by zero or turn the wrong way?* No. A factor of
   exactly 1 or a sign change falls back to min to max, named (§4).
8. *Is two points a trend?* No, and the record does not call it one. The
   step continues the last change once, and its other end is "the change
   stops". n is shown beside each end.
9. *Can a stale chain move the top band silently?* The halving window
   stays as last read, and `chain_source.stale` and its health line say so
   (ADR-0059 §8).
10. *Can a currency move a cycle?* Only by the listing chosen. The read
   uses the security's own quote currency, and a EUR listing has its own
   cycle (§1).
11. *Can a state be computed from closes that made the band?* No. §7's check
    refuses it.
12. *Can anyone compute a past cycle's band?* Not through the API (no
    `as_of`, §8), and the engine reads today's series only. A meta-test
    pins that the controller refuses `as_of`, and B4's vocabulary keeps
    `backtest`, `simulation`, `scenario` and `replay` out of every name.

### 14. The asks, answered and deferred (ADR-0043)

**Source of the asks:** idea I12's row (2026-11-01 to 2026-11-10) and its
triage points 3 to 7; the three idea boards and the owner's six answers of
2026-11-10.

| Ask | Source | Verdict |
|---|---|---|
| Every halving as an event, the next one estimated | I12 | **Answered**: ADR-0059 §5, §6; drawn as lines and a dashed window (§11) |
| The cycle's top and low with date and price | I12 | **Answered differently**: the peak and trough of the window's maximum drawdown, not the highest close (§2) |
| Days and change low → low, top → top, low → top, top → low | I12, triage 4 | **Answered**: §3, with halving → top and low → next halving, ladder (b) |
| A projection of the next top and low, by date and price | I12, triage 5 | **Answered differently**: an analog band per event, no point forecast (§4 to §6, §8) |
| The ladder entry for the projection | I12 row, owner ("rules that keep the feature out go on the test bench") | **Answered**: §8, the amendment text |
| "No advice" and a forecast ban on the test bench | owner, 2026-11-10 | **Answered**: "no advice" does not block a band with its basis; a point forecast stays outside the entry (§8) |
| A toggle on the security chart, two modes, the interval table, a dashboard card | board 01, owner ("Ja find ich gut") | **Answered**: §11 |
| An agent reads the current projection and its band over MCP | owner, third round | **Answered**: `portfolixir.securities.cycles` (§11) |
| Lines top to top, low to low, top to low | owner, fourth round; board 02 | **Answered**: §6, three switches |
| A range in which the bands are large | owner, fourth round; board 02 | **Answered**: "Zyklus", reaching past today (§11) |
| The lines run on into the bands | owner, fifth round; board 03 | **Answered**: as cones (§6) |
| The band rule corrected | owner's review; board 03 | **Answered**: §4, the log step on price, min to max on time |
| One combined prediction from both low bands | owner, sixth round | **Answered differently**: one band per event as the hull, `agree` marked, no average or intersection (§5), as the owner adopted |
| A band's state from the stored closes | board 03 | **Answered**: §7 |
| Computed at read, never stored | board 01 | **Answered**: §10 |
| The Yahoo limit stated | triage 3 | **Answered**: §12 |
| Scoring the projection on past cycles | triage 5 | **Refused**: level (d) (§8) |
| A single date and price recorded as an ADR-0055 prediction | triage 5 | **Deferred in part**: ADR-0055 records a direction by a date, not a price level or an event date (§8). Reopened by an ADR-0055 amendment with a level kind |
| B: a "Zyklen" page | board 01 | **Deferred**: worth it once more than one security has the view (board 01's own condition). Reopened when a second security is bound |
| Aligning any security on Bitcoin's halvings | triage 6, board 01 B | **Deferred**: it needs a reference chain distinct from the binding, and a comparison of one security's cycle against another's. Reopened by an amendment of ADR-0059 §4 |
| The event markers on one board with I13's note markers and F1's resolved predictions | triage 7 | **Deferred**: halvings are drawn only with cycles on; markers for every event kind and for resolved predictions are a chart-marker idea of their own, beside the note pins Sprint 28 drew |

## Consequences

- The operator and the agent read the same cycles, because the figures
  come from one rule over one series, and the agent gets them in one call
  with their basis.
- The view shows its own weakness: n = 2 or 3, a partial cycle, a top
  that may still be replaced, and two ways to a low that need not agree.
  Nothing is smoothed into a confident figure.
- Nothing about a cycle is stored, so there is nothing to correct when a
  close changes. What a band said yesterday is not kept, unless someone
  recorded a prediction.
- The ladder gains an entry. An analog band elsewhere (another relation,
  another security) follows this record's shape: parts, hull, n, basis, no
  point.
- AR-3's float island gains `:math.log/1`.
- The chart gains a toggle, a range that reaches past today, and a dashboard
  card. The companion gains one tool.

## Choices and how to flip them

| Choice | Default | Flip by comment |
|---|---|---|
| Top and low | peak and trough of the window's maximum drawdown | none offered |
| Currency | the security's own quote currency | "Zyklen in EUR" |
| A partial window | its low counts, marked `partial` | "Teilzyklen ohne Tief" |
| The open window's top as an anchor | from 20 % below it | a number by comment |
| The open window's low as an anchor | only when final | "Tief vorläufig verankern" |
| Price side of a part | last factor to one more log step | "Band nach Min/Max" |
| Time side of a part | min to max | "Band-Zeit nach Trend" |
| One band per event | the hull, `agree` marked | "Band als Schnittmenge" |
| Line switches | "Top ↔ Tief" on, the other two off | "alle Strecken an" |
| Stored or computed | computed at every read | none offered (§10) |
| No point forecast | the band only; one figure is an ADR-0055 prediction | none: the ladder entry is this shape |
