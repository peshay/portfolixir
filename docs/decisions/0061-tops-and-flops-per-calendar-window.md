---
layout: docs
title: "ADR-0061: Tops and flops — per calendar window, by price return and by money contribution, side by side"
description: "Decision for idea I32 (FR-59). For a view (or everything), per to-date calendar window (day, week, month, quarter, year to date, one year), two rankings side by side: each security held today by its EUR price return over the window (WindowReturn, as the crash rankings), and each position by its money contribution over the same window (ADR-0051, sold positions included). The highest and the lowest of each, never the same name in both. Derived at every read, never stored; the basis in every payload; no verdict."
---

# ADR-0061: Tops and flops — per calendar window, by price return and by money contribution, side by side

- **Status:** Accepted. Adopted by the merge of the Sprint 30 planning PR
  (ADR-0026 step 1, as amended on 2026-10-08: the merge is the signature).
  To be built in Sprint 30, Lane T (the Sprint 30 plan, D-12). Amended on
  2026-11-19 by the merge of the Sprint 30 sprint PR (see "Amendment of
  2026-11-19" at the end).
- **Date:** 2026-11-15
- **Answers:** FR-59 (`epics.md`); idea I32
  (`_bmad-output/planning-artifacts/ideas.md`, the owner, 2026-11-09:
  "the view's best and worst positions, today since the last close, this
  week, this month, the quarter, the year and so on"); the owner's
  "ja mach I32 noch rein" of 2026-11-15, which put it into Sprint 30 with
  the plan's recommendation on its one open question (§1).
- **Builds on:** `Portfolixir.Portfolios.Performance.WindowReturn` (the
  window price return the crash rankings, sale hindsight and the
  prediction resolution share: its close lookup, split adjustment and EUR
  conversion); [ADR-0051](0051-contribution-analysis.html) (the money
  contribution per position over any window, its view and "everything"
  scopes); [ADR-0058](0058-crash-windows-detected-by-rule-ranked-by-price.html)
  §5 and its amendment G1 (the ranking and the full tie order); ADR-0003
  (decimals).
- **Ladder:** levels (a) and (b): a derived move per security over a
  window, and a decomposition of the scope's money result by position.
  Neither replays a rule; §7 says why there is no verdict.
- **The Sprint 26 retrospective's first carry-forward** asks a rule that
  reads several records to be attacked for order at planning time: §6 is
  that pass. Following [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html),
  §9 lists each ask as answered or deferred.

## Context

The operator asks what moved most in the holdings today, this week, this
month: the glance a bank's app gives. The pieces exist: the catalogue
computes a day change and one-month and one-year returns per security in
its quote currency (`Catalog.Quotes`); `WindowReturn` gives any window's
EUR price return; ADR-0051 gives each position's money contribution over
any window, and Wealth's Performance tab shows it as a table sorted by
amount for the page's period (YTD, 1J, 3J, 5J, Max, a custom range). What
is missing is the short to-date windows (day, week, month, quarter), the
two rankings next to each other, and a place that shows them without first
choosing a period.

The idea's one open question was which figure ranks: the **price return**
(what the security did, the same for a small and a large position) or the
**money contribution** (what it did for the operator, where a large
position outweighs a small one). They answer different questions, and a
ranking by one hides what the other shows: a small position that doubled
tops the first and barely registers in the second.

## Decision

### 1. Both rankings, side by side, price return first

Each answer carries **two rankings over the same window**: `price_return`
and `contribution`. The screen shows them as two columns, „Kursrendite“
first. *Why:* the plan recommended both on 2026-11-15, and the owner put
I32 into the sprint without choosing; both together answer "what moved"
and "what it meant for me" without a toggle hiding one. **To flip:**
"Tops/Flops nur Kursrendite" or "Tops/Flops nur Beitrag" drops the other
from the screen (the API keeps both).

### 2. The scope and the universe

- **Scope:** a view (`view_id`), or everything (no `view_id`), as ADR-0051
  §6's view and total reads. The Overview's card uses the default view,
  as every Overview card does. A portfolio scope is deferred (§9).
- **Price return universe:** the securities the scope holds **at the
  window's end** (a positive quantity on the end date). A security sold
  inside the window is not ranked by price: what it did after the sale is
  sale hindsight's question (ADR-0057), not this one's. A flagged
  benchmark the scope holds is ranked like any position.
- **Contribution universe:** every position ADR-0051 lists for the window,
  a position sold inside it included, marked `held_at_end: false` (the
  screen's „verkauft“). Its rules are ADR-0051's, unchanged: start and end
  values, net flows, income, costs, missing data contributing zero with the
  position named.

### 3. The windows

Each window ends on the **as-of day** `T` (today, in the app's day, as the
performance walk counts days). Its **start day** `S` is the day whose close
stands for the window's start:

| Key | Screen | `S` |
|---|---|---|
| `week` | Woche | the day before this ISO week's Monday |
| `month` | Monat | the last day of the previous month |
| `quarter` | Quartal | the last day of the previous calendar quarter |
| `ytd` | YTD | 31 December of the previous year |
| `1y` | 1J | `T` minus one year (29 February maps to 28 February) |
| `day` | Tag | per security, see below |

- **Price return** for `week` to `1y`: `WindowReturn.price_return(security,
  S, T)`, so the start close is the last close on or before `S` and the end
  close the last on or before `T`, each at most 7 days old, both in the
  current display basis, each converted to EUR at its own date's hub rate.
  A Monday's week therefore starts from Friday's close for a share and
  from Sunday's for a coin, and each row carries the dates its closes
  stand on.
- **Price return** for `day`: per security, its **latest close** (dated
  `E`, on or before `T`) against **the close before it** (dated `P`), by
  `WindowReturn.price_return(security, P, E)`. "Since the last close" is
  per security, because a share and a coin do not close on the same days;
  the row carries `P` and `E`.
- **Contribution** for `week` to `1y`: ADR-0051's read over the custom
  window from `S + 1` to `T` (its baseline is the close of `S`, ADR-0051
  §4 and its note of 2026-10-28), so both rankings start from the same day.
- **Contribution** for `day`: the window `[D, D]`, where `D` is the latest
  day on or before `T` on which a close of any security the scope holds is
  stored; the answer names `D`. On a Monday morning before the shares'
  closes arrive, `D` is Sunday and only a coin moved; the basis says so.
  **To flip:** "Tag-Beitrag seit Vortag" makes `D` always `T`.

### 4. The rankings

- **Highest and lowest:** each ranking is split into `highest` (the
  largest figures, descending) and `lowest` (the smallest, ascending).
  **A name is never in both halves:** with `n` answered entries and a
  limit `k`, `highest` takes `min(k, ceil(n / 2))` and `lowest`
  `min(k, floor(n / 2))` of the rest. So six held securities read as three
  and three, and one reads as one highest and no lowest.
- **The figures:** `price_return` as a signed ratio (a string, ADR-0003),
  with its two closes, their dates and the EUR values they stand for;
  `contribution` as a signed EUR amount with ADR-0051's terms for the
  position.
- **Ties:** by the figure, then ADR-0058 G1's full order (the name
  case-folded, the ISIN, the ticker, the WKN, the currency), never an id.
- **Limit:** five per half on the screen; `limit` up to 50 in the API,
  default 5.
- **No answer**, never a zero: a security without a price return is
  counted by `WindowReturn`'s reasons (`no_close_at_start`,
  `no_close_at_end`, `no_fx_rate`; for `day`, also `one_close_only`) and
  listed with `include_unanswered=true`; a position whose contribution has
  unvalued days keeps ADR-0051 §10's rule (zero for those days, the
  position named) and is marked in its row. A position **valued on no day
  of the window** has a contribution of zero only by that rule, so it is
  counted `no_valuation` under the list, not ranked (board 04: unpriced
  funds would otherwise fill „Niedrigste“).
