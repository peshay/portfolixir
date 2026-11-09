---
layout: docs
title: "ADR-0059: Lifecycles named once — a record's status derives in one module, says what it permits, and reads the same on the screen, the API and the companion"
description: "Decision for the owner's ask of 2026-11-09: find every implicit state machine and take the one decision that lifts the operator's, the developer's and the agent's experience without breaking anything. Nothing stores a status. Each lifecycle gets one status module in its own context that names its closed sets, derives the status from the evidence, says which writes the record permits today and why one is refused, and states its basis; the API carries status, permits and status_basis; the screen's buttons and labels read the same module; the companion's text names every status and permit; one invariant couples the four surfaces. Piloted on policy rules in this PR; the other lifecycles follow in the order §7 gives."
---

# ADR-0059: Lifecycles named once — a record's status derives in one module, says what it permits, and reads the same on the screen, the API and the companion

- **Status:** Proposed; adopted by the merge of this PR (ADR-0026 step 1,
  as amended on 2026-10-08: the merge is the signature). **The pilot, the
  policy rules, is built in this PR**; the migration of §7 is planned
  sprint by sprint, one lifecycle a lane.
- **Date:** 2026-11-09
- **Answers:** the owner's ask of 2026-11-09 ("find all of the implicit
  state machines in my app; make the best decision that elevates UX, DX and
  AX without breaking anything"). The inventory it rests on is
  `_bmad-output/planning-artifacts/lifecycle-triage-2026-11-09.md`; its row
  in the idea list is I31.
- **Builds on:** ADR-0004 and [ADR-0039](0039-durable-derived-values.html)
  (a figure reproduces from the ledger, so a derived value is never a
  source); [ADR-0044](0044-security-knowledge-as-an-append-only-log.html)
  (the thesis state, a projection that names the entry it derives from and
  carries its basis); [ADR-0047](0047-derived-metrics-per-security-and-per-view.html)
  (a metric states its computation basis in the payload);
  [ADR-0049](0049-policy-rules-as-first-class-objects.html) (the pilot's
  lifecycle); [ADR-0054](0054-the-agents-surface-one-authority-named-principals-escaped-text.html)
  (the companion spells out what the operator cannot see);
  [ADR-0055](0055-predictions-scored-for-calibration.html) (a resolution
  derived at read, never stored).
- Following [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html), §10
  lists what this record asks of the owner.

## Context

An audit of the whole code base on 2026-11-09 (six read-only passes, one
per domain, each finding checked against the code; the triage document
has every file and line) found about thirty records and flows whose state
the product shows without naming it in one place. Only two of them keep a
status column (a target plan's `status`, a news item's `status`); the rest
derive it at read, which is the architecture, not a defect: a thesis
state is a projection over the research log (ADR-0044), a prediction's
resolution is derived from stored closes on every read (ADR-0055), a
policy rule's status from its versions (ADR-0049 §9), the identity freeze
from reference counts (ADR-0050 §11). A stored status can be wrong; a
derived one reproduces from the ledger. **That stays.**

What is implicit, and what each of the three users pays for it:

1. **The status is not named.** The identity freeze exists only as a
   `422` on a failed write (`validation: :frozen`), so an agent learns
   that a currency is frozen by trying to change it, and the form tells
   the operator after the save, not before. A feed's health is six
   columns (`enabled`, `last_fetch_at`, `last_ok_at`, `last_error`,
   `failures`, `retry_at`), and the health read shows four of them, so no
   client can tell a feed in backoff from one that failed once. A security
   event's queue states — upcoming, past and unconfirmed, checked and
   stale — live in a boolean and a date, and the security page shows none
   of them. "Is this quote stale" is written four times
   (`DataQuality.stale_quote?/2`, `DataQuality.matches?/2`,
   `Valuation.stale_quote?/2`, two LiveViews), two of them disagreeing on a
   security never priced. A prediction's "open, waiting for the close" is
   a state only the screen knows.
