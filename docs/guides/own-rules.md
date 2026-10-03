---
layout: docs
title: Own Rules Guide
description: Writing, changing and reading your own caps, floors and bands on the Risk page.
lang: en
lang_en: /guides/own-rules.html
lang_de: /de/guides/own-rules.html
---

# Own Rules Guide

An **own rule** writes down a limit you hold the portfolio to — "no single
security above 10 %", "cash never below 5 %", "bonds within 3 percentage
points of their target" — so that it is checked every time the Risk page is
read, instead of living in your head or in an agent's prompt, where limits
drift. The section **Own rules** at the top of **Wealth → Risk** lists the
rules of the active view with what each one finds. This guide walks through
writing a rule, reading its finding, changing it and ending it, with the
labels the screen uses. The decision behind the model is recorded in
[ADR-0049](/decisions/0049-policy-rules-as-first-class-objects.html); the
reference description of the Risk page is in the
[product documentation](/product-documentation.html#risk-concentration-and-movement),
and the same rules as your agent reads and writes them are described in
[API and MCP](/integration/api-and-mcp.html#policy-rules-adr-0049).

All names and figures below are examples.

## What a rule is

A rule reads **one figure** the app already shows, for one thing, and draws a
line against it. It is one of three kinds:

- **Cap** — breached when the figure is strictly above the line. "No single
  security above 10 %" is a cap at 10.
- **Floor** — breached when the figure is strictly below the line. "Cash never
  below 5 %" is a floor at 5.
- **Band** — breached when the figure is outside the range from **From** to
  **To**. "Bonds within ±3 percentage points of their target" is a band from
  -3 to 3 on the drift.

"Strictly" matters: a figure exactly on the line is inside it, the same way
the generic thresholds further down the Risk page read a line.

A rule belongs to the **view it was written in**. It is evaluated on that
view's steerable basis, and Risk lists it only while that view is active. A
rule written under **Everything** is a portfolio-wide rule.

## Which figures a rule can read

A rule computes nothing of its own: each figure is one the app already serves
elsewhere, read in the rule's view.

| Measure | Subject | The line is typed as |
|---|---|---|
| **Weight** | a security, a category, Cash, or a view | percent of the view's steerable basis, 0 to 100 |
| **Drift** | a category, or a security | percentage points, actual minus target in the view's active plan, -100 to 100 |
| **Concentration (HHI)** | **Whole basis** | 0 to 10,000 |
| **Volatility** | **Whole basis**, with a **Window** of 30, 90 or 365 days | percent, annualized, 0 or more |
| **Maximum drawdown** | **Whole basis**, with a **Window** | percent as the negative figure it is, -100 to 0 |

- **The subject follows the measure.** The **Subject** list offers only what
  the chosen measure can be read for, so the dialog cannot save a pair that
  has no figure.
- **A security's weight** is its single-name weight, merged across depots —
  the figure the *Largest single names* table shows.
- **A security's drift** needs one more choice, **Plan of the classification**:
  a position target lives in one classification's plan, and the drift is only
  one figure once the plan is named.
- **A bucket is capped through a view.** "The speculative bucket stays under
  5 % of everything" is a **Weight** cap whose subject is the view that
  selects that bucket, written while **Everything** is the active view.
- **A drawdown reads negative** ("-12.0 %"). "Never more than 20 % down" is
  therefore a **Floor** at -20. A positive line is refused, because a
  drawdown never rises above 0.

## Writing a rule

1. Open **Wealth → Risk**. The page header names the active view
   ("Concentration and movement · view: Everything"). The new rule will
   belong to that view. To write a rule for another view, pick that view in
   the view switcher on **Wealth → Holdings** first; the choice holds on every
   Wealth tab.
2. Click **New rule**. The dialog's first line repeats the view: "Evaluated
   in the view “Everything”, on its steerable basis."
3. Give it a **Name** in your own words, for example `Single names at most
   10 %`. The name is a label: it is never read for meaning, and two rules may
   share one.
4. Pick the **Measure**, then the **Subject**, and for a volatility or a
   drawdown the **Window**.
5. Pick the **Kind**. Type the **Line** in the unit its label shows ("Line
   (%)", "Line (pp)") — or **From** and **To** for a band — written the way
   the page writes numbers.
6. Pick the **Severity**: **Warning** or **Hard**.
7. **In force from** is today. A later date schedules the rule; an earlier
   date is refused, because a rule is never applied to a past it did not
   exist in.
8. Add a note if it helps, and click **Save rule**.

<!-- screenshot: risk-own-rules-new-rule-dialog -->

A worked example: a rule `Bonds near target` with **Measure** Drift,
**Subject** the category *Bonds* of the *Asset class* tree, **Kind** Band,
**From** -3 and **To** 3, **Severity** Warning. It stays met while the bond
category sits within three percentage points of its target in the active
plan, and it is undetermined while the view has no active plan.

## Reading the findings

Every rule in force is evaluated each time Risk is read; a finding is never
stored and never sent anywhere. The section's heading counts them
("· 1 breached · 1 undetermined · 3 met"), and the table lists one row per
rule: the **Rule** (its name, and under it its words — measure, window,
subject, kind and severity), the **Measured** figure, the **Line** and the
**State**. Breached rows come first, then undetermined, then met; within each,
hard before warning.

- **met** — the figure was read and is on the right side of the line.
- **breached** — the figure was read and is strictly beyond the line. The
  badge carries the signed distance to the nearest line ("breached ·
  +2.4 pp"). That is arithmetic, not an instruction.
- **undetermined** — the figure could not be read. The badge is dashed, and
  the reason stands under it: "12 of 20 observations" for a volatility
  without enough history, "no active plan" or "no target in the
  plan" for a drift with nothing to drift from, "nothing to weigh" for an
  empty view, "held, but not valued" for a position without a usable price or
  exchange rate, "the subject no longer exists", "the figure is undefined" or
  "not measured".

A rule set for a later date is listed under **Scheduled rules** with its
start and its line until it begins. A change scheduled for a rule in force
shows in the rule's row ("From 2026-06-01: line 8.0 %").

<!-- screenshot: risk-own-rules-findings -->

### Why undetermined is never met

A rule whose figure is missing has checked nothing. If it counted as met, a
rule set would read green precisely when half its inputs were gone — the same
silent drift the rules exist to replace, with a check mark on it. So an
undetermined finding is never counted as met, is never hidden, and always
says why. A security you do not hold is a different case: its weight is 0,
which *is* a reading, so a floor on it can breach. Only a subject that no
longer exists is undetermined.

### What severity does — and what a finding does not

**Severity** changes how a breach looks and where it sorts: a hard breach
carries the danger colour, a warning the warning colour. Nothing else
depends on it. No rule blocks a booking, an import or any other change, and
no finding says what to do: it carries no quantity, no trade and no
suggestion. Deciding what a breach means is yours.

The section *Largest single names* below it is titled "generic thresholds, not
policy rules". Its lines (a single stock above 10 %, 7 % being the first line,
an ETF above 25 %) are the app's generic heuristic. Your rules do not change
them, and they do not read your rules: a position can carry a breached rule of
yours and a generic "above 10 %" at the same time, as two separate statements.

## Changing a rule: a new version from a date

A rule's name in the table is a link. It opens the dialog "Change rule —
“…”", the one place a rule is changed. A change never overwrites: saving
creates **a new version** from the date in **In force from**, and the dialog
says so before you save — "Saving creates version 2. Version 1 (10.0 %) is in
force since 2026-03-01, ends the day before the new one and stays readable."
The button reads **Save new version**. Under the fields, **Versions** lists
every version of the rule with its period, its line, its severity and who
wrote it.

- The new version starts today by default, or tomorrow when the version in
  force only began today: a version that has started is the standard of that
  day and keeps it. A later date schedules the change.
- A version that has been in force is never changed and never deleted; its
  period ends the day before its successor starts. A version that has not
  started yet can still be changed: the dialog opens on it, and saving
  replaces it.
- So "what was my limit in March?" has an answer you can read: the version
  list shows which line was in force on which days.

## Renaming: no new version

The name is the rule's label, not part of its standard. Change only the
**Name** and the dialog says "Only the name changes: saving creates no new
version. …", and the button reads **Save name**. A rename creates no version:
the new name applies to the rule with all its versions, and the audit journal
keeps the previous name. Change the name and the line together, and the
version note gains "The new name applies to the rule with all its versions.";
one save writes both or neither. A retired rule is renamed the same way.

## Ending a rule

- **Retire rule** (in the dialog, confirmed first) ends the rule: it is no
  longer evaluated from today, and a version that only started today ends
  tonight. A change that was scheduled is dropped with it. The rule and all
  its versions stay readable under **Show the retired rules**, and a retired
  rule opens the same dialog. Saving a new version there takes the rule up
  again from that version's date.
- **Delete rule** appears instead of **Retire rule** while none of the rule's
  versions has been in force — a rule scheduled for a later date, say.
  Nothing was ever measured against it, so nothing of it needs to be kept.

## What a rule protects

A security, a category, a classification or a view that a rule reads cannot be
deleted while the rule exists. The refusal — in the page's message band on the
Views and Classifications pages, in the **Cannot delete** dialog on the
securities page — names each rule with its status and its view, as in
“Single names at most 10 %” (in force, view “Everything”), and each name links
to Risk in the view the rule applies in. Following the link makes that view
the active view on every Wealth tab, the way picking it in the view switcher
does.

Retiring the rule stops its evaluation but does not free the object: a version
that has been in force keeps its subject as the record of what the standard
was. Only deleting a rule that was never in force frees it. A security a rule
reads can still be retired, and it cannot be merged away into another
security.

## Your agent's rules

Your agent writes rules over the API or MCP with its token, and they are the
same rules you write on this page. They are in force like yours; nothing waits
for your approval.
What tells them apart is a word: a rule whose version in force the agent wrote
ends its words with “· Agent”, and so do scheduled and retired rules whose
version the agent wrote. In the dialog, every entry of **Versions** names its
author, **Operator** or **Agent**. Your own rules carry no word, so a page
without the agent's rules reads exactly as before. The audit journal names the
token that wrote each version.

An agent's rule is changed, renamed and retired like any other. A version you
save on this page is yours, and the word follows the version in force, not the
name: a rename moves no word.

## What rules do not do

- **Nothing is pushed.** A finding exists while it is read: on this page, or
  by your agent reading the breached findings. There is no notification and
  no mail.
- **No look back.** A rule is evaluated for today only, and never for a day
  before its version's **In force from** — testing a rule against a past it
  did not exist in would be backtesting, which Portfolixir does not do.
- **No advice.** A rule is your standard, evaluated; it never proposes a
  trade, a size or an order.