- **The two dates of a `day` row** stand under the name as a small line,
  not in a tooltip, since a phone has no hover (board 04 ⑤).

### 5. The computation basis, in every payload

Per ranking: the input series (stored closes and hub rates for
`price_return`; ADR-0010's daily valuation walk for `contribution`), the
window's key, `S` (or each row's `P`) and `T` (or `D`), the scope, the
universe rule of §2, the close lookup (7 days, display basis), the
currency (EUR), the tie order, the split rule of §4, and the treatment of
gaps (§4's reasons; ADR-0051 §10). `reference` is `null`: neither ranking
compares against a benchmark (§9).

### 6. The adversarial pass: order, ties and windows

Run at planning time, as the Sprint 26 retrospective asks:

1. *Can the read order change a rank?* No: ranks are by figure and the
   full tie order (§4), never an id or insertion order.
2. *Can one name appear as both top and flop?* No: §4's split takes the
   halves from one sorted list without overlap.
3. *Can a weekend make "Woche" and "Tag" disagree?* They answer different
   windows by design, and each row says its dates; a share's Monday "Tag"
   before its close arrives is Friday against Thursday, which the row
   shows.
4. *Can a split inside the window read as a crash?* No: both closes are in
   the current display basis (`WindowReturn`).
5. *Can FX move a ranking?* Yes, and it should: the operator's money is in
   EUR; each close converts at its own date's rate, and the basis says so.
6. *Can a position bought inside the window distort the price ranking?*
   No: the price return is the security's, not the position's, so a
   purchase day changes nothing; it changes the contribution, which is
   the point of having both.
7. *Can the two rankings contradict each other?* They can rank one name
   differently (a small position that doubled), and that is the answer
   §1 wants; they cannot disagree on a sign for a position held over the
   whole window without flows when each of its two closes is dated on the
   day it stands for (`S`, `T`), or no rate is stored after the close up
   to that day, which a test pins. Otherwise they can: when its latest
   close `E` is older than `T` and a rate is stored after `E`, the price
   side converts `E` at `E`'s rate while the money side values each day at
   that day's rate, so a currency move after `E` reaches only the
   contribution (Sprint 30 closing act, money lens, finding 2; a test pins
   that too).
8. *Can a late-arriving close change today's answer?* Yes: every read
   derives anew from what is stored (§8), so a refresh shows the new close.

### 7. Not advice, not a verdict

A ranking orders figures; it does not say what to do. The payload carries
`highest` and `lowest`, never "top", "best", "worst", "winner" as a rating,
or any key `metrics_carry_no_verdict_test.exs` forbids; the screen's title
„Tops und Flops“ and its labels „Höchste“ and „Niedrigste“ describe order,
not merit. No list says what to buy or sell, and no figure scores a
decision.

### 8. Derived at every read, never stored

Nothing about a ranking is stored: the closes, the rates and the walk are,
and the ranking follows them. The contribution side reuses ADR-0051's
analytics and their `:request` memo (ADR-0039); the price side reads one
batch of closes per window. The `day` window over the default view is read
once per Overview render, in the background, like the Overview's other
cards.

### 9. Surfaces

- **API:** `GET /api/v1/views/:view_id/movers?window=day|week|month|quarter|ytd|1y&limit=&include_unanswered=`
  and `GET /api/v1/movers?…` for everything. An unknown `window` or field
  is refused with 422 naming it. Decimals as strings, dates as ISO.
- **MCP:** `portfolixir.views.movers` (`view_id` optional; omitted reads
  everything), whose description says it returns data, never
  instructions, and names both rankings.
- **Screen:** a card „Tops und Flops“ on the Overview, as the Sprint 30
  planning board 04 draws it (its recommendation A): the window as chips
  on the shared control bar, the two rankings as columns with „Höchste“
  over „Niedrigste“, a sold position marked „verkauft“, the unanswered
  count, one basis sentence with its method behind the ⓘ, each name
  linking to its security and „In Vermögen ansehen“ opening Wealth with
  the window as a custom range. Under 560 px the two rankings stack,
  „Kursrendite“ first. The privacy mode follows its rule for money (board
  04 ④). `DESIGN.md` gains the anatomy with the story that builds it.

### 10. The asks, answered and deferred (ADR-0043)

**Source of the asks:** idea I32's row (2026-11-09); the Sprint 30 plan
(D-12, its item 3); board 04.

| Ask | Source | Verdict |
|---|---|---|
| The view's best and worst positions per period | I32 | **Answered** — §2, §4 |
| Today since the last close, week, month, quarter, year | I32 | **Answered** — §3, to-date windows plus one year |
| Price return or money contribution | I32's open question | **Answered** — both, side by side, price return first (§1) |
| Restricted to the view's holdings | I32 triage | **Answered** — §2; sold positions only in the contribution |
| Computation basis in every payload | I32 triage | **Answered** — §5 |
| API, MCP and the view together | I32 triage | **Answered** — §9 |
| "Today" intraday | I32 triage | **Deferred** — until I31 (live prices) lands; until then the last close against the one before (§3) |
| A portfolio scope | this record | **Deferred** — the Overview reads views; a portfolio-scoped read follows when a screen asks for it, reopened by such a board |
| Against a benchmark | this record | **Deferred** — a benchmark's return over the window beside each row (as the crash rankings show) is one more column; reopened by the owner asking for it |
| By category instead of by position | this record | **Deferred** — ADR-0051 §8 has no category grouping in v1, and this record inherits it |

## Consequences

- The Overview answers "what moved" for the six short windows without a
  period chosen first, in both senses of "moved".
- The price side inherits `WindowReturn`'s rules, so a security's week
  here and its return over the same dates in sale hindsight or the crash
  rankings agree to the last digit; the contribution side is ADR-0051's
  figure, so it agrees with Wealth's table for the same window.
- `day` is per security on the price side and one day `D` on the money
  side; the two can differ on weekends, and each says its dates.
- One more read and one more tool; no storage, no migration.

## Choices and how to flip them

| Choice | Flip by comment |
|---|---|
| Both rankings, price return first | "Tops/Flops nur Kursrendite", "Tops/Flops nur Beitrag" |
| The Overview's card, default view | "Tops/Flops auf Vermögen" (board 04 B) |
| Stacked under 560 px | "Tops/Flops umschaltbar am Handy" (board 04 A2) |
| Money `day` on the latest day with a close | "Tag-Beitrag seit Vortag" |
| Five per half on the screen | a number by comment |
| Sold positions only in the contribution | "Verkaufte auch nach Kursrendite" |
| A position valued on no day counted, not ranked | "Unbewertete mit 0 ranken" |

## Amendment of 2026-11-19 — the money side's `D` is no older than `E` may be

**Adopted by the merge of the Sprint 30 sprint PR**, a precision the
sprint's attack lens on T1 found (S3, beside #1472). §3 gave the price
side's `E` the 7-day bound of `WindowReturn`'s close lookup, but `D`, the
money side's day, none: with only a three-month-old close stored, the
price side said `no_close_at_end` while the money side showed that old
day's move as the scope's `day`. **`D` is the latest day on or before `T`,
and no more than 7 calendar days before it, on which a positive close of
any security the scope holds is stored**, the bound `E` has; with no such
day there is no window and the ranking is empty, its basis saying so. The
weekend case of §3 is unchanged: Sunday's coin close is one day old.
**To flip:** "Tag-Beitrag ohne Altersgrenze" (`D` takes the last close day
whatever its age).