2. **What a status permits is never said.** The agent learns that a rule
   cannot be deleted from a `409`, and the `409`s of the API carry four
   shapes (`errors.code` with a detail, `errors.detail` alone,
   `errors.remedy` with a route, no code at all), while two "already in
   that state" answers are not `409`s (a split already booked is a `422`
   on `date`; a repeated merge is a `200` with `already_applied`). The
   policy rule's `scheduled` covers a rule never started and a retired rule
   taken up again, and only the versions tell which one `delete` applies
   to.
3. **The guard is copied.** "Past its day" for a prediction is written
   four times (the resolution, the label module, the open-window
   pre-filter, the due query); "in force" for a policy rule three times
   (the annotation, the list's SQL filter, the findings' SQL filter); the
   merge's `same_digest` three times (one per kind); a security's
   `:retired_target` twice (the context and the merge dialog's candidate
   filter); the news item's two-to-one collapse twice with different
   column sets; the import's row layer twice (preview and apply) with two
   vocabularies.
4. **The words differ per surface.** A finding's `ok` is "met" on the
   screen; an event's `confirmed` is "Took place"; a prediction's `miss` is
   "missed" and `unresolved` "not resolved"; the finding's JSON key is
   `state` while its filter is `status`; and "stale" means five things
   (a superseded performance value, a target whose category moved, an old
   tax snapshot, a feed silent for a day, a quote older than seven days).
5. **A screen flow's phase is a combination of booleans.** The same
   idle → editing → saved flow is written four ways (an id or nil, a
   boolean, two independent ids, a boolean per entity); busy is encoded
   four ways; a destructive confirm has three mechanisms; and a few
   combinations nobody meant are reachable by a pushed event — the merge
   dialog takes `back` and `close` while it applies, the import's `apply`
   is not guarded on its stage, the security form takes `back_from_confirm`
   in edit mode and keeps `editing` set.

Two first-class users (AGENTS.md: the operator, and the agent the operator
runs) read these states, and a third — whoever maintains the code — writes
them. Each pays separately today, and a fix on one surface does not reach
the others, because nothing couples them.

What this record does **not** do, and why: it does not introduce a
state-machine library, a stored status column, or a `transition/2` that
moves records between states. The transitions of this product are its
writes — a retirement, an added version, a booking, a merge — and its clock;
they are already journaled (ADR-0017), locked and guarded where they run.
A second place that "owns" the transition would be a second truth. What is
missing is the **name**, in one place, read by every surface.

## Decision

### 1. One status module per lifecycle, in its own context

Every record or process whose state the product shows gets one status
module in the context that owns the record, implementing
`Portfolixir.Status`:

- `statuses/0` — the closed set of statuses, in the order the product
  lists them; `actions/0` — every write the record may accept, **named as
  the API's verb** (`retire`, `delete`, `add_version`, `rename`);
- `status/2` — the status on a date, **derived** from the record's
  evidence (a rule's versions, a security's references, a feed's columns),
  never read from a stored column;
- `permits/2` — the actions the record accepts today, and `refusal/3` —
  why one is refused, as the reason the API already answers
  (`:never_in_force`, `:already_retired`, `:in_force`);
- `basis/0` — one sentence: how the status and the permits derive, and
  that nothing is stored.

**The write guards consult the same function.** A context's write that
refuses by state calls `refusal/3` under the row's lock and answers its
reason; the guard exists once. A SQL filter that mirrors a status in the
query (the rule list's `maybe_not_retired`, the findings' `in_force/3`)
stays, says which function it mirrors, and a test pins that they agree.
*Why:* a guard copied three times was found drifting in wording and in
nil-handling; a guard written once cannot.

### 2. The payload: `status`, `permits`, `status_basis` — additive

Every API read of such a record carries `status` (the name), `permits`
(the list of actions it accepts today, in the order of `actions/0`) and,
once per payload, `status_basis` (`basis/0`). Nothing existing is renamed
or removed: a resource that already carries `status` keeps it, and a key
that says `state` keeps saying `state` until its own flip (C2). *Why:* a
rename breaks every client that reads the key, and the gain is the new
keys, not the old name; `permits` is what the agent asks for — "what can
I do with this" — answered before the write instead of by the `409`.

`status` is relative to the read's date (`as_of`, where the read takes
one), `permits` to **today**, the day a write would run. *Why:* a write
never runs on `as_of`; a list of past standards still tells the agent what
it can do now.

