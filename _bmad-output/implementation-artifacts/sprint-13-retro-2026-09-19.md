# Sprint 13 Retrospective — two object families, an epic closed, and a closing act that earned its cost (2026-09-19)

ADR-0026 step 5 for the Sprint 13 batch. Written against the commits on `main`
and the Actions runs on the merge push, not against this repository's prior
claims. Three tags are outstanding, not one — `0.11.0` and `0.12.0` were
prepared by their close-outs and never pushed, so the commands for all three
are under "Close-out ledger" (D-6; ADR-0026 step 5 as amended on PR #780). The
plan was adopted by the merge of the Sprint 13 planning PR and its D-1 held:
the branch opened on the commit that merged the planning layer.

## What shipped

Fourteen issues across nine lanes on one branch, PR #832 rebase-merged
2026-09-19 20:15 UTC, `main` at `6e7de6ef`, 23 commits linear
(`2131fe0..6e7de6e`, zero merge commits). The merged tree is byte-identical to
the pre-merge head `aa5e7db`.

- **Lane A1/A4 — derived metrics per security** (#823, #824). A pure engine
  over an injected close series — SMA-50/200 with the distance to each,
  realized volatility, maximum drawdown with peak/trough/recovery dates,
  3M/6M/12M momentum, distance to the 52-week extremes — its shell loading the
  split-adjusted series in the security's own currency, the API read, the MCP
  tool, the metric strip under the price chart, and the key-set meta-test that
  makes the level (a)/(d) boundary mechanical.
- **Lane E — security events, whole** (#826–#829). The journaled table with its
  closed sets cast by hand, four reads and three writes on API and MCP with the
  **catalog** as the default scope, the Dates tab, the Fällig card, the
  re-import guarantee extended.
- **Lane C — E11's remainder** (#806–#809, #816, #817), which closed the epic.
- **Lane B** (#814) — the holdings projection's positions and a column picker.
- **Lane D** (#811) — the journal read onto the shared limit parser.
- **Lane M** — the maintenance lane and its version report.

## What the closing act found

Four roles ran under D-5. **They found eleven defects in the batch's own work,
and every one was fixed on the branch before the merge.** Three were blocking:

- Deleting a security that carried an event raised `Ecto.ConstraintError` — a
  500 on the API and a LiveView crash — because the new `:restrict` foreign key
  had no `foreign_key_constraint` beside the three already declared. Record a
  reporting date for a candidate, then drop the candidate: an ordinary
  sequence.
- A category re-homed under its own descendant hung `/classifications` forever.
  `parent_id` carries a foreign key and nothing else, so one ordinary API call
  bricked the only page that could undo it — and `Classifications` already
  guarded its own root walk at depth 32, which is the copy the new index did
  not inherit.
- `days=` was unbounded where `limit=` is capped. A huge horizon walked
  `Date.add/2` for minutes forward and left the storable date range backward,
  so the read answered a 500 or never answered at all.

The one worth reading twice is not on that list: **`held_only: true` counted
buys and sells only**, while the canonical projection also moves quantity with
the deliveries. A depot transferred in — the Portfolio Performance import's
normal shape — was reported as unheld *and marked "no position"* on the Fällig
card. That is ADR-0048 §2's own failure, the one the whole decision exists to
prevent, rebuilt one layer down inside the feature that implements it. A
default that has to be remembered is the defect rebuilt inside the product; so
is a predicate that has to be remembered.

**The risk-tier pass found two of ADR-0047's own identities unpinned.** I2's
*at scale 6* clause was unasserted because the test helper compared with
`Decimal.equal?/2`, which ignores scale — removing `round_scale/1` from the
drawdown left all twenty Lane A tests green while a real, non-terminating
peak/trough quotient would have shipped as a 34-digit string. And the I6
meta-test deleted `computation_basis` before walking the payload, although it
collects keys and never values, so the prose was already outside the match and
a verdict *key* on the basis map went uncaught. Both were mutation-verified
red, then fixed, then green.

## Process findings

1. **D-5's ordering fix worked, and the result is a negative.** The
   patch-coverage listing was read *before* promotion for the first time. It
   put `security_event_controller.ex` at 70.96 % with 27 uncovered lines, all
   error branches — where a 500 hides behind a green suite. Every reachable one
   was exercised over HTTP; every one answered a 4xx. **The read found no
   defect.** That is a result, not a formality: Sprint 11 and Sprint 12 both
   read the same listing and both found real defects, and both landed the fixes
   after promotion. Ordering was the fix, as Sprint 12's finding 2 said.
2. **`AGENTS.md` → "Required Local Checks" is incomplete, and it cost a round.**
   The list names six commands; CI's `quality` job runs four more —
   `mix compile --warnings-as-errors`, `mix credo --strict`, `mix sobelow` and
   `mix dialyzer`. One round of this batch went red on CI for exactly the two
   the list omits, and the fix (`b6f521b`) was a commit that should never have
   existed. This is the third batch to run the four anyway out of habit rather
   than instruction. **The list is a documented process rule, so an agent does
   not edit it** — it is recorded here and in the version report for the owner.
3. **"Green at promotion" has a shelf life.** `mix hex.audit` reads the
   advisory database at run time, so a job that was green can go red with
   nobody pushing anything. It did: EEF-CVE-2026-82672 was published against
   `mint 1.10.0` hours after promotion and turned `quality` red on a commit
   that changed one Markdown file. The patch released the same day and was
   ported rather than waited on. Worth knowing before reading a red check as a
   regression.
4. **Subagent reports are evidence, not verdicts.** ADR-0036 clause 2 says
   findings are verified before they are surfaced, and every role was briefed
   to reproduce first. It held: the reports arrived with reproductions
   attached, and the two that mattered most — I2's scale and the I6 blind spot
   — came with mutation proofs rather than readings. Two early findings that
   did *not* reproduce against the committed tree were discarded by the agent
   that raised them. The discipline is what made the reports usable.
5. **Small self-inflicted friction, recorded so it is not repeated.** The
   walkthrough comment's first version used HTML `<img>` tags, whose URLs the
   API mangled into code spans; Markdown image syntax survives and is what the
   next batch should use. And the PR body's gate figures went stale one commit
   after promotion — the body describes the state at promotion, so
   post-promotion changes belong in a comment, which is where they went.

## Two-way coverage

**The deadline was met, and this is the first time it has been exercised end to
end.** Sprint 12's close-out recorded that #803 removed the Transactions
holdings panel and with it the column picker that was the human half of the
holdings API's `fields=` sparse fieldset, leaving the projection's valuation
fields agent-only — allowed for the batch that creates the gap, with the human
view due in the same or the **next** epic batch. This is the next batch and
**#814 shipped in it**: Wealth → Positions lists the holdings projection with a
picker over its own fields. The rule fired, was tracked across a sprint
boundary, and was discharged on time.

Nothing in this batch is agent-only. E23's two human surfaces landed in the
same batch as its API and MCP reads, so ADR-0048's deferred-view clause never
had to fire; E22's human view landed with its engine.

## Surface check

One new bounded parameter landed — `days=` on the events family — and the
family is named in full. Its three horizon-capable reads are
`GET /api/v1/events/upcoming`, `/stale` and `/unconfirmed`. `days=` is carried
by the first two and is **deliberately absent from `unconfirmed`**: that queue
has no horizon, because every unconfirmed past date belongs in it however old
it is.

The absence is exactly what the check is for. The MCP tool advertised `days=`
on `unconfirmed` anyway — a parameter an agent could pass, that was silently
dropped and never echoed — and the correctness hunter caught it. The tool now
has its own schema, and a test pins the property set so the schema cannot drift
from the route again.

`limit=` became uniform in the same batch: #811 put the journal read on the
shared `ListLimit` parser, so the bounded-list family has one parser and no
second copy to drift.

## Close-out ledger

- **Merged:** PR #832, 2026-09-19 20:15 UTC, rebase-merge, `main` at
  `6e7de6ef`, 23 commits linear (`2131fe0..6e7de6e`, zero merge commits), tree
  byte-identical to the pre-merge head `aa5e7db`. Actions on the merge push
  verified green before this entry: CI 1552, Commit authorship 566.
- **Closed by the merge's keywords (14):** #823, #824, #826, #827, #828, #829,
  #814, #811, #807, #809, #816, #817, #808, #806.
- **Closed by hand (3):** #815, as #808's duplicate with the evidence (D-4);
  #356, E11's tracker, with the where-each-UX-DR-landed evidence; and #822,
  E23's tracker, with the four stories, the two human surfaces and this
  family's closing-act findings. A tracking issue carries no direct PR, so no
  keyword reaches it — closing the epic tracker is step 5's own job, and this
  is that pass. #819 was closed in the maintenance lane with the LTS reason,
  the third time that bump is declined for the same trigger.
- **Filed, not built (13):** #825, #830, #831 from the build; #833–#842 from
  the closing act. Every one reproduced before filing; none widened into the
  diff (Scope Lock). #838 is the only one that needed the owner, and the owner
  decided it inside the batch.
- **Epic states:** E11 **done**, E23 **done**, E22 **in-progress** — Lane A2
  (the portfolio and view figures, with identities I1 and I4's portfolio half),
  #825 and #838's payload half are still open under it.
- **The tags — three outstanding.** The latest published release is still
  `0.10.0` of 2026-09-07. The agent credential cannot push a tag (owner action,
  the 2026-09-07 decision); the owner runs:

  ```bash
  git tag -a 0.11.0 c2164f54 -m "Portfolixir 0.11.0" && git push origin 0.11.0
  git tag -a 0.12.0 5ea57ea3 -m "Portfolixir 0.12.0" && git push origin 0.12.0
  git tag -a 0.13.0 6e7de6ef -m "Portfolixir 0.13.0" && git push origin 0.13.0
  ```

  Each push triggers the Release workflow, which creates the GitHub Release
  with generated notes — a rollback point for self-hosted instances plus a
  communicable changelog, never an installable artifact (#659).
