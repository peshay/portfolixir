# Sprint 19 — trust before the announcement: every figure right or named, a first run that builds, and a backlog that shrinks

**Status: ADOPTED by the merge of the Sprint 19 planning PR.**
The merge is the signature (ADR-0026 step 1 as amended on PR #780). This
planning PR **signs one decision gate**:
[ADR-0053](../../docs/decisions/0053-a-pp-csv-books-its-gesamtpreis.md)
("a Portfolio Performance CSV books its Gesamtpreis"), the gate for #1076,
which is risk-tier (money and import idempotency). It is carried as this PR's
opening commit. The merge also adopts:

- the lane cut, the three lane PRs and **D-1** to **D-15**;
- answers to the six questions Sprint 18's closing acts put to the owner:
  #1076 (**D-2**), #1081 (**D-3**), #1082 and #1083 (**D-4**), #1079 and
  #1080 (**D-5**);
- the design picks of **D-8**, on the boards of
  `planning-artifacts/ux-design-2026-10-04-sprint19.md`.

Nothing here is `DRAFT` or `Proposed`. A decision the owner rejects is
removed on the PR before the merge. A closure the owner rejects is undone by
a comment naming its issue.

**One question goes to the owner, and silence has a default** (D-2): did the
live instance's Portfolio Performance history come in as a CSV or as JSON?
Silence builds the correction. "JSON" moves it to the shrink order's top.

**Verification basis:**

- **`main` and CI:** `main` at `bfc61010` (the Sprint 18 close-out). CI 1702
  and Commit authorship 716 on it are green. The latest release is
  **2026.10.7** (PR δ's merge), API contract version 12.
- **The open-issue list of 2026-10-04:** 117 open: six trackers, 73
  `agentic`, 36 `needs-decision`, 2 `needs-uat`. One open pull request,
  Dependabot's #977 (Node 26).
- **What Sprint 18 did to the backlog:** it closed 53 (48 by keyword, 5 by
  hand) and filed 51. Net: **−2**.
- **Every open `agentic` issue, read for this plan:** all 73 bodies, sized,
  sorted into lanes and checked for a rendered change. Five UI defects and
  seven non-UI ones were reproduced against the code on this branch.
- **The code, read for every claim this plan makes about it:**
  - the CSV parser, the content hash, the economic key and the projection
    (ADR-0053's Context);
  - the Overview's total, its data-quality line and Wealth's notes (D-3);
  - the history's month head (D-4) and the Trades page's title (D-4).
- **Portfolio Performance's source**, read on its `master` branch for
  ADR-0053 (no test reads it).
- **The companion's schema budget, measured on this branch:** read 103,991,
  book 177,085 and full 207,448 bytes, each **exactly at its ceiling**.
  Headroom is zero in every profile (D-10).
- **The design pass this PR carries:** ten boards, rendered with the real
  `priv/static/app.css` (D-8).

## State of play, in five lines

1. **Sprint 18 shipped everything, both exit tests passed, and the
   launch-readiness summary still said "do not announce yet".** Two open
   decisions sit on exactly what the 2026-09-30 research says a switcher
   checks first: whether the numbers are right, and whether the app can say
   why.
2. **The first one is worse than its issue reads.** In Portfolio
   Performance's CSV export, Betrag is the gross value and Gesamtpreis the
   cash. Portfolixir books Betrag. Every buy, sale, dividend and interest
   row with fees or taxes therefore books the wrong cash. The announcement's
   audience is Portfolio Performance users, and their first check is whether
   the figures match PP's. The synthetic sample hid it, because its Betrag
   was copied from the JSON sample's cash. **The issue's fear about the
   hash is unfounded:** a fix can keep every stored hash byte-identical
   (ADR-0053 §3).
3. **The second one is the first figure a stranger reads.** The Overview's
   "Alles" total leaves out what it cannot value and does not say so. Only
   Wealth names it. Every figure on the first-look test was exact, and the
   test still found the gap. A test that scores figures does not see a
   figure that is right by its own rules and wrong by the reader's.
4. **The backlog does not converge.** Sprint 17 grew it by 24 and Sprint 18
   shrank it by 2. The owner's launch path says to announce "only when all
   of that is clean". A list that refills as fast as it empties never gets
   there. This sprint is cut to close more than it can plausibly file, and
   the count becomes an exit criterion (D-1).
5. **A stranger's install still needs a machine-local file on a host whose
   egress blocks the Debian mirrors** (#1092). Both launch tests passed only
   through a Dockerfile kept outside the tree. A self-hoster behind the same
   kind of firewall has no documented route.

## Why this cut

- **No new feature.** The research's parity candidates (#1002–#1004), #899
  and #900 wait for the announcement decision, as Sprint 18's D-2 put them.
  This sprint fixes, names and closes.
- **Money first, with its record signed.** #1076 is the one change that
  needs a gate. ADR-0053 rides this PR, so PR α can start the morning after
  the merge.
- **Every H issue is in, and none is shrinkable.** The backlog triage put six
  `agentic` issues at "can show a wrong or silently incomplete money
  figure, or block install or upgrade for a stranger": #1048, #1051, #1055,
  #1068, #1042 and #1092. #1076 and #1081 join them once decided.
- **The rest is chosen by surface, not by size.** Of the 26 M issues, every
  one except #1052 is in (D-6 decides #1052). Of the 41 L issues, 12 are in,
  and each rides a file, a board or a verification pass that an H or M issue
  already opens. The other L issues stay open with a reason (D-12).
- **Every rendered change is boarded on this PR.** Ten boards: most are
  before/after conformance repairs, and seven questions are genuine choices.
- **The companion's budget has no room left.** Every byte β adds to a tool
  description is paid for by trimming another in the same PR (D-10).

## Lanes

### PR α — the money a stranger checks first

Risk-tier throughout: each item below is its own commit group, TDD first,
with exact `Decimal` fixtures.

- **M1, a PP CSV books its Gesamtpreis (#1076; ADR-0053 §1–§5, §7, §8).**
  - **Order:** the digest list of today's hashes (K2) is the first commit,
    taken before anything changes. The rewritten fixture's red test (4038.29
    on today's code) comes next.
  - **Then the change itself:** the reading, the identity check, the hash's
    amount input, the two-reading economic key, and the companion rule.
  - **#1094 rides along.** The converter prompt's closing summary asks for
    "rows per Konto", which mixes cash accounts and depots. The prompt gains
    ADR-0053 §1's sentence in the same commit.
- **M2, the correction (ADR-0053 §6; pick J9).** A re-dropped PP CSV whose
  rows hit stored hashes with a different cash shows a correction section of
  its own, with its own confirm. Each correction is journaled. A
  cross-currency trade's settlement legs change in the same write.
  - **Coverage:** none on the API, because the import is an operator action
    (ADR-0029). The PR states that.
  - **Shrinkable only by the owner's "JSON" answer** (D-2).
- **M3, foreign cash held before its first rate (#1055).** Today such a
  balance counts zero, unnamed, and then reads as a currency gain. It gets
  named instead (pick J2).
- **M4, cross-currency fees in the walk (#1051).** The walk converts a
  cross-currency trade's fees from the trade's currency, while the
  settlement guard reads them in the account's. The values change, so the
  analytic's computation version moves with them.
- **M5, the category result across base currencies (#1048; pick J10.2).**
  The roll-up stops adding cost bases of different currencies. β's read of
  the roll-up (#1091) is built on this answer.
- **M6, the Overview's total names what it leaves out (#1081; picks J1 and
  J1.2, D-3).**
  - **The screen:** an attention note under the total, and the stale count
    states its catalog scope.
  - **The payload half:** the valuation reads state that unvalued cash is
    left out of `total_cash` and count it, which takes a contract entry.
  - **The count and its list agree:** both leave out benchmarks.
- **M7, bonds the guard misses, and inference inside words (#1068, #1078).**
  - **#1068:** the two-scales guard covers the reverse case and a bond that
    carries master data but no class, and the Overview's line counts the
    finding (pick J2, board 01). This reverses two settled statements, so
    D-15 carries it as a decision. It is not a conformance repair.
  - **#1078:** the asset-class inference stops matching legal forms inside
    other words.

**Contract entry 13** carries M4's computation version and M6's payload.

**Lane M, maintenance (always present):**

- the version report, before α's closing act;
- **Node 26 is declined again with its date** (#977, LTS on 2026-10-28,
  after this sprint's window);
- the BMAD modules and #727's two triggers, re-checked.

### PR β — a stranger's first run, and the agent's reads

- **B1, four more migrations frozen or pinned (#1042).** As #1015 did for
  two: plain SQL, a private copy, or a seeded-upgrade case that a later
  schema change would turn red. The story chooses per migration, under the
  widened rule of Sprint 18's D-7.
- **B2, the build behind a firewall (#1092, #1093, #930, #933).**
  - The build CA reaches the Dockerfiles' apt steps.
  - A host that cannot reach the Debian mirrors gets a documented route.
  - The quick start's secrets step names the UI password, and the entry
    points say where the Imports page sits.
  - The release warns at boot when `PHX_FORCE_SSL` is on and no trusted
    proxy is set.
  - A missing logo file counts as a missing logo.
- **B3, the companion's failure modes (#1043, #1045).**
  - When the HTTP companion's port is taken, it fails with a message instead
    of reporting "listening" and exiting 0.
  - A proxy's 502 or 504 on a write reads as "outcome unknown, check before
    retrying", like Sprint 18's G31 answer (#955), not as a JSON parse
    error.
- **B4, import rows that fail alone, and hashes that hold (#1044, #948,
  #923, #917).**
  - A blank Gegenkonto or an unknown currency code becomes a row error at
    parse time. The rest of the file still previews (board 09's row-error
    frame).
  - A file whose rows are all hash hits no longer blocks Confirm.
  - A hash a live transaction still holds is never retired. **#917 and #923
    are risk-tier (import idempotency)** and form one commit group.
- **B5, the agent reads what the operator sees (#1056, #1091's read half,
  #959).**
  - **#1056:** the performance family gets its Everything form. The MCP
    tools take an optional `view_id`, as Sprint 18's D-5 did for the
    valuation, and the API gets the matching view-less routes. They answer
    in EUR (D-7).
  - **#1091's read half:** the all-portfolios category-result roll-up gets a
    read and an optional scope on its tool, built on α's #1048.
  - **#959:** the benchmark parameter answers `merged_into` for a
    merged-away security.
  - **Contract entry 14** carries B5. The schema bytes are paid inside β
    (D-10).
- **B6, the German API reference and test isolation (#1077, #1046,
  #1047).**
  - The German reference catches up with the English one: the logo routes,
    position targets, plan versions and five tool families.
  - A test for the parity of the two references keeps them level.
  - Two test-isolation repairs.

### PR γ — the screens a stranger meets, second pass

All of it is boarded on this PR. A pick's code is its board's number.

- **U1, the transaction history (board 03).**
  - #1083's month head becomes the count alone (pick J3).
  - Desktop cash rows name their account (#1084, pick J3.2).
  - A long name no longer overflows the phone row, and the Price column shows
    a stored price with its stored digits (#1073).
- **U2, reaching and reading trades (board 04).**
  - The page is titled "Trades" while the Trades facet is open (#1082, pick
    J4).
  - Every result carries its sign; a trade without p. a. says why (#1089).
  - The Trades tab formats through `Format` (#1060) and its ⓘ pill is no
    longer clipped (#1059).
  - "1 units" reads correctly (#1074).
- **U3, dates and chart axes, as one sweep (board 05).**
  - **What #1061, #1087 and #1088 list:** the ISO dates left on the security
    detail and in the merge dialogs (#1061), the Wealth notes and basis line
    (#1087's Wealth half), and the chart axes' locale and phone label size
    (#1088, pick J5). The Overview half of #1087 rides α's board 01.
  - **What the issues missed:** the board found ISO displays outside every
    issue's list: the detail Overview, the Termine tab, the range chips, the
    metric window, the bond strip and the import result lists. So U3 is a
    sweep, not a list. Every displayed date goes through `Format.date`
    (`Format` gains a month form for the Termine tab), and DESIGN.md's eight
    ISO-for-display sentences are rewritten.
  - **A test keeps it swept:** no template or LiveView renders
    `Date.to_iso8601` or an ISO `strftime` outside an allow-list (`<time
    datetime>`, inputs, the API, files).
- **U4, Wealth at 390 px and the twin names (board 06).**
  - The Positions table uses two-line phone rows (#1065, pick J6).
  - Two securities with one name are told apart (#1057, pick J6.2).
  - The top-bar title clips with its ellipsis, and the KPI band's labels
    stay whole (#1086).
  - No sideways scroll at 768 px with the detail pane open (#1063).
- **U5, the floor, second pass (board 07).** #1062, #1064 (pick J7), #1069,
  #1071, #1085 (pick J7.2) and #1067.
- **U6, copy and dialog states (board 08).**
  - A newcomer's misreadings (#1090) and "journalisiert" (#1074's drawer
    half).
  - The split wizard's preview (#1066) and a vanished merge target (#1072).
  - Risk findings and the SOLL refusal name their row (#944, #945).
- **U7, the category result's view scope on the screen (#1091's screen half;
  pick J10).** Together with β's read, this closes #1091 in both directions.
- **U8, the screenshots.** Every documentation screenshot of a surface γ
  changed is regenerated from the synthetic seed with Sprint 18's script
  (`priv/demo/screenshots.mjs`). Never from a live instance.

### Lane Z — registry (small)

- **Right after the merge:**
  - #1079 and #1080 are closed by hand as not planned, each with D-5's
    reason and what reopens it.
  - #1076, #1081, #1082 and #1083 lose `needs-decision` and gain `agentic`,
    because this plan answers them.
  - ADR-0053's two deferred asks are filed under #991: a suspect list
    without a file, and the JSON path's negative tax.
- **At each lane PR's opening:**
  - its issues move under #991 when they have no parent;
  - the design pass's "Found while drawing" items on that PR's surface are
    either fixed in the story that touches the surface (D-14) or filed, as
    the UX document marks each one.

  **The PR body carries Lane Z as a checklist, ticked before the closing
  act** (Sprint 18 retrospective).
- **Registry edits already on this PR:**
  - the Tracker Index's E26 line names Sprint 19 as planned;
  - FR-5's row names ADR-0053;
  - `sprint-status.yaml` gains the PLANNED entry.

## Decisions

### D-1: what this sprint is for, and its four exit criteria (recommended)

**Sprint 19 is the last sprint before the owner's announcement decision.**
It passes when all four hold:

1. **Every H issue is closed.** By keyword: #1076, #1081, #1055, #1051,
   #1048, #1068, #1042 and #1092. A miss names the issue and its step.
2. **The operator's first-look test passes again, with one question added
   per figure: "is this everything?"** It runs at γ's closing act, set up as
   Sprint 18's D-1 set it up: synthetic seed, German UI, 1440 and 390 px,
   light and dark.
   - The four figures stay the same: the total, the largest contributor
     this year, a closed trade's p. a., and a cash balance.
   - For each figure, the persona names from the screen what it leaves out,
     or that it leaves out nothing, without the documentation.
   - **A fifth step is new: the Portfolio Performance round trip.**
     1. The persona drops the rewritten synthetic `sample.csv` into a fresh
        portfolio on the Imports page.
     2. It reads Test-Cash's balance on the screen: **4.017,68 EUR**,
        exact.
     3. It drops the file again: the preview books nothing.
3. **The agent's launch test passes against `main` at the close-out, on the
   documented build route.** The protocol is unchanged from Sprint 17's D-1.
   The machine-local Dockerfile both earlier runs needed is retired by
   #1092. If the documented route needs something this machine cannot
   reach, the record names that one prerequisite. It does not substitute a
   file.
4. **The open-issue count at the close-out is below 100**, against 117 at
   this planning. The plan closes 51 by keyword and 2 by hand, and files 2
   at the signature. The closing acts can then file 33 before the criterion
   fails, against Sprint 18's 51 across four PRs.
   - **Scope Lock still binds.** A finding is filed, never withheld to make
     the count (D-14).
   - **If the criterion misses**, the close-out says by how much and what
     filled it. The launch-readiness summary says so too.

**Passing all four is necessary for the announcement and not sufficient**:
the owner decides (see "What the owner decides after this sprint").

**To flip by comment:** name a criterion to drop, or a different threshold
for the fourth.

### D-2: ADR-0053 is signed, and one question about the owner's instance (recommended)

**The record, in four sentences.**

1. A row with a Gesamtpreis books it, checked to the cent against Betrag ∓
   (Gebühren + Steuern). A row without one books its Betrag, which is how
   every converter-written file looks.
2. The content hash keeps reading Betrag, so every stored hash stays valid
   and a re-drop books nothing.
3. The economic key is checked under both readings.
4. Bookings made under the old reading are corrected by a separate,
   journaled confirm, which a re-dropped PP CSV feeds.

**Why the correction needs a file.** No stored row says which format it
came from. A dividend booked through the CSV path looks exactly like one
booked through JSON.

**Why it is a gate and not a quiet fix.** It changes what the importer books
and touches the hash that ADR-0050's re-import contract stands on. Risk-tier
semantics need their record signed before the batch (ADR-0036, point 4).

**The owner's question.** Did the live instance's Portfolio Performance
history come in as a CSV or as JSON?

- **CSV:** its cash balances are off by every fee and tax of those rows. M2
  is the remedy. After α merges, the owner re-exports the history from
  Portfolio Performance as CSV, drops it, and confirms the correction
  section.
- **JSON:** nothing on it is affected. M2 moves to the shrink order's top,
  because no known instance needs it.
- **Silence builds M2.** Building it unneeded costs about a day. Not
  building it when it is needed leaves wrong balances with no remedy.

**Nothing in this repository can tell which it was.** The check is the
owner's, on the live instance.

**To flip by comment:** "A2" asks for a versioned hash with a legacy lookup
instead (ADR-0053 lists it; it changes no outcome and adds a permanent dual
lookup). "No correction" leaves already-imported rows as they are.

### D-3: #1081 — the total says what it leaves out, beside the figure (recommended; picks J1, J1.2)

**I am overriding #703's routing for this one case.** The owner confirmed
that split on 2026-08-15: the Overview carries the count as the alarm, and
Wealth carries the consequence and the names. UX-DR25 came a week later and
is more specific: "when an aggregate cannot include a row, the surface states
how many and which — beside the figure". The Overview's total is such an
aggregate, and today it states nothing.

- **J1, A:** an `attention` data note in its own row under the "Alles" card
  (the card's section is a grid, so the note spans it):
  - it names the left-out cash accounts with their **native** balances
    (UX-DR25 clause 2) and the positions without any price;
  - it links to Wealth's data-quality section;
  - it carries no call to action that cannot act.

  The valuation already carries every name; the helpers that build them move
  out of the Wealth LiveView into a shared module, so the Overview does not
  copy them.
- **J1.2, A:** the stale count stays catalog-wide and says so ("25 veraltet
  im Katalog"). A held-only count would include never-priced holdings,
  where "veraltet" is the wrong word, and would still not match Wealth's
  view-scoped figure.
  - **The count and its list agree:** today the count leaves out benchmarks
    and the linked list does not. Both leave them out.
- **The agent's half.** The view-less and view valuation payloads say that
  unvalued cash is not in `total_cash`, and count it
  (`unvalued_cash_count`). The routine `include_positions=false` answer then
  no longer hides the gap from an agent either. This costs payload, not
  schema bytes.

**The risk if left as it is:** a stranger's first number is wrong by the
reader's rules, and nothing on the page says so.

**To flip by comment:** "J1 B" puts the counts into the bottom data-quality
line instead (no names, far from the figure); "J1.2 B" counts held positions.

### D-4: #1083 and #1082 — two surfaces the first-look test misread (recommended; picks J3, J4)

- **#1083, the month head: the count alone (J3, A).**
  - **Why today's figure goes:** the head adds buys, deposits, sales and a
    "Saldo gesetzt" level into one unsigned sum. That is neither a cash flow
    nor a turnover.
  - **Why nothing replaces it:** the filter summary above the table already
    carries the per-kind sums with their basis line. A signed head (B)
    needs the rows' signs fixed first: a transfer reads "−" even on the
    receiving account's filter. It would also need sign colour on every row
    (DESIGN.md's "subtotals and totals alike").
  - **H2's sentence still holds:** "the month subtotal follows" a deleted
    row, because the count follows.
- **#1082, Trades: the page says "Trades" while the facet is open (J4, A).**
  - **The change:** the top bar's title follows the facet. The sidebar, the
    route and the information architecture are unchanged.
  - **What it fixes:** at 390 px nothing in the top bar says Trades today,
    because the subtitle is hidden under 560 px.
  - **Why not more:** Sprint 17's G1-B (a sidebar entry and its own route)
    stays a later option, with its costs listed on the board.

**To flip by comment:** name the variant ("J3 B", "J4 C").

### D-5: #1079 and #1080 — not now, each with what reopens it (recommended; each row flips by naming its issue)

| Issue | Answer | Reason | Reopened by |
|---|---|---|---|
| **#1079** storing the inferred asset class at write time | **keep it** | Clearing stored inferences needs a migration that cannot tell a guess from a statement. #1078 (α) improves the rule for new writes and for rows reset with **Unassign**, and the handbook says so. ADR-0012's 2026-10-03 note already states the behaviour. | a second inference fix that must reach rows stored before it |
| **#1080** a confirmation step for an agent's research-log entries | **keep the journal as the record** | AGENTS.md's rule on machine-extracted data lets an agent confirm. An entry is not extracted from an unstructured source: an agent writes it, under its credential, journaled, and an MCP host that asks before each write asks before each entry. The features page states exactly that. Draft-then-commit is a new write path on ADR-0044 | an operator's or a stranger's report of an entry they would have stopped |

### D-6: #1052 — delete-and-rebook stays the screen's correction for the cash kinds, and the deadline is missed on purpose (recommended)

- **The gap.** The API corrects a dividend's, a deposit's or a fee's facts
  in place, and the screen cannot. Since Sprint 18 the screen deletes such a
  booking. It cannot book these kinds at all: the product's goal 4 asks the
  screen for buys and sells, and the other kinds arrive by import or by the
  agent.
- **The deadline.** The gap was filed at Sprint 18 γ's opening, so under
  "API And MCP Coverage" its human view is due by the end of this batch.
- **Why it waits.** Building it means a form per kind family: the cash
  kinds, transfers, deliveries and the balance level, each with its own
  refusals. That is a design pass of its own. It also competes with this
  sprint's purpose, which is to close, not to open.
- **What the close-out records.** The miss as a two-way finding, with this
  reason. The work comes back as the first design pass after the
  announcement decision.

**The risk:** an operator whose dividend imported wrong cannot fix it from
the screen without a re-import. ADR-0053's correction covers the PP CSV case
(M2). The agent's update covers the rest.

**To flip by comment:** "build #1052" puts the cash kinds' form into γ, boarded
mid-batch, above the shrink order's first step.

### D-7: #1056 — the Everything scope reads in EUR, as the view-less total does (recommended)

- **The shape.** The performance, benchmark and contribution tools take an
  **optional** `view_id`. Omitted, they read the Everything scope, as Sprint
  18's D-5 made `portfolixir.views.valuation` do. The API gets the matching
  view-less routes beside `GET /api/v1/valuation`.
- **Why EUR.** These reads answer in EUR, the hub, like every view read and
  the view-less total. The screen computes Everything in the first
  portfolio's base currency, so for a non-EUR first portfolio the two
  differ. The payload's basis names its currency, and the close-out's
  surface check names the difference.

**To flip by comment:** "the screen's base" makes the reads follow the first
portfolio's currency instead. That makes the read depend on which portfolio
was created first.

### D-8: the design picks (recommended; silence adopts them)

Ten boards, under
`planning-artifacts/design-language/mockups/ux-design-2026-10-04/`, argued in
`planning-artifacts/ux-design-2026-10-04-sprint19.md`. The pick letter skips
I, so it does not collide with ADR-0051's identities I1–I9.

| Pick | Item | Board | Lane | Kind | Recommended |
|---|---|---|---|---|---|
| **J1**, **J1.2** | The Overview's total names what it leaves out; the stale count's scope (#1081; #1068's and #1087's Overview halves) | `01-overview-total` | α M6 | variants, two questions | **A**, **A** |
| **J2** | What Wealth says about money it cannot value (#1055, #1068; D-15) | `02-money-notes` | α M3, M7 | before/after with one choice | after; **A** |
| **J3**, **J3.2** | The history's month head; the account on desktop cash rows (#1083, #1084, #1073) | `03-history` | γ U1 | variants, two questions | **A**, **A** |
| **J4** | Reaching and reading trades (#1082, #1089, #1060, #1059, #1074) | `04-trades` | γ U2 | variants and before/after | **A** |
| **J5** | Dates and chart axes (#1061, #1087, #1088) | `05-dates-charts` | γ U3 | before/after, one pick (phone labels) | after; **A** |
| **J6**, **J6.2** | Wealth at 390 px; twin names (#1065, #1057, #1086, #1063) | `06-phone-wealth` | γ U4 | before/after, two picks | after; **A**, **A** |
| **J7**, **J7.2** | The floor, second pass (#1062, #1064, #1069, #1071, #1085, #1067, #933) | `07-floor` | γ U5, β B2 | before/after, two picks | after; **A**, **A** |
| **J8** | Copy and dialog states (#1090, #1074, #1066, #1072, #944, #945) | `08-copy-dialogs` | γ U6 | before/after, one pick (#1066) | after; **A** |
| **J9** | The PP CSV correction, and two row-error states (ADR-0053 §6, #1044, #948, #923) | `09-import-correction` | α M2, β B4 | variants and before/after | **A** |
| **J10**, **J10.2** | The category result's view scope; mixed currencies (#1091, #1048) | `10-category-results` | γ U7, α M5 | variants, two questions | **A**, **A** |

**Items with no board:** everything in PR β except B2's logo fallback and
B4's two row states, which are drawn on boards 07 and 09. The rest of β is
migrations, the build, the companion, payloads and documentation. In α,
M1, M4 and M7's inference fix change values, not anatomy.

### D-9: three lane PRs, merged in order, and the retrospective's carry-forwards (standing, amended)

| PR | Lanes | Merged | Why this order |
|---|---|---|---|
| **α** | M (money), Lane M | first | wrong cash before anything else; β's roll-up read stands on M5 |
| **β** | B (first run, reads) | second | the companion's tool list and the contract manifest are shared with α's entry |
| **γ** | U (screens) | third | it draws on α's and β's figures, and its closing act runs the first-look test |

**The Sprint 18 retrospective's carry-forwards, each a duty from the first
commit:**

1. **When a lane PR merges, change the next PR's base to `main` first, then
   push the moved head.** Delta's move was pushed while its base still
   pointed at gamma's branch, so GitHub built no merge ref and ran no
   workflow.
2. **A history rebuild proves the invariants of every commit it writes, not
   only the tip's.** That covers the gettext catalogs, the localization test
   and the hand-maintained `errors.pot` entries.
3. **Lane Z is a checklist in each PR body, ticked before the closing act.**
4. **Every agent brief names its base commit, and the agent checks it
   first.**
5. **A fixture that encodes an external format is checked against that
   format's source before it is written or "corrected"** (ADR-0053 §7).
6. **Every push runs all fifteen gates.** Dialyzer included: one skip cost a
   red CI in Sprint 18.

Each PR opens as a draft with its first commit, carries its own briefing, is
promoted under `AGENTS.md`'s four conditions, and is rebase-merged by the
owner.

### D-10: the schema budget has zero headroom, and β pays inside itself (standing rule, stated with its cost)

Measured on this branch, every profile sits exactly at its ceiling. α adds
no tool and no parameter: M6 changes a payload, not a schema. β adds
#1056's optional `view_id` on three tools, #1091's optional scope, and #959's
answer. **β trims existing descriptions by at least what it adds, then
lowers the ceilings to the new figures.** A raised ceiling is a weakened
gate and a review reject; #1027's test refuses it anyway.

### D-11: maintenance (recommended)

- **Node 26** (#977) is declined again: LTS on 2026-10-28, after this
  sprint's window. The next sprint that runs on or after that date takes it.
- The version report, the BMAD modules and #727's two triggers, as every
  sprint.

### D-12: what stays open on purpose (recommended)

| Issue | Action | Reason |
|---|---|---|
| **#328**, **#354** | stay open | the owner's runs on real data |
| **#1002–#1004**, **#899**, **#900** | stay open | after the announcement decision (Sprint 18's D-2, unchanged) |
| **#937, #938, #940, #941, #942, #953, #956, #965, #967** | stay open | E25's defence-in-depth follow-ups with no known path to harm. Together they are a clean lane of nine closures with no rendered change: the first maintenance batch after the announcement decision |
| **#957, #958, #1070** | stay open | the security merge's preview and its bond data. Merges are rare on day one; one later lane, risk-tier |
| **#894, #949, #951, #962, #971, #925, #922, #1058, #314** | stay open | each is L, none touches the launch path; #925 waits for #971's measurement, #1058 for #941's helper, #951 for a budget plan of its own |
| **#727** | stays open | blocked upstream; re-checked in Lane M |
| **#1052** | stays open | D-6 |
| **#987–#990**, **#999–#1001**, **#866**, **#895–#898**, **#902–#907**, **#926**, **#928**, **#931**, **#939**, **#946**, **#950**, **#970**, **#972–#974** | stay open | decisions waiting for a need, as Sprint 18's D-12 left them |

### D-13: the closing act, one lens per risk class (standing)

| PR | Lenses |
|---|---|
| **α** | correctness hunter; **money lens on ADR-0053's K1–K8, one at a time, K2 and K3 first**, then on #1055, #1051 and #1048; edge-case hunter on the correction (M2); design critic against J1, J2, J9 and J10.2 in German at 390 px, light and dark |
| **β** | correctness hunter; the seeded-upgrade lens over #1042; a build-trust lens over #1092 (what the CA is trusted for, and for how long); the idempotency lens over #917 and #923; the companion lens over #1045 |
| **γ** | edge-case hunter; design critic against J3–J8 and J10; **the operator's first-look test as the UAT persona (D-1)**; a privacy lens over every regenerated screenshot |

A cascade stops when a layer yields no major finding. Every finding carries
its reach label. Each lane PR reserves its closing act and its briefing
before its first story. If the weekly usage limit comes into view, the
shrink order applies from its first step, and the closing acts are not what
is cut. A closing keyword is checked against the diff before a PR body names
it.

### D-14: a closing act's finding on the PR's own surface is fixed, not filed (recommended)

This is how "confirmed findings fixed on the branch" (ADR-0026 step 3)
reads, stated because Sprint 18 filed 51 issues:

- **A finding on a surface the PR already changes**, small and with its
  answer already in the spec, is fixed on the branch.
- **A finding outside the PR's surface, or one that needs a choice**, is
  filed under Scope Lock, as before.
- **Nothing is withheld to make D-1's count.** The count measures what is
  left, not what was found.

### D-15: #1068 reverses two settled statements, and the guard gets a positive bond signal (recommended)

The design pass found that #1068 asks for three things, and two of them
were settled the other way:

- **ADR-0052's Consequences** say that the reverse case (quotes near 1,
  booked prices per unit near 100) is not named, and that a bond with no
  class and an unrecognised name escapes the guard.
- **DESIGN.md** says that the dashboard's data-quality line does not count
  the finding.

**The merge reverses both, for these reasons:**

1. **The reverse case is named** in a problem note of its own (J2). A bond
   whose quotes are on the unit scale counts a hundredfold too low in every
   total. "It needs a convention the catalog does not have" was a reason
   not to *convert*, not a reason to stay silent. The note names and
   converts nothing, as §4 of ADR-0052 requires of the forward case.
2. **The guard reads a security as a bond when its effective class is a
   bond class, or when it carries ADR-0052's master data** (a maturity date
   or a coupon). It does **not** widen to every unclassed security: that
   would flag an unclassed share that rose twentyfold. The board found the
   inference recognises only government-bond names, so the seed's own
   corporate bond escapes. The handbook says that a class or master data
   brings such a bond under the guard.
3. **The Overview's line counts the finding**, at problem severity, and
   links to a `dq=two_scales` list, so the count equals the list. A total
   inflated a hundredfold is exactly the alarm the Overview's line exists
   for. "The two scales are read where the total they inflate is read" put
   them on Wealth only, and the Overview's total is inflated too.

**Not risk-tier:** the guard names and converts nothing (ADR-0052's own
verdict). The story writes a dated note into ADR-0052 and amends DESIGN.md's
"Settled here" items.

**To flip by comment:** "keep ADR-0052" leaves #1068 open with this
decision recorded against it, and M7 builds only #1078.

## Sequencing

```text
after the merge ── Lane Z: #1079 and #1080 closed by hand; four relabelled;
                   ADR-0053's two deferrals filed under #991
PR α opens ─────▶ M1 #1076 (K2 digests ▶ red fixture ▶ reading ▶ keys) + #1094
                   ─▶ M2 the correction ─▶ M3 #1055 ─▶ M4 #1051 ─▶ M5 #1048
                   ─▶ M6 #1081 ─▶ M7 #1068 #1078; Lane M
                   closing act ─▶ merge = a release
PR β opens ─────▶ B1 #1042 ─▶ B2 #1092 #1093 #930 #933 ─▶ B3 #1043 #1045
                   ─▶ B4 #1044 #948, #923 #917 ─▶ B5 #1056 #1091(read) #959
                   ─▶ B6 #1077 #1046 #1047
                   closing act ─▶ merge = a release
PR γ opens ─────▶ (base changed to main when β merges, then the head pushed)
                   U1 ─▶ U2 ─▶ U3 ─▶ U4 ─▶ U5 ─▶ U6 ─▶ U7 #1091(screen) ─▶ U8
                   closing act with the first-look test ─▶ merge = a release
close-out ─────── the agent's launch test on the documented route; the count;
                   the two-way check; the surface check; launch readiness, v2
```

## Shrink order (cut from the top, name the cut in the briefing)

1. **M2, the correction**, only if the owner answers "JSON" (D-2).
2. **U6's dialog states** (#1066, #1072, #944, #945) move to the next sprint.
3. **#1077**, the German API reference, and its parity test.
4. **#933**, the logo fallback.
5. **U7, #1091's screen half.** Its read stays (β). #1091 then stays open as
   a two-way finding with its deadline at the next batch's end.

**What does not shrink:**

- every H issue (D-1, criterion 1);
- M6 (#1081);
- U1's month head and U2's title (D-4), which the first-look test found;
- U8, the screenshots;
- both tests.

## What is deliberately not in this sprint

- **New features**, the peer candidates #1002–#1004, **#899** and **#900**
  (D-12).
- **#1052**, the screen's in-place correction of the cash kinds (D-6).
- **A suspect list without a file** (ADR-0053, deferred and filed).
- **An import route under `/api/v1`**: the import stays an operator action.
- **B3.3, B3.5, B3.7, B3.8** and ladder level (d): shut.
- **Phone access**: the widening phase, after the announcement.

## What the owner decides after this sprint

The close-out ends with **launch readiness, version 2**: one page, in the
shape of `launch-readiness-2026-10-04-sprint18.md`. It holds:

- all four exit criteria's records, step by step;
- the open issues that touch money or an upgrade path. The plan expects
  none known; each one that is known is named;
- the open-issue count by label, and what filled it;
- the owner's checks that no agent can run: the correction on the live
  instance if its history came in as CSV (D-2), #328 and #354.

**The announcement stays the owner's call** (Sprint 17's D-1).

- **If all four criteria hold**, the summary recommends announcing to the
  small group the launch path names: self-hosters who run LLM agents, in the
  self-hosting and Portfolio Performance communities. The widening phase
  then starts with the E25 maintenance lane (D-12) and the peer candidates.
- **If a criterion fails**, the summary names it, and that becomes Sprint
  20's plan.

## What "done" means for this sprint

1. **PR α, β and γ are merged in order**, each green on its head, each with
   its closing act under D-13 and its briefing.
2. **ADR-0053 is built as signed:** K1–K8 pinned and mutation-checked; #1076
   closed by keyword; the correction built, or shrunk by the owner's "JSON".
3. **The four exit criteria of D-1 are recorded**, each pass or fail with
   its step.
4. **#1052's miss is recorded as a two-way finding** with D-6's reason, and
   #1091 is closed in both directions or recorded the same way.
5. **Each merge that touched shipped code produced a calendar release**, and
   contract entries 13 and 14 name what changed.
6. **The schema budget's ceilings are no higher than today's.**
7. **The close-out's surface check** names:
   - the valuation family's new `unvalued_cash_count`, across the view and
     view-less reads;
   - the performance family's Everything forms, against its view forms;
   - the category-result roll-up, against its portfolio and view scopes.
8. **Launch readiness, version 2** is in the close-out.
