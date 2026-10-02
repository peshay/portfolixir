# Sprint 18 — the operator's first look: the calculation breakdown, the screens a stranger meets, and two money bugs found on the way

**Status: ADOPTED by the merge of the Sprint 18 planning PR.**
The merge is the signature (ADR-0026 step 1 as amended on PR #780). This
planning PR **signs one decision gate**: the
[ADR-0034 amendment of 2026-10-02](../../docs/decisions/0034-money-weighted-metrics.md)
("the solver scales large flows before it tests its tolerance"), the gate for
#1031, carried as this PR's opening commit. FR-41's gate,
[ADR-0051](../../docs/decisions/0051-contribution-analysis.md), was signed by
the Sprint 17 planning merge and is unchanged. The merge also adopts:

- the lane cut, the four lane PRs and **D-1** to **D-13**;
- answers to the decisions Sprint 17 left waiting that touch the launch path
  (**D-5**, **D-7**), and a verdict on Sprint 17's three Sprint 18 candidates
  (**D-2**);
- the design picks of **D-8**, on the boards of
  `planning-artifacts/ux-design-2026-10-02-sprint18.md`.

Nothing here is `DRAFT` or `Proposed`. A decision the owner rejects is
removed on the PR before the merge. A closure the owner rejects is undone by
a comment naming its issue.

**Verification basis:**

- **`main` and CI:** `main` at `d73ecf55` (the Sprint 17 close-out's launch-test
  record). CI 1658 and Commit authorship 672 on it are green. The latest
  release is **2026.10.3** (PR γ's merge).
- **The open-issue list of 2026-10-02:** 119 open, six of them trackers
  (#416–#420, #991). Two open pull requests, both Dependabot's (#881, #977).
- **What Sprint 17 did to the backlog, counted from the issue list:** it
  closed 16 of the 95 issues open at its planning and 7 it filed itself, and
  it left 40 newly filed issues open. Net: **+24**.
- **The code, read for every claim this plan makes about it:** the CSV
  parser's transfer mapping (D-4), the solver's three callers (D-3), the web
  layer's paths to `Ledger.delete_transaction/2` (D-6), the unscoped
  valuation `Valuation.for_view(nil)` (D-5), and the companion's schema
  budget, measured on this branch (D-10).
- **The design pass this PR carries:** eight boards, rendered with the real
  `priv/static/app.css` (D-8).

## State of play, in five lines

1. **Sprint 17 merged in three lane PRs, nothing shrunk, and the launch test
   passed twice.** The agent's half of E26 is done. Calendar versions made
   three releases without a hand-pushed tag.
2. **The backlog grows faster than sprints close it.** Sprint 17 filed 40
   issues it did not close and closed 16 older ones. Most of the 40 are
   honest Scope Lock notes, and growth alone does not block a launch.
   **Two of them do: they put wrong money figures in front of a stranger
   without saying so.** #1023: a Portfolio Performance CSV that carries both
   sides of a cash transfer books it twice, once in reverse, and the preview
   shows no error. #1031: the money-weighted return reads "n/a" for large
   amounts where a rate exists. Both go first (PR α).
3. **The Sprint 18 that Sprint 17's D-2 sketched does not fit in one sprint.**
   It held FR-41 (risk-tier money math, nine identities), about twenty UI
   repairs, the human documentation with its screenshots, #330, #899, #900
   and three peer-feature candidates. Sprint 16 ran into the weekly usage
   limit for about 36 hours. D-2 takes out what the launch does not need.
4. **The operator's half has no measure.** Sprint 17's exit criterion tested
   the agent. Nothing yet tests whether a person who installs from the README
   finds the figures on screen. D-1 adds that test.
5. **One debt carries a deadline into this sprint, and one is older than its
   deadline.** #1029 (the per-security Trades tab's p. a. figure) is due by
   this sprint's end. #912 is the older one: no booking can be deleted from
   the screen at all. The only correction path for a wrong booking is the
   API. A stranger's first wrong import makes that visible on day one.

## Why this cut

- **Correctness before polish.** The two money bugs and the upgrade hazard
  (#1015) ride the first PR. The harnesses Sprint 17 built (seeded upgrades,
  lock order) then protect everything after it.
- **FR-41 is the operator's headline, and the only new feature.** It is the
  research's top-ranked parity item ("a calculation breakdown from initial to
  final value"), its record is signed, and it was moved once already. The
  three other peer candidates wait for the announcement decision (D-2).
- **Every rendered change is boarded on this PR.** The polish lane is
  conformance repairs, so most boards are before/after. Two items, deleting a
  booking (#912) and the bond master data (#330), are genuine choices.
- **Text after surface.** The human documentation and its screenshots come
  last, in their own PR. They show what β and γ build, and Sprint 17's rule
  holds: nothing is written twice.
- **The companion's budget is full.** Measured on this branch, the schema
  budget leaves **149 bytes** under the `read` ceiling, **36** under `book`
  and **167** under `full`. Every tool this sprint adds is paid for by
  trimming descriptions in the same PR, which is the rule as written (D-10).

## Lanes

### PR α — money correctness, upgrade safety, and the companion's write gap

- **C1, a cash transfer booked once, in the right direction (#1023;
  risk-tier: import idempotency and money).** D-4 sets the order. First,
  establish what Portfolio Performance actually exports for an account
  transfer, from its open-source exporter, read at story time (tests make no
  network call): one row or two, and which column names which account. Then
  book each transfer exactly once, in the right direction, with a test for
  every export shape against the golden master. If both sides are exported,
  an instance that has already imported such a file carries reversed
  duplicates that a re-import cannot remove, because the content hash
  already holds them. The story then gives the operator a way to find them.
  If that way has a rendered surface, it is boarded before it is built.
- **C2, the solver scales large flows (#1031; risk-tier: money math).**
  Built exactly as the ADR-0034 amendment states, with its three identities
  and the mutation check. `Ledger.TradeReturn` loses its own scaling, and
  the `−1` guard lands with it.
- **C3, upgrades that do not depend on today's code (#1015, #1016).** The two
  migrations that call application code get the code they need frozen into
  the migration, as plain SQL or a private copy, or a seeded-upgrade case
  that a later schema change would turn red. The story makes that call per
  migration. The seeded-upgrade rule widens as D-7 answers #1016.
- **C4, an unknown write outcome is reported (#955, G31).** A connection
  reset during a write makes the companion answer "outcome unknown, check
  before retrying", as the API's G31 error already does. This is the gap a
  stranger's agent would retry through. It is cheaper than #899 and covers
  the same failure (D-2).
- **C5, the release's outbound fetches can be switched off, and a build can
  trust a proxy's CA (#1026; D-7).** `PORTFOLIXIR_BACKGROUND_FETCH=off` is
  honoured by a release as it is by the development stack. The screens say
  what they already say about stale quotes and rates, so there is no new
  rendered surface. Both Dockerfiles also take an optional CA file as a
  build secret. **The CA half is shrinkable** (shrink order, step 3).

**Lane D — hygiene with no rendered difference:** #1022, #1027 (its enforced
ceiling: a test that fails when a ceiling goes up), #1021 (a real-transport
test for stdio and for `tools/call` over HTTP), #1018, #1019, #915 (the
AGENTS.md architecture block names `Portfolixir.Lifecycle`), #964 (gettext
contexts), and the fixture repair D-7 answers for #1020. If a story finds it
changes rendered output after all, it stops and gets a before/after board.

**Lane M — maintenance (always present):** the version report before α's
closing act; sobelow 0.16.0 with its six new findings read (#1006); Node 26
on its LTS date (D-11); the BMAD modules and #727's two triggers re-checked.

### PR β — the operator's money surface

- **F1, the contribution engine (FR-41, ADR-0051; risk-tier: money math in
  the walk).** The walk keeps the per-security figures apart inside a window
  (§5). Identities I1–I9 are pinned TDD first with exact `Decimal` fixtures
  and mutation-verified one at a time. **I9 protects everything already
  shipped**: with the accumulators on, every existing walk output is
  byte-identical.
- **F2, the two reads and their tools (§6, §11).** Two endpoints, two MCP
  tools, the payload's computation basis, and contract entry 11. The tools
  are paid for inside the budget (D-10).
- **F3, the screen (§12, board pick A of ADR-0051).** A contribution table
  under the Wealth performance chart. It shares the period control and the
  page's view, its sum row equals the badge's money figure, and it shows the
  ten largest rows with "show all N". It uses two-line rows under 560 px. The
  anatomy goes into `DESIGN.md`.
- **F4, the category result's view scope (#901).** The same scope parameter
  on the shipped read and its tool, as ADR-0051 §6 sequences it.
- **F5, the total across every portfolio (#1007; D-5).** A view-less
  valuation read. Afterwards `first_setup` and `llms.txt` drop the
  view-creating workaround.
- **F6, the security's Trades tab gets its p. a. column (#1029; pick H1).**
  This is the two-way deadline. The orphan-sells warning names an inbound
  delivery as the usual cause, as the facet does, and the moduledoc stops
  promising lots the tab does not show.
- **F7, the Overview card computes what it shows (#1030).** It no longer
  runs the whole realized report to show five rows. No rendered difference.

**Coverage:** F1–F5 change the API and MCP surface and carry the PR's
contract entry. F3 and F6 are the human views of F2 and of Sprint 17's
per-security figure. F4 and F5 have human views already (the classification
screen's scope, the dashboard's "Gesamt").

### PR γ — the screens a stranger meets

All of it is boarded on this PR. A pick's code is its board's number.

- **U1, deleting a booking from the screen (#912; pick H2).** This is the
  missing human view of an existing API and MCP capability. "Split erfassen"
  and pick G12.3's help line link to it. **It does not shrink.** The design
  pass found it bigger than the issue says, in two ways:
  - **A split cannot be deleted whole today.** It is stored as one row per
    portfolio (`Ledger.Splits`, ADR-0028 §1), and the existing delete removes
    one row. The rows left behind keep the split event alive, and "Split
    erfassen" then refuses the corrected ratio. So U1 adds an atomic write
    that deletes a split's rows together, journaled, with its API and MCP
    counterpart in the admin profile. This is risk-tier attention (ledger
    invariants): its own commit, and a verification pass in γ's closing act.
  - **"Bearbeiten" fails for most kinds.** Verified on this branch with a
    throwaway LiveView test: for every kind except buy, sell and split, the
    row menu opens the buy/sell drawer with no type selected, and saving is
    refused with "Security can't be blank, …". Nothing is corrupted, but the
    form can only refuse. Pick H2's second question decides what those rows
    offer instead.
- **U2, tables (pick H4):** the sticky subject column that sticks nowhere
  (#1009, which needs three companion rules beside its one-line fix, as the
  board shows), sign colour lost in table cells (#1010, which makes Sprint
  17's trades-table copy of the rule redundant), the split-ratio cell (#913,
  together with its sibling: the Balance column's `numeric` class has no CSS
  rule), Allocation → Positions (#911; **the one pick on this board: A, the
  hint moves into the Drift cell**), and the stylesheet drift (#1011). Every
  disclosure summary moves to the spec's 12 px/500, so #1011 is a rendered
  change at 24 places, not a dedupe.
- **U3, light-mode contrast (pick H5; #908).** Only coral fails, so the fix
  is one token (`--color-accent-coral`), changed in both places it is set
  for light mode. DESIGN.md's contrast table gets its wrong verdict
  corrected and the data-note surfaces added.
- **U4, touch and focus (pick H6):** the data-note remedies under 44 px
  (#1013), dialog close buttons, the attention rows' focus ring, and the
  inline result's dismiss (#1033).
- **U5, the phone (pick H7):** the Quotes tab at 390 px and its toast (#1012),
  the selected tab off-screen, "1Y" in German, the sync scope (#1033), and
  the import result's label overflow (#909). **One defect the design pass
  found, filed at γ's opening:** on a security's Overview at phone width the
  six figures stay in three columns ("Durchschnittseinstand" spills out of
  its cell), because `.overview-reading .overview-metrics` (`app.css:8331`)
  outranks the two-column rule under 720 px (`app.css:2810`). Board 03 draws
  its before and after. It lands here, or with U7 if U7 comes first.
- **U6, dialogs and copy (pick H8):** #910, #918 (pick A: the refusal names
  what blocks, with counts), #921 (German field errors; the two formal-address
  "Sie" strings it reuses become impersonal, as `EXPERIENCE.md` binds), #969
  (pick A: a muted "Nicht verteilt" row, ✓ only at exactly 100 %), #966
  (pick A), #920 (pick A: reload, and a note naming the vanished row), the UI
  half of #1032, and #968's isolation of stored names. **#1032 is bigger than
  it reads:** the cash merge's check dates include the target's own booking
  dates, so the story chooses between the wording and what the writer
  counts. The second option is a payload change and takes a contract entry.
- **U7, bond master data and display-only metrics (#330, as rescoped by
  Sprint 17's D-13; pick H3).** Master data, remaining term, current yield,
  an optional linear yield to maturity with its formula stated, and the
  two-scales guard. API and MCP read and set the fields, and each metric
  carries its basis. **It is shrinkable** (shrink order, step 4): the owner's
  own instrument class, not the launch path.
- **#1014 answered as D-7 rules:** `EXPERIENCE.md` follows the screens. This
  is a spec edit with no rendered difference.

### PR δ — the human documentation

This PR is written after β and γ merge, from what they shipped.

- **D1, what is better here.** A features page, in English and German, built
  around what the 2026-09-30 research found peers lack: the calculation
  breakdown, trades with their annualized figure, the append-only research
  log, policy rules, the MCP companion with its profiles, and auditable
  imports. Each claim links to the page that shows it. The page says what
  Portfolixir is not, as `llms.txt` does.
- **D2, the human first run.** The README quick start, home deployment, and
  the first import, made safe and complete: a backup step before every
  `down -v` and the contributor workflow pointed at the development stack
  (#1017); the Imports address, the password-only login, detached Compose,
  and the converter prompt's dividend depot (#1037); the CSV limits and the
  synthetic sample's Betrag rule (#1024).
- **D3, screenshots from the synthetic seed (#1034).** Regenerated, plus the
  new surfaces: the contribution table, the Trades tab, the delete dialog,
  the merge list and the release dialog. The README gains its screenshot.
  Never from a live instance.
- **D4, the documentation gaps already filed:** #952, #960, #943, #929.

### Lane Z — registry (small)

- **At PR α's branch opening:** the operator's first-look test is filed under
  E26's tracker #991, as #998 was for the launch test. The issues α builds
  (#1023, #1031, #1015, #1016, #955, #1026 and Lane D's) move under #991 when
  they have no parent.
- **At PR β's branch opening:** FR-41's own issues are filed under #991, the
  engine with its reads and the screen, as ADR-0051's Consequences require.
  The numbers land on FR-41's row in the FR Coverage Map the same day. #901,
  #1007, #1029 and #1030 move under #991.
- **At PR γ's and δ's openings:** the issues they build move under #991, and
  the design pass's Scope Lock observations are filed (γ).
- **Registry edits already on this PR:** the Tracker Index's E26 line names
  Sprint 18's half as planned, and FR-41's row names the build lane.

## Decisions

### D-1: the operator's first-look test is this sprint's exit criterion, and the agent's launch test runs again (recommended)

**The operator's first-look test.** It runs as δ's UAT persona: a fresh
agent driving a browser, with no repository context beyond the README and
the human documentation.

1. **Setup:** an instance on the synthetic demo seed (`priv/demo`), German
   locale, at 1440 px and at 390 px, in light and in dark.
2. **Four questions with known answers**, each answered from the screen,
   starting at the Overview:
   - the total value across every portfolio;
   - which position contributed most to this year's result, and how much
     (FR-41);
   - the annualized return of a named closed trade held over a year (#1029,
     or the facet);
   - the balance of a named cash account.
3. **The persona records its path for each:** the clicks it took, and any
   point where it needed the documentation to find a screen.
4. **Pass:** all four exact at both widths. A path that needed the
   documentation is a finding for δ, not a failure. A wrong or unreachable
   figure is a failure, with the step it failed at.
5. **One correction:** the persona deletes a deliberately wrong booking from
   the screen (#912) and confirms the balance it affected changed back.

**The agent's launch test** (Sprint 17's D-1) runs again at the close-out,
against `main`, unchanged. Its question 1 then measures the view-less total
of D-5.

**Passing both is necessary for the announcement and not sufficient**: the
owner decides (see "What the owner decides after this sprint").

**To flip by comment:** name a different measure, or "no operator test".

### D-2: what leaves the Sprint 18 that Sprint 17 sketched (recommended)

**I am narrowing Sprint 17's D-2, which put "the Sprint 18 candidates of D-8"
and #899 here.** That plan adopted the list as a direction, not as a fit, and
the list does not fit.

| Item | Verdict | Reason |
|---|---|---|
| **#1002** excess return per trade | after the announcement decision | the benchmark series builder is private to `Benchmark`, and the page needs a picker: a design pass of its own |
| **#1003** returns heatmap | after the announcement decision | a new surface with its own basis and board; FR-41 is the breakdown peers are compared on |
| **#1004** presenter mode | after the announcement decision | every public screenshot comes from the synthetic seed (Sprint 17 D-8), so the launch does not need it |
| **#899** Idempotency-Key | widening phase | a contract on every irreversible write; **#955 (C4) closes the failure a stranger's agent would hit**, an unreported outcome on a reset, at a fraction of the cost |
| **#900** slice two of the category result | after the launch | ADR-0051 §9 keeps it its own story. It is risk-tier money math competing with FR-41 for the same verification pass, and slice one ships |
| **#330** bond master data | **stays**, shrinkable | Sprint 17's D-13 put it here. It is the owner's instrument class, so it is cut before anything on the launch path |

**The risk if all of it stays:** Sprint 16's pattern. The batch runs into the
weekly usage limit, and the cut lands where nobody chose it: in the closing
acts or the documentation.

**To flip by comment:** name the issue number to put it back. Each one then
joins the shrink order above #330.

### D-3: the ADR-0034 amendment is signed (recommended)

The amendment is this PR's opening commit. Below a largest flow of one
million nothing changes, by construction. Above it, the solver scales in
`Decimal` before its one float step, so the float exception is not widened.
**Why it is a gate and not a quiet fix:** it changes §2's stated method, and
risk-tier semantics need their record signed before the batch (ADR-0036,
point 4).

**To flip by comment:** "relative tolerance" asks for that method instead.
Every fixture's last digit then has to be re-proven, which is why it is not
the recommendation.

### D-4: #1023 — verify the export, book once, and tell an affected instance (recommended)

The parser maps both "Umbuchung (Ausgang)" and "Umbuchung (Eingang)" to
`cash_transfer` and always reads `Konto` as the source
(`csv_parser.ex:47-48`, `:318`). On an "Eingang" row, `Konto` is the
receiver. Whether this is a live bug or a latent one depends on what
Portfolio Performance exports, and nothing in the repository says. So C1
**establishes that first** and records the source it read in the commit.

- **One row per transfer:** the "Eingang" mapping is still wrong for an export
  filtered to one account. It is fixed and pinned, and no instance is
  affected by a double booking.
- **Both sides:** the parser pairs them and books once. Instances that
  already imported such a file have reversed duplicates, which a re-import
  cannot remove. The story ships a way to find them: a read with its human
  view, boarded mid-batch, or the existing history filter documented with
  the exact query. Then the close-out tells the owner how to check their
  own instance. **Nothing in this repository will say whether the owner's
  instance is affected.** That check is the owner's, on the live instance.

### D-5: #1007 — the total across every portfolio gets a read, as an optional view (recommended)

**Yes, before the announcement.** Sprint 17's D-6 argued that a surface
should change before strangers learn it, and today the first contact needs a
structural write (a catch-all view) to read one number. The cheapest shape is
also the one the budget can carry:

- **API:** `GET /api/v1/valuation`, the unscoped union `Valuation.for_view(nil)`
  that the dashboard's "Gesamt" already reads: deduplicated, in EUR, with
  `include_positions` as on the view read.
- **MCP:** `portfolixir.views.valuation` with `view_id` **optional**. Omitted,
  it reads the total. That costs a sentence of schema, not a tool, and the
  twins' descriptions already point there.
- **Not added:** a view-less performance or benchmark read. The close-out's
  surface check names them as the family's members that do not carry it, and
  why: no one has asked, and the budget is full.

**To flip by comment:** "keep the workaround" leaves F5 out, and the launch
test's question 1 keeps measuring the two-call route.

### D-6: #912 is a two-way debt, and it does not shrink (recommended)

`Ledger.delete_transaction/2` has exactly one caller in the web layer, the
API controller (`transaction_controller.ex:175`). No screen can delete a
booking. The coverage rule runs both ways, and a capability whose human view
is missing is a close-out finding. This one was filed in Sprint 16 and fell
outside Sprint 17's two-way list because it predates the agent-first
shipping that list tracks. Pick H2 decides where the action sits and what
its confirmation says. The confirm states every refusal the API states.

**What a delete does to an imported booking stays as it is.** Deleting a
booking removes its import hash with it, so a re-import of the same file
books it again. A merge retires the hash instead (ADR-0050). U1 does not
change that: the screen gets the capability the API has, and the confirm
says so in one sentence. Making a delete retire the hash would change what
the API's delete means, and that is import-idempotency semantics, which
needs its record signed before the batch (ADR-0036, point 4).

**To flip by comment:** "retire on delete" files that record for Sprint 19.
The confirm's sentence then changes with it.

### D-7: the decisions Sprint 17 left waiting (recommended; each row flips by naming its issue)

| Issue | Answer | Reason |
|---|---|---|
| **#1014** dates in display | `EXPERIENCE.md` is amended to the locale's date (DD.MM.YYYY in German). ISO stays for inputs, the API, files and exports | the screens, three passes of boards and German readers agree. Moving the screens to ISO would be a rendered change everywhere, for a spec sentence |
| **#1016** the seeded-upgrade rule | **widened**: a UNIQUE index, a foreign key or an exclusion constraint added to an existing table needs a seeded case, including one built `CONCURRENTLY` or behind a cleanup step, because the cleanup is what the case proves | `20260925210000_unique_position_target_per_plan.exs` already raises on legacy duplicates, and the rule says nothing about it |
| **#1020** real public instruments in fixtures | **test fixtures use invented instruments**, repaired mechanically in the shape of the bond repair (α, Lane D). **The demo seed keeps well-known company names**, because it is a demo, not a test, and its screenshots are public; it never takes a name from a real portfolio | "synthetic all the way down" (AGENTS.md); an agent that writes the next fixture copies the last one, and nothing tells it whose ISINs those were |
| **#1026** outbound fetches and the proxy CA | **both, in α** (C5), the CA half shrinkable | the launch test hit the proxy twice. A self-hoster whose host must not call out has only the firewall today |
| **#1038** a parse-only check before the drop | **not now** | ADR-0029's non-interactive rules bind the moment a route exists. The launch test passed twice without it, and a wrong file costs a failed preview, not wrong data. Reopened by a stranger's report of the round trip |
| **#1025** a settlement field in JSON v1 | **not now** | it makes the JSON v1 format diverge from Portfolio Performance's own shape. The prompt states the limit. A design gate when a stranger needs it |

Still waiting, deliberately: #999 (scoped tokens), #1000, #1001,
#987–#990, and the rest of the `needs-decision` list (D-12).

### D-8: the design picks (recommended; silence adopts them)

Eight boards, under
`planning-artifacts/design-language/mockups/ux-design-2026-10-02/`, argued in
`planning-artifacts/ux-design-2026-10-02-sprint18.md`:

| Pick | Item | Board | Kind | Recommended |
|---|---|---|---|---|
| **H1** | The security's Trades tab: the p. a. column (#1029, F6) | `01-trades-tab-pa` | before/after | after |
| **H2** | Deleting a booking from the screen (#912, U1) | `02-booking-delete` | variants | **A** |
| **H3** | Bond master data and metrics (#330, U7) | `03-bond-master-data` | variants | **A** |
| **H4** | Tables (#1009, #1010, #913, #911, #1011; U2) | `04-tables-conformance` | before/after, one pick (#911) | after; **A** for #911 |
| **H5** | Light-mode contrast (#908, U3) | `05-light-contrast` | before/after | after |
| **H6** | Touch and focus (#1013, #1033; U4) | `06-touch-focus` | before/after | after |
| **H7** | The phone at 390 px (#1012, #1033, #909; U5) | `07-phone-390` | before/after | after |
| **H8** | Dialogs and copy (#910, #918, #921, #969, #966, #920, #1032, #968; U6) | `08-dialogs-copy` | before/after, four picks (#918, #969, #966, #920) | after; **A** for each pick |

**FR-41's screen** is ADR-0051's own board (`mockups/fr41-2026-09-25/`, pick
A), adopted with the record. It is not redrawn.

**Items with no board:** everything in PR α and δ changes no rendered output
of the app (δ is the documentation site and the README). F2, F4, F5 and F7
are payload or performance only. #1014 amends the spec to match the
screens: the picture is identical.

### D-9: four lane PRs, merged in order, and no stacked PR merged into a branch (standing, amended by the Sprint 17 retrospective)

| PR | Lanes | Merged | Why this order |
|---|---|---|---|
| **α** | C, D, M | first | the money bugs before anything shows money; the harnesses guard what follows |
| **β** | F | second | FR-41 and the reads; `mcp-server/src/tools.ts` and the contract manifest are shared with γ |
| **γ** | U | third | the polish lane, and #330's fields after β's tools |
| **δ** | the documentation | last | it shows what β and γ shipped |

**The Sprint 17 retrospective's carry-forward, both halves:**

1. **Owner action, one checkbox:** in the repository settings, turn on
   "Automatically delete head branches". GitHub then retargets a stacked PR
   to `main` when its base branch disappears with the merge.
2. **Agent duty, whatever the setting:** the moment a lane PR merges, the
   agent retargets the next one to `main` and says so on it, before the
   owner can merge it.

Each PR opens as a draft with its first commit, carries its own briefing, is
promoted under `AGENTS.md`'s four conditions, and is rebase-merged by the
owner. Each one that changes the API or MCP surface opens its own contract
entry, because each merge is a release.

### D-10: the schema budget is paid inside each PR (standing rule, stated with its cost)

The ceilings leave 149, 36 and 167 bytes (read, book, full) as measured on
this branch. β adds FR-41's two tools, #901's parameter and D-5's optional
view. γ adds #330's fields. **Each of those PRs trims existing descriptions
to pay for what it adds, then lowers the ceiling to the new figure**, as the
rule in `schema-budget.ts` says. A raised ceiling is a weakened gate and a
review reject. The Sprint 17 retrospective's lesson holds: words are added
tightly from the start, and each PR measures against the PRs ahead of it at
its closing act. #1027's check makes "only down" a test in α, before β needs
it.

### D-11: maintenance (recommended)

- **Node 26** becomes LTS on 2026-10-28. If α's lane runs on or after that
  date, the bump is taken (#977). Otherwise it is declined again with the
  date.
- **sobelow 0.16.0** (#1006) is taken with its six new findings read. A
  finding is fixed or argued, never ignored.
- **#881** (codecov-action) has sat open since 2026-09-24 as the
  maintainer's. **Owner action:** merge or close it. It is the only open PR
  that is neither a lane PR nor a recorded decline.
- The version report, the BMAD modules, and #727's triggers, as every sprint.

### D-12: what stays open on purpose (recommended)

| Issue | Action | Reason |
|---|---|---|
| **#328**, **#354** | stay open | the owner's runs on real data |
| **#330** | in γ, shrinkable | D-2; its UAT is the owner's, on the live instance |
| **#727** | stays open | re-checked in Lane M |
| **#987–#990**, **#999–#1001** | stay open | ADR-0051's deferrals and Sprint 17's follow-ups, each waiting for a need |
| **#866**, **#894–#898**, **#902–#907**, **#946**, **#950**, **#970**, **#972–#974**, the other `needs-decision` issues | stay open | none blocks the launch path, and nobody has asked for any of them yet |
| **The E25 review follow-ups not named here** (#917–#962 and #965–#971 outside this plan's lanes) | stay open | small and agentic. They are the first maintenance batch after the announcement decision, not launch work |

### D-13: the closing act, one lens per risk class, and the budget (standing)

| PR | Lenses |
|---|---|
| **α** | correctness hunter; **money lens on C1 and C2** (the import's book-once property, the amendment's three identities); the seeded-upgrade lens over C3; dependency chokepoint for Lane M |
| **β** | correctness hunter; **money lens on I1–I9**, one at a time, I9 first; edge-case hunter; design critic against ADR-0051's board and H1, in German at 390 px, light and dark |
| **γ** | edge-case hunter; UAT persona on the synthetic seed; design critic against H2–H8 |
| **δ** | **the operator's first-look test as the UAT persona** (D-1); a privacy lens over every screenshot and example |

A cascade stops when a layer yields no major finding. Every finding carries
its reach label. Each lane PR reserves its closing act and its briefing
before its first story. If the weekly usage limit comes into view, the shrink
order applies from its first step, and the closing acts are not what is cut.
A closing keyword is checked against the diff before a PR body names it.

## Sequencing

```text
after the merge ── Lane Z: nothing to close by hand
PR α opens ─────▶ C1 #1023 ─▶ C2 #1031 ─▶ C3 #1015/#1016 ─▶ C4 #955 ─▶ C5 #1026
                   Lane D hygiene (with #1027's enforced ceiling early)
                   Lane M: version report, sobelow, Node 26 on its date
                   closing act ─▶ merge = a release
PR β opens ─────▶ F1 engine (I1–I9) ─▶ F2 reads + tools ─▶ F3 the table
                   F4 #901 ─▶ F5 #1007 ─▶ F6 #1029 ─▶ F7 #1030
                   closing act ─▶ merge = a release
PR γ opens ─────▶ (retargeted to main when β merges)
                   U1 #912 ─▶ U2–U6 the boards' repairs ─▶ U7 #330
                   closing act ─▶ merge = a release
PR δ opens ─────▶ D2 first run ─▶ D1 what is better here ─▶ D3 screenshots
                   ─▶ D4 gaps; closing act with the operator's test ─▶ merge
close-out ─────── the agent's launch test against main; the two-way check;
                   the surface check; the launch-readiness summary
```

## Shrink order (cut from the top, name the cut in the briefing)

1. **Lane D's test hygiene** (#1018, #1019, #1021) moves to Sprint 19.
2. **The fixture repair** of #1020 moves to Sprint 19. D-7's answer stands.
3. **C5's CA half** moves to Sprint 19. The runtime switch stays.
4. **U7, #330**, moves to Sprint 19, boarded already.
5. **U6's copy-only items** (#910, #918, #966, #968) move to Sprint 19.

**What does not shrink:** C1 and C2 (wrong money figures in front of a
stranger); C3 (an upgrade a stranger cannot finish); F1–F3 (the headline,
signed); F5 and F6 (#1029 is the two-way deadline); U1 (#912, D-6); D2 and D3
(the first run and its screenshots); both tests (D-1).

## What is deliberately not in this sprint

- **The three peer candidates** #1002–#1004, **#899** and **#900** (D-2).
- **#1038** and **#1025** (D-7).
- **An import route under `/api/v1`**: the import stays an operator action
  (ADR-0029).
- **A view-less performance or benchmark read** (D-5).
- **B3.3, B3.5, B3.7, B3.8** and ladder level (d): shut.
- **Phone access**: the widening phase, after the announcement.

## What the owner decides after this sprint

The close-out ends with a **launch-readiness summary** of one page, so the
announcement decision rests on something read rather than remembered:

- both tests' records, step by step;
- the open issues that touch money or an upgrade path, which should be none
  known, each named if not;
- the open-issue count by label, and what changed in it this sprint;
- what Portfolixir deliberately does not do, as `llms.txt` and the features
  page state it;
- the owner's own checks that no agent can run: #1023 on the live instance
  (D-4) and #330's UAT, if U7 landed.

The announcement stays the owner's call (Sprint 17's D-1). If the owner
announces, the widening phase starts with the first maintenance batch (D-12)
and the three peer candidates (D-2). If the owner does not, the summary
names what is missing, and that becomes Sprint 19's plan.

## What "done" means for this sprint

1. **PR α, β, γ and δ are merged in order**, each green on its head, each
   with its closing act under D-13 and its briefing.
2. **#1023 and #1031 are closed by keyword**, with the export shape C1
   established recorded in α's body.
3. **FR-41 shipped**: I1–I9 pinned and mutation-verified, the two reads and
   tools, and the table on board A. Its registry row moves.
4. **#1029 and #912 have their human views**, or the close-out records the
   miss as a two-way finding.
5. **The operator's first-look test passed** at δ's closing act, and **the
   agent's launch test passed** at the close-out against `main`. A failure
   names its step.
6. **Each merge that touched shipped code produced a calendar release.**
7. **The schema budget's ceilings are no higher than today's**, and #1027's
   check enforces that.
8. **The close-out's surface check** names FR-41's family (both scopes),
   #901's scope parameter across the category-result family, and D-5's
   view-less valuation against the view family's performance and benchmark
   reads.
9. **The launch-readiness summary** is in the close-out.
