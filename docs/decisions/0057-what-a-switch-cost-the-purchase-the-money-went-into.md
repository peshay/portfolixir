---
layout: docs
title: "ADR-0057: What a switch cost — a sale compared with the purchases its money went into, found by rule"
description: "Decision for I18's third comparison (FR-50's mode 3). A sale is compared with the buys its proceeds paid for: the buys booked from the same cash account within 30 days of the sale consume the proceeds in date order, by a fixed rule, so nobody chooses the comparison after seeing its outcome. Per span the kept side (the sold position, scaled to the money that went on) stands beside the switched side (the bought positions, cash until each buy); fees sit inside the difference, the sale's booked taxes are stated apart, because the kept side's latent tax is not known either. Price only, in EUR, derived at read, nothing stored, no verdict."
---

# ADR-0057: What a switch cost — a sale compared with the purchases its money went into, found by rule

- **Status:** Accepted. Adopted by the merge of the Sprint 26 planning PR
  (ADR-0026 step 1, as amended on 2026-10-08: the merge is the signature).
- **Date:** 2026-11-06
- **Answers:** FR-50's third comparison (`epics.md`: "the trade the
  sale's money went into with its booked costs, needs its own decision");
  idea I18, mode 3 (`_bmad-output/planning-artifacts/ideas.md`; the owner's
  second answer of 2026-11-05: "another trade, the purchase the money went
  into, where the whole money counts, fees and taxes included"); the
  Sprint 25 plan's D-3 and D-7, which owe this record to the Sprint 26
  planning PR.
- **Builds on:** FR-50 as built (the spans, the start close, the reasons
  for no answer; the Sprint 25 plan's D-3); the one window-return function
  `Portfolixir.Portfolios.Performance.WindowReturn` that FR-50 and
  ADR-0055's resolution share; ADR-0003 (decimals); ADR-0031 (the tax pot
  is recorded, never derived).
- **Ladder:** level (c), evaluation of decisions. It compares what was
  done with what was held before; it replays no rule against past prices,
  so it is not level (d).
- **The Sprint 25 retrospective's first carry-forward** asks a rule that
  evaluates a decision to be attacked at planning time: can the evaluated
  party game it, and can its answer move after the fact. §7 answers both.
- Following [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html), §9
  lists each ask as answered or deferred.

## Context

FR-50 answers "how did the sold security move after the sale", against
nothing, a fixed rate or a benchmark security. The owner's third question
is a different one: **was the switch worth it** — did the money do better
in what it was put into than it would have done in what was sold, with the
costs of switching counted?

Two things make it harder than modes 1 and 2. The comparison is not
chosen per request but is a fact of the ledger: which buys did this sale's
money pay for. And the switch had costs, some of which the kept position
would have had too (its tax, later) and some it would not (the fees of
selling and buying).

The I18 triage of 2026-11-05 assumed a stored link from a sale to a buy,
chosen by the operator, and noticed its problem at once: the link is
chosen after the outcome shows, so it needs the time it was set. A stored
link that is chosen in hindsight is exactly what the Sprint 25 closing act
found three times in ADR-0055: a rule the scored party can game.

## Decision

### 1. The purchases are found by rule, never chosen

**The matching rule.** A sale's proceeds go into the buys that paid from
the same cash account after it:

1. **Proceeds** are the sale's booked cash amount on its cash account (its
   settlement, after its fees and taxes), in that account's currency.
2. **Candidates** are `buy` bookings that debit the same cash account,
   dated on or after the sale's date and at most **30 calendar days**
   after it, of any security other than the one sold.
3. **Order:** proceeds wait in a queue by sale date, then booking id; buys
   take from the oldest proceeds first, in date order, then booking id.
   A buy takes at most its own cash debit (its price, quantity and fees);
   a sale's last buy may be funded in part, the rest of it by the next
   proceeds or by other money.
4. **What is left over** after 30 days is `unallocated` and stays out of
   the comparison: money that waited is not money that switched.