### 3. The screen reads the same module

A screen's buttons, badges and chips for such a record derive from
`permits` and `status` of the struct the context annotated — never from a
re-derivation in the LiveView. One label module per lifecycle in the web
layer carries a clause per status with **no fallback**, as
`PortfolixirWeb.PolicyRuleLabel` does, and the German catalogue carries
each. Where an action means something else in one status (a retirement on
a retired rule scheduled to restart cancels the restart), the
confirmation says which. *Why:* the dialog re-deriving "never started"
from the versions worked today and would silently diverge the day the
rule changed; a screen reading `permits` cannot.

### 4. The companion names every status and every permit

The description of the tool that reads such a record names the statuses,
the permits, what each permit does, and that `permits` is read instead of
a refusal; the companion keeps publishing no output schemas (its
descriptions are its contract, and the schema budget rules them). *Why:*
the agent's surface is the text (ADR-0054); a status the text does not
name is one the agent infers.

### 5. One invariant couples the four surfaces

`test/invariants/status_named_once_test.exs` holds the registry: one row
per lifecycle naming its status module, its web label function, its MCP
tool and the API reads that carry it. For every row the build checks that
the closed sets are named, that every status has a non-blank label with a
German translation, that the tool's text names every status, every action
and `permits`, and that the API reads carry `status` within the statuses,
`permits` within the actions and the module's `status_basis`. The test
carries its own attack case. **Adding a lifecycle is adding a row**; a
status added to a module without its label, its translation, its line in
the companion's text or its payload key fails the build. *Why:* the
coupling is what was missing; a convention without a gate decays
(ADR-0036).

### 6. One status word means one thing

A status name is used for one meaning across the product. A new lifecycle
does not reuse a word another lifecycle uses with another meaning; where
one already does ("stale", C6), the migration renames the later meaning or
qualifies it in its own payload (`stale_quote`, `feed_silent`), never the
first. The screen's label may be a phrase ("in force", "met"), but the
same status reads the same on every screen. *Why:* an agent that reads
"stale" in five payloads has five rules to remember.

### 7. The migration order

The pilot is the **policy rule** (`Portfolixir.Portfolios.PolicyRuleStatus`),
built in this PR: it has real transitions with real refusals, a screen with
buttons, a tool family, and an ambiguity (`scheduled`) that `permits`
resolves. The rest, in the order of payoff over risk, one per lane; none of
them changes an existing key:

1. **The identity freeze** (ADR-0050 §11): `status` `unfrozen` ·
   `frozen` with the frozen fields and their reference counts on the
   detail reads of securities, cash accounts and depots; the form disables
   a frozen field before the save and says why. The agent stops probing
   with writes.
2. **Security events** (ADR-0048): `status` `upcoming` · `due` ·
   `unconfirmed` · `confirmed` and a `check` of `never` · `fresh` ·
   `stale`, derived in one module from `date`, `timing`, `confirmed` and
   `checked_at`; the security page shows the two queue states it shows
   nowhere today; "Took place" becomes the label of `confirmed`.
3. **Predictions** (ADR-0055): the resolution names `awaiting_end_close`,
   so the screen's "waiting" is the payload's, and the four copies of
   "past its day" become one.
