# Sprint 16 — the second security pass, the lifecycle merges, and the scope line made mechanical

**Status: ADOPTED by the merge of the Sprint 16 planning PR.**
The merge is the signature (ADR-0026 step 1 as amended on PR #780). This
planning PR **signs one decision gate**:
[ADR-0050](../../docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md),
the design gate for #328 and #608, risk-tier. The merge also adopts:

- the lane cut and **D-1** to **D-12**;
- the security review triage of 2026-09-24
  (`planning-artifacts/security-review-triage-2026-09-24.md`), with its epic
  **E25** and its eight issue groups (**D-4**);
- the design picks of **D-5**, on the boards of
  `planning-artifacts/ux-design-2026-09-24-sprint16.md`;
- the decision on #872 (**D-6**) and the route for FR-41 (**D-7**).

Nothing here is `DRAFT` or `Proposed`. A decision the owner rejects is
removed on the PR before the merge. A closure the owner rejects is undone by
a comment naming its issue.

**This PR also carries three repairs that could not wait for a batch**, each
as its own commit: a scrub of five committed records that described the
maintainer's real data rather than synthetic cases; invented values for one
real booking that two parser tests reused, with the comments and user docs
that repeated its date; and the removal of an unreferenced screenshot with no
provenance (**D-11**).

**Verification basis:**

- **`main` and CI:** `main` at `44fb82a9` (the Sprint 15 close-out), with
  **CI 1595** green on it, read 2026-09-24. No pull request was open.
- **The open-issue list of 2026-09-24:** 24 open, every body and comment
  read, each claim checked against the code on `main` (the design pass and
  D-8 name where a claim no longer holds).
- **The published releases:** latest **0.14.0** (2026-09-23). **`0.15.0` is
  not yet published**, so one tag is outstanding (D-9).
- **The security review of 2026-09-24:** a whole-system review against
  `main` in eleven dimensions plus a completeness round, every finding verified
  by three independent lenses before it was counted: 107 survive (one high,
  six medium, sixty-seven low, thirty-two informational, one needing no action)
  and one was refuted. The triage names each by class and fix; the full report
  is held privately by the owner (D-4).
- **The scanners, run locally the same day:** `mix sobelow --skip --exit`,
  `mix hex.audit`, `mix deps.audit` and `npm audit` all clean.
- **The design pass this PR carries:** twelve boards, rendered with the real
  `priv/static/app.css`.

## State of play, in five lines

1. **Sprint 15 merged and E24 is done.** PR #867 rebase-merged 2026-09-24,
   fourteen issues closed by keyword and #861 by hand. Nothing was shrunk.
   The closing act filed nine findings (#868–#876), and two agent-only debts
   older than the two-way rule were paid.
2. **The second security review found no hole inside the trust boundary that
   the first one closed, and one outside it that nobody was looking at.** The
   release image builds on an Elixir tag Docker Hub stopped rebuilding in May
   2025. Every operator instance therefore runs an Erlang/OTP whose TLS client
   has two published certificate-verification bypasses, while CI tests a
   patched OTP. None of the audit gates reads the runtime. D-2 ships the fix
   before the batch.
3. **Everything else the review confirmed is hardening, not rescue.** Credentials
   and sessions, the deployment files and log level, provider redirects and
   plausibility, input bounds that stop a crafted request from pinning a core
   or crashing a page, import robustness, and the audit trail's remaining
   silent paths. Eight issue groups, **E25**, filed at branch opening (D-4).
4. **The lifecycle merges get their gate, and the gate closes a live hazard
   first.** ADR-0050 turns #328 and #608 into one relabelling with a
   re-import contract. Its importer half also closes a defect that exists
   today with no merge involved: renaming an account over the API makes the
   next import create an empty "zombie" account, or double the history if
   the export drifted.
5. **The runway moves by one sprint, deliberately.** The triage of 2026-09-23
   counted about three sprints of product work, the last of them Sprint 17.
   The security pass is the owner's ask for this sprint and takes a real share
   of it, so whatever Sprint 16 shrinks lands in Sprint 17 next to FR-41's
   build and B4.2, whatever that displaces lands in Sprint 18, and maintenance
   mode starts after Sprint 18 (D-12).

## Why this cut

- **Security first, because the owner asked for it and because one finding is
  shipping today.** The hotfix (D-2) goes out before the batch opens. The
  rest of E25 is the batch's first lane. The triage names each weakness by
  class and fix in public from the moment this planning branch is pushed, so a
  named weakness stays public for this planning round plus one batch, not a
  backlog age (the 2026-09-05 precedent); its issues are filed the day the
  branch opens (D-4).
- **The lifecycle merges are the runway's headline, and their importer half is
  a correctness fix in its own right.** ADR-0050's L1 and L2 never shrink.
  The security merge (#608's L4) is the lane's fallback cut (shrink order,
  steps 3 and 4: its screen first, then L4 in full).
- **NFR-9 turns the scope line from prose into tests.** It is tests only, no
  production code, and it discharges precondition (b) of the Phase 3 gate.
  It belongs next to a security pass: both make a promise mechanical.
- **The closing act's debt splits by reach (Sprint 15 D-9).** The
  user-reachable E24 remainder (#870, #871, #872) rides the batch. The design
  conformance findings (#869, #873–#876) ride last and are the first cut.
  #868 is hostile-input only and joins E25's input-bounds group, where it
  belongs by class.
- **File ownership keeps one branch safe.** Lane S owns the plugs, config,
  the Docker and Compose files, `Net.Http`, the controllers' input parsing
  and the importer's parsers. Lane L owns `Imports.Applier`, the portfolios
  and catalog lifecycle modules, `portfolio_accounts_live.ex` and the new
  `lifecycle/` modules. **Two places are shared.** In `imports/applier.ex`,
  Lane S's import group touches only the content hash, the
  companion-with-parent rule and the result recorders (F36, F37, F40), after
  Lane L2's hash-first reordering (sequencing below), because F36 and F37
  change the hashes L2's retired-hash contract reads. In the account, depot
  and security changesets, S4's length bounds land after L1's identity
  freezes (ADR-0050 §11).

## Lanes

### Lane H — the runtime hotfix (before the batch; D-2)

One small single-concern PR, squash-merged, tagged **`0.15.1`** (patch
versions are reserved for hotfixes):

- both images and CI move to one exact toolchain on **OTP 27.3.4.18**:
  `hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20260918[-slim]` for
  the build and dev images, `debian:bookworm-20260918-slim` for the release
  runtime, CI's `elixir-version: 1.18.5` and `otp-version: 27.3.4.18`, the PLT
  key and the agent install script. This also closes the Elixir 1.18.3
  advisory the Sprint 14 and 15 reports tracked as "no official image";
- each new `FROM` line is pinned by **tag and digest**
  (`<tag>@sha256:<digest>`), as ADR-0045 §2 requires; the existing Dependabot
  `docker` entry keeps the digests current, and S2 (F25) extends the pin to
  the Compose images and the companion's image;
- an **invariant test** that the CI inputs, both `FROM` lines and the install
  script name one Elixir and one OTP, like #728's Node pin;
- `scripts/version-report.sh` prints the OTP **inside** the base image beside
  the OTP CI resolves, because checking the tag is exactly what hid this;
- the operator docs (EN and DE) say to rebuild with `--pull`, because
  `docker compose up --build` reuses a cached base image and would not deliver
  this fix either;
- **lane evidence:** CI green, a PLT rebuilt under the new key, and the
  release image built and booted, printing its OTP version;
- **its issue** (triage S0), filed by Lane Z right after this merge and named
  in the hotfix PR with a closing keyword.

Risk-tier attention (ADR-0036): the invariant is that images, CI and the
install script name one toolchain; the test above pins it.

### Lane S — E25, the second security pass (first in the batch)

Eight issue groups, each its own commit group, each fix landing with the test
that reproduces its finding **red first**. The triage (Part 3) lists what each
group holds; the table here is the lane's order.

| Group | Class | Why this order |
|---|---|---|
| **S1** | Credentials and sessions: the MCP token policy and a failure throttle on the companion; a password change ends existing sessions; the proxy header read across all its lines, and the proxy contract's wording; login throttling with a scope-wide ceiling; boot validation of the secret key and a warning for a short UI password (T-2); the CSRF token rotated at login | the perimeter first: every other finding's severity depends on who can reach the port |
| **S2** | Deployment and logging: the production log level; the development Compose file on loopback; image digests; file modes for secrets and dumps; the Compose exposure warning and the qualified loopback-only reach; the recommended database roles (T-6); the image build context mirroring `.gitignore`; Erlang distribution off in the release; the release tree not writable by its user; the restore procedure; stack traces and error views | the documented deployment is what adopters run |
| **S3** | Outbound requests and provider data: no redirect without a policy re-check; plausibility bounds on provider quotes and FX rows; bounded inserts; bounded search payloads; path encoding; the URL policy's IPv6 ranges; one serial worker for the enrichment every created security starts | provider data feeds every valuation |
| **S4** | Input bounds and cost: dates, decimals and their scale bounded at the boundary for every writer; one text validator for length and the characters the database refuses; list sizes; a cap on the risk read's Top-N and its correlation cost; a bound on the derived-value memo; cycle guards in the category walk; duplicate ids and dates answered as 422; LiveView events and params parsed through the shared parsers, **with #868 folded in** | a crafted request must never pin a core, crash a page or backdate a rule |
| **S5** | Import robustness: files that crash or stall the preview, encoding, bounded names and renders, hash separators, the tax-refund companion hash; **F36 and F37 are risk-tier: idempotency** (ADR-0036), each its own commit inside the group | the importer is the one path that eats third-party files |
| **S6** | The audit trail and integrity: cascades that remove journaled rows silently, bucket deletes included (T-10); future dates on research entries and event checks; view definitions under in-force rules; length caps on the append-only text and no journal entry for a write that changes nothing; races on the assignment and target writers; data-version ordering, memo races and the delta cursor; the quote overwrite (T-9); split rows outside the split flow; tax identity folding; the settlement guard when the gross amount is missing | integrity of the records is a security property here |
| **S7** | Browser and agent-surface hygiene: cross-site writes of the UI scope; `Cross-Origin-Resource-Policy`; invisible Unicode in text an agent reads; the MCP companion's published schema, its rebinding guard, its redirect behaviour, its tool hints, an opt-in read-only switch, named principals and an author on rule versions (T-8); stored text marked as data | low reach, and the agent's mistakes made smaller |
| **S8** | CI supply chain: dependency lifecycle scripts in the MCP image build and the documented install; unpinned tooling; the migration-immutability gate's rename bypass; workflow token persistence and interpolation | hygiene; the first group cut inside the lane, after the informational items |

**Overlap with Lane L, stated so it is not done twice:** the silent cascades
on **accounts, depots and securities** are ADR-0050 §11's, built in L1. S6
covers the cascades from **classifications, categories, plans, views and
snapshots**.

**What a reader sees changes in few places, and each is boarded** (design
pass, Parts 11 and 12). Board 11 draws four before/after repairs: the named
import file errors (S5), the research log's refusal of a future date (S6),
Risk's pair that cannot be computed (S3, S4) and an error page for every
status (S2). Board 12 draws the three new marks with their picks (G12.1 to
G12.3 in D-5) and two more before/after repairs: the bucket-delete confirm
(T-10) and a zero-value position's drift (G14).

**Within the lane, informational items are the first cut** (thirty-two of the
107), ahead of S8 and S7 (shrink order, step 2): each stays filed under its group, and whatever does not ship moves to
Sprint 17's debt lane with its public window named in the close-out.

**The briefing callout** names, per group, the finding class, the invariant
and the test, and never the reproduction (D-4). Four records gain amendment
notes in the batch where E25's decisions and fixes touch them: ADR-0049 (an
author on each rule version, T-8; view-definition writes journaled, F45),
ADR-0017 (its quote exemption narrowed to the sync writers and ADR-0050 §13's
merge writer, T-9), ADR-0018 (a bucket delete journals its cascade, T-10;
view-definition writes journaled, F45) and ADR-0045 (sessions bound to the UI
password, F02; its loopback-only reach qualified, F76).

**T-9's release of manual quotes ships agent-first**, over API and MCP only:
quotes have no human write surface today, so a release control would be the
page's first quote write. Its control on the security's quotes lands no later
than Sprint 17, on a board drawn at that planning, under the two-way
deadline.

### Lane L — the lifecycle merges (ADR-0050; risk-tier)

Five commit groups, in the order below. ADR-0050 fixes only that the importer
half (L2) lands before any merge endpoint; the rest of the order is this
plan's. Three issues under E3's tracker **#417**: the existing **#328** and
**#608** (attached to #417 at branch opening), and one new issue for L2, filed
at branch opening:

- **L1, foundation (risk-tier: audit):** `merge_records` and
  `retired_import_hashes`, append-only and journal-armed; the foreign-key
  disposition map and its `pg_constraint` meta-test; delete hardening on the
  three existing delete paths (journaled removals, declared constraints, a row
  lock, the 409 remedy body); the identity-field freezes swept over every
  writer. No endpoint.
- **L2, the re-import contract (risk-tier: idempotency; one commit group):**
  hash-first ordering with preview decisions executed from the mapping;
  retired-hash consultation and the insert trigger; lazy creation; the
  internal-transfer skip; the scoped in-run key; former names with their
  resolution, their guard and the identity lock; stale-mapping revalidation;
  the "already imported" counts. **This closes today's rename hazard on its
  own**, and no merge endpoint lands before it. *New issue.*
- **L3, cash and depot merge (risk-tier: money and quantity)**, API and MCP
  for accounts, the former-names routes. **#328.**
- **L4, security merge (risk-tier: quantity and idempotency)**, API and MCP.
  **#608.**
- **L5, the operator surfaces** on the picks of D-5 (boards 01–04): the
  accounts row menu with rename, merge and delete; the merge preview; the
  security merge flow; the import preview's new states. `GET /api/v1/merges`
  and its MCP tool ship agent-first, and the list view lands no later than
  Sprint 17 under the two-way deadline (ADR-0050 §12). `GET /api/v1/merges`
  in the batch's contract entry, the MCP descriptions carrying the re-import
  sentence, EN and DE docs.

**Mutation-verified in the closing act** (D-10), and re-run after the fix
rounds: every invariant of ADR-0050 §16. The UAT persona runs #328's five-step
plan on the synthetic seed; the owner's run on real data stays the
`needs-uat` step, and #328 is closed by hand once it is done.

### Lane N — NFR-9, the scope line made mechanical (tests only)

One issue, filed at branch opening under **#420**. Seven invariant files under
`test/invariants/`, each standing alone, each with a matcher self-test so a
clean tree cannot pass vacuously, each allowlist entry carrying a reason (the
permanent class) or an accepted ADR (the gated class):

- **B1** no credential-bearing schema, column, virtual field or settings key;
- **B2** one GET-only outbound chokepoint, a registry of its adapters, a host
  allow-list, an environment-name allow-list, and the MCP companion's single
  egress. **B2 lands after S3**, which changes `Net.Http`'s redirect default;
- **B3** direct and transitive dependencies checked against the non-goal and
  gated classes. The denylist names protocols and categories generically and
  **never the providers of any one operator**, which would disclose them;
- **B4** no route, tool, event, table or module named for a non-goal or for a
  gated capability without its ADR;
- **B5** registries of the system writers and the self-scheduling processes;
  the dormant scenario index stays dormant; the rules' as-of line cannot be
  moved from the web layer;
- **B6** no intake path accepts PP XML or the binary workspace;
- **B7** a registry tying every hard gate's sentence in AGENTS.md to its
  backstops, so amending one without the other fails.

No API, MCP or UI coverage applies (no capability is added). No board
applies (no rendered difference).

### Lane D — the E24 remainder and one accessibility repair

- **#872, decided (D-6):** a rule may be renamed, as a journaled rule-level
  edit outside the versioning; `PATCH /api/v1/policy_rules/:id` and an MCP
  tool; the dialog's name field on edit; the affordance on the pick of board
  07 (G7).
- **#871:** a view-context rule reachable from the refusal that names it, on
  the pick of board 06 (G6). Under G6-A the issue's shape half (the refusal
  dialog for a view delete) is **declined**, not built: Sprint 15's board
  `06-rule-reference-409` kept the message band for view deletes. The issue
  says so when it closes.
- **#870:** every row kebab named for its row, through one shared trigger
  component; a transaction row gets a composed name (kind, security, date).
  No rendered difference, so no board.

### Lane C — design-spec conformance (last; first cut)

Held against the spec by the standing design-critic gate (ADR-0038), each
with its before/after or options board:

- **#869**, narrowed to its numeric half: one shared render-and-parse helper
  for decimal inputs in the page's locale and an `input.num` rule (board 05).
  The two date bullets are **not** defects (UX-DR19 fixes ISO dates in
  inputs); the issue says so when it closes;
- **#873** and **#874**, the classification detail at 390 px and the live
  children-Σ hint (board 08, with pick G8 for the category row);
- **#875**, five rough edges of the Positions mode at 390 px (board 09). The
  drift item needs no decision: ADR-0040 §2 settles the computation, and only
  its basis line is missing;
- **#876**, the area tab row at its end (board 10, pick G10).

### Lane R — research and one decision record

- **#330's discovery story.** A synthetic Portfolio Performance export with
  one invented bond (a made-up name and identifier; no example from the issue
  is reused in the fixture, the test or the verdict), a characterization test of what today's valuation does with it,
  and a verdict on the issue: does it shrink (master data only, a small
  Sprint 17 story, or close) or grow (its own ADR, risk-tier)? Nothing is
  built on valuation before the verdict. The owner can confirm the one
  unknown privately, without any figure entering the repository: whether a
  bond's quantity is exported as its face amount or as a hundredth of it.
- **The FR-41 decision record** (D-7), written in this sprint with its board
  and delivered as the opening commit of Sprint 17's planning PR, whose merge
  signs it.

### Lane M — maintenance (always present)

- **The first commit of the branch:** the BMAD re-pin deferred by Sprint 15
  (core and method 6.11.0 → 6.12.0, test architect and creative suite to
  their current tags). The installer rewrites `_bmad/`; the diff is read for
  personal configuration before anything is committed, and
  `_bmad/config.user.toml` and `_bmad/memory/**` are never force-added. The
  builder module's major version is its own decision and stays out.
- **`hpax` 1.0.4 → 1.1.0** (transitive; hardening only), its own commit.
- **#314:** Codecov's project target from 85 % to 90 %, confirmed against the
  current figure first; the stale comment fixed.
- **#727:** both triggers re-checked (neither fired on 2026-09-24). The
  hotfix's move to 1.18.5 is a patch within the pinned minor and needs neither.
- **Node 26 LTS arrives 2026-10-28**, after this sprint; recorded, not taken.
- **The version report** before the closing act, with the OTP inside the
  image as its own row from now on.

### Lane Z — registry (small)

- **Right after the merge, before the branch opens:** the closures by hand in
  D-8, and the hotfix issue (triage S0), which the Lane H PR closes by keyword.
- **At branch opening:** E25's tracker and its eight group issues; the new L2
  issue under #417, and #608 attached to #417; the NFR-9 issue under #420;
  the FR-41 side findings (D-7); ADR-0050's six deferrals (§15); the
  follow-ups the security triage names inside its rows (dry-run deletes, G28;
  a Compose network split, F62; a per-portfolio rule cap, F74; commit-ordered
  delta cursors, G06; the database-role migration, T-6; the architecture's
  Idempotency-Key, G31); the Scope Lock observations the design pass lists in
  its Part 13. Every number is recorded on its registry row the same day.
- **Registry edits already on this PR:** FR-4's row gains #608, ADR-0050 and
  an out-of-scope note for the stale "move between portfolios" clause, which
  FR-4's inventory line and E3's Tracker Index line drop; FR-41's row names
  its route; NFR-9's row names its lane; the Tracker Index lines of E3, E4 (no
  tracker any more: #470 closes by hand per D-8, NFR-9's B6 named) and
  E25.

## Decisions

### D-1: one branch, after the hotfix (recommended)

`agent/claude/security-second-pass-and-lifecycle-merges`, opened on `main`
**after this PR merges and after the hotfix of D-2 merges**, rebased daily.
The hotfix is its own branch and PR, because a single-concern fix that ships
to every instance should not wait behind a batch.

### D-2: the runtime hotfix ships before the batch, as 0.15.1 (recommended)

Two critical certificate-verification bypasses in the TLS client of every
shipped instance are not batch work. The fix is a version move within the
pinned Elixir minor and OTP major, so none of #727's blockers applies (those
were Elixir 1.20's cover break and OTP 28's opaqueness warnings).

**The image source moves** from Docker's official `elixir` library to the Hex
team's `hexpm/elixir` images, the source `mix phx.gen.release --docker`
itself generates. That is the one choice in this decision: the official
library has no 1.18.5 image, and its 1.18.4 tag would close the TLS advisories
but not the Elixir one. The cost is that an OTP patch becomes an explicit bump
from now on, which the invariant test and the version report make visible.

**To flip by comment:** "no hotfix" makes Lane H the batch's first commit
group after Lane M's re-pin. "Official images" moves to `elixir:1.18.4-otp-27`
and leaves the Elixir advisory open (it is not reachable today).

### D-3: ADR-0050 closes the design gate for #328 and #608 (recommended)

The record is on this PR. It answers #328 and #608 in one mechanism, names
the asks it answers and defers (§15), and states the invariants the batch
writes first (§16). Its ten choices, each the recommendation and each
flippable by a comment naming it:

| # | Choice | Recommended |
|---|---|---|
| Q1 | A security with research notes or rule versions naming it, as a merge source | refuse, naming them; file the tombstone |
| Q2 | Balance anchors in a cash merge | restate them to the combined balance; the linearity check pins it |
| Q3 | The pre-import #533 layer | keep set semantics; report the residual; file one-to-one matching |
| Q4 | A manual remap in the import preview | remembered by default, with an opt-out |
| Q5 | Key-equal pairs | an explicit choice every time, nothing preselected |
| Q6 | Accounts or positions in different views | refuse; the operator aligns the buckets first |
| Q7 | ISIN-less securities that could not stay resolvable | refuse; file generalized aliases |
| Q8 | A security's currency once it has bookings or quotes | frozen, in this batch |
| Q9 | Reading a merged-away id | 404 with `merged_into` |
| Q10 | Account-name uniqueness | an application guard, no unique index |

### D-4: the security triage is adopted, and the report stays private (recommended)

`planning-artifacts/security-review-triage-2026-09-24.md` is the PM triage of
the review: what it covered, what it found sound, the dedup against the
pipeline, the groups and the fix per item. **It names classes and fixes, never
a reproduction**, as `SECURITY.md` asks. The full report with reproduction
sketches was delivered to the owner privately and is not committed.

The triage itself is public from the moment this planning branch is pushed,
so the window between naming a weakness in public and fixing it runs from that
push to the batch's merge: this planning round plus one batch, and longer for
anything the shrink order moves to Sprint 17. That window is accepted
deliberately: the rows name classes and fixes only, the one high item ships as
the hotfix right after this merge, and the issues filed **at branch opening**
add nothing the triage does not already carry. **To flip by comment:**
"group level only" cuts Part 3 to its group introductions on this PR before
the merge and moves the per-row text into the issues; the branch history
already holds the rows, so the window has opened either way.

### D-5: the design picks, recommendation first (recommended)

The recommendation is the default, a comment naming another option changes
it, and the story writes the picked anatomy into `DESIGN.md`. The design pass
lists every board, variant and argument; the picks are:

A pick's code is its board's number.

| Pick | Item | Board | Options | Recommended |
|---|---|---|---|---|
| **G1** | Where rename, merge and delete live on Accounts & depots (#328) | `01-accounts-lifecycle` | the existing row menu, one dialog per action · one "edit" dialog with a danger zone | **A** |
| **G2** | The merge preview and confirm (#328) | `02-merge-preview` | one dialog, target on top and preview below · two steps, target then the preview of exactly that pair | **B** |
| **G3** | The identity choice in the security merge (#608) | `03-security-merge` | two option cards with one consequence line each · a side-by-side compare with the pick in the table | **A** |
| **G4** | Remembering a remap in the import preview (ADR-0050 §4) | `04-import-memory` | a checkbox in the row, only where a prefill was changed · one toggle at the end of the step | **A** |
| **G6** | A view-context rule's reach from a refused delete (#871) | `06-view-rule-reach` | the existing message band links each rule to Risk in its view · a view switcher on Risk · the refusal dialog for views too | **A** |
| **G7** | The rule name as a control (#872) | `07-rule-name-affordance` | the name as a link at rest · a row kebab per rule · a visible "edit" button | **A** |
| **G8** | A category row at 390 px once the page has its gutter (#873) | `08-classification-detail` | the row wraps to two lines under 560 px · only "+N", the rest in the title | **A** |
| **G10** | The area tab row at its end (#876) | `10-area-tab-end` | a trailing inset with arrival on a tab boundary · accept the fragment and amend D6 · mandatory snapping with scroll padding | **A** |
| **G12.1** | The author of an agent-written policy rule on Wealth → Risk (T-8, G30) | `12-e25-new-marks` | "Agent" as the last word of the rule's words line, plus the author in the version list · the author in the version list only | **A** |
| **G12.2** | Stored text carrying invisible characters (G20) | `12-e25-new-marks` | an inline escape chip per character · one attention data note with the escaped text in a disclosure | **B** |
| **G12.3** | Editing a stored split row (G07) | `12-e25-new-marks` | the split's facts disabled, only the note editable · no edit item on split rows | **A** |

Boards 05, 09 and 11 are before/after conformance repairs and carry no pick,
and so are the gutter, the disclosure marker and the live children-Σ hint on
board 08, and board 12's bucket-delete confirm and zero-value drift. Board 12
holds three picks, so they are numbered G12.1 to G12.3; plain G12 to G14 are
already finding ids in the triage.

### D-6: #872 is decided: a policy rule may be renamed (recommended)

The name is the operator's label and is never parsed (ADR-0049 §1). The
versions answer "what was the standard on date D", which the label never was.
A rename is therefore a rule-level edit **outside** the versioning, journaled
(ADR-0017 keeps the old name and who changed it), refused for nothing,
allowed on a retired rule, and never unique per context. That is exactly how a
target plan is renamed today (`PATCH /api/v1/plans/:id`), the precedent
ADR-0049 §4 itself cites. A rename-as-version would add versions identical in
every predicate, which FR-48 would later read as changes of the standard, and
refusing a rename forces retire-and-recreate, which destroys the history the
rule exists to keep. The context (portfolio, view) stays immutable.

**ADR-0049 is amended on this PR** to say so (§4: the name is a label on the
rule's identity, not part of it), and its §8 is corrected in the same edit: the
built behaviour, which the Sprint 15 closing act settled on its board
`06-rule-reference-409`, is that a
version that has been in force keeps its reference for good, so retiring a rule
does not free a security, category or view it names. The record said the
opposite.

**To flip by comment:** "no rename" closes #872 as decided-no, only the
affordance half is built, and §4's amendment is removed (§8's correction
stays, because it describes the code).

### D-7: FR-41 gets its own design-gate record, written in this sprint (recommended)

The check against ADR-0041 the registry asked for is done, and its answer is
**no, FR-41 is not a thin extension**. ADR-0041's category result is defined
by having no period ("there is no period, no membership variant and no as-of
qualifier to choose"); FR-41 asks which position produced how much of the
return **over a period, scoped to a view**. Four things it needs are missing
from the category result, and three were excluded on purpose: a period,
positions sold inside it, flows, and the view scope. The engine that has them
is the performance walk, which values every security every day and then sums
the values away.

So FR-41 gets its **own design-gate record** in the shape of ADR-0047 (a design
gate, not a scope gate: ladder level (b) is open), written in this sprint with
its board and signed by the merge of **Sprint 17's** planning PR. The record
must answer, at least:

1. the contribution method: money contribution (per position, end value −
   start value − net flows + income − costs, summing exactly to the period
   result) as v1, or percentage points linked across days, which adds up to
   TTWROR but needs per-security flows inside the walk and possibly a float
   exception;
2. whether and how a share is shown, when the total is near zero or signs mix;
3. what the contributions sum to, and what the remainder row holds (cash
   interest, standalone fees and taxes, cash FX, snapshot jumps, unvalued
   days);
4. periods, reusing the walk's period parameter and its baseline rule;
5. flows per position: buys, sells, deliveries, transfers, splits, dividends,
   trade costs (per security, which the walk does not yet keep);
6. the view scope and the endpoint family (portfolio plus `view=`, and the
   view endpoint), named in the close-out's surface check;
7. the currency split, deferred or stated;
8. grouping by category: none, by today's classification with a basis line,
   or over time (which needs a separate membership gate);
9. whether it absorbs ADR-0041 §5's "slice two" (realized result and income
   per category), which is on no issue today;
10. missing data: keep the walk's "contributes zero" so the sum holds, or
    follow ADR-0041 §4 and exclude, which breaks it;
11. the payload: the standard `computation_basis`, strings for decimals, a
    contract bump, and no signal or verdict keys;
12. the storage lifetime under ADR-0039, and the screen (next to TTWROR on
    the Wealth performance surface, never in the classifications tree).

**Two side findings** go to Lane Z at branch opening: ADR-0041 §5's slice two
has no issue, and ADR-0041's promised view scope was never built on the API
or MCP side.

### D-8: closures by hand, and what stays open on purpose (recommended)

| Issue | Action | Reason |
|---|---|---|
| **#573** | close | the bucket and view guide exists in English and German with all four use cases and is pinned by a docs test named for the issue. The one-time notice's link (its third criterion) is dropped: the notice reaches almost no one, and nothing in the app links to the docs site today |
| **#470** | close | all seven sub-issues are closed; it was a finite critique epic, not an area address. E4's Tracker Index line loses it |
| **#866** | stays open, deferred | flow rules need usage evidence of v1 (shipped today) and, for `budget`, their own risk-tier record. Revisited when a feedback round names the need |
| **#849** | stays open, deferred | Sprint 15's D-6 set its decision for Sprint 17's planning; nothing new |
| **#354** | stays open | the owner's restore on their own instance is the `needs-uat` step; closed by hand when done |
| **#727** | stays open | neither trigger fired; the hotfix is a patch inside the pinned line |

**To flip by comment:** name the issue number.

### D-9: one tag outstanding, and two to prepare (standing)

The releases list read on 2026-09-24 ends at **0.14.0**. **`0.15.0` is still
outstanding**, and it is the owner's command in the Sprint 15 close-out:

```text
git tag -a 0.15.0 096b80e5 -m "Portfolixir 0.15.0" && git push origin 0.15.0
```

The hotfix of D-2 is tagged **`0.15.1`** by the owner once it merges, from
the command its PR records, and the Sprint 16
close-out prepares **`0.16.0`**. From Sprint 15's D-8 on, every tag sentence is
written from the releases list, not from the record.

### D-10: the closing act (standing, with a fifth role)

**Sprint 15's D-10 stands:** DE, one full pass at 390 px, light and dark, on
`priv/demo/finding_surfaces_seed.exs`, screenshots in a PR comment with every
image URL under ~140 characters, read back after posting and edited when an
image's `!` is lost. The seed is extended with a merged account, a former
name, a merged security and one refusal of each kind.

**Five roles:** the correctness hunter, the edge-case hunter, the UAT persona
(running #328's five-step plan on the seed), the design critic against each
board, and **a security reviewer** who re-runs the review's dimensions against
the batch's diff, because a hardening batch is exactly where a new seam
appears.

**Mutation-verified**, and re-run after the fix rounds:

- every invariant of ADR-0050 §16;
- the E25 fixes whose failure would be silent: the redirect re-check, the
  plausibility bounds, the date bound on rule versions, the session binding
  to the password, the cascade replacements, the import hash's injectivity
  and the companion-with-parent rule (F36, F37);
- the NFR-9 matchers, through their own self-tests.

Every finding carries its reach label (Sprint 15's D-9). **The patch-coverage
listing is read from the last pre-promotion CI run.**

### D-11: the privacy repairs on this PR, and the history (recommended)

The review's privacy pass found five committed records describing the
maintainer's real data instead of synthetic cases, one real booking that two
parser tests reused (with code comments and the user docs repeating its date),
and one unreferenced screenshot with no provenance. This PR rewrites the
passages qualitatively, gives the booking invented values, and removes the
file, each as its own commit, without restating what they said. The decisions
in those records and the behaviour the tests pin are unchanged. The same
classes found outside the committed planning records are listed for the owner
privately.

The passages remain in the git history, and the repair commits' own diffs
show what they removed: a named broker attached to the maintainer's private
tooling with an outline of its authentication setup, one real holding, and a
few dataset figures (a count, a span, one booking), but no balance, quantity,
net-worth or performance figure. **Recommended: no history rewrite.** A
rewrite invalidates every clone and fork and cannot reach copies already
fetched, and the forward rule (AGENTS.md "Privacy And Disclosure") is what
prevents a recurrence. **To flip by comment:** "rewrite"
schedules a `git filter-repo` pass as an owner action with its own
instructions.

### D-12: the runway moves by one sprint (recommended)

| Sprint | Content |
|---|---|
| **16** | the hotfix; E25; ADR-0050's build; NFR-9; the E24 remainder; the conformance lane if capacity allows; #330's discovery; the FR-41 record |
| **17** | FR-41's build (its record signed at the planning); B4.2 **if** the agent's next round confirms it will record predictions; whatever Sprint 16 shrinks; #849's decision |
| **18** | whatever Sprint 17 displaces: the rest of Sprint 16's shrink, or the part of FR-41's build and B4.2 that no longer fits |
| **after** | maintenance mode, as the triage of 2026-09-23 described |

The triage's count, "about three sprints of planned product work", still
holds. What moved is where it ends, from after Sprint 17 to after Sprint 18,
because the security pass takes a share of Sprint 16 by the owner's ask.

## Sequencing

```text
after the merge ── Lane Z closures by hand (D-8), the hotfix issue (S0)
Lane H ─────────── hotfix branch, PR, 0.15.1 (D-2), before the batch
branch opens ────▶ Lane M: BMAD re-pin as the first commit
                   Lane Z: E25 tracker + S1–S8, the L2 issue, NFR-9, FR-41 side findings,
                           ADR-0050 deferrals, triage follow-ups, the design pass's Part 13
Lane S1, S2 ────── credentials, sessions, deployment, logging
Lane L1 ────────── foundation, no endpoint
Lane L2 ────────── the re-import contract (applier.ex), before S5 touches the parsers and the hash
Lane S3 ────────── Net.Http's redirect default, then Lane N's B2
Lane S4–S6 ────── input bounds (+ #868), imports, audit trail
Lane L3, L4 ───── merges, after L2
Lane L5 ────────── surfaces on G1–G4
Lane D ─────────── #870, #871 (G6), #872 (D-6, G7)
Lane N ─────────── B1, B3–B7 any time; B2 after S3
Lane R ─────────── #330's discovery, the FR-41 record, independent
Lane S7, S8 ────── hygiene
Lane C ─────────── #869, #873–#876, last
Lane M ─────────── hpax, #314, the version report before the closing act
closing act ────── D-10, the mutation passes, promotion
```

**One contract entry for the batch.** The published contract is at version 7.
The first commit that moves the API or MCP surface opens version 8, because the
manifest meta-test fails any route or tool without an entry; in the sequencing
that is S6's F20 or L3's merge routes, whichever lands first. Every later
surface change extends that entry rather than adding a second: the merge
family and `GET /api/v1/merges`, Lane D's `PATCH /api/v1/policy_rules/:id` and
its tool, T-9's quote release, and the S4 and S6 parameter and schema
changes.

## Shrink order (cut from the bottom, name the cut in the briefing)

1. **Lane C** (#869, #873–#876) moves to Sprint 17. Each is a spec drift, not
   a broken function.
2. **E25's informational items**, then **S8** and **S7**, move to Sprint 17's
   debt lane, in that order. Their issues stay filed, so the public window is
   named rather than silent.
3. **The security-merge screen** (#608's half of L5) moves to Sprint 17 under
   the two-way deadline, which the close-out records. Its API and MCP ship.
4. **L4 in full** moves to Sprint 17, behind the same signed record.
5. **NFR-9's second cut** (B3, B5, B6) moves to Sprint 17.

**What does not shrink:**

- **Lane H**, the hotfix.
- **S1–S6's high, medium and low items.** They are the review's confirmed
  findings with reach.
- **L1, L2 and L3.** L2 closes a live hazard; L3 is #328.
- **Lane D.** It finishes E24's surface.
- **NFR-9's first cut** (B1, B2, B4, B7): the three backstops the registry
  records as missing (credential schema, bank-domain HTTP, non-goal names),
  and the coupling. The PRD's third backstop, the dependency allowlist,
  already exists for the MCP companion as `mcp_dependency_allowlist_test`; B3
  widens it to the Hex tree and is the second cut.

## What is deliberately not in this sprint

- **FR-41's build** (D-7), **B4.2** and **#849's decision**: Sprint 17.
- **The flow rules** (#866): deferred, with the trigger in D-8.
- **ADR-0050's deferrals** (§15): the tombstone, generalized aliases, the
  probe for never-seen identities, one-to-one matching on the pre-import
  layer, unmerge, and merger and spin-off (a follow-on of ADR-0028 §4). Each
  is filed at branch opening.
- **#727's minor and major moves** (Elixir 1.19/1.20, OTP 28/29), the
  **Node 26** runtime (LTS on 2026-10-28), **PostgreSQL 19** (beta) and the
  BMAD builder's major version.
- **A dedicated database role** for the application, which the review names
  as a hardening option rather than a finding with reach: the triage records
  it as a documented recommendation (S2) and not as a migration; the
  migration itself is a later decision, filed at branch opening (T-6).
- **The architecture's Idempotency-Key** (D11/P8, AR-5): S7 ships only the
  outcome-unknown error for a timed-out write (G31); the key is filed at
  branch opening for Sprint 17.
- **B3.5, B3.7, B3.3, B3.8** and ladder level (d): shut.

## What "done" means for this sprint

1. **The hotfix is merged.** Every instance that rebuilds with `--pull`
   runs OTP 27.3.4.18 and Elixir 1.18.5; the pin-parity invariant is green;
   the `0.15.1` tag command is recorded for the owner, or `0.15.1` is
   published.
2. **E25's S1–S6 ship at high, medium and low**, each fix with the test that
   reproduced its finding red first, and the triage's per-item table says where
   each landed. The informational items, S7 and S8 ship or are named as cut.
3. **ADR-0050's contract holds in tests.** A re-applied export creates nothing
   after a rename and after each merge kind that ships; a later export lands
   on the target; the cash, depot and security identities hold; every
   invariant of §16 is mutation-verified for the merge kinds that ship. #328's
   API, MCP and screen ship. #608 ships, or its screen (shrink step 3) or all
   of L4 with its §16 security-merge cases (step 4) is named as cut in the
   briefing.
4. **Today's rename hazard is closed** by L2, pinned by a test that renames an
   account over the API and re-imports both a byte-identical and a drifted
   export, and by one that seeds a journaled rename from before the migration
   and shows the backfill routing a drifted export to the renamed account.
5. **NFR-9's first cut is green** with its self-tests, and B7 ties each gate
   to its backstops.
6. **#870, #871 and #872 ship**, #872 as decided in D-6.
7. **#330 has a verdict** and the FR-41 record is ready for Sprint 17's
   planning PR.
8. **The closing act ran under D-10**, with five roles, and the patch-coverage
   listing was read before promotion.
9. **The `0.16.0` command is in the close-out**, and `0.15.0` and `0.15.1` are
   named as published or as the owner's.