*Why a rule:* nobody chooses which buy counts, so nobody can choose the
flattering one. The rule is a reading of the ledger, so it needs no
table, no migration and no write, and the same ledger always gives the
same matches.

*What the rule cannot see,* stated in the basis: money is fungible, so a
deposit or a dividend that arrived in between could have paid for the buy
instead; the rule assumes sale proceeds are spent first. A buy on the
sale's own date counts, though it may have been paid otherwise (bookings
carry a date, not a time). Money moved to another account by a
`cash_transfer` is not followed (§9, flip "I18 follow transfers").

### 2. The two sides, per span

The spans are FR-50's: 1, 3 and 12 calendar months after the sale and to
the latest close, each `pending` until it is reached, each measured from
the sale's start close (the close on the sale day or the last before it,
within 7 days, as in mode 1). For a sale whose matched buys took a share
`a` of its proceeds (the sum of the amounts the buys took, divided by the
proceeds):

- **Kept side** at the span's end: `a` × the sold quantity × the sold
  security's close at the end, in EUR. What the part of the position whose
  money went on would be worth had it been kept.
- **Switched side** at the span's end, summed over the matched buys: for
  a buy dated after the end, the amount it took, as cash in its account's
  currency, in EUR at the end's rate; for a buy dated on or before the
  end, the share of the buy this sale paid for (the amount it took over
  the buy's cash debit) × the buy's quantity × the bought security's close
  at the end, in EUR. Before a buy, the money waits as cash and earns
  nothing, which counts against the switch.
- **The difference** is switched minus kept, **before tax** (§3).
- **Both sides are measured with the one window-return function's price
  rules:** split-adjusted closes, the stored EUR-hub rates, the 7-day
  staleness bound and its named reasons for no answer (`incomplete` with
  the side and the reason).

### 3. Costs: fees inside, taxes apart

- **Fees are inside the difference.** The sale's fees (its share `a`) and
  the buys' fees (each buy's share) are paid out of the money that
  switched, so the switched side already carries them. The read also
  states them as one line, `fees_inside`, so the reader sees how much of
  the difference they are.
- **The sale's booked taxes are stated apart** as `taxes_apart` (its share
  `a`, signed, so a refund is negative) **and added back to the switched
  side before the difference.** *Why:* the kept position would owe tax too
  when it is sold one day, and that latent tax is not booked; deriving it
  is the tax forward projection, F7, behind its own gate (ADR-0031 records
  the tax pot and never derives it). Counting the switch's tax and not the
  kept side's would make every switch look worse than it was. Both sides
  are compared before tax, and the basis says so.
- **Income is price only on both sides.** The kept side's distributions
  after the sale are not booked, so they cannot be counted; the bought
  positions' booked distributions within the span are named apart as
  `income_apart` and never added. The basis says that this understates
  whichever side paid more.

### 4. Where it is read

`GET /api/v1/sales/hindsight` gains `include=reinvestment`. Each sale row
then carries a `reinvestment` block: the matched buys (booking id, date,
security, the amount taken and the share of the buy), `days_to_first_buy`,
`a`, `unallocated`, and per span `kept`, `switched`, `difference`,
`fees_inside`, `taxes_apart` and `income_apart`, or `pending` /
`incomplete` with its reason; or, for a sale with no match, `no_match`
with one of `no_buy_within_30_days`, `proceeds_taken_by_earlier_sale`,
`no_cash_account` (an orphan sell with no settlement) and its
`computation_basis` naming the rule of §1, the 30 days, the order, the
spans, before tax, price only. The MCP tool `portfolixir.sales.hindsight`
takes the same `include`. Amounts are decimal strings (ADR-0003).

`include=reinvestment` and `benchmark=` are independent: a row can carry
both, since they answer different questions.

### 5. No verdict and no total

No field says the switch was right, wrong or too early; the figures are
the answer (no advice). **No total over all switches** is reported in
this version: a sum of every switch's difference reads as a score of the
operator's switching, which would deserve its own adversarial pass
(survivorship of the matched sales, the 30-day cut) before it is shown.
**To flip:** "I18 total", with that pass in its own amendment.

### 6. The human view