4. **Feed health** (ADR-0056, the news layer's second half): `status`
   `disabled` · `never_fetched` · `ok` · `failing` · `backing_off` ·
   `silent`, with `failures` and `retry_at` in the health read; the
   operator's page, when it lands, reads it.
5. **Quote freshness**: one `DataQuality.quote_status/2` (`fresh` ·
   `stale` · `unpriced`), the four copies gone, a per-row key in the
   valuation payloads.
6. **Target plans**: a status module over the `status` column with its
   transitions named (`activate`, `duplicate`, `delete`; archiving stays
   what activating another plan does), the changeset refusing a status
   it did not derive, and the merge preview's string-versus-atom
   mismatch (its three clauses can never match) fixed on the way.
7. **Merged-away records** (ADR-0050): `merged_from` on the survivor's
   API read, which the screen shows and the API does not.
8. **The screen flows** (§9), as each screen is touched.

### 8. What this is not

No state-machine library, no stored status column, no transition table,
no second write path. A status module **reads**; it never writes. The
rules of ADR-0004 and ADR-0039 stand: a derived value is never a source.
A status module for a lifecycle whose status is already a projection
(the thesis state) wraps that projection; it does not replace it.

### 9. The screen flows

The LiveView flows of the inventory's fifth pattern follow the same rule
in the web layer, migrated as each screen is touched, never in one pass:
a flow's phase is **one assign with a named set** (`stage`, `step`), not a
combination of booleans; busy is one encoding (the `{:busy, message}`
result slot the imports and the logo lookup use, with the server-side
guard the quote sync has); a destructive confirm is one mechanism (the
`DeletePreviewDialog` shape: a state atom, a kind and an id, confirmed only
in the one state that removes); and an event a phase does not take is
refused in the handler, not in the template. The three reachable holes
the audit found are lines on their screens' polish lists.

### 10. The asks, in ADR-0043's shape

- **Answered here:** the shape of the module, the payload keys, the
  invariant, the pilot, the order.
- **Deferred, by design, to the lane that builds each:** the exact status
  words of §7's lifecycles (each lane's ADR amendment names them against
  §6), and the boards for the screen states §7.2 and §7.4 add.
- **Not asked of the owner:** nothing here needs a fact from the owner's
  instance, changes how money is booked, or touches scope; every choice is
  flippable by a comment on this PR.

## Consequences

- The agent reads a record's status and what it may do with it off the
  payload, with the basis beside it, instead of inferring from nulls and
  learning from `409`s. The screen cannot disagree with the API, because
  both read one function. A guard exists once.
- Every payload of such a record grows by one list and one sentence; the
  companion's descriptions grow by a permits sentence each, paid for under
  the schema budget by tightening the same tools' wording (the pilot lowered
  every ceiling).
- One module and one registry row per lifecycle; the invariant is one more
  file every lifecycle story runs. A status word becomes a decision, not a
  local choice.
- Not done here: §7's seven migrations. Each is a lane with its own tests;
  none is a prerequisite of another.

## Choices and how to flip them

- **C1 — the key is `permits`.** Not `allowed`, `actions` or
  `transitions`: it reads as the record's own sentence ("the rule permits
  retire") and names writes, not states. Flip: rename the key before the
  first client reads it; after that, add the new name and keep the old.
- **C2 — additive only; the finding's `state` stays `state`.** The key
  that disagrees with its own filter (`status=`) is the one rename with a
  real cost, and this record does not pay it. Flip: a later record renames
  it with a deprecation period, both keys carried meanwhile.
- **C3 — `permits` is relative to today, `status` to `as_of`.** A write
  runs today; a read may ask about any day. Flip: carry `permits` only on
  reads whose `as_of` is today, or add `permits_on`.
- **C4 — the basis once per payload, not per row.** A list of a thousand
  rules would carry the sentence a thousand times. Flip: per row, as the
  thesis state does on a detail read.
- **C5 — a behaviour plus a registry in the invariant, not a library or a
  macro.** The behaviour makes the shape checkable by the compiler; the
  registry makes it checkable by the build; a macro would hide the
  derivation the owner may want to read. Flip: when the eighth module
  repeats the same `permits/2`, fold it into a `use`.
- **C6 — "stale" is not renamed now.** Five meanings exist and clients
  read them. Flip: each of §7's lanes that touches one qualifies its own
  (`feed_silent`, `quote_stale`) and the last meaning standing keeps the
  bare word.
- **C7 — the pilot is the policy rule, not the freeze.** The freeze is the
  larger agent gain, but it has no actions and no screen buttons today, so
  it proves less; it is first in §7. Flip: build §7.1 first.
