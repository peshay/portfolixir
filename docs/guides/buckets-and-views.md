---
layout: docs
title: Buckets & Views Guide
description: Worked use cases for grouping wealth with buckets and views.
lang: en
lang_en: /guides/buckets-and-views.html
lang_de: /de/guides/buckets-and-views.html
---

# Buckets & Views Guide

Portfolixir groups wealth with two tools instead of portfolios: a
**bucket** is a label on depots and cash accounts, a **view** is a saved
filter over buckets that scopes the analytics pages and can carry its own
target plan. This guide walks through four real grouping needs with the exact
clicks, so an existing setup maps onto the model instead of being
reverse-engineered. The reasoning behind the model is recorded in
[ADR-0024](/decisions/0024-buckets-and-views-replace-portfolios-in-the-ui.html);
the reference description lives in the
[product documentation](/product-documentation.html#accounts-and-depots).

## Which do I need — a bucket or a view?

A **bucket** answers "what is this account part of?" — it is a label on
depot and cash-account rows, and nothing more. A **view** answers "what do
I want to look at (and steer)?" — it is a saved include/exclude filter over
buckets, picked in the view switcher, settable as the default, and the
carrier of a target plan. Rule of thumb: tag reality with buckets, then
create one view per recurring question. Buckets alone change nothing on the
analytics pages; only a view scopes what is shown.

## Use case 1: "My wealth" vs. "whole household"

Scenario: some accounts are shared with a partner, and two numbers are
wanted: own wealth and the whole household — without a joint account ever
counting twice.

1. Open **Accounts & depots** (sidebar, Administration area). Every row shows
   its bucket memberships as chips.
   <!-- screenshot: accounts-depots-bucket-chips -->
2. On each solely-owned row, click the **+** chip (**Add bucket**),
   type `Mine` into the **New tag** field, and click **Create tag**. The tag
   is created and assigned in one step.
3. Tag the partner's rows the same way with a new tag `Partner`. Tag shared
   accounts with **both** — buckets are free overlapping labels, so a joint
   account may carry `Mine` and `Partner` at once.
4. Open **Views** (sidebar, Administration area — the same page the view
   switcher's **Manage…** link opens). Under **2. Views**, type `My wealth`
   into **New view** and click **Add view**.
5. Click **Edit view buckets** on the new row. In the **Buckets for My
   wealth** dialog, check `Mine` under **Include buckets** and press
   **Save view**.
   <!-- screenshot: views-page-edit-view-buckets -->
6. Repeat for a second view `Household` that includes `Mine` **and**
   `Partner` (or simply check **Include all buckets**).
7. Open **Wealth**, pick `My wealth` in the **View:** switcher at the top of
   the page, and click **Set as default** under **Default view**. The Wealth
   page and the Overview page now open on the personal number; the switcher
   still flips to `Household` or the built-in **Everything** at any time.
   <!-- screenshot: wealth-view-switcher-set-default -->

**The counts-once guarantee.** In a view's total, every account is counted
exactly once, no matter how many of the view's buckets it carries. The joint account
tagged `Mine` and `Partner` appears once in `Household`, not twice. When a
view's buckets share an account, the Wealth page shows a badge next to the
total — *Overlapping buckets — accounts counted once* — stating that
the per-bucket figures are overlapping facets and must not be summed; the
total itself is already deduplicated.

## Use case 2: a strategy view with its own target plan

Scenario: a retirement strategy runs across depots at several brokers and
needs its own target allocation and drift tracking — independent of
everything else held.

1. On **Accounts & depots**, tag every depot that belongs to the strategy
   with a new tag `Retirement` (the **+** chip → **New tag** → **Create
   tag**), regardless of which broker it sits at.
2. On **Views**, create a view `Retirement` that includes the `Retirement`
   bucket (steps 4–5 above).
3. Open **Classifications**, select the custom tree used for steering, and find
   the **Target plan** section of its detail pane. In the selector **Target
   plan for view:** pick `Retirement`.
4. Click **Create plan** (or **Copy from another view…** to prefill from an
   existing plan), enter a **Target %** per category plus the **Cash**
   target, watch the **Σ** footer reach 100 % ✓, and press **Save plan**.
   Plans are bound to the view (ADR-0020): `Retirement` now carries its own
   plan, and other views keep theirs — or none.
   <!-- screenshot: classifications-target-plan-for-view -->
5. Open **Wealth** and switch to `Retirement`. The Target and Drift columns
   now measure only the strategy's holdings against the strategy's plan; the
   drift amounts state what to trim or add inside the strategy.

## Use case 3: coming from Portfolio Performance

In Portfolio Performance, depots or portfolios often serve as
categories — one "portfolio" per strategy, employer, or family member.
Buckets and views replace that habit without the bookkeeping split.

- **What the one-time migration created.** When the data was migrated
  (ADR-0024), every former portfolio became **one bucket and one view of the
  same name**, so every previously visible number still has a view that
  shows it. The Wealth page announced this once with a dismissible notice
  listing the seeded views. Rename both freely on the **Views** page
  (**Rename bucket** / **Rename view**) — the names were only carried over,
  nothing depends on them.
- **Migrated an empty database, restored data afterwards?** The one-time
  migration only converts the portfolios it finds. After an upgrade run
  against an empty database with the data restored later, run
  `mix portfolixir.seed_scope_buckets` once — it seeds the missing scope
  bucket + view per portfolio and is safe to re-run (already-seeded
  portfolios are skipped).
- **What imports do now.** The import preview no longer asks for a target
  portfolio. Instead it offers an editable bucket tag — *The accounts created
  by this import get the bucket tag:* — pre-filled with a date-stamped
  `PP Import <date>`. Keep it to find the imported accounts later, type the
  name of an existing bucket to reuse it, or check *No tag — leave the new
  accounts untagged* to skip tagging entirely.
  <!-- screenshot: import-preview-bucket-tag -->
- **Where the portfolio records went.** Portfolios still exist as internal
  compatibility records, but they carry no behavior in the UI. The
  **Accounts & depots** page lists them in the collapsed, read-only
  **Portfolio records (compatibility)** panel; there is no create or edit UI
  anymore.

So the PP habit "one depot per category" translates to: keep depots as the
bookkeeping reality the broker statements match, and put the categories into
bucket tags — an account can carry several, which depot-as-category never
allowed.

## Use case 4: count it, don't steer it

Scenario: Bitcoin held as a long-term store of value. It belongs in total
wealth, but it should not distort the strategy's target allocation —
the motivating case of ADR-0018 (see
[ADR-0018](/decisions/0018-buckets-tag-based-wealth-scoping.html)).

1. On **Accounts & depots**, tag the depot (or account) holding the position
   with a new tag, e.g. `Store of value`.
2. On **Views**, click **Edit view buckets** on the strategy view and check
   `Store of value` under **Exclude buckets**. Exclude always wins: even if
   the account also carries an included bucket, it stays out. Press
   **Save view**.
3. Check the result on **Wealth**: under the built-in **Everything** view the
   position counts toward the total as before; under the strategy view it
   disappears from the 100 % basis and the drift table, so every other
   category's actual weight is measured against the steered mix only.

Nothing is hidden and nothing is flagged per security — the same position is
simply inside one view and outside another.

## Honesty note: re-tagging rewrites history

A view resolves its buckets **as of today**. When an account is re-tagged, the
view's whole historical series is recomputed with the new membership — there
is no "tagged since" date. That is why view-scoped performance series carry
the label *Composition as of today*: the chart answers "how would this view
have developed with its current composition?", not "what did I see last
year?". Bucket changes are recorded in the audit journal, so when a
membership changed stays reconstructable — but historical view figures move
when buckets are reorganized.