The I18 view (Sprint 26, board 03) shows it as its third comparison,
beside the fixed rate and the benchmark security, with the cost line, the
taxes apart and the days to the first buy. Built in the same sprint as
the read, so no coverage deadline arises.

### 7. The adversarial pass (Sprint 25 retrospective, carry-forward 1)

- **Can the evaluated party game it?** Not by choosing: the operator and
  the agent choose nothing, and changing the rule is an amendment of this
  record. The ways left are ledger bookings, which are journaled and
  either true or a correction: booking the buy from another account, or
  routing the money through a transfer, removes a switch from the
  comparison; that leaves it out, never makes it look better, and the
  sale row then reads `no_match` with its reason. Measuring from a close
  the party has seen is closed as in mode 1: the start is the sale day's
  close or earlier.
- **Can the answer move after the fact?** Yes, and only by the ledger: a
  booking added or corrected later (a back-dated buy, a late import)
  re-derives the matches, because nothing is stored. That is a correction,
  journaled under ADR-0017, not a silent move. A late close moves nothing
  that was final: a span is `pending` until its end close exists, as in
  FR-50.
- **Can a unit flatter it?** Both sides are in EUR, price only, over the
  same spans from the same start, so neither side can pick a better
  measure than the other.
- **The manual link, and why it is deferred:** a link the operator sets is
  the one shape that can be gamed (choose the buy that flatters), so it is
  not built. If it is ever wanted, it carries the time it was set, a link
  set more than 7 days after its buy is shown apart and never counted with
  the rule's matches, and it is journaled; flip "I18 manual link" in its
  own amendment.

### 8. What it does not do

It stores nothing, books nothing and corrects nothing. It derives no tax.
It follows no transfer. It replays no price history beyond the closes the
two sides were held over.

## Consequences

- A sale shows, beside what it missed against a rate or a benchmark, what
  the money did where it went, with the fees counted and the taxes named.
- A switch made through another account, or after more than 30 days,
  reads `no_match` with its reason and is not compared.
- The read grows by one optional block; no migration, no new tool, no
  schema change beyond the tool's `include` parameter and its description.
- The comparison is honest about its limits in its basis: fungible money,
  dates without times, price only, before tax.

## 9. The asks, answered and deferred (ADR-0043)

**Source of the asks:** I18's row in the idea list (the triage of
2026-11-05 and its open points) and the Sprint 25 plan's D-3.

| Ask | Source | Verdict |
|---|---|---|
| Which buy is "the purchase the money went into" | owner, 2026-11-05 | **Answered** — §1, by rule |
| A stored link with the time it was set | I18 triage | **Answered differently** — no stored link (§1); a manual link deferred with its conditions (§7), flip "I18 manual link" |
| A buy smaller or larger than the proceeds | I18 triage | **Answered** — §1 (a buy takes at most its debit; the rest `unallocated` or funded by the next proceeds) and §2 (the share `a`) |
| "Fees and taxes included" | owner, 2026-11-05 | **Answered** — §3: fees inside, the sale's taxes apart, both sides before tax |
| The kept position's latent tax | I18 triage | **Deferred** — F7's tax forward projection, behind its own gate |
| The buy's booked income beside the kept side's unknown income | I18 triage | **Answered** — §3, price only, the buy's income named apart |
| A buy in another currency | I18 triage | **Answered** — §1 (the queue runs in the cash account's currency) and §2 (each side in EUR through the stored rates) |
| Money moved through a transfer | this record | **Deferred** — not followed, `no_match`; flip "I18 follow transfers" |
| A total over all switches | this record | **Deferred** — §5, flip "I18 total" with its own adversarial pass |

## Choices and how to flip them

| Choice | Default | To flip |
|---|---|---|
| Which buys | by rule, same cash account | "I18 manual link" (§7's conditions) |
| The window | 30 calendar days | a comment naming another number |
| Transfers | not followed | "I18 follow transfers" |
| Taxes | apart, both sides before tax | "I18 taxes inside" (counts the switch's tax and not the kept side's) |
| A total | none | "I18 total" |
