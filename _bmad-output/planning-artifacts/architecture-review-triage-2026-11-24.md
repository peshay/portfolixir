# Architecture Review Triage — 2026-11-24

Source: a read-only architecture review (idea row I38; lens 2 of the audit of
2026-11), run from 2026-11-11 to 2026-11-24 against `e014f284`, the head of
`main` on 2026-11-10, the same commit lens 1 (security,
`security-review-triage-2026-11-11.md`) read. It asked the five questions of
section 3: whether the context seams of ADR-0001 hold, whether every MCP tool
goes through the API only (ADR-0002), which modules do more than one job and
how each would split, whether two code paths compute the same figure, and
where a read bypasses the derived-value layer (ADR-0039). The review edited,
committed, pushed and filed nothing. **The evidence, which carries the
reproductions, is held privately by the owner and is not committed.** Four
rows were held, as the security triage's "Disclosure handling" orders, and
stood here by ID and severity only, with one owner decision (AD-9) that
concerns one of them. On 2026-11-25 all four and AD-9 were stated here with
their fixes, which #1489 merged that day. The complete report stays private
with the evidence; "the private report" below is that report.

This document is the repository version of the report's sections 1 to 4, 6
and 8 to 13, under the report's own section numbers. Where a public row
touched a held one, that part was left to the private report too; R-098's
part is restored with the four rows. Section 5,
the S1 and S2 in full, is `architecture-review-findings-2026-11-24.md`, and
section 7, the proposed split per module, is
`architecture-review-splits-2026-11-24.md`; both lie beside this file.

**Status: PROPOSED** — adopted by the merge of this planning PR (ADR-0026 step
1 as amended on PR #780: the merge is the signature). A decision in section 10
that the owner rejects is changed on the PR before the merge.

`main` has moved on since: 180 commits by 2026-11-15, a feature sprint and a
rule review. Every finding describes `e014f284`. For each S1 and S2 a reader
then looked at that later `main` and said whether the code that makes the
defect is still there; the index in section 4 has that column. That check read
code and ran nothing. No S3 was held against the later `main`; section 13
names two that it has since answered.

On 2026-11-24 the ten S1 were run again on a still later `main`: `a1e54b18`
of 2026-11-23, 393 commits after the audited one. Each reproduction ran in a
test slot on that commit. All ten still stand, with the audit's figures.
The private evidence holds that check and says what no lens has read,
among it 46 code files that are new since the audit.

Findings carry an ID (`R-001` to `R-159`, most severe first) and, in
brackets, the key of the lane that found them. The key is the heading of their
entry in the private evidence.

## 1. Result

- **159 findings confirmed: 10 S1, 19 S2, 130 S3.**
  28 reader lanes wrote 174 candidates. 15 were duplicates of 13
  findings, each found by two or three lanes, and were merged.
  Six candidates of one gap lane reached a verifier only after the report's review had found them missing from the registry; all six were confirmed. Each finding was confirmed by a second agent that executed
  something: a scratch test in a throwaway copy, a request against the test
  endpoint, or a count or search over the source. Many were narrowed on the
  way; the report states the verifier's wording, not the reader's.
- **Second readings.** The 40 findings that a verifier graded S1 or S2
  were then read by skeptics whose job was to refute them: two for an S1, one
  arguing reach (can the operator or the agent get there?) and one arguing
  "already decided or tracked"; one for an S2. That is 52
  readings. None fell. 13 came out one grade lower
  (2 from S1 to S2, 11 from S2 to S3), for a recorded
  decision the verifier had missed or for a reach that needs an unusual
  state; section 12 lists them. The counts above are the final grades.
- **The audit lead re-ran all 10 S1 reproductions** on 2026-11-16: 37
  scratch tests, all passed, each printed the figures its entry quotes.
- **130 S3** are structure, records behind the code, missing pins and
  small screen defects. None was graded a wrong money figure in normal use.
  Some print a figure on two decided bases, or one that is off by a last
  digit, a day or a narrow state; their rows say by how much (for example
  R-033 (D1-03), R-047 (D5-02), R-050 (G2-04), R-093 (D4-06), R-130 (D3-01)).
- 261 leads were written down and not verified. They are listed per
  lane at the end of the private evidence, not among the findings.

### The governing finding: a figure has one owner on paper and several in the code

The seams that a test enforces hold. No web module calls the Repo (0 calls in
the compiled call graph). All 166 MCP tools reach the application through the
one API client. A third seam holds for calls with no test behind it: the
contexts call the web layer in two places, both in `Application` (the boot
step and the configuration-change callback), and translate through it at 190
call sites (R-073 (A1-01), R-074 (A1-02)).

What no test and no written rule enforces is who owns a figure. The same
question is answered a second time, by other code with another rule, in three
kinds of place. All 10 S1 are one of the three:

1. **Two engines inside the domain.** The valuation and the performance walk
   each resolve today's price, and each decide which bookings count today
   (R-001 (D2-01), R-002 (D1-01)). The snapshot comparison decides which fees belong to a view
   by another rule than the return they are subtracted from (R-004 (D4-01)).
2. **A page or a preview that folds its own figure** beside the context's
   read: the plan editor's sum (R-003 (O4-01)), the chart's cost line (R-009 (A2-02)), the
   performance table's start value (R-010 (O2-01)), the depot merge's cost (R-005 (A4-01)),
   the cash merge's quantity (R-006 (G4-02)).
3. **A stored answer whose invalidation is narrower than what it read.** The
   policy findings and the performance walk are kept after a write that
   changes their inputs (R-007 (V1-01), R-008 (V1-02)).

The S2 repeat the second kind seven times (R-012 (D2-03), R-013 (A2-03), R-016 (G4-03), R-022 (G2-01), R-023 (G2-02),
R-024 (O1-02), R-025 (O1-04)). The measurement behind it (R-048 (D5-04)): the web layer holds 89 lines
of decimal arithmetic in 24 files, at 35 places that derive a figure. Two are
pinned to their API twin. Six differ from it today. Twelve the API cannot
answer at all.

This is lens 1's governing finding seen from the other side. Lens 1 found
money rules that live in a form and not in the context. Lens 2 finds money
figures that live in a page and not in the context.

## 2. How this was done

- **Measured first.** The compiled call graph of the project's own modules
  (474 modules, 8,132 call rows) and `mix xref` (455 files; 119 compile-time,
  333 export and 2,043 runtime edges; seven cycles, the two large ones of 96
  and 75 files). Both are the test build's; the dev build has 149
  compile-time edges (R-091 (A7-05)). This is the "scout" data the evidence
  cells cite: the scout's counts and its call table.
- **24 reader lanes**, each with a fixed set of files and questions: A1 to A7
  the seams, M1 and M2 the MCP companion and coverage, O1 to O8 the oversized
  modules, D1 to D5 duplicate figures, V1 and V2 the derived-value layer. A
  completeness critic then named four gaps (the target-plan write path;
  figures on pages no lane had read; what the agent is told; the twin account
  merges and News). Four more lanes, G1 to G4, read them.
- **Every finding verified by something executed.** A second agent had to
  reproduce a candidate before it counted. Runs happened in four isolated
  containers on an internal network with no route out, on synthetic fixtures
  and seeded ledgers only. Scratch tests were written into a throwaway copy and removed
  afterwards. In the entries, a test slot is one of those containers
  and `test/audit_scratch/` the scratch directory inside the throwaway copy.
  The bearer value in a scratch test is the test environment's own fixture
  (`config/test.exs`).
- **Split proposals reviewed.** Each reader's proposal for an oversized module
  was recounted by an independent reviewer, who also traced by reading the
  calls that cross the proposed module boundaries. Nothing was compiled or
  run for a split. Section 7 states the corrected proposal.
- **The report itself reviewed.** Thirteen independent reviewers held the
  finished report against its evidence: every number of the hand-written
  parts, the index, the split sections, the severities, disclosure, and the
  owner's read. Their 226 remarks were checked and worked in.
- **Severity** follows `docs/development/sprint-workflow.md`. Its S1 ("a
  figure can be wrong") and S2 ("a figure contradicted between two surfaces")
  overlap for this lens. Each grade is the verifier's, moved where a second
  reading gave a reason that holds. The line that results:
  - **S1** when a figure is wrong by a written rule or by arithmetic on a
    surface, display-only included, and nothing on that surface says so.
  - **S2** when each figure is right on a basis of its own and the two are
    shown as if they answered one question (R-022 (G2-01), R-023 (G2-02)); when the wrong
    figure stands beside a marker that dates its input (R-021 (O1-01)); when the
    figure is arithmetically right and a written sentence about it is wrong
    (R-012 (D2-03)); or when it is stale in one open page only and a save or a reload
    corrects it (R-015 (O4-02), R-026 (O2-04)).
  - **S3** for a gate or pin that is narrower than its claim while nothing
    passes through it today, the rule lens 1 used for N-78 to N-90. R-144 (M1-01) is
    the nearest to the ladder's "a gate silently checks nothing": it reads 40
    of 166 tools, and all 166 are documented today.

  Six S1 have a small or narrow reach by their own entries (R-002 (D1-01), R-006 (G4-02),
  R-007 (V1-01), R-008 (V1-02), R-009 (A2-02), R-010 (O2-01)). They stay S1 because nothing on the surface
  says the figure is off: no read names a booking dated ahead, the stored walk
  is marked fresh and the findings carry no stale key, the preview is what
  the operator confirms, and the chart line and the table cell stand beside
  the right figure with no note. R-002 (D1-01) is S1 although nothing written decides
  the rule; if AD-1 picks option (b), neither figure is wrong and what is
  missing is the marker, an S2. The line is not sharp. A reader who draws it
  elsewhere will move R-012 (D2-03), R-021 (O1-01) and R-022 (G2-01) up; section 12 lists every grade
  that moved, with the reason.

## 3. The five questions

### 3.1 Do the context seams of ADR-0001 hold?

**The one seam ADR-0001 states holds for calls. The seams it does not state
do not exist as seams.**

- *Contexts never depend on the web layer.* Holds for calls: 2 calls from
  `lib/portfolixir` into `PortfolixirWeb`, both in `Application`. It does not
  hold for translation: seven domain modules translate through the web
  layer's Gettext backend at 190 call sites (R-073 (A1-01)). At `e014f284` no gate
  failed when a context named the web layer (R-074 (A1-02)). The later `main` has
  such a gate and registers the Gettext backend as its exception (section
  13).
- *The web layer reaching into internals.* The web layer never calls the Repo,
  and a test pins that. But nothing says which context modules are public. The
  LiveViews and components make 341 calls to a context's top-level module and
  306 past it, to 65 submodules (R-078 (A2-08)). One dialog authors its own database
  transaction through a context function that hands out `Repo.transaction`
  (R-076 (A2-05)). Three places build a schema changeset themselves as a dry run of a
  write (R-077 (A2-06)).
- *Between contexts.* Nothing is written. ADR-0001 names four contexts; the
  tree has 13 context directories and 19 supervised children (R-075 (A1-05)). Twelve
  of the 13 contexts form one call cycle, and a layering needs 13 edges cut
  (R-084 (A6-01)). Contexts read and lock each other's tables with queries of their
  own at 125 places: Lifecycle and Imports at 59 (R-080 (A4-05)), Portfolios, Ledger,
  Catalog and Fx at 32 (R-083 (A5-05)), News, Buckets, Predictions and Knowledge at
  34, eleven of them row locks (R-085 (A6-02)). Imports and Lifecycle call each other
  (R-079 (A4-04)). Catalog, the base context, calls up into News (R-086 (A6-03)). The Ledger
  calls up into the valuation (R-081 (A5-02)).
- *Rules the web layer holds.* This is where the seam costs figures. The plan
  save's write rules live in the LiveView, and the API writes the same plan
  without them (R-057 (O4-03)). Twelve domain rules live in the securities page, four
  with a second holder (R-052 (O1-07)). About 60 basis and rule sentences served in
  payloads are written in the web layer (R-046 (A3-03)). The S1 and S2 of the second
  kind above are the visible result.
- *Compile-time coupling.* Five small causes hold the two large cycles
  together or widen what an edit recompiles (R-087 (A7-01) to R-091 (A7-05)). Each is a few
  lines.

What to do: one amendment of ADR-0001 (section 9, AD-5) that names the
contexts, says which modules are public, gives the calls between contexts one
direction, and adds the gate that fails when any of it is broken.

### 3.2 Does every MCP tool go through the API only (ADR-0002)?

**Yes.** 166 tool declarations, 166 dispatch cases, 166 requests through the
one client, no path outside `/api/v1`, no file, process, database or second
host in the companion's source. Two tests pin it
(`mcp-server/test/published.test.ts`,
`test/invariants/scope_b2_outbound_chokepoint_test.exs`), and the dependency
list equals its allowlist. The answer is passed through unfiltered.

What has changed since ADR-0002 is the word "thin". The companion is 8,623
lines, of which 979 forward. It now holds rules of its own:

- Five request shapes get another answer from a tool than from the API
  (R-097 (M1-02)). Every tool's input contract is written twice by hand, the
  test between the two compares neither bounds, patterns nor closure, and one
  bound and four date patterns are enforced without being published
  (R-098 (M1-03); its closure half fixed in #1489). 28 closed sets
  are typed by hand in the companion; the 24 that have an accessor in the
  application agree with it today, and no test compares one (R-145 (M1-04)).
- The single-egress scan has one gap that needs no dependency (R-146 (M1-07),
  worded by its class here, like lens 1's gate rows; fixed in #1489). The docs
  gate reads 40 of the 166 tool declarations (R-144 (M1-01)).
- What the agent is told is thinner than what the routes do: a cap on a word
  that is no asset class is accepted and answers "no class over cap"
  (R-018 (G3-02); fixed in #1489); the contract
  read that the first-setup prompt calls as a connection check answers
  241,722 bytes (R-020 (O6-03)); one read states less of its computation
  basis than the metric rule in AGENTS.md asks (R-095 (G3-01)). On the API
  itself a malformed filter is dropped and the unfiltered list answered; only
  a direct caller meets that, because the tool's schema refuses the value
  first (R-019 (A3-02); fixed in #1489).
- Coverage, both ways: no test pairs a route with a tool or a screen write
  with a route (R-147 (M2-01)). Section 6's agent theme lists the gaps (R-099 (M1-06), R-100 (M2-02)
  to R-104 (M2-06)); the Transactions figures that have no API twin (R-059 (O4-08)) are in
  its theme "Rules and figures the web layer holds".

### 3.3 Which modules do more than one job, and how would each split?

All six that I38 names, and the others listed at the head of section 7.
Section 7 gives each one's jobs today, the proposed modules, the order of
work and the pins, as corrected by the review.

Three things are common to the page modules:

- **They grew by addition only.** The securities page grew by 7,823 lines in
  154 commits and shrank by 85 in 14; none of its twelve sibling modules was
  an extraction (R-113 (O1-05)). The imports page is four times its size of ten weeks
  ago (R-115 (O3-05)).
- **Page mechanisms are written per page.** 20 dialog shells, 31 sign-class
  clauses, 19 private URL readers, 9 changeset-error helpers (R-118 (O5-05)). The API
  has 37 private copies of `not_found` and 35 of `unprocessable` (R-121 (O6-02)).
- **The safe order is the same on every page:** shared helpers and labels
  into plain modules first (the markup modules do not compile without them),
  then markup out into function-component modules (no state, no process), and
  the rules that are domain rules into the context last. The reviews prefer
  function-component modules to LiveComponents. Section 7 puts the figure
  fixes before the moves: in the securities page they had been queued behind
  4,250 lines of moves.

### 3.4 Do two code paths compute the same figure?

**Yes. Eight of the ten S1 and eight of the 19 S2 are this.**

- Different answers today, in the domain: today's price by two rules (R-001 (D2-01));
  a booking dated after today counted by one read and not by the other
  (R-002 (D1-01)); a view's transaction costs (R-004 (D4-01)); the two merge previews against
  the reads they promise to equal (R-005 (A4-01), R-006 (G4-02), R-016 (G4-03)); a one-year return
  of 0.0 % from one read where the other refuses a figure (R-021 (O1-01)).
- Different answers today, page against context: R-003 (O4-01), R-009 (A2-02), R-010 (O2-01), and the
  S2 R-013 (A2-03), R-012 (D2-03), R-024 (O1-02), R-025 (O1-04), R-022 (G2-01), R-023 (G2-02).
- Copies that agree today and that no test, or only a narrow one, holds
  together: the cash a trade books and FIFO consumption, each written twice
  inside the Ledger (R-035 (D1-06)); the dated EUR-hub conversion in four modules
  beside `Portfolixir.Fx`, with four treatments of a missing rate (R-036 (D2-04));
  the settlement legs of an imported cross-currency trade, compared by one
  test at one exact rate (R-043 (O8-02)); "the securities a view holds", written out
  four times (R-032 (A6-07)); a booking's write-time rule chain, three times (R-030 (A4-03));
  which way a booking kind moves cash, in two hand-written lists beside the
  one reducer ADR-0011 decided (R-058 (O4-07)).
- Bounded or decided differences that a record should state: R-033 (D1-03), R-037 (D3-03),
  R-038 (D3-04), R-039 (D3-05), R-040 (D4-03), R-041 (D4-05).

What to do: the fixes one by one (section 11), and one pin that would have
caught most of the page-against-context cases: a test that holds every figure
a page derives against the API's answer for the same fixture (R-048 (D5-04)).

### 3.5 Where does a read bypass the derived-value layer (ADR-0039)?

**I34 is confirmed, and its first step should change.** On Wealth's stacked
chart every change of level, sort, scale or filter at one period runs a full
windowed walk, although the walk reads none of them; each new period runs the
same walk twice, once for the table and once for the bands (R-066 (V1-03)). Measured
on the synthetic ledger the measure task seeds (50 securities, 1,000
bookings, 10 years): 335 to 413 ms per click at three years, 1.2 s at the
full history. I34's step 1 as written would memoise each request shape. The
walk does not depend on the request shape, so one stored walk per period can
serve the table and every stack request. I34's row should say so.

Since the audit both steps of I34 were built: step 1 in Sprint 29 as its row
said, the bands memoised per period and request, and step 2 in Sprint 31, the
default period warmed. This section describes the state before both. The
re-run of R-008 (V1-02) on the later `main` shows the new bands memo serving the same
stale figure after an exchange-rate write.

Generalised, the same pattern at other reads:

- A page computes in `mount/3`, in the dead render and again on the connected
  mount: the Wealth positions projection (R-063 (O2-03)), the Risk page's lens, walk
  and findings (R-068 (V2-02)).
- A page recomputes on every event what did not change: with a security
  open, every tab click, keystroke and filter chip runs 70 queries, 65 of
  them the detail's (R-062 (O1-03)); the tree page reloads every tree on every search
  keystroke (R-064 (O4-05)); both merge previews read the database while rendering
  (R-065 (O5-02)).
- The layer is not asked when it has the answer: a current walk in the memo
  is not served at page open (R-070 (V2-04)); a return to Wealth starts a walk for a
  period the page never shows (R-069 (V2-03)).
- The warm set rests on a premise that no longer holds (R-071 (V2-05), R-072 (V2-06)), and
  the Ledger's holdings and trades reads build a pricing context per call
  instead of joining the one ADR-0035 decided (R-081 (A5-02)).

The layer itself has two S1, both an invalidation narrower than the read
(R-007 (V1-01), R-008 (V1-02)), and four pins that are missing or narrower than they say: the
freshness meta-test lists six payloads by hand and four of the eight
registered analytics are outside it (R-152 (V1-04)); two memoised payloads changed
after their last computation-version bump and no test pins either number
(R-153 (V1-05)); the hand-kept lists of journaled kinds miss the News context
(R-061 (A1-03)); the activation measurement ADR-0039 calls a task with an owner stops
at 2026-08-18 (R-067 (V1-06)).

## 4. Findings: index of S1 and S2

Every row was reproduced by a run. The "Finding" column is the audit lead's plain statement; the entry in section 5 has the verifier's own title. "Second reading" is what the skeptics, whose job was to refute it, answered. "On `main`" is a reading of the later `main` (2026-11-15), not a run.

| ID | Sev | Finding | Stands against | Fix | ADR amendment | Second reading | On `main` |
|---|---|---|---|---|---|---|---|
| R-001 (D2-01) | S1 | The Wealth total and the performance walk price a holding by two rules: after a buy newer than the last stored close, the two reads state two portfolio values for today (9,800 against 10,200 in the run), and the Wealth page shows its total by one rule and its period result by the other. | lib/portfolixir/portfolios/valuation.ex:189-192 ("no surface prices a position two ways"); docs/integration/api-and-mcp.md:2899-2900; ADR-0010 :84-86 | L | ADR-0010 | not refuted (2) | still stands |
| R-002 (D1-01) | S1 | A booking dated after today counts at once in the balance, the holdings and the valuation, and on no day of the performance walk; no read names such a booking. | Nothing written decides it; ledger.ex:131-133 and valuation.ex:5 say "current", performance.ex:894-896 walks to today; only splits refuse a future … | M | ADR-0004 (or ADR-0010) | not refuted (2) | still stands |
| R-003 (O4-01) | S1 | The plan editor says a plan sums to 100 % where the engine, the API and both pages read 60 % with 40 % unallocated; a portfolio held exactly on plan is reported up to 40 pp off target. | ADR-0040 §1 (docs/decisions/0040-unallocated-remainder-in-target-plans.md:49-50); allocation.ex:93-94 "so no surface disagrees with another" | M | ADR-0040 (§1, §2), with a note on ADR-0030 §4 | not refuted (2) | still stands |
| R-004 (D4-01) | S1 | In a snapshot comparison bound to a view, a trade's fee is a cost by where its cash account sits: one shape removes the fee twice, the mirror shape not at all. | ADR-0027 amendment 2026-08-15 §2 (docs/decisions/0027-plan-versions-and-depot-snapshots.md:191); ADR-0019 :50-51, :57-58; ADR-0051 :128-131, :530-531 | M | ADR-0027 (one sentence in ADR-0051 §1) | not refuted (2) | still stands |
| R-005 (A4-01) | S1 | The depot-merge preview states shares that arrived by a transfer from a third depot at zero cost, before and after, against the holdings read. | ADR-0050 §16 invariant 12 (0050:699); the payload's own positions_basis (merge_json.ex:54-56); the @doc contract of Ledger.position_costs/1 … | S to M | none | not refuted (2) | still stands |
| R-006 (G4-02) | S1 | The cash-merge preview states a position change in booked units, without the splits: after a 2:1 split the depot loses 6 where preview, API and dialog say 3. | cash_merge_test.exs:354-358 "the depot holds exactly that much less"; ADR-0050 §16 invariant 12 (:699) | S | none | not refuted (2) | still stands |
| R-007 (V1-01) | S1 | A stored policy finding outlives a trade in another portfolio that changes the price it was read off: served "ok" at 20 % where its rebuild says "breached" at 50 %. | ADR-0049 §5 (0049:216-220, the basis it names); ADR-0039 I1 (0039:154); policy_findings.ex:40-43 | S | ADR-0049 (§5, the basis) | not refuted (2) | still stands |
| R-008 (V1-02) | S1 | An exchange-rate write does not reach a portfolio whose only foreign-currency touch is a delivery's price; its stored walk is served unchanged and marked fresh. | ADR-0039 I1 (0039:154); blast_radius.ex:213 and :29; the decided radius row is ADR-0032 §3.2 (0032:146), narrower than the walk's reads | S | ADR-0039 (dated note widening the exchange-rate row carried from … | not refuted (2) | still stands |
| R-009 (A2-02) | S1 | The security chart's cost-basis line is a second cost fold in the page: it ignores deliveries and pools all depots, so it draws another average cost than the Holdings tab. | ADR-0033 (0033-per-position-pnl-fx-decomposition.md:308, the four surfaces change together); ledger.ex:741-743 and ADR-0028 §3 (no catch-all in a … | M | ADR-0028 §3 (dated note: its "ends in a catch-all" is out of date) … | not refuted (2) | still stands |
| R-010 (O2-01) | S1 | The performance table's first row counts a first-day deposit in "Start value" and again in "Net flows", against the opening-value card above it. | table_summary/1's own contract (portfolio_live.ex:5905-5906); module doc :6-7; ADR-0051 baseline rule (0051:174-175) | S | none | not refuted (2) | still stands |
| R-011 (O4-04) | S2 | The transaction history has no paging; at about 10,000 bookings the page's process is killed by the heap cap. | heap_cap.ex:12-13 (lists are bounded where they arrive); PRD NFR-8 (prd.md:760-762); the choice is recorded only in a code comment … | L | none | not refuted (1) | still stands |
| R-012 (D2-03) | S2 | A held category the plan does not target gets a full drift and a sell-everything hint over the API, and each page hides it by a rule of its own. | lib/portfolixir/portfolios/allocation.ex:149-152 ("carries drift_weight: nil ... a threshold never selects it") … | M | ADR-0023 | not refuted (1) | still stands |
| R-013 (A2-03) | S2 | A category with an explicit 0 % target reads "all targets within ±5 pp" on the Overview while the engine counts it off target. | allocation.ex:985-986 (has_target is the fact target_weight cannot tell apart); dashboard_live.ex:1095; portfolio_live.ex:784-786 | S to M | none | not refuted (1) | still stands |
| R-014 (G1-01) | S2 | A category weight blanked in the plan editor is not deleted by "Save plan", and "Copy from another view" over an existing plan stores the union of both (140 % in the run). | docs/product-documentation.md:1618-1619 "Save plan writes the whole (view, classification) plan at once"; :1646-1648 (an empty position field … | S | none on its own; one sentence in R-057 (O4-03)'s ADR-0030 amendment | not refuted (1) | unchanged |
| R-015 (O4-02) | S2 | After a tree edit the plan editor keeps its old tree: the sum stays "100 % ✓" while the stored plan is 60 %, or a save stores 110 %. | docs/product-documentation.md:1620-1621 (a live Σ, updating on input); the page's own reload rule at classifications_live.ex:2160-2163 | S | none | not refuted (1) | unchanged |
| R-016 (G4-03) | S2 | A cash merge that removes a duplicated trade lists no flow across a view's boundary: the view's flow of the day halves while the preview's list of flow changes is empty. | ADR-0050 §16 invariant 9 (:685-687) "the preview lists every flow a collapse removes or moves"; merge_figures.ex:272-279 | S to M | ADR-0050 (dated note under §16 invariant 9) | not refuted (1) | still stands |
| R-017 (A4-02) | S2 | The security-merge preview says the realized-gains read converts its figures at each close date; for a sale that closes a lot booked in another currency that read takes the cash moved, so the base-currency result is not the preview's figure converted. | AGENTS.md:113-116 (computation basis, review-blocking); merge_json.ex:161-163; ADR-0015 note of 2026-10-31 (0015:423-429) | S | ADR-0015 (a note naming the preview as a reader); ADR-0050 §9 only if … | not refuted (1) | still stands |
| R-018 (G3-02) | S2 | A cap on a word that is no asset class is accepted by the risk read and answers "no class over cap", the same as no cap at all; the caps applied are not echoed. | policy_finding_controller.ex:94-95 ("an unknown one is a 422, never a silently empty list"); sale_hindsight_controller.ex:15-20 (a misspelled value … | S; fixed in #1489 (`f07b0d42`, `baf9c5f9`) | none | not refuted (1) | still stands |
| R-019 (A3-02) | S2 | A malformed security, depot or tax-year filter is dropped on three API reads, which answer the unfiltered list with 200 where their siblings answer 422. | docs/integration/api-and-mcp.md:138-141 (a malformed id gets a field error); #1301 precedent, graded S2 … | S; fixed in #1489 (`426de12a`) | none | not refuted (1) | unchanged |
| R-020 (O6-03) | S2 | The contract read without `since` answers the whole manifest, 241,722 bytes, and the first-setup prompt calls it that way as a connection check. | api_v1_contract_test.exs:16-18 ("one cheap read"); contract_controller.ex:8-10; ADR-0044 §8; docs/llms.txt:177-179 | M | ADR-0044 §8 for a summary default; the prompt fix alone (size S) … | not refuted (1) | still stands |
| R-021 (O1-01) | S2 | A security whose newest close is over a year old reads "1Y 0.0%" on the Overview and in the list, where the Chart tab says "not computable". | price_metrics.ex:269-271 ("no figure", not "0 % over zero days"); ADR-0047:312-315 is silent on the coverage rule | S | ADR-0047 | not refuted (2); the verifier graded it S1 | still stands |
| R-022 (G2-01) | S2 | For a benchmark whose history starts inside the shown period, the chart tooltip and the table print an anchored level under the benchmark's name (+15.5 % in the run) beside the card's and the API's plain return (+10.0 %). | portfolio_live.ex:4225-4226 (tooltip comment: 'bought-once return on the hovered day'); ADR-0046 §2 (0046:71-72); the table column is a built story … | S | ADR-0046 | not refuted (2); the verifier graded it S1 | still stands |
| R-023 (G2-02) | S2 | The performance table prints each row's own return beside the benchmark's cumulative return since the period's start, under a line that says "return and flows per period". | portfolio_live.ex:4131 (the table's stated purpose) and :4121-4124; the basis is in a code comment only (:4151-4152); no ADR, board or idea row names … | S | none | not refuted (1) | still stands |
| R-024 (O1-02) | S2 | When one of two depots holding a security has no derivable cost, the Overview reads "Unrealised —" and the Holdings total prints the other depot's result beside the value of both, with no note. | DESIGN.md:1675-1676 (UX-DR25: named beside the figure, not in a tooltip); securities_live.ex:2051-2052 | M | none | not refuted (1) | still stands |
| R-025 (O1-04) | S2 | The chart's moving averages are computed from the visible range only: the default-on 200-day average draws nothing on 1M, 3M and 6M while its button stays pressed and the grid states its value. | DESIGN.md:290 (SMA-50 and SMA-200 draw by default, legend names every active overlay); ADR-0047:328-329 | M | ADR-0047 only if the API serves the series; none for a page read | not refuted (1) | still stands |
| R-026 (O2-04) | S2 | After the active view is deleted elsewhere, the Wealth page says "showing Everything", lists Everything's positions and keeps the deleted view's total until a reload. | portfolio_live.ex:1253-1256 and :1272 (the page's own degrade promise); capped_async.ex:3 covers starting only; nothing else written | M | none | not refuted (1) | still stands |
| R-027 (G1-03) | S2 | "Delete plan" leaves the cash target that the same form saved: the view stays in target mode on the cash target alone, where the confirm text, the documentation and the tool description promised "actual-only", and no screen has a control for it. In the run the Overview then reads cash at 8 % against a stored 5 % as "92.0 pp below target". | lib/portfolixir_web/live/classifications_live.ex:1572 (confirm text); docs/product-documentation.md:1629-1630, :1703-1704 … | S | none beyond R-136 (G1-02)'s ADR-0027 amendment; the cash-only drift … | not refuted (1) | still stands |
| R-028 (G1-04) | S2 | Wealth's "Create a plan" link on a built-in tree, the default on a fresh instance, opens a page with no plan control and no reason given. | lib/portfolixir_web/live/portfolio_live.ex:5975-5977 (the link's purpose); design-language/DESIGN.md:2512-2514 (dot and editor never contradict) | S | ADR-0008 only if plans on built-in trees are refused; otherwise none … | not refuted (1) | still stands |
| R-029 (G1-05) | S2 | "Delete plan" acts on the status the editor loaded: after another writer activated a successor, the click deletes the newly active plan the page never showed and answers "Plan deleted". | docs/product-documentation.md:1702-1704 (Delete plan on an archived version removes just that version) | S | none | not refuted (1) | unchanged |

## 6. S3 findings by theme

Each row was confirmed by something a verifier executed: a scratch test, a count or a search. The full write-up of each, with locations, reproduction and observed output, is in the private evidence under its key. Where a cell cites a numbered row, item or hop, the number is that of the private entry. "Fix" is the size: S under a day, M one to three days, L more.

### Two paths for one figure (14)

| ID | Finding | Stands against | Evidence | Fix | ADR amendment |
|---|---|---|---|---|---|
| R-030 (A4-03) | A booking's write-time rule chain is written three times (the Ledger's create, the import apply, the import dry run), and the Ledger's own importer entry (create_transaction/3 with import_hash:) has no caller in lib/ | nothing broken; ADR-0017 slice 4 decides who journals, ADR-0050 §3 (0050:202-206) names two writers of import_hash, one unused outside tests | Scout and grep counts: validate_cash_account_currency/3 has three call sites (Ledger, apply, dry run); no call under lib or priv passes import_hash: (27 test calls in 16 files do); git log shows the dry run's copy patched after it had been missed. | M | ADR-0050 §3 |
| R-031 (A6-05) | Classifications hands out rows but no tree operation: 15 parent-chain walkers in 9 files (one a copy), the map and the category list fetched as a pair at 9 sites, and the map reads the whole securities table even for a custom tree that never uses it | The module's own contract at lib/portfolixir/classifications.ex:219-225 (one shared cap for every walk); no ADR fixes the module's shape | Scratch test: security_category_map of a custom tree issued 4 statements, one reading all 40 securities, none used; one whole-catalogue read per allocation (of 22) and category-result read (of 17). Greps: 15 walkers, 11 call sites, 9 pairs. | M | none |
| R-032 (A6-07) | "The securities a view holds" is one pipeline written out four times, the newest copy in News; the copies agree on one fixture, and the scoped question has no home while the unscoped one has | Nothing written for the scoped set; the lesson of lib/portfolixir/ledger/held_securities.ex:21-25 for the unscoped one | One fixture, three entry points: digest, valuation and reconcile named the same three securities. The digest read every transaction once per portfolio. Outputs differ only for a security negative in one depot and positive in another, by definition. | M | none |
| R-033 (D1-03) | The walk scales a split on the security's total across a portfolio's depots, the ledger scales each depot's position; they differ by one unit of the sixth decimal, and in the walk a position sold as each depot states it never closes | ADR-0028 §3 :289-293 (quantized at the fold so a broker-stated sell zeroes the position) and :325-327 (identical results across positions, holdings, FIFO and the walk) | Two depots, 1:3 split, both sold 0.333333: ledger empty, walk end value 0.0003 above the valuation, contribution route says held_at_end true. A 3:2 split on 0.333333 each leaves a negative remainder (-0.00006). One-depot and exact-ratio controls agree. Bounded at one unit of the sixth decimal times the price per further depot and split, far below a printed cent at ordinary prices; it needs one security in two depots of one portfolio and a split whose result does not end within six decimals. | M | None if the walk rounds per depot; ADR-0028 §3 if the per-security rounding is kept |
| R-034 (D1-04) | Five reducers sum position quantities per security; three drop a zero total, Ledger.positions_by_security/0 keeps it although its doc says it is omitted, so the holdings-by-security read lists a security with quantity 0 that the held set excludes | ledger.ex:2082-2083 ("securities that net to zero are omitted"), valuation.ex:72-73, api-and-mcp.md:2703-2705 (one row per currently held security), held_securities.ex:3-6 | Five in depot A, minus five in depot B (also: bought in A, sold from B): GET /api/v1/holdings/by_security answers a row with quantity "0", valued true; HeldSecurities and the catalog's held filter exclude it. Sold in its own depot: no row. | S | none |
| R-035 (D1-06) | Two rules are written twice inside the Ledger and agree today: the cash a trade books (projection and settlement guard) and FIFO consumption (matcher and sale preview); no test compares the members of either pair | Nothing written is broken; settlement_guard.ex:132-134 and ledger.ex:1429-1431 each claim to be the other copy; ADR-0011 :29-31 (each kind's effect defined once) | Eight buy and sell rows: booked_cash equals the projection's cash amount on each. Preview and booked sale closed the same lots after a split, with fees (gain differs by the fees, 12, as documented) and on an over-sell. No existing test compares either pair. | S | none |
| R-036 (D2-04) | The dated EUR-hub conversion is written out in four modules beside Portfolixir.Fx, with four treatments of a missing rate; on rated days the copies agree | ADR-0007 :35-37 ("a dedicated bounded context Portfolixir.Fx that owns exchange rates and conversion"); nothing forbids the copies, a move would amend ADR-0007 | Counts reproduced: GBX constant in 5 modules, 10/10/9 FX clauses, 8 Fx.series/hub_rate_before sites in 4 files. Scratch test: walk, frozen walk and Fx.convert all 800 and 1,000 on rated days; without a rate: no_rate, 0, and an excluded gap. | M to L | ADR-0007 |
| R-037 (D3-03) | A benchmark security's return between the same two dates is computed by two rules (ADR-0046's in the comparison, ADR-0055's in sale hindsight and predictions) that answer differently when the standing close is older than the newest rate or older than 7 days | nothing broken; ADR-0046:83-85 and ADR-0055:126-135 each define the figure without naming the other's rule | One CAD benchmark, same two dates: comparison benchmark_return -0.2, WindowReturn.price_return 0; with the close on the rate's day both read -0.2; after 8 days without a close the comparison still reads -0.2 and the window return answers :no_end_close. | S | ADR-0055 §3 (or ADR-0046 §2 if one rule is to own both; then size M, risk tier) |
| R-038 (D3-04) | Reads of one walk name a window by the same two dates and mean different days: performance counts the start date's return, the risk read and the snapshot comparison measure from its close; no basis says which, and one code comment names the wrong start | AGENTS.md:113-116 (the basis states its window); lib/portfolixir/portfolios/snapshot_comparison.ex:377-379 (comment off by a day) | A +10 % move dated on the start day: under identical start_date/end_date the performance read answers ttwror 0.1 over 31 points, the risk read volatility 0 over 30 observations, the snapshot comparison real_ttwror 0. The snapshot basis shape is ADR-0027's, decided. | S | ADR-0047 §6 (only if the meaning of window.start_date is written into the record) |
| R-039 (D3-05) | One position's unrealised gain is two figures by two decided cost methods; the trades payload names its method twice, the holdings payload not at all, and a holding's valuation arithmetic is written twice in one file | FR-13, _bmad-output/planning-artifacts/epics.md:56 (responses self-describing: method); lib/portfolixir_web/controllers/api/v1/json.ex:553-554 | Buy 10 at 100, 10 at 200, sell 10, quote 250: holdings unrealised 1000 (cost basis 1500), open lots 500. Holdings payload names neither 'moving' nor 'fifo'; trades says fifo twice. The two valuation functions differ by one comment. | S | none |
| R-040 (D4-03) | A dividend's fee is a cost in the Costs report and no part of Income's gross, so gross is before taxes but after fees and gross minus the booking's costs is not its net | nothing written decides a fee on an income booking; sits between ADR-0053 :43-52 (PP's gross value) and income.ex:21-28, :159-160 | Dividend net 83, tax 15, fee 2: Income gross 98 and year total 98, Costs fees 2 and taxes 15, statement gross 100. The repository's PP fixture row parses to gross_of 9.50 against Betrag 10.00. Cash, tax and net are right. The verifier graded it S2. Audit lead: S3 after the second reading: what gross means is decided (Sprint 22 D-5 and D-6: gross is net plus tax), and the payload states it. | S | ADR-0053 (or a signed plan decision, as Sprint 22's D-5) |
| R-041 (D4-05) | The allowance ceiling of one taxpayer and year is resolved twice, at two dates, by two copies of one function, and ADR-0031 §5 defines the roll-up's remaining allowance from the ceiling while the code sums granted minus used | ADR-0031 §5 and C8 (docs/decisions/0031-recorded-tax-statement-snapshots.md:329-332, :289) | Profile single then joint mid-year: C8 fires on the March statement (2000 against 1000), not on October's, and the roll-up shows ceiling 2000. Granted 800, used 500: allowance_remaining 300, ceiling minus used 500. Advisory figures only. | S | ADR-0031 |
| R-042 (O6-08) | The decimal wire rule has five implementations in the controllers and no owner; JSON.decimal/1 prints a signed zero as "-0" and accepts a float or an atom | ADR-0016 §3 (docs/decisions/0016-rounding-policy.md:54-56); api-and-mcp.md:1298-1299; irr.ex:398-399 ("a zero is a zero") | GET securities metrics for closes 60000.00 then 59999.98: momentum 3m and max_drawdown 90d, 365d are "-0"; JSON.decimal(1.5) gives "1.5"; a probe of 72 reads over an ordinary ledger found no signed zero. | S | ADR-0016 §3 (one sentence) |
| R-043 (O8-02) | The hub-rate settlement legs of an imported cross-currency trade are derived by two copies of one rule (the Applier's public function and the Ledger backfill's own steps); they agree on every shape run, and one existing test pins them at one exact rate only | Nothing broken; the promise is ADR-0015:372-377 (amendment 2026-10-09, point 6), kept today. ADR-0001:39 (one-way direction) is why the Ledger carries its own copy. | Scratch test, 8 cases: import-with-rate and import-then-backfill stored identical legs for six shapes (non-terminating rate, sale with taxes, CHF/USD, GBX, zero). Reader wrong on 'no test': history_backfill_test.exs:765-767 compares both paths. Applier's quantity x price branch is unreachable by import. | S | ADR-0015 (dated note: the function's new name at :231 and :377, the unreachable branch) |

### Rules and figures the web layer holds (17)

| ID | Finding | Stands against | Evidence | Fix | ADR amendment |
|---|---|---|---|---|---|
| R-044 (A1-04) | The rule "which security may be a benchmark" is held at three doors and not by the context that computes: Benchmark.for_portfolio/3 compares against an unflagged security the API refuses with 422, and one rate selector is read by three rules | benchmark.ex:12 "a catalog security flagged is_benchmark" against its validation at :223; nothing written on where such a rule lives, a change would amend ADR-0001 | One unflagged security: Benchmark.for_portfolio/3 and for_view/3 answered :ok with a full comparison, both API routes 422 "is not a benchmark security", the prediction write refused. A rate selector with sixteen decimals passed the API reader and was refused by page plug and prediction. | M | ADR-0001 |
| R-045 (A3-01) | #950 keeps the research log's provenance guard at the web callers until "a new caller of the note writer"; Sprint 28 added one that stores the author its attributes claim, and the API derives the note author by a private twin of Actor.author/1 | Sprint 20 plan D-4 row #950 (sprint-plan-2026-10-07-sprint20.md:464, "Reopened by: a new caller of the note or event writers"); ADR-0054:84-85; ADR-0044:294-295 | Under a token actor Knowledge.append_note and Sprint 28's News.append_note_from_story stored author=operator, machine_generated=true; Events.update_event moved an event; the API answered author=agent and left the event. Mechanism itself is decided (#950); its reopening condition is met. | S | ADR-0044 §4 (and ADR-0048 §6 for events); answers #950, the owner's decision |
| R-046 (A3-03) | About 60 rule, basis and note sentences served in payloads are written in the web layer; two are behind their rule, one missed by the commit that changed the rule and four other copies of its sentence | AGENTS.md:113-118 (computation basis in the payload, a doc page does not satisfy it); nothing written on where a basis sentence lives; a change would amend ADR-0047 §6 | Unreviewed read listed a row with last_entry_as_of 2026-11-07 while its only entry's as_of is 2099-01-01 and the basis says "newest entry as_of". Retiring a stale-quoted holding took stale_priced_count from 1 to 0; the note's sentence names no such exclusion. | M | ADR-0047 §6 (for the move; the two corrections alone need none) |
| R-047 (D5-02) | The Snapshots comparison table prints its two return columns through a float and string interpolation, not through Format: a decimal point on a German page, no plus sign, "-0.0%" for a small loss, and at an exact tie another last digit than the card | lib/portfolixir_web/live/snapshots_live.ex:264-266 ("the numbers on the cards and in the table stay Decimal-exact"); DESIGN.md:531 (zero carries no sign, names the snapshot comparison) | Three page renders: German page card "+9,1%" against table "600,00 9.1% 0.5%"; factor 1.0025 card "+0.3%" against table "0.2%" (float 0.24999999999999467); small loss card "0.0%" against table "-0.0% -0.0%". API serves exact strings. | S | none |
| R-048 (D5-04) | No rule and no test holds the figures a page derives against the API's answer as a set: 89 lines of Decimal arithmetic in 24 web files, 35 figure sites, two pinned to their twin (not one), six that differ today, 12 the API cannot answer | nothing written; nearest: lib/portfolixir_web/live/portfolio_live.ex:6-7 and AGENTS.md "Coverage runs both ways"; a rule would be a sentence there or in ADR-0001 | Counts hold (89 lines, 24 files; the merged candidate's 97 calls in 21 files). Row 7 control: page "+100.00 EUR", API-derived 100, contribution totals.result "100"; performance payload has no result field. Existing tests pin rows 7 and 2; both files pass. Also reported as A2-07. | M | none |
| R-049 (G2-03) | Under the token '1Y' a security's pane measures the price change by two anchors: the Overview tile and 12-month momentum from the last close on or before the window's start, the chart's percent view from the first close inside it | nothing written requires agreement; securities_live.ex:1842-1843 ('one range vocabulary'); the chart's base is itself written (security_chart.ex:14-15, DESIGN.md:6656-6657) | Three cases: gap at the window's start gives tile '+21.0%', momentum 0.21, chart's last point '+10.0%'; a history inside the year gives tile '—', momentum refused, chart '+50.0%'; a close on the first day, all three agree. | S | ADR-0047, together with R-021 (O1-01) |
| R-050 (G2-04) | The Predictions tab names the day a waiting call is scored 'at the latest' as resolves_on + 7; on that day the engine still holds the call open, and it becomes final on resolves_on + 8 | ADR-0055 amendment §2 (0055-predictions-scored-for-calibration.md:295-302: 'until 7 days after resolves_on have passed'); prediction_label.ex:8-10 ('nothing derives ... a date again') | Engine: open on resolves_on+6 and +7, resolved on +8. On +7 the API reads 'open' and the tab reads 'open · waiting for the close' beside 'at the latest on `<today>`'. The board's sentence carries the same {Datum + 7}. | S | none |
| R-051 (G4-04) | The news reads' defaults are controller attributes hand-copied into two LiveViews; the News page reads 12 digest rows where the API's default reads 10, under a comment saying "the API's defaults" | news_live.ex:7-10 and :53-55 "with the API's defaults ... its 12 rows"; ADR-0056 :794-795 "the digest defaults to max_rows=10" | Scratch test with 11 securities: API default digest rows=10, truncated, more=1; the page shows 11 rows and "at most 12 rows". With 13: API 10/more 3, page 12. Greps confirm the dropped as_of option. | S | none |
| R-052 (O1-07) | Twelve domain rules live in the page; four have a second holder, and the page's 3Y and 5Y ranges start one day after Wealth's; MAX reads the whole quote history three times | nothing broken; ADR-0001:30-31 and security_dossier.ex:7-9 are the nearest sentences | On 2026-11-11 the page's 3Y starts 2023-11-12 and Wealth's 2023-11-11; 5Y 2021-11-12 against 2021-11-11; 1Y agrees. One switch to MAX reads 2,301 quote rows three times. Items 3 to 9 checked by reading both holders. | M | ADR-0047 |
| R-053 (O2-02) | The Wealth page counts its data-quality rows itself, by another rule for retired holdings and another unit (distinct names) than the valuation payload's trade_priced_count, unvalued_count and stale_priced_count; no LiveView reads those counts | docs/product-documentation.md:1832-1835; valuation.ex:16-18 ("so the UI can flag"); data_quality.ex:114-117 | API against page on one fixture: retired trade-priced holding, API 1, page no row; one unquoted security in two depots, API 2, page "One held position"; same unit gap for stale quotes (2 vs one). Staleness copies agree at the 7-day boundary. The verifier graded it S2. Audit lead: S3 after the second reading: the page's unit (distinct securities) and the payload's (positions) are a recorded decision (commit 4700077c, issue 703). Audit lead: The page's rule for retired holdings is recorded too (PR #1102, `lib/portfolixir_web/valuation_notes.ex:12-16`). New are the payload's `trade_priced_count` keeping a retired holding, two documentation sentences, the module doc's "so the UI can flag" and three copies of one staleness comparison. | M | none |
| R-054 (O2-05) | ADR-0034 §2's short-window rule (MWR instead of IRR) has its day count in two private web-layer functions and none in the context; the agent is told the rule in prose, without the day count or a field | ADR-0034 §2 (0034:72-73); performance.ex:849-850 holds the rule as a comment only | Greps only: the expression "+ 1 < 365" at portfolio_live.ex:6053 and dashboard_live.ex:1024 and :1034, none in Performance or IRR. Narrower than written: two MCP tool descriptions do say to read mwr under a year. | S | ADR-0034 |
| R-055 (O3-01) | Portfolixir.Imports.Mapping's moduledoc names two responsibilities it does not hold; the prefill and both translations are private functions of the page, and five test files apply the import under a hand copy of the prefill that books what the page refuses | lib/portfolixir/imports/mapping.ex:3-8 ("derive an initial UI mapping ... translate the LiveView form params ... Two responsibilities only") | Greps: 5 public functions, none builds a mapping; 5 copies, 21 call sites; 1 lib caller of apply/2 against 259 in tests. Scratch test: the copies' prefill gives {:create, name} for an unseen name and apply/2 books 3 rows; the page withholds it. | M | ADR-0050 (note on the 2026-10-09 building order); none for the small alternative of correcting the moduledoc |
| R-056 (O3-04) | Two figures of the Imports page are computed twice, in Portfolixir.Imports and in the page: what a correction moves per cash account, and the held-back rows per portfolio; both pairs agree on the fixtures run | nothing written; nearest docs/decisions/0053-a-pp-csv-books-its-gesamtpreis.md:901 | One fixture: the page's total line reads -50.00 EUR and Correction.absorbing_balances/1 answers amount -50.000000. The held-back test passes with "1 entry" on preview and done page. No test calls absorbing_balances/1 (grep: 0). | S | none |
| R-057 (O4-03) | The plan save's write rules (category follows its positions, clears, stale rows) live in the LiveView; Targets.edit_plan/5 has one caller, the API writes the same plan without them, and ADR-0030 still lists the editor as deferred and says no row is overwritten | ADR-0030 §2 (docs/decisions/0030-position-level-soll-targets.md:76-78) and :175-176; AGENTS.md:72 | After two API writes: explicit 0.5, position_sum 0.3, conflict true. After the operator's Save with no field changed: explicit 0.3, conflict false, two more journal entries. Scout data: edit_plan/5 has one caller, the LiveView. Also reported as A2-04. | M | ADR-0030 (§2, §3, §4) |
| R-058 (O4-07) | Which way a booking kind moves cash is kept in two hand-written lists and one catch-all in the Transactions LiveView, beside the one reducer ADR-0011 decided; the lists agree with the reducer today | ADR-0011 (docs/decisions/0011-unified-ledger-projection.md:29-31); projection.ex:13-15 | Probe row through Projection.cash_amount/1 for all 15 kinds: outflow set buy, cash_transfer, fee, removal, tax and credit set deposit, dividend, interest, tax_refund equal the LiveView's two lists. Grep: 11 list lines in one file, no test guards them. | S | none |
| R-059 (O4-08) | Three figures of the Transactions screen are derived in the web layer and have no twin on the API or MCP: the cash a booking moved, the per-kind sums, and what a delete changes | AGENTS.md:39-43 and :230-231 (coverage runs both ways) | A buy booked over the API: row has gross_amount null and no cash field; the screen shows -965.00 EUR, the summary 965.00 EUR, the dialog the delete's consequence. | M | none |
| R-060 (O6-09) | The serializer holds rules, not only shapes: a rounding the domain's basis text promises, an ordering rule, the read date, the tax snapshot's derived block and about 86 lines of basis prose; all figures agree today | ADR-0016 §3 (docs/decisions/0016-rounding-policy.md:54); json.ex:2790 ("serializers never query"); security_dossier.ex:7 | Scratch test: domain ratio 3.333... (34 digits), API 3.333333, screens 3.33, while the domain's basis says "rounded half up at scale 6"; Valuation and Risk results carry no as_of; no Tax function returns the derived block. Also reported as A3-06. | M | none for the moves; ADR-0016 §3 only if the rounding stays API-side |

### The derived-value layer and repeated reads (12)

| ID | Finding | Stands against | Evidence | Fix | ADR amendment |
|---|---|---|---|---|---|
| R-061 (A1-03) | The hand-kept lists of journaled kinds miss the News context: a news_feed or news_source write supersedes every portfolio's and security's derived values, and the Audit journal page neither offers nor names the four news kinds | journal/row.ex:22-23 "Every resource_type code a journaled writer files under"; EXPERIENCE.md:1153-1156; blast_radius.ex:102-103; a classification rule would amend ADR-0039 | Source rating and feed create, update, delete each moved 8 of 8 bases and forced a recomputation of a memoised figure; a label write moved only the global basis. Row.kinds has 30 of 34 kinds; the four news kinds print as raw codes. | S | ADR-0039 |
| R-062 (O1-03) | With a security open, every tab click, keystroke and filter chip runs 70 queries (65 the detail's): three booking lists, three whole-ledger price scans, thirteen split reads | ADR-0035:84-85 and :152-153 (one pricing pass per read; the security detail is not named) | Telemetry count per click: 70 queries on every tab (72 on Trades), 5 without a security open; 22 on transactions, not the reader's 6. Wall time 9 ms small, 56 to 84 ms at 6,000 bookings: no visible wait, so S3. | M | ADR-0035 |
| R-063 (O2-03) | The positions projection runs synchronously in mount/3, twice per page load and on the tab that draws none of it; each tab also computes the other tab's data | DESIGN.md:1624-1625 ("the first frame must never block on a read"); portfolio_live.ex:9-10, :868-869; ADR-0035:73-74 | Call trace, two portfolios: 2 projections and 2 pricing-context builds in the dead render, 2 more in the connected mount, same on Allocation (0 rows drawn). Timed on a seeded ledger: about 30 ms per mount at 1,000 bookings, 95 ms at 4,000. | M | none |
| R-064 (O4-05) | The tree page has no read of one tree: every search keystroke, toggle and holdings arrival reloads every tree and reads the whole securities table twice (4 + K queries, K = custom trees) | nothing written; a Classifications.get_tree/1 needs no ADR | Queries per search keystroke: 5, 6, 8 for 1, 2, 4 custom trees, securities read twice each time. Opening the page: 55 to 64 queries, securities read 11 times. Assigning one security: 27 to 30 queries. | M | none |
| R-065 (O5-02) | Both merge previews read the database while rendering (13 call sites, 3 to 5 queries per radio press) against their moduledocs' "and nothing else"; the claimed gap in the plan digest does not exist | securities/merge_preview.ex:4-6 and portfolio_accounts/merge_preview.ex:5-7 ("rendered from … and nothing else"); ADR-0050 §10 itself holds | Scout count 13 rows. Telemetry: 3 queries per radio press (security), 5 with three pairs (depot). Hop 4 refuted: a booking in another depot after the preview answered plan_changed, nothing merged; the digest hashes every booking of both securities. | M | none |
| R-066 (V1-03) | On Wealth's stacked chart every level, sort, scale and filter change at one period runs a full windowed walk although the walk reads none of them, and each new period runs the same walk twice (table, bands); I34 records the missing memo, and its step 1 as written would memoise each request shape instead of removing the repeats | ADR-0039 §3 (0039:128-132, de-duplicate before materialising); idea row I34 step 1 (ideas.md:51) proposes the per-request key | Call tracing, layer on: open 2 walks; re-sort, level, scale, back 1 each; new period 2; period seen before 1. Bands walk equals table walk plus three kept keys. Per click 335-413 ms at 3y, 1.2 s at max on the 50-security seed. The verifier graded it S2. Audit lead: S3 after the second reading: the wait is recorded as I34. New is that one walk per period can serve every request. Also reported as V2-01. | M | ADR-0051 (§12, dated note) |
| R-067 (V1-06) | The activation measurement ADR-0039 calls a task with an owner stops at 2026-08-18: the measure task times none of the six analytics registered since, its recorded risk-read row no longer holds, and ADR-0047 §8 still says the per-security basis does not exist yet | ADR-0039 amendment point 4 (0039:366-371) and §6 (0039:198-201); ADR-0047 §8 (0047:214-215, :295) | Greps: 12 candidates, 0 of the newer analytics; ADR-0047 never mentions #825. Ran the task's seed: Risk.for_portfolio 667/633 ms beside a 636 ms walk (recorded 53 beside 2,527); bands 397 ms at 3y, findings 13 ms, security metrics 4 ms. | M | ADR-0039 (measurement table amendment) and ADR-0047 (§8) |
| R-068 (V2-02) | The Risk page computes its lens, its metrics walk and its findings inside mount/3, in the dead render and again on the connected mount, with no pending state; for a remembered view that is neither the default view nor Everything the first open after every write pays a whole walk before the first byte | ADR-0032 §6 (docs/decisions/0032-derived-series-memoization.md:225-227, the maintainer does not have to watch the wait); lib/portfolixir/derived/refresher.ex:9-11; EXPERIENCE.md:261 (pending state) | Traced calls: dead render and connected mount each run lens, findings, valuation and walk. Warmed instance: default view 0 walks; remembered third view 1 walk in the request process, again after each booking. Bench: 681-725 ms before first byte against 71 ms. The verifier graded it S2. Audit lead: S3 after the second reading: a non-operative view's walk is left to its first reader by decision (ADR-0032 §5). | M | none |
| R-069 (V2-03) | A return to Wealth on an address without a period starts the 1-year contribution walk, then the browser's remembered period asks again: two window walks per open (four at a stacked level), the first for a period the page never shows | lib/portfolixir_web/live/portfolio_live.ex:868-869 ("computed exactly once"); ADR-0039 §3 (docs/decisions/0039-durable-derived-values.md:128-132) | Trace: /portfolio plus restore_period 3y calls Contribution.for_view for 1y then 3y (two window walks; four at a stacked level) against one for /portfolio?period=3y. Bench: the table lands after 300 ms instead of 213 ms. | S | none |
| R-070 (V2-04) | A current walk in the memo is not served at page open: both callers of the non-computing read keep its stale answer and drop its fresh one, so a superseded walk shows a number on the Overview at once and a current one a skeleton with the computing cue (narrower than written: the contribution table's part is idea row I34 step 2) | EXPERIENCE.md:280 (the cue appears only while a value is genuinely being recomputed); nothing written decides the fresh peek (lib/portfolixir/derived.ex:124-130 covers the stale case) | With a current walk in the memo, Overview and Wealth render skeletons with the computing cue (1 and 5 cues) while zero walks run; with a superseded walk the Overview shows its number in the first paint. The memo read takes 1 ms. | S to M | ADR-0039 (optional: state the fresh case in the amendment I34 step 2 needs) |
| R-071 (V2-05) | The warm set and the write-triggered refresh hold only the two full walks on the premise "periods cost nothing"; since FR-41 Wealth's default open also waits on a window walk every write empties, the API's EUR walk is unwarmed on a non-EUR instance, and the committed measurement has timed nothing added since 2026-08-18 while the Risk read it records at 53 ms now costs a walk | ADR-0039 amendment §4, finding 3 (docs/decisions/0039-durable-derived-values.md:366-371, :243-245, :219); ADR-0032 §5 (0032-derived-series-memoization.md:217-219, "Periods are free"); warmup.ex:19-21 | Warm-up fills the walk, not the 1y table: after each write Wealth's next open walks the window. USD instance: the API's EUR walk is never warmed. The measure task prints the same 12 rows as 2026-08-18; Risk now 678 ms, bands up to 1.3 s. | M | ADR-0039 (ADR-0032 §5 by reference) |
| R-072 (V2-06) | On every boot, midnight and write the warm-up walks each portfolio's ledger once as performance_analysis and once more inside performance_view_analysis; in one base currency the two calls have the same arguments, and with one portfolio two durable rows hold one identical series | nothing written is broken; the order skipped is ADR-0039 §3 (docs/decisions/0039-durable-derived-values.md:128-132); a change would amend ADR-0039 | Warm-up traced: 2 walk_portfolio calls with identical arguments for one portfolio (4 with a default view, 4 per booking); the stored series are identical term for term. Bench: 2.47 s of walking where 1.23 s would do, two 1.36 MB rows per series. | M | ADR-0039 (ADR-0032 §5 by reference) |

### Context seams and direction (14)

| ID | Finding | Stands against | Evidence | Fix | ADR amendment |
|---|---|---|---|---|---|
| R-073 (A1-01) | Seven domain modules translate through the web layer's Gettext backend (190 call sites, 4 locale reads), so Catalog and Imports depend on PortfolixirWeb although ADR-0001 says contexts never do | ADR-0001:30-31 "contexts do not depend on the web layer"; AGENTS.md:220-221; docs/architecture.md:123-124 | AST walk printed 11 PortfolixirWeb references in 7 context files; xref lists them as runtime callers. A seed under locale de stored "Aktie" and "Hebelprodukte" as built-in category names; Currencies.name("USD") answered "US-Dollar". Boot seeds in English, so nothing is wrong today. Audit lead: On the later `main` the rule review of 2026-11-12 registered the Gettext backend as the one exception a context may name (`test/invariants/context_web_boundary_test.exs`), so this is a decided matter there. Also reported as A5-06. | S | ADR-0001 |
| R-074 (A1-02) | No gate fails when a context names the web layer: a context module calling PortfolixirWeb.Format compiles, lints and passes every source-reading test, and ADR-0001 leaves that direction to review | ADR-0001:37-38 "enforced by review" against AGENTS.md:58-59 and ADR-0026:73-76 (gates stand in for the read) | In a scratch copy with a Ledger module calling PortfolixirWeb.Format and Endpoint: compile --force --warnings-as-errors exit 0, credo --strict no issues, invariants 311 tests and 66 lib-reading files 649 tests with the baseline's failures only; no output names the file. Audit lead: Answered on the later `main`: `test/invariants/context_web_boundary_test.exs` (rule review of 2026-11-12) fails when a context names a web module outside its registered exceptions. | S | ADR-0001 |
| R-075 (A1-05) | ADR-0001 names four contexts and the published overview six contexts and 7 supervised processes; the tree has 13 context directories, 19 supervised children and about 6,500 lines of shared modules with no written direction, three of which call into contexts | ADR-0001:21-28 (list of four); docs/architecture.md:95-121; decisions/index.md:11-14 "not change silently"; nothing written for the shared layer | Ten unnamed namespaces have 0 mentions in both documents; Application.children/0 returned 19 against 7 listed; xref puts journal.ex, settings.ex and 8 derived files in the 96-file cycle and shows cascades.ex compile-depending on three context files. Also reported as A5-07, A6-09. | S | ADR-0001 |
| R-076 (A2-05) | The account dialog authors its database transaction in the web layer through Portfolios.all_or_nothing/1, a Repo.transaction handed out as a context function; the use case lives in a LiveComponent | ADR-0001 (0001-modular-phoenix-monolith.md:30) | Traced; grep and scout data show one caller (account_form_dialog.ex:300). A scratch test ran an arbitrary closure over two contexts inside the transaction and rolled both back. Atomicity itself is decided (K14). | M | none |
| R-077 (A2-06) | Three places in the web layer build a schema changeset themselves as a dry run of a write, and one edits its error list; two schema modules without a moduledoc are called 14 times from four web files | nothing written; nearest ADR-0001 line 30; a rule would ride on R-078 (A2-08)'s amendment of ADR-0001 | Grep: 3 changeset sites; scout: 13 rows in 4 files (not 5), 34 calls on 9 schema modules. Scratch test: bare changeset valid where the write refuses (taken ISIN, foreign-currency deposit, split). All three sit on refusal paths; no wrong record. | S | none |
| R-078 (A2-08) | Nothing written says which context modules are public; the LiveViews and components call 65 context submodules, and 47 % of their context calls go past the context's top-level module | nothing written; a change would amend ADR-0001 (0001-modular-phoenix-monolith.md:30-31, :37-38 cover only the other direction) | The reader's awk over the scout calls reproduces 341 top-level calls, 306 submodule calls, 65 submodules, 33 files (47.3 %); 63 of 65 have a moduledoc; 8 are schema modules (32 calls), so the allowlist seed is 57, not 56. | S | ADR-0001 |
| R-079 (A4-04) | Identity resolution is split so that Imports and Lifecycle each call the other (29 call rows one way, 16 the other), and Portfolios' and Catalog's own schemas call up into Lifecycle | nothing written; nearest is ADR-0001:39, whose only stated direction is web onto contexts | mix xref callers in the container and scout counts: 29 rows Imports to Lifecycle (AccountNames 21), 16 back (SecurityResolver 10, DedupKey 6), 14 from Portfolios and Catalog up into Lifecycle against 61 down; every edge runtime. Portfolios.Reconcile also calls the importer's ladder. | L | ADR-0001 (direction between contexts), with a note in ADR-0050 §4/§9/§11 |
| R-080 (A4-05) | Lifecycle and Imports read other contexts' tables with 59 Ecto queries of their own (43 and 16); the Ledger offers no read for the bookings that name given accounts or securities, so each caller decides what a complete input of a Ledger fold is | nothing written; ADR-0001:30-31 separates contexts from web code only; a rule would amend ADR-0001 | The scout count and an independent grep agree: 43 Lifecycle and 16 Imports queries on foreign schemas, 25 of them on transactions, in 10 files; 15 call rows hand caller-built row sets to Ledger folds. Its one run consequence is R-005 (A4-01). | M | ADR-0001, only if the rule is to be written down |
| R-081 (A5-02) | The Ledger's holdings and trades reads call up into Portfolios.Valuation and build a pricing context per call: one whole-ledger trade-price scan per portfolio in the category result and per sold security in the realized report (13 queries per sold security; 0.5 s at 4,000 bookings where the batched read takes 0.05 s) | ADR-0035 Decision, docs/decisions/0035-one-pricing-pass-per-read.md:73-75 (one pricing pass per read, no per-row lookups); ADR-0039 :253-258; nothing written for the call's direction | Scratch test: the realized report issues 13 queries and one whole-ledger scan per sold security (2,606 queries, 0.5 s at 4,002 bookings; batched read 6 queries, 0.05 s); category result builds one pricing context per portfolio; one rate query per cross-currency row. | M | ADR-0035 (the holdings and trades reads join the one pricing pass); ADR-0001 for the direction |
| R-082 (A5-03) | Catalog.DataQuality is a read across four contexts placed in Catalog, and the two guards it calls sit under Portfolios without reading a Portfolios row: 9 of Catalog's 12 calls into Fx, Ledger and Portfolios, and a loop with Portfolios.Valuation | nothing written; ADR-0001 states only the web direction (docs/decisions/0001-modular-phoenix-monolith.md:30-31); a home for the module would amend ADR-0001 | Scout counts and mix xref: 9 of Catalog's 12 calls into Fx, Ledger and Portfolios come from DataQuality; QuotePlausibility reads no Portfolios table; Valuation calls back for stale_days/0; all three files sit in the 96-file cycle. | M | ADR-0001 |
| R-083 (A5-05) | Portfolios, Ledger, Catalog and Fx name another context's Ecto schema in 32 queries of their own (Ledger 14, Portfolios 10, Fx 7, Catalog 1, Engines 0); for 12 of them the owning context already has the function (9 identical), for 20 it has none | nothing written; ADR-0001's reason for seams (docs/decisions/0001-modular-phoenix-monolith.md:36); the existing invariant pins the web layer only | An independent AST scan found exactly 32 sites (securities 11, transactions 10, cash_accounts 5; Ledger 14, Portfolios 10, Fx 7, Catalog 1); nine repeat an owner's function. Four association joins and the cross-context preloads are outside the count. | M | ADR-0001 (only for the rule and its invariant test) |
| R-084 (A6-01) | Twelve of the thirteen contexts form one call cycle; a layering needs 13 edges cut (75 call-table rows, 68 source sites), and nothing written or tested says which way one context may call another | Nothing written among contexts; ADR-0001 consequences at docs/decisions/0001-modular-phoenix-monolith.md:36 and :39 no longer hold | Script over the call table printed 13 contexts, 52 edges, one group of twelve (Tax outside), minimum cut 13 edges, 148 minimal sets, three edges in all of them; mix xref printed 7 cycles, the largest 96 files. Also reported as A5-01. | M | ADR-0001 |
| R-085 (A6-02) | News, Buckets, Predictions and Knowledge read and lock other contexts' tables with queries of their own at 34 sites (11 row locks); at 6 of them the owner already exports the same read | Nothing written; idea row I38's first question (ideas.md:47) and ADR-0001:36; a rule would be part of an ADR-0001 amendment | The greps printed 15, 14, 5 and 1 lines (34 sites), none for Classifications and Tax; five hand-written FOR KEY SHARE locks on securities outside Catalog; the call table sees only 15 of the 34. | M | ADR-0001 |
| R-086 (A6-03) | Catalog, the base context, calls up into News at four sites, an edge in every minimal cut: the alias schema of securities.news_aliases lives in News, and Catalog.update_security/3 runs News' re-match | Nothing forbids the call; ADR-0056:99-100 and :415 file the news identity with the catalogue | Greps and the call table printed the four sites; News.Alias (108 lines) aliases only Input.Text; xref shows a runtime dependency, so the reader's recompilation cost does not hold, the cycle membership does. | S | ADR-0056 (one sentence); the direction in ADR-0001 |

### Compile-time coupling (5)

| ID | Finding | Stands against | Evidence | Fix | ADR amendment |
|---|---|---|---|---|---|
| R-087 (A7-01) | Seven LiveViews take a compile-time dependency on PortfolixirWeb.CappedAsync, whose file reaches 411 of the 431 files under lib/, so an edit to almost any file recompiles 19,838 lines of pages (measured: 9 files and 2.6 s where 1 file and 0.4 s would do) | _bmad-output/project-context.md:274-275 ("mix xref cycle gate (add when the first real cycle appears)"); no ADR or AGENTS.md rule on compile-time coupling | Compiler probe on a scratch copy: a comment added to note_controller.ex compiled 9 files in 2.6 s (the seven LiveViews and endpoint.ex); with the three flags moved to a leaf module, 2 files in 0.47 s. Reach is 411 files, not 412. | S | none |
| R-088 (A7-02) | Thirteen compile edges, made by module attributes and one doc string that read another module while compiling, point into the 96-file cycle or at the serializer; an edit to any of 166 files recompiles ten files because of them, the largest page among them, in about 3 s | nothing written on compile edges; nearest is _bmad-output/project-context.md:274-275 (xref gate deferred); no gate counts them | mix xref trace printed all 15 source lines as (compile); a comment added to ledger.ex compiled 18 files in 3.4 s, and these ten alone took 2.9 s. After all fixes 16 compile-connected edges remain, not the reader's 9. | S | none for the lines; ADR-0001 only if the xref gate is to be a rule (else AGENTS.md Required Local Checks) |
| R-089 (A7-03) | Six lines in five helper modules that name PortfolixirWeb.Endpoint hold the web layer's 75-file cycle together, and the endpoint depends at compile time on a session store that calls back into it, so endpoint.ex recompiles on an edit of any of 411 files | _bmad-output/project-context.md:274-275 (xref cycle gate deferred until the first real cycle); no ADR on cycles in the web layer | grep found six lines in five files; xref reports one compile-connected cycle of 75 files. With the store's call replaced on a scratch copy, endpoint.ex left the recompile set (1 file, 0.44 s) and xref printed "No cycles found". | S | none for the store edge; ADR-0045 §2 only if the secret's configuration moves |
| R-090 (A7-04) | One call, Lifecycle.Freeze asking Lifecycle.Delete.referenced_by/1, ties the schema modules of the 96-file cycle to its logic: without it the cycle is a 46-file logic cycle and a 21-file data group, and a schema reaches 43 files instead of 165 (the second call the reader names moves one file) | nothing written; nearest is docs/decisions/0001-modular-phoenix-monolith.md:36 ("Clear seams make it possible to split a context out later"); ADR-0050 §11 stays as decided | Graph what-if over the xref JSON: cutting freeze.ex onto delete.ex alone leaves cycles of 46 and 21 files (reader: 45 and 27, two calls); a schema then reaches 43 files, not 165. Build-time gain is small: mean 11.4 to 10.8. | S | none |
| R-091 (A7-05) | config/dev.exs never sets plug_init_mode, so in the dev build the router and the endpoint depend at compile time on their module plugs: 30 more compile edges than the test build (149 against 119), 13 of them compile-connected, and router.ex joins every recompile set | deps/phoenix/lib/phoenix.ex:66-68 ("We recommend to set it to :runtime in development"); config/test.exs:38 sets it for the test build only | Dev build made on a scratch copy: 149 compile edges against 119, 43 compile-connected against 30; a ledger.ex edit compiled 19 files, router.ex among them. With the config line added, router.ex left the listing and one file compiled. | S | none |

### The agent contract: API, MCP and coverage (14)

| ID | Finding | Stands against | Evidence | Fix | ADR amendment |
|---|---|---|---|---|---|
| R-092 (A3-07) | PUT /api/v1/portfolios/:portfolio_id/cash_target answers the request's value as spelled, not the stored one, although the contract says it echoes the stored value; an empty string clears the target and is answered as "" | docs/integration/api-and-mcp.md:3711-3714 ("It echoes the stored value back") | PUT "0.10" answered "0.10", GET "0.1"; "1e-1", "+0.25", ".5" echoed as sent; "" answered "" with the target cleared (GET null). A call trace over 831 controller tests: cash_target is the only caller of JSON.decimal's to_string fallback. | S | none |
| R-093 (D4-06) | The tax statement's staleness assessment says it counts bookings up to today, and the query has no upper bound, so a future-dated booking counts | AGENTS.md:113-116 (computation basis); the stated window at lib/portfolixir/tax.ex:648-649 | A dividend dated thirty days after the clock's today is stored; the assessment goes from count 0, warning false to count 1, warning true while its basis still says up to today. Four callers, not three. Audit lead: Known since Sprint 6 as a conservative, advisory count. It rides with R-002 (D1-01) under AD-1. | S | none |
| R-094 (G1-06) | A targets write that names no target creates and journals an active plan (a write with an empty list is accepted and answered with an empty list, and the scope enters plan mode); a cash-target write with an empty value creates a cash plan row that holds nothing | docs/integration/api-and-mcp.md:3207-3208 "Only the supplied categories are changed."; ADR-0008:51-52; targets.ex:503-506 and :985-986 (the module's own comments) | API scratch test: the empty targets write was accepted and stored plan "Plan" active plus 1 journal create; has_plan false to true; Wealth left "actual allocation only"; position rebalance_quantity null to "10". The empty cash-target write was accepted and stored an inert plan row. Companion refuses the empty list (read). Audit lead: The companion's minimum of one target is the only thing that keeps the agent from the first shape. Fix R-097 (M1-02)'s row on that minimum from the API's side (an empty batch writes nothing or is refused); dropping the companion's minimum first would make this an S2. | S | none |
| R-095 (G3-01) | One level-(b) read states less of its basis than its siblings: the allocation answers category weights with no read date, no price rule, no word on what its 100 % is and, as a roll-up, no basis key at all | AGENTS.md:113-116 (a metric states its basis in the payload); backlog-triage-2026-09-23.md:279-281 (the allocation is level (b)) | Allocation basis has two keys (drift_value, gaps), no as_of, none as roll-up. | S | none |
| R-096 (G3-03) | portfolixir.securities.list offers sort as a bare string: the only closed-set one of 486 published top-level arguments with no enum, description or word in its tool description; of its 21 keys 8 are no row field, 7 of them named only in contract changelog entries, 1 nowhere | AGENTS.md:39-40 (everything reachable through API and MCP); api-and-mcp.md:4636-4639 (the tool's schema is its definition); its own practice, five other closed sets with enums (tools.ts:3625-3631) | Registry answered 25 fields, 21 sortable, each sent and answered 200; four wrong keys answered 422 sort is invalid; published property is {type: string}, description has 0 "sort"; rows carry none of the six quote figures; contract read names seven of eight non-field keys. | S | none |
| R-097 (M1-02) | ADR-0002 promises MCP the same validation as the API; the companion holds rules of its own and five request shapes get another answer from the tool (the sixth claimed, the 1970 year floor, is the API's rule too) | docs/decisions/0002-thin-mcp-over-json-api.md:27-30 ("the same code paths, validation, and authorisation"; "No second data path"); AGENTS.md:223-226 | API half run: unpriced delivery 201, default view without view_id 422, oversized limits 200 capped, empty targets 200, provider quote source stored manual. Year 1969 answers 422 on all eight reads, so row 5 is refuted. Tool half read, not run. | S | ADR-0002 |
| R-098 (M1-03) | Every tool's input contract is written twice by hand, and the test that holds the two together compares neither bounds, patterns nor closure; one bound and four date patterns are enforced without being published | docs/integration/api-and-mcp.md:4636-4640 ("checks every call against the same properties"); mcp-server/src/server.ts:54-59 | Text scan in the container: targets minItems is unpublished; four date regexes are enforced with no format or pattern published. The companion suite was not run (no Node). | M; the closure half fixed in #1489 (`8d67a199`), with N-08; bounds and patterns open | none |
| R-099 (M1-06) | Three by-id reads that the reference and one tool description send an agent to have no tool; the four logo routes have none either and are already recorded (issue #1413 and a stated reason) | AGENTS.md:230-231 (coverage runs both ways); docs/integration/api-and-mcp.md:4826-4830; mcp-server/src/tools.ts:4457-4459 | Router table against apiCall: 182 routes, 158 reached directly and 16 by two-form tools; eight unreached: three by-id reads, four logo routes and the deprecated portfolio PATCH, which ADR-0024 decides. Audit lead: Narrower than written: the three logo writes are already issue #1413 (`_bmad-output/planning-artifacts/feedback-triage-2026-11-07.md:60` and `:123`, classed S2 there and accepted by the owner on 2026-11-07), and the missing logo-status tool is stated with the read to use instead (`lib/portfolixir_web/controllers/api/v1/contract.ex:1223`). Item 5 of this entry does not hold. New are the three by-id reads only. | S | none |
| R-100 (M2-02) | A statement that shows church tax cannot be recorded on the Tax page: the save is refused for a rate the form does not carry, and the taxpayer profile that supplies it is written only over the API | AGENTS.md:230-236; docs/product-documentation.md:3099-3103 and :3116-3120; tax_live.ex:467. ADR-0031 section 6 names no human view. | LiveView run: submitting church tax 72.00 answers 'must be 0 when the church-tax rate is 0', nothing stored; after POST /api/v1/tax/profiles a new statement saves at 0.09, but a row saved earlier keeps rate 0 and its correction is refused. The verifier graded it S2. Audit lead: S3 after the second reading: the agent as the primary write path for tax data is the owner's decision of 2026-08-05; what is left is a refusal that does not say where the rate is set. Audit lead: The verifier's size M is for a Taxpayer block on the Tax page, which would go against the decision of 2026-08-05; the wording fix and the sentence in ADR-0031 §6 (AD-4) are size S. | S | ADR-0031 section 6 |
| R-101 (M2-03) | Security events, hand-kept quotes and a classification's name can be written only over the API; no record gives a reason or a deadline (the catalog-wide queues are the ADRs' own design) | AGENTS.md:230-236; ADR-0048 title and section 8 ('entered by hand or by an agent'); docs/product-documentation.md:4235-4245 (quotes kept by hand) | LiveView run: the Dates and Quotes panels render no entry control, none of 222 screen events writes an event, quote or classification name; the five API writes answer 201/200/204. The five queue reads are decided by ADR-0044 section 6 and ADR-0048. By the repository's precedent for the mirror case (a route without a tool, _bmad-output/planning-artifacts/feedback-triage-2026-11-07.md:60: S2) the event and quote writes would be S2; kept S3 because no control is dead and the operator's agent completes each write. | L | ADR-0048 (what 'by hand' means); planning lines for quotes and the classification rename |
| R-102 (M2-04) | ADR-0029 section 3 promises the ISIN change and the alias delete/reassign at UI/API/MCP parity; the screen records a change only inside an import or a merge, never deletes an alias, and the reassign has no route, tool or screen | docs/decisions/0029-stable-identities-and-reimport-survival.md:248 and :274-275; docs/product-documentation.md:4114 | Run: the dialog's write (Catalog.update_security) changes the ISIN and records 0 aliases; POST isin-change records one; the security page names the former ISIN with no control on it; Catalog.update_identifier_alias/3 has no caller in the compiled calls. | M | ADR-0029 section 3 |
| R-103 (M2-05) | The screen recolours a built-in category; the API refuses the same write as an edit of a built-in tree, so the colour of an asset class or a currency can be set only by the operator | AGENTS.md:230-231; lib/portfolixir/classifications.ex:830-831 ('Allowed for built-in categories too'); docs/integration/api-and-mcp.md:4037-4040 | Run: PATCH with only a colour on the built-in equity category answers 422 'classification is built-in and cannot be edited'; the page's recolor_category event stores #112233, journaled as owner_ui, and the API then reads it back. S3 because the colour is a display attribute: nothing stored or computed is wrong. | S | none |
| R-104 (M2-06) | The sale preview (which FIFO lots a sale would consume, and the gross gain per lot) is computed for the booking drawer only; no route or tool serves it, so the agent walks the open lots itself | AGENTS.md:230-231 and :38-43 ('the agent recomputed what the server could have handed over'); ADR-0029:402-406 | grep and compiled calls: one caller, transaction_management_live.ex:2143; no /api/v1 route names it. Run: the function answers 650 for a two-lot fixture; the trades read serves the same lots split-scaled, so a walk and a subtraction remain for the agent. | M | none |
| R-105 (O1-06) | The effective-class filter runs in the page and has no API twin: the list read offers no class, currency or attribute filter, while the reference says link and API read describe the same set | docs/integration/api-and-mcp.md:451-455; AGENTS.md "Coverage runs both ways" | Three securities: the screen shows 2, 1 and 0 rows under a class, a currency and an attribute filter; the API read has no such filter. The payload carries the stored class only. S3 because the three filters are the screen's URL keys, which neither the API nor the tool's published schema offers: no figure is wrong. | S | none |

### Modules with several jobs (21)

| ID | Finding | Stands against | Evidence | Fix | ADR amendment |
|---|---|---|---|---|---|
| R-106 (A5-08) | Portfolios is nine jobs under one name (18,320 lines, 39 modules), and its Performance sub-tree is a context in all but name: 10 modules, 7,244 lines, 91 public functions, 61 call sites from 27 modules outside it, 10 call sites into the rest of Portfolios | nothing written; ADR-0001 gives Portfolios 'portfolios, cash accounts, depots' (docs/decisions/0001-modular-phoenix-monolith.md:25); a split or named sub-context would amend ADR-0001 | Scout counts and wc reproduce every number: 7,244 of 18,320 lines, 91 public functions, 61 outside call sites from 27 modules (38 web, 8 Predictions, 1 Ledger), 10 call sites into the rest of Portfolios, no table owned. | M | ADR-0001 |
| R-107 (A6-06) | Portfolixir.Buckets is one 1,536-line module doing five jobs for three kinds of caller | Nothing written; lib/portfolixir/buckets.ex:33-35 cites architecture D2/P3, which architecture.md:390 and :58 mark proposed and not citable | The awk printed the ten sections as claimed (21 to 292 lines), 39 public and 56 private functions; the scope seam has 35 context and 4 web call sites (reader: 34 and 5); the 261-line seed has one caller. | M | none |
| R-108 (D4-07) | The four Cash-flow reports are four hand-built copies of one shape: 17 identical lines in three modules, the cash-currency rule in three, the year by month matrix in four, three shapes of excluded, two scopes and two rate rules | nothing written; a shared module needs no amendment (ADR-0001 names no sub-structure); one rate rule would amend ADR-0015 (R-133 (D4-02)) | Four diffs printed nothing (17, 17, 5 and 5 identical lines); four matrix builders; six private homes of the cash-currency rule in six files; 1,360 lines in four modules. The behavioural cost is R-133 (D4-02)'s run. | M | none |
| R-109 (G1-07) | targets.ex is seven jobs in one module: 1,595 lines, 34 public and 86 private clauses, 52 call sites from 14 modules; one public function and three option branches are reached by tests only, and the plan-race retry receives no input | nothing written; a split that keeps Portfolixir.Portfolios.Targets as the public name moves no ADR-0001 seam | Counts over the checkout and scout data match the job table (batch 483 lines, not 482; 16th largest lib file). Three two-connection first-writer races: second waits, at most one plan INSERT, no unique violation. max_batch/0 is a test pin, not dead. | M | none |
| R-110 (G4-01) | The cash and the depot merge are one protocol written twice: 39 shared function names over 586 and 605 lines; the two drifted rules (R-006 (G4-02), R-016 (G4-03)) sit in the cash merge's private copies of what MergeFigures holds | ADR-0050 §1 "One mechanism for three entities" (docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md:96, :127-129); merge_flow.ex:8-11 "cannot drift apart" | comm, diff and git log counts hold: 39 shared names, 586/605 lines, 20 commits (5 touched both). Corrected: 8 byte-identical bodies plus transact (comment only), 13 noun-only, 17 differ in substance. | L | ADR-0050 (dated note under §1; no decision changes) |
| R-111 (G4-05) | The four News files (3,915 lines) hold 9, 8, 9 and 12 jobs; News.Reads answers wire-shaped maps, so the agent's token budget is split over two layers and reaches the operator's page | nothing written; naming the public News modules would amend ADR-0001 | Counts hold (23 public, 14 delegations, 30 fence lines); corrected: 19 web calls to News.Reads, 24 past the facade, 24 budget numbers. Scratch test: a 99-character title shows cut at 45 on the News page. | M | ADR-0001 (only for naming public News modules; see R-078 (A2-08)) |
| R-112 (M1-05) | tools.ts does five jobs in 6,054 lines, a family's parts lie up to 3,000 lines apart, and three gates read the file by name, so a split moves them in the same change | nothing written is broken; a split would amend ADR-0002 (dated note). Strained: AGENTS.md:154-156 (readable multiline files) | Counts reproduced: 6,054 lines, 166 cases, 126 markers with 16 empty pairs, 73 lines over 500 characters, 284 commits (129 since October), 41 family runs. | M | ADR-0002 |
| R-113 (O1-05) | The securities page grew by 7,823 lines in 154 commits and shrank by 85 in 14; none of its twelve sibling modules was an extraction, and three child calls reach back into the page | nothing written; a page-structure rule would amend ADR-0001 | Recount by wc, grep, a read-only git loop and awk over the scout's call table: 7738 lines, 73 and 19 clauses, 154/+7823/14/-85/181, 162 calls into 34 modules, three back-calls. October's month end is 6,906, not 7,032. | L | ADR-0001 |
| R-114 (O2-06) | One module of 6,201 lines serves two pages that never share a process and twelve jobs: 51 % of its template is Holdings-only, 42 % Allocation-only, and 57 of 240 private functions are called across jobs | nothing written; a recorded page shape would amend ADR-0001 (0001:28); an own route for Allocation would amend ADR-0022 (0022:92) | Count script and scout data: the twelve job ranges partition the file (6,163 lines plus 38 blank); render/1 is 1,796 lines, 916 under a Holdings guard, 756 under Allocation; 57 cross-job private names (written: 69); 490 clause heads. | L | ADR-0001 |
| R-115 (O3-05) | PortfolixirWeb.ImportsLive is twelve jobs in one module: 5,365 lines, 234 hand-written functions, 35 assigns of its own, 153 call sites between the jobs, a 755-line render function, and four times its size of ten weeks ago | nothing written; docs/decisions/0001-modular-phoenix-monolith.md:30-31 holds for the module | Counts reproduced: 5365 lines, 15/3/10 callback clauses, 19 templates, 101 commits, 1307 to 4955 lines in two months. The reader's twelve line ranges partition the file; recount gives 153 cross-job call sites (reader 154) and 35 own assigns at runtime. | L | ADR-0050, for the step that moves the mapping rules only |
| R-116 (O4-06) | TransactionManagementLive serves as a formatting library for five other web modules (11 call sites, 4 public functions), and its delete dialog calls back into it | nothing written; a web-internal split needs no ADR | awk over the scout calls: 9 lines summing to 11 inbound calls from 5 modules; source grep finds the same 11 plus 4 test sites; both files sit in the 75-file xref cycle; the two format_quantity bodies differ only in an alias. | S | none |
| R-117 (O5-01) | The two merge previews are one markup anatomy written twice; the security preview already calls three functions of the account preview, and six parallel pieces differ | nothing written; DESIGN.md:3185 calls it one anatomy ("The flow is G2-B's anatomy") | Counts recounted: 14 of 24 data-roles, 34 of 49 merge-* classes, 24 msgids shared, 4 cross-module call sites. Scratch test: an equal delivery reads "10 shares" in the depot preview and "800.00 EUR" in the security preview. | M | none |
| R-118 (O5-05) | Page-level mechanisms are written per page: 20 dialog shells, 31 sign-class clauses, 19 private URL readers, 9 changeset-error helpers, 8 result helpers, 7 row-menu handler pairs | nothing written; a rule on where shared page mechanisms live would amend ADR-0001 (0001:28 names only "LiveViews, JSON API, components") | Every grep count recounted and equal to the reader's. Corrected: components/ is 3.2 % of the web layer, but 44 top-level helper modules add 7,698 lines (12.7 % shared); the exclusion-reason wording difference is a recorded choice. | L | ADR-0001 (only for the written rule; the extractions need none) |
| R-119 (O5-06) | Three page modules hold several jobs: Cash flow (four facets in one 1,233-line render clause), Accounts & depots (five jobs, 22 event clauses, 23 assigns), Overview (seven blocks plus four in-page domain reads) | nothing written; no ADR sets a page module's shape (ADR-0022 only if a facet got its own route) | Counts recounted (22 handle_event, 7 handle_info, 13 reload sites; facet assigns disjoint). Call trace: income_bars, top_contributors and the income read each ran once per connected open on all four facets, and again on a costs-to-flows switch. | L | none |
| R-120 (O6-01) | json.ex is 17 resource families behind one module name (3,014 lines, 59 dependent files), and the one written rule on where wire shapes live (the single presenter) has been left three times without a record | _bmad-output/planning-artifacts/architecture.md:896-900 ("ALL new actions render through the single presenter ... no per-controller JSON modules"); ADR-0031:377-379 | mix xref: 59 files depend on json.ex, 34 outgoing; scout: 328 call sites, 197 on five primitives; window_end bodies diff SAME; no record of the three sibling JSON modules anywhere in docs. Also reported as A3-05. | L | ADR-0001 (where wire shapes live); a note on ADR-0031; architecture.md:610, :829, :896-900 |
| R-121 (O6-02) | The API has no shared answer helper: 37 private copies of not_found and 35 of unprocessable, and one 404 is answered in three spellings of detail | nothing written to the letter; docs/integration/api-and-mcp.md:128-132 and error_view.ex:18 name the envelope but no owner | ConnCase run: securities 404 "not found", tax/plan/snapshot 404 "Not found", unknown route "Not Found". 72 copies, 344 lines. Also reported as A3-04. | M | none |
| R-122 (O7-03) | layout_view.ex is one render function around a 2,490-line inline client (20 hooks) that every full page load sends again (111,778 bytes as served) and that 23 test files check by reading its source text | nothing in force: the triage of 2026-09-05 prescribed one static file, Sprint 11 shipped the nonce instead (section 7); a change reopens that choice and amends ADR-0037 or needs a new ADR | Scratch test over six pages: 111,778 B inline script each, byte-identical, 77 to 98 % of the document (gzip 25,961 B); app.css answers 304. Counts hold: 2,548 lines, 20 hooks, 23 files/27 read sites, 56 copied lines. | L | ADR-0037 amendment or a new ADR (where the browser client lives and how it is tested) |
| R-123 (O7-04) | AppShell's moduledoc names the shell; 10 of its 15 public functions and 256 of its 294 external call sites (87 %) are the shared component kit | lib/portfolixir_web/components/app_shell.ex:2 (moduledoc); DESIGN.md:827 and :894 (stale census); nothing in an ADR | awk over the scout table: 294 call sites in 39 files, 256 kit, 38 shell and tabs. mix xref: all 39 callers runtime-only, 8 files recompile on an edit via the web cycle, so the reader's recompile argument does not carry. | M | none |
| R-124 (O8-03) | ledger.ex holds eight jobs in 2,345 lines (the write path with its checks, six kinds of read, six payload sentences); 99 outside call sites in 40 files reach them through one module, and the write path shares no function with any read | Nothing written; a facade split would take a dated note in ADR-0001 (:27 gives the scope, nothing on module shape) and the two path lines of ADR-0033 (:36, :298). | Scout counts reproduce: 34 public names (44 arities), 88 private, 99 call sites, 40 files, 52 in web; mix xref gives 40 lib files. A check over all 121 function names finds 0 calls between the write ranges and the read ranges. | L | ADR-0001 (dated note, with R-084 (A6-01)'s amendment); ADR-0033 path lines |
| R-125 (O8-04) | performance.ex holds seven jobs in 2,604 lines; the contribution's and the stacked chart's accumulators (478 lines, 31 functions) sit inside the walk's file and call back into 14 of its private functions at 25 sites, and two public @doc false functions exist only for two sibling modules | Nothing written; ADR-0051 §5 (:184-210) decides the accumulators live in the walk's state, not in which module. | Counts reproduce: 4 hook sites, 14 names and 25 call-back sites, 16 public and 156 private names, 44 outside sites in 11 files, IRR the only outgoing edge. Correction: the kept block is entered at 13 sites by 8 names, not only the walk's four. | L | none |
| R-126 (O8-05) | The preview's counts are a second job inside the Applier (655 of 3,245 lines, 5 of its 9 public names, 28 functions), tied to the apply at 9 call sites; the dry run through the apply's loop by one flag and four clause pairs is a decided design | Nothing written; the module's own first sentence (applier.ex:3-4) gives it one job. The dry run sharing the loop is decided (security review 2026-10-12, H53). | Counts reproduce: 28 functions in lines 538-1192 (5 public), 6 sites into the apply and 3 back, four simulate clause pairs, 12 outside call sites in 3 files. Corrections: the state map has 17 keys at birth, 28 in all; the per-section spread is not reproducible. | M | none |

### Records behind the code (ADR drift) (12)

| ID | Finding | Stands against | Evidence | Fix | ADR amendment |
|---|---|---|---|---|---|
| R-127 (A6-08) | ADR-0056 section 5 promises an on-demand run for the UI and the agent; News.fetch_now/2 and News.fetch_due/2 exist for it and no route, screen event or tool calls them | docs/decisions/0056-news-layer-fetched-matched-stored-labelled-outside.md:180-182, withdrawn by no amendment; its own section 9 (:281) and D8 (:1025) describe surfaces without it | Grep printed 13 lines in two News files and none in the web layer or the companion; the call table has no caller of either function; 11 news tools, none fetches. Only an instance with background fetch off is affected. | S | ADR-0056 |
| R-128 (D1-05) | ADR-0011 still says the holdings cost view reads buys and sells only and a new kind needs no further code; the cost-follows-shares rule came by a fix commit that touched no ADR, and the contribution walk's per-kind reader has no pin | ADR-0011 :49-53 ("only the priced buy/sell kinds ... deliveries carry no own cost") and :57-59 ("no further code"); AGENTS.md: amend the ADR, do not silently change it | git: a830f448 changed 8 files, none under docs/decisions; ADR-0011 has one commit. Scratch test: keep_internal/5 has 8 clauses naming exactly the 10 non-external kinds, no catch-all; no test iterates the kinds through a windowed walk. Both invariant tests pass. | S | ADR-0011 |
| R-129 (D2-02) | A weight rule on a security and one on a category are shares of two different totals, while the Risk screen, the rule dialog, the guide, the API reference, the risk moduledoc and ADR-0049 state one basis | ADR-0049 :99 ("percent of the context's steerable basis"); lib/portfolixir/portfolios/risk.ex:11-13 ("the same basis"); lib/portfolixir_web/live/risk_live.ex:601-606; docs/guides/own-rules.md:55 | One security, sole member of one category, 100 of 1,000 in cash: risk weight 100, category weight 90; the same 95 % cap reads breached and met on the Risk screen under one line naming "the steerable basis". Payload scales are correct per finding. The verifier graded it S2. Audit lead: S3 after the second reading: ADR-0049 §2 names the two sources on purpose; what is left is a basis line that names one denominator for two. | S | ADR-0049 |
| R-130 (D3-01) | ADR-0047 §3's row defines the risk-adjusted return over the annualized chain return; engine, payload, reference page and test use the arithmetic mean of daily returns times 365 | docs/decisions/0047-derived-metrics-per-security-and-per-view.md:114 (the row); the built formula is stated on every surface | Pure engine scratch test: a 30-day window chaining to exactly 0 reads risk_adjusted_return 2.122775; at 1 % daily deviation the built figure is 0.000000 where the row's formula gives -0.094663. No amendment or other record restates the row. | S | ADR-0047 (§3 row) |
| R-131 (D3-02) | The per-band TTWROR has a private day factor with its own flow timing; the rule is decided and stated in the payload, but no ADR carries it, day_factor/2's doc still says one shared definition, and two walk rules are written twice | lib/portfolixir/portfolios/performance.ex:2042-2043 and ADR-0010:210-212 (one shared definition); ADR-0010:50 (flows at the start of the day) | Scratch test, one holding that is the whole view, half sold and withdrawn the same day: band ttwror 0.1, view line and performance read 0.222222; the payload's reference says so. Two day_factor definitions; 'band' occurs 0 times in ADR-0010 and ADR-0051. | S | ADR-0010 |
| R-132 (D3-06) | ADR-0047 §4 widened the float island because Decimal has no square root; Decimal.sqrt/1 exists, was already called when the record was signed, and ADR-0055 §4 prescribes it | docs/decisions/0047-derived-metrics-per-security-and-per-view.md:141-143 against docs/decisions/0055-predictions-scored-for-calibration.md:166-167; AR-3, epics.md:140 | decimal 3.1.2 exports Decimal.sqrt/1 (3.1.1 at the signing commit, where quote_adjustment.ex:229 already called it). Both roots of 0.0365 round to 0.191050; for 1e400 Decimal.sqrt answers 1E+200, Statistics.square_root nil, which triage F73 picked on purpose. | S | ADR-0047 §4 (and AR-3's wording) |
| R-133 (D4-02) | A foreign-currency booking on a day without a stored hub rate is a figure in Income, the walk and the contribution (last earlier rate) and excluded in Costs, flows, realized and the benchmark's costs_paid; ADR-0015 names one rule | ADR-0015 amendment 2026-10-07 point 3 and identity 2 (docs/decisions/0015-cross-currency-settlement-fx-rate.md:158-160, :194-196); Sprint 8 D-1 (sprint-plan-2026-08-20-sprint8.md:110-117) | One Saturday USD world: Income tax 12, gross 80, excluded 0; Costs.report empty with 2 excluded; walk trade_costs 4 and contribution costs 4; Costs.paid fees 0; deposit 80 in the walk's flow, excluded from the flows report. Narrow reach, each payload names its rule. The verifier graded it S2. Audit lead: S3 after the second reading, which found each rule recorded: the exact-date exclusion is Sprint 8 D-1 and Sprint 9 D-1, `costs_paid` is ADR-0046's amendment point 2, Income's on-or-before rule is DESIGN.md UX-DR25. ADR-0015 decides the currency, not one date rule. What is left is that no record says why the rules differ. | S | ADR-0015 |
| R-134 (D4-04) | ADR-0011 says the walk no longer dispatches on the kind and a new kind needs one clause; the walk dispatches at five sites and the Costs report reads every unnamed kind through a silent catch-all with no coverage gate | ADR-0011 (docs/decisions/0011-unified-ledger-projection.md:42-47, :57-59); ADR-0028 §3 :311-317 lists change sites without the Costs report | AST count: cost_legs/1 has 4 heads, 1 catch-all taking 12 of 15 kinds. A hypothetical fee_refund booking raises in Projection.effects/1 and answers {[], []} in Costs.series/2. No invariant test reads costs.ex (count 0). Nine dispatch sites in five modules. | S | ADR-0011 |
| R-135 (D5-01) | ADR-0016 §4 and §6 do not describe how the screens round: percentages print at one decimal where it says two, percent and quantity each have four scales, the largest-remainder rule was never built, and Format's "rounding happens only here" is one of 12 web files that round | docs/decisions/0016-rounding-policy.md:64, :66, :73-76, :58-59; lib/portfolixir_web/format.ex:11-12; AGENTS.md "Do not silently change architecture decisions" | Formatter scratch test printed percent(0.12345) = "12.3", a quantity as "0.3333", "0.33" or every digit by site, three thirds as 33.3 + 33.3 + 33.3 = 99.9; greps: 0 largest-remainder lines, 15 Decimal.round calls outside Format, ADR one commit. | S | ADR-0016 (amend §4 and §6) |
| R-136 (G1-02) | A plan's cash target has two stored homes: every computing reader and every door use the view's cash-only plan row, while the plans read, the duplicate and ADR-0027 speak of a per-version column that no route, screen or tool writes, so the steering plan answers cash_target_weight null while the scope steers 20 % cash | ADR-0027 §3 (docs/decisions/0027-plan-versions-and-depot-snapshots.md:81-82, duplicate copies the cash target); ADR-0020 :68 and :85; docs/integration/api-and-mcp.md:3280-3287 … | Scratch API test: GET plans answers null for the steering tree plan and lists an unexplained cash row with 0.2; cash_target and allocation answer 0.2; the duplicate carries null; activation leaves cash untouched. 9 call sites, 0 pass plan: or classification_id:. The verifier graded it S2. Audit lead: S3 after the second reading: that the cash target is the view's and a version's copied column is inert is stated in the product documentation and three module docs and pinned by a test (#1185). What is left is an ADR-0027 §3 sentence and a reference sentence that still speak of a per-version cash target, a field that is always null, and branches only tests reach. Its screen-side consequence is R-027 (G1-03). | M | ADR-0027 §3 (and one sentence of ADR-0020) |
| R-137 (O3-03) | Imports.apply/2 books an unseen name the mapping leaves out; the refusal ADR-0050 words as "Apply refuses the name unmapped" is the page's confirm alone, as decided, and nothing written says which page rules a later caller of apply/2 inherits | docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md:770-771 beside :783-784 and :609-610; lib/portfolixir/imports/applier.ex:100-101 | apply/2 with the renamed name unmapped answered {:ok, _}: 1 account created, 3 bookings, the interest of 2.55 on both accounts. The page's P1 test refuses the same drop. Narrower than written: the placement is decided; the wording and inheritance list are open. | S | ADR-0050 (amendment note: who refuses, and what an import route inherits) |
| R-138 (O8-06) | Two public functions of these modules have no caller in lib/ and two more are public but called only inside their own module; a doc sentence and an ADR sentence still name one of the dead ones as the performance walk's price source | ledger.ex:2227-2228 (doc names the valuation and the walk as users of latest_trade_prices/1) and ADR-0010:129-130 (names Ledger.latest_trade_prices as the walk's fallback); neither is true. | Greps and the scout table agree: latest_trade_prices/1 and previous_analysis/2 are called by tests only; cross_portfolio_hits/2 only inside its module. A sweep of all public functions adds a fourth the reader missed: Performance.unvalued_cash_accounts/3. | S | ADR-0010 (dated note correcting :129-130) |

### Gates and pins narrower than their claim (15)

| ID | Finding | Stands against | Evidence | Fix | ADR amendment |
|---|---|---|---|---|---|
| R-139 (A4-06) | The merge half of the foreign-key disposition map is a declaration nothing executes: all 23 acting merge values can be exchanged and the whole suite stays as it was, and a key declared with no merge code makes that merge answer plan_changed on every attempt | ADR-0050 §14 (0050:588-594) and foreign_keys.ex:11-13: the declaration is said to keep a future table from breaking every merge | In a container copy, 23 acting values exchanged: full suite unchanged (6435 tests, the same 12 environment failures); one value set to :refuse turns a test red. A declared key without merge code answers plan_changed with the same digest, twice. | M | ADR-0050 §14 |
| R-140 (A4-07) | Transaction.reassign_changeset/2 skips a booking's validators and is safe only when a merge calls it; nothing pins that the merge writer is its only caller: a second caller of it, and of the public MergeWriter.reassign_transaction/3, leaves the whole suite as it was | ADR-0050 §13 (0050:569-575): safe only behind the merge's guards, and the merge writer asserts legs, portfolio and currency (it does not; the three merges do, one level up) | xref: one caller of the changeset, the three merges call the writer. Called directly, the writer moved a EUR buy onto a USD account that Ledger.update_transaction refuses. Two added second callers left the full suite unchanged (6435 tests, same 12 failures). | S | none |
| R-141 (A5-04) | What Portfolixir.Engines is, is written only in its module docs and in AR-2 and pinned by no test: a clock read, a config read and a Repo read put into three engines leave the invariant and engine tests exactly as they were; the namespace holds 7 of at least 15 engine-shaped modules, and the Ledger calls into Portfolios for the IRR solver | AR-2, _bmad-output/planning-artifacts/epics.md:139 (no Repo/clock/config inside engines); the engines' own moduledocs; ADR-0049 :221-224; no ADR defines the namespace | Mutation on a private copy of the tree: with a clock read, a config read and a Repo read inserted into three engines, test/invariants and the engine tests gave the baseline's result (357 tests, the same one unrelated git failure). | S | ADR-0001 |
| R-142 (A6-04) | The seven restricting foreign keys onto views, classifications and categories are kept by hand in two files and enumerated by no test, so a new one makes the delete and its dry run raise; the two delete shapes themselves are a recorded split | lib/portfolixir/classifications.ex:804-805 and :813-815 (never an Ecto.ConstraintError); the pin pattern of lib/portfolixir/lifecycle/foreign_keys.ex:8-13 | pg_constraint lists seven restricting keys, all named today; a scratch test with a new restricting key made delete_category and its dry run raise Ecto.ConstraintError, where a named key answered a changeset. Two-shapes half is decided (triage 2026-09-24:160). | S | none |
| R-143 (D5-03) | Format.decimal/3 and Format.plain_decimal/3 still round into a negative zero ("-0.00"), and exact/2, plain_exact/2 and native_amount/2 print one they are handed; the two rounded forms carry 97 call sites, among them the negative-holdings note and the Risk tab's ratios | DESIGN.md:531 ("wherever it is printed"); docs/product-documentation.md:2880-2881 ("anywhere in the app: "0.00", never "-0.00""); lib/portfolixir_web/format.ex:309-310 | Formatter sweep: money, percent and the signed forms print "0.00" for -0.004, decimal and plain_decimal print "-0.00"; Wealth page with a holding of -0.004 reads "Dust Co. (Depot: -0.00 · total across depots -0.00)", German "-0,00". | S | none |
| R-144 (M1-01) | The docs gate reads 40 of the 166 MCP tool declarations and 170 of the 182 API routes, so a tool or route declared across two lines can ship without a line in the API reference | test/portfolixir/docs_test.exs:297-298 ("every current /api/v1 route, and every current MCP tool"); sprint-workflow.md:113-115 ("a gate silently checks nothing") | A scratch copy of the gate's loop finds 40 of 166 tools and 170 of 182 routes; with the 126 unseen names stripped from the page it still passes, and a control with one seen name stripped fails. Nothing is undocumented today. The verifier graded it S2. Audit lead: S3 after the second reading: all 166 tools and all 182 routes are documented today, and no state of `main` kept a gap through the gate's blind spot. It is the nearest row to the ladder's "a gate silently checks nothing". | S | none |
| R-145 (M1-04) | 28 closed sets and the bounds beside them are copied by hand from the application into tools.ts; the 24 with a public accessor agree today, and no test on either side compares one of them | mcp-server/src/tools.ts:277-278, :1347-1348, :2558-2559 (comments claiming an exact mirror); mcp-server/test/tools.test.ts:600; ADR-0002:29 | The pin written as a scratch test passes: 24 of the 28 named sets (185 names) and six bounds equal the application's accessors, in the same order; none of 1,373 files under test, lib or mcp-server/test names one of the constants. Also reported as O6-06. | S | none |
| R-146 (M1-07) | The single-egress scan has one gap that needs no dependency and no import statement, and AGENTS.md names the weaker of the two tests as the rule's pin | test/invariants/scope_b2_outbound_chokepoint_test.exs:56-59 ("imports only registered modules"); ADR-0002:22; AGENTS.md:223-226 | A copy of the scan fed a synthetic source, and a control. Held like lens 1's gate rows until its fix merged: the detail is in the private evidence only. | S; fixed in #1489 (`4eb903d4`) | none |
| R-147 (M2-01) | No test pairs a route with a tool or a screen write with a route; each list is held only against the manifest and the reference, and the close-out's two-way check is prose | AGENTS.md:230-236 (coverage runs both ways); epics.md:148 (AR-11); sprint-workflow.md:204-208. A pin would amend ADR-0026. | Scratch test over Router.__routes__ and tools.ts: 182 routes, 174 tool paths, 8 routes without a tool, 0 tool paths without a route; both existing gates pass, and stay true on an in-memory copy with a mistyped tool path. | M | ADR-0026 (compensating controls); one sentence in ADR-0002 |
| R-148 (O1-08) | The raw/1 gate scans the ten render_cell clauses; the asset-class cell is built by three raw/1 calls in a helper it does not follow, under a sobelow_skip, against the test's own story | securities_render_cell_test.exs:208-210 ("no securities cell built by raw/1 … without a skip"); securities_live.ex:4670-4672 | Confirmed by the gate test and a scan per function of the page; the run is in the private evidence. Sprint 26 M1 scoped four clauses only. | S; fixed in #1489 (`b0e4b241`) | none |
| R-149 (O4-09) | Two event handlers of the tree page (assign_security, unassign) have no sender in the product; six test calls push them, and on the asset-class tree they do not do what the hook's events do | nothing written; the premise of AGENTS.md:56-59 (test first stands in for the owner's read) | Greps: no template or script pushes either event; the hook pushes only assign_securities and unassign_many; 6 test pushes, 2 of 33 clauses. On the asset-class tree the hook's events reclassify, assign_security is refused, unassign does nothing. | S | none |
| R-150 (O6-04) | The manifest's prose is 80.7 % of contract.ex and is compared with no behaviour; its one pin is a 2,040-line test that repeats it | contract.ex:20-22, :25-27 ("a one-sentence summary"); docs/integration/api-and-mcp.md:4488-4489 ("one sentence per parameter") | Scratch test: 245 parameter items, 180,707 bytes, 157 over 500 characters, longest 2,985; 131 of 131 tool names in prose are real, 11 of 149 route spellings are not the router's; 543 substring assertions, four in-place corrections. | M | ADR-0044 §8 |
| R-151 (O6-05) | since= compares dates strictly, three pairs of entries share a date and the meta-test accepts equal dates; two pairs shipped in consecutive same-day releases, and the later release answered changed: false | contract.ex:1598-1600, :49-50 (the manifest's own rule); api_v1_contract_meta_test.exs:14-15, :115 | Release manifests compiled from tags: 2026.10.6 polled with 2026.10.5's date answers no entries, changed=false, though it added splits.delete; same for 2026.10.14 after 2026.10.13. Latent at the audited commit. | S | ADR-0044 §8 (a version cursor); tightening the meta-test needs none |
| R-152 (V1-04) | The freshness meta-test lists six payloads of three serializers by hand; four of the eight registered analytics are outside it, and three of their payloads, two of them memoised, carry an evaluation day and no stale key | ADR-0039 I4 (0039:157) and property 3 (0039:142-143); derived.ex:26-27 | Greps: three serializers named, Registry never read. Scratch API read with the layer on: the performance, contribution and bands routes carry an instant and stale; risk metrics, policy findings and security metrics carry a date and no stale key; two findings reads are byte-identical. Also reported as O6-07. | M | ADR-0047 §6 and ADR-0049 §5 (dated notes for the payload additions), or ADR-0039 I4 if its scope is narrowed |
| R-153 (V1-05) | Two memoised payloads changed after their last computation-version bump (a zero drawdown's dates in portfolio_metrics, rule_name_author on every finding in policy_findings), and no test pins either number | registry.ex:24-27 (bump on shape or arithmetic); ADR-0039 §5 (0039:165-167) | Git history: neither #1343's commits nor e570df8a touched the registry; both analytics stand at version 2. A finding of the pre-H14 shape raises KeyError in today's serializer. Latent: both lifetimes are request, so nothing old is served today. | S | none |

### Screen defects met on the way (6)

| ID | Finding | Stands against | Evidence | Fix | ADR amendment |
|---|---|---|---|---|---|
| R-154 (O3-02) | A confirm that does not reach the done page drops the mapping's recount flag: a recount still due is never run, and a diverged apply counts again without the operator's kept choices, so a row's count is not what the confirm books | lib/portfolixir/imports.ex:127-128 and DESIGN.md:3362-3366 ("a row's count after the operator's choice is what the confirm skips and books") | Flag true before, absent after a refused confirm. Row mapped onto the old account then reads "4 bookings new", undimmed, and the confirm books 1, skips 5. After a diverged apply rows read "1 new" and the confirm books 0. Display only; small reach. The verifier graded it S2. Audit lead: S3 after the second reading: every path needs a confirm that is refused inside the dry run's own runtime, or the race ADR-0050 §10 names. | S | none |
| R-155 (O5-03) | Accounts & depots states a refused changeset with the raw field key, untranslated and with its placeholder unfilled; nine private changeset-error helpers, three on the shared one | EXPERIENCE.md:365 "No user-facing string bypasses gettext"; field_label.ex:17 "the one way these pages state a refused changeset" | German page printed "name should be at most %{count} character(s)", "name must not contain invisible characters (%{characters})…" and "date is invalid"; the shared helper gives "Name darf höchstens 100 Zeichen lang sein", "Datum ist ungültig" for the same changesets. | S | none |
| R-156 (O5-04) | After a failed overview read the Overview keeps five regions aria-busy for good: four key-figure cells and the Off target block, beside the load-failed note | EXPERIENCE.md:261 (Pending "Lasts seconds") and :300 ("Never the pending glyph"); busy_placeholders_test.exs:7-10; capped_async.ex:26-28 | With the overview task failed, the page showed the problem note, 0 busy elements in the value card, 4 busy strip cells and 1 busy Off target skeleton; unchanged 300 ms later, page process alive. | S | none |
| R-157 (O7-01) | The x on a Snapshots problem note does nothing: SnapshotsLive renders the shared result slot and has no clause for the dismiss_result event the slot's x sends | lib/portfolixir_web/components/app_shell.ex:554-557 (the dismiss button sends dismiss_result to the parent LiveView, which clears the result assign); DESIGN.md:459 | Scratch LiveView test: the note's own x clicked three times, note still rendered, view alive; same from a stale ?snapshot= address; only a successful selection clears it. 8 of 9 hosts have the clause. Reach small: error path only. The verifier graded it S2. Audit lead: S3 after the second reading: the note needs an address that names no snapshot, which the page's own flows prevent. | S | none |
| R-158 (O7-02) | The shared chart's hook pushes SecuritiesLive's two zoom events from every page that draws the chart; PortfolioLive (Wealth) and SnapshotsLive have no clause and drop both | lib/portfolixir_web/components/security_chart.ex:57-58 (interactivity is handled at the LiveView level); stale comment lib/portfolixir_web/layout_view.ex:1128-1133; nothing in an ADR | render_hook with the hook's payload: Wealth and Snapshots HTML byte-identical after both events; Securities narrows 365 to 291 points. Wealth's own select_range takes the same payload (41 to 16). Rectangle traced only, no browser in the slot: S3 because nothing is wrong or crashes and Wealth has its own working range control; whether the dead drag reads as a broken control (then S2, the verifier says) is a browser observation still to make. | S | none |
| R-159 (O7-05) | The sidebar's Views entry still draws the funnel, which the design language gave to filter alone on 2026-08-05; :bookmark, the glyph it assigned to Views, is defined and drawn nowhere | _bmad-output/planning-artifacts/design-language/DESIGN.md:908 (the funnel keeps filter; Views takes :bookmark); EXPERIENCE.md:146, :567 | Scratch LiveView test on /securities: #nav-buckets (Views) draws the funnel path, as do Filter and More filters; 0 bookmark paths; icon: :bookmark and name={:bookmark} occur 0 times. No later record reverses the ruling. | S | none |

## 8. What holds

Seams and invariants a reader checked and found intact at `e014f284`. The lane that checked each is in square brackets.

**Context seams (ADR-0001).**

- The web layer never calls the Repo (the database access module): the audit's call data (every module-to-module call, extracted once) counts 0,
  a search of the web layer finds no query code; pinned by `test/invariants/web_repo_boundary_test.exs`. [A1, A2, A3, A5, M2, O1, O3, O4, O5, O6]
- The web layer calls no domain code marked internal: joining the call data with the documentation marks gives 0 rows; its only undescribed
  callees are two table definitions (`lib/portfolixir/ledger/transaction.ex`, `lib/portfolixir/catalog/security.ex`). [A1, A2, A3, O2, O3, O4]
- Outside start-up and translations, no context names the web layer: a search finds code references only in `lib/portfolixir/application.ex:41`,
  `:100`, `:151`, `:159` and `lib/portfolixir/release.ex:66`; the translation backend is finding R-073 (A1-01). [A1, A7]
- No dependency cycle crosses the layer line: of the 7 cycles in the compiler's dependency report, the 96-file one lies wholly in `lib/portfolixir`
  and has no compile-time edge, the 75-file one wholly in `lib/portfolixir_web`; 0 compile-time edges run from domain to web. [A1, A7]
- No controller or plug (a request filter) builds a query or a changeset (a write with its validation): two searches over
  `lib/portfolixir_web/controllers` and `lib/portfolixir_web/plugs` find no code; the plugs' 11 call sites reach shared helpers only. [A3]
- Every screen write hands the actor (who is writing) to a context function: 95 `Actor.owner_ui()` call sites under
  `lib/portfolixir_web/live` (recounted); handlers read, e.g. `lib/portfolixir_web/live/buckets_live.ex:791-862`. [A2, O1, O4, O5]
- Portfolios, Ledger, Catalog and Fx (currency rates) write no other context's table: a search for write calls shows the Ledger
  writing bookings only (`lib/portfolixir/ledger.ex:1633`, `:1775`, `:1852`) and Fx rates only (`lib/portfolixir/fx.ex:67`). [A5]
- The engines (pure calculation modules) touch no database, clock or setting, and only context code calls them: a search over
  `lib/portfolixir/engines/` prints nothing; the call data lists 7 caller modules, none in the web layer or the MCP companion. [A5]
- Tax leans on one function of another context and nothing leans on Tax: its single outside call counts bookings since a date
  (`lib/portfolixir/tax.ex:633`); a search finds no caller of Tax in another context and no foreign key in its migrations. [A6, D1, D3, D4, V1]
- Buckets alone writes its tables, and the web layer reaches Buckets and Classifications through their top modules only: a search
  finds no outside write (`lib/portfolixir/buckets.ex:19-20`); the call data counts 101 and 64 calls, none to a submodule. [A6]
- Lifecycle (merges and deletes) writes through six primitives of its own, each journaled in its transaction, else through the owning context
  (read at `lib/portfolixir/lifecycle/merge_writer.ex:44`, `:110`, `:138`); its one bulk write is a journaled backfill (search). [A4, A6, O8]
- The importer writes one foreign table itself, the bookings, with its journal entry (`lib/portfolixir/imports/applier.ex:3062-3069`);
  accounts, securities and buckets go through their contexts' functions (call sites read at `:2423`, `:2664`, `:1653-1677`). [A4, O3, O8]

**MCP through the API only (ADR-0002).**

- Every tool makes one request to an existing API route under `/api/v1`: 166 declarations, 166 dispatch cases and 166 request calls counted in
  `mcp-server/src/tools.ts:5076-5942`; a script found 0 of their 174 method-and-path pairs outside `lib/portfolixir_web/router.ex`. [A1, G1, M1, M2]
- The companion opens no file, process, database or second host: a search over `mcp-server/src/*.ts` finds none, its network call sits in
  `mcp-server/src/api-client.ts` only, redirects refused (`:241-249`); pinned by `test/invariants/scope_b2_outbound_chokepoint_test.exs:716-765`. [A1, M1]
- Its packages are exactly the allowlist: the 4 runtime and 5 development packages in `mcp-server/package.json:20-32` equal
  `test/invariants/mcp_dependency_allowlist_test.exs:23-36` (lists compared); no database driver is among them. [A1, M1]
- The API's answer is passed through: the tool caller returns the payload with no filter, sort, rename or dropped field
  (`mcp-server/src/tools.ts:5066-5073`, read); the one change, spelling out invisible characters, is decided in ADR-0054 §4. [M1, V1]
- The companion computes and rounds nothing: a search for number parsing, rounding and summing over `mcp-server/src/*.ts`
  gives 6 lines, all ports and the lock-out timer (e.g. `mcp-server/src/http.ts:287`); the tool file has none. [D2, D5]
- Every argument a tool offers is forwarded and none is forwarded unoffered: a script compared schema and forwarded keys for the
  164 published tools (486 properties, `mcp-server/test/fixtures/stdio-surface.json`) and the two label tools; no difference. [G3]
- Every forwarded query key is read by the API action it reaches: the 65 query allowlists in `mcp-server/src/tools.ts`
  were held against the keys each controller action reads, shared readers included; 0 keys forwarded and unread. [G3]
- Tool list, router and manifest (the contract the API publishes about itself) agree both ways: `test/portfolixir_web/controllers/api_v1_contract_meta_test.exs:25-64`
  holds each against the manifest; an independent parse found 182 endpoints and 166 tools, no difference. [M1, M2, O6]

**One figure, one path.**

- What each booking kind does to cash and quantity is written once: holdings, cash and the performance walk (the daily replay behind return
  figures) read one effects table (`lib/portfolixir/ledger/projection.ex:65-146`, callers traced); split scaling is finding R-033 (D1-03). [A5, D1, D2, O8]
- Held quantity per depot and security has one fold (one pass over the bookings) outside the walk: the holdings, the reports,
  the split preview and 7 call sites in 5 other modules read it (`lib/portfolixir/ledger/positions.ex:25-30`, call data). [D1]
- Cash balance has one fold and no SQL sum (`lib/portfolixir/ledger/projection.ex:297-303`), and the running balance is one function over the
  whole history on the page and the API (calls traced to `lib/portfolixir_web/controllers/api/v1/transaction_controller.ex:87`). [A2, A3, D1, O4]
- The unscoped question "is this security held?" has one answer for Catalog, Knowledge and News: the only SQL sum over
  bookings (`lib/portfolixir/ledger/held_securities.ex:56`, by search), with 10 call sites in 6 modules. [A5, A6, D1]
- Inside the Ledger, cost basis has one moving-average fold: both cost reads reduce with the same step function (`lib/portfolixir/ledger.ex:677`,
  `:783`, read), and `test/invariants/cost_fold_kind_coverage_test.exs` pins that it names every booking kind. [D1, O8]
- Realized gains have one FIFO matcher (first bought, first sold): the three trade reads and the merge restatement feed it through one input shaping
  (`lib/portfolixir/ledger.ex:232`, `:268`, `:317`; `lib/portfolixir/lifecycle/merge_fifo.ex:122`, traced); Tax matches no lots. [A4, D1, D3]
- Portfolio and view share one valuation, and a holdings row uses its price rule: both entry points run the same helpers
  (`lib/portfolixir/portfolios/valuation.ex:380-388`, `:477-486`), both holdings reads call its price function (`lib/portfolixir/ledger.ex:385`, `:589`). [A5, D2, G2, O1]
- Allocation, risk, category result and policy findings value nothing themselves, and a screen's view totals are the view valuation's:
  call sites read (`lib/portfolixir/portfolios/allocation.ex:253-254`, `lib/portfolixir_web/live/dashboard_live.ex:196`). [D2]
- The API layer does no money arithmetic: a search for decimal add, subtract, multiply and divide over the API's files
  prints nothing; its one rounding site is `lib/portfolixir_web/controllers/api/v1/json.ex:179`, a ratio. [D2, D4, D5]
- One day factor (the daily return step) serves the return chain's readers: a search shows snapshot comparison and risk metrics calling it
  (`lib/portfolixir/portfolios/snapshot_comparison.ex:416`), the others use the walk's own summary; the bands' copy is finding R-131 (D3-02). [D2, D3]
- One solver computes every money-weighted return (IRR), and the fixed-rate formula exists once: a search prints 7 solver
  calls in 3 files; `(1 + rate)^(1/365)` is at `lib/portfolixir/portfolios/performance/benchmark.ex:590-604` only. [D3]
- One window return (the price return over a time span, in EUR) serves sale hindsight, switch cost and prediction resolution: a search
  finds its return functions called from those three modules only (`lib/portfolixir/portfolios/performance/window_return.ex:3-6`). [A6, D3]
- One cost rule serves cost report and benchmark (`lib/portfolixir/portfolios/costs.ex:49`), one trade-cost function the walk and the contribution
  (a result split by position), pinned equal for a trade in scope by `test/portfolixir/portfolios/performance/contribution_test.exs:925`. [D4]
- Income by position follows one rule in the Income report and the contribution: same booking kinds, currency, rate and division, compared
  clause by clause (`lib/portfolixir/portfolios/income.ex:84`, `:335-339`; `lib/portfolixir/portfolios/performance.ex:2423-2436`). [D4]
- A statement's remaining allowance and tax-free trim budget have one implementation for the API, the Tax page and the roll-up
  (`lib/portfolixir/tax/budget.ex:49-61`; callers traced, e.g. `lib/portfolixir_web/live/tax_live.ex:974`). [D4, O5, O6]
- The drift threshold is one predicate for the Wealth chips and the API's `min_drift` filter: both call the allocation's own test
  (`lib/portfolixir_web/live/portfolio_live.ex:774`, `:801`; `lib/portfolixir_web/controllers/api/v1/json.ex:1438`, traced). [A2, D2, D5, O2, O6]
- Screens and API call the same context function in each of the 13 read families compared: 60 rows of call data, e.g. the category result
  at `lib/portfolixir_web/live/classifications_live.ex:2651`; one base-currency difference is finding R-071 (V2-05). [A2, A3, G2, M2, O4, O5, V2]
- The contribution table's total is the performance read's own result and the Wealth badge equals the table's sum: pinned by
  `test/portfolixir/portfolios/performance/contribution_test.exs:933-952` and `test/portfolixir_web/live/performance_contribution_live_test.exs:242-245`. [D3, D5]
- Where two figures differ by decision, the payload says so: cash flows against invested capital (`lib/portfolixir/portfolios/external_flows.ex:8-17`),
  a holding's cost without fees against a closed trade's with them (`lib/portfolixir/ledger.ex:1309-1315`), both read. [D1, D3]

**The derived-value layer (ADR-0039).**

- No write path reads a derived (memoised) value: `test/invariants/derived_never_a_write_source_test.exs:79-130` scans the code against 13 allowed
  files, and the call data from Lifecycle (390 functions) and Imports (308) meets the layer only where a write notifies it. [A1, A4, O8, V1]
- Every walk read from the web layer goes through the memoised wrapper, the bands read excepted (finding R-066 (V1-03)): the call data lists 11
  web calls into the walk module, none past its memoised entry points (`lib/portfolixir/portfolios/performance.ex:156`, `:353`). [O2, V2]
- No request option that changes a result is missing from a memo key: the keys of all eight registered analytics were read in full (e.g.
  `lib/portfolixir/portfolios/performance.ex:192-199`), and the computation version is part of the key (`lib/portfolixir/derived.ex:100-102`). [V1]
- Every journaled write notifies the layer through one function (`lib/portfolixir/journal.ex:131`), as does every quote and rate writer
  (`lib/portfolixir/catalog/quotes.ex:481-482`, `:642`; `lib/portfolixir/fx.ex:78`), write sites searched; two gaps in reach are R-007 (V1-01) and R-008 (V1-02). [A1, V1]
- A fetch answers fresh values only; a superseded one needs a separate call carrying its age (`lib/portfolixir/derived.ex:92-116`), pinned by
  `test/portfolixir/derived/derived_test.exs:228-272`; Wealth labels it (`lib/portfolixir_web/live/portfolio_live.ex:1222-1251`). [O2, V1]
- The served walk equals a fresh recompute after writes, a corrected price, a deleted or backdated booking and a rebuild: invariants I1, I2,
  I3 and I6 each have a test (`test/portfolixir/derived/derived_invariants_test.exs:182-275`, `:343-370`, read), for the cases they try. [V1]
- A write the layer cannot narrow invalidates every portfolio: the fallback resolver answers "all" (`lib/portfolixir/derived/blast_radius.ex:129`),
  pinned by `test/invariants/blast_radius_widening_test.exs:35-56`; scope, classification and target writes widen this way. [A1, V1]
- The freshness fields `as_of` and `stale` are on the four performance-family payloads that serve a derived value
  (`lib/portfolixir_web/controllers/api/v1/json.ex:2017-2018`, `:2128-2129`, `:2386-2387`, `:2438-2439`, read), and the MCP tools pass them through unchanged. [O6, V1]
- What is not memoised is so by decision: custom ranges and fine rates are computed per read (pinned by `test/portfolixir/derived/memo_budget_test.exs:83`),
  and the reads outside the walk were measured at 13 to 393 ms (`docs/decisions/0039-durable-derived-values.md:213-258`). [V1, V2]
- A write's notice cannot be lost between its transaction and the commit: a pending mark and a post-commit bump close the gap
  (`lib/portfolixir/derived/data_version.ex:152-166`, read), pinned by `test/portfolixir/derived/commit_order_test.exs:78`. [V1]

**Other invariants found intact.**

- A booking kind the code was not taught fails loudly instead of counting as nothing: `test/invariants/projection_no_catch_all_test.exs`
  pins that the effects table has no catch-all (12 clauses for 15 kinds, `lib/portfolixir/ledger/projection.ex:65-146`). [D1]
- Every ledger write is one transaction together with its journal entry (`lib/portfolixir/ledger.ex:1632-1640`, `:1774-1793`,
  `:1851-1860`, read), and `test/invariants/import_hash_writers_test.exs:40-47`, `:67-90` pins that no code bulk-writes bookings. [A4, O8]
- A booking's counter cash account cannot sit in another portfolio: composite foreign keys enforce it (`lib/portfolixir/ledger/transaction.ex:366-370`,
  read), so a per-portfolio cash fold loses no leg and a view can sum its portfolios' walks. [D1, D2]
- A target write that names its plan version lands on that version or is refused, at screen, API and MCP, and a refused batch writes
  nothing: the checks and the single transaction were read at `lib/portfolixir/portfolios/targets.ex:1114-1135` and `:463-472`. [A3, G1]
- The import's preview and apply cannot drift: the preview is the apply run in a transaction that rolls back (`lib/portfolixir/imports/applier.ex:427-456`),
  and the apply re-checks every row (`lib/portfolixir_web/live/imports_live.ex:1386-1404`), both read. [D1, O3, O8]
- No float is stored, and the five largest pages print none as a money figure: searches find floats as chart coordinates only
  (`lib/portfolixir_web/live/portfolio/stacked_chart.ex:57-58`); money prints at two places, half up (`lib/portfolixir_web/format.ex:44`). [D5, G2, O1, O2, O3, O4]
- No atom (a permanent name in the runtime) is made from input in the web layer: a search for `String.to_atom(` under `lib/portfolixir_web` prints
  nothing; the few lookups of existing atoms are guarded (e.g. `lib/portfolixir_web/live/portfolio_live.ex:5055-5056`). [A3, O1, O2, O3, O4, O5]
- The lists that steer deletes are held against the database's foreign keys: `test/invariants/lifecycle_foreign_key_dispositions_test.exs` allows
  no cascading key onto the three identity tables, `test/invariants/cascade_removals_test.exs` checks the journal's cascade list. [A1, A4, A6]
- A news label is always stored as a machine-made proposal: the marker is forced true by the write validation and by a database
  check (`lib/portfolixir/news/label.ex:117-130`, read), so the API's constant and the stored value cannot disagree. [G4]
- The research log and the predictions stay append-only: a search for updates and deletes of a note or a prediction
  finds none, inside or outside their contexts (`lib/portfolixir/knowledge.ex`, `lib/portfolixir/predictions.ex`). [A6]
- The screens' write families each have an API route, one excepted (finding R-103 (M2-05)): the call data shows 67 write functions called from
  both a page and an API controller; screen-only cases carry a written reason (e.g. `docs/integration/api-and-mcp.md:4371-4374`). [M2]

## 9. Proposed ADR amendments

I38 asks for "ADR amendments where a decision no longer fits". 89
findings name an ADR, some only as an option. Most are one dated sentence
that brings a record up to the code. Six change or add a rule and are worth a
decision of their own:

| Amendment | What it would say | Why now | Findings |
|---|---|---|---|
| **ADR-0001**, the contexts and their direction | Name the 13 contexts and the shared kernel. Say which modules of a context are public (a list, seeded from the 57 submodules the LiveViews and components call today that are not schema modules). Give calls between contexts one direction and name the edges to cut. A context reads another context's table only through that context's function. One gate fails on a web call to a non-public module and on a new call against the direction. Two more paragraphs ride in it (AD-7): how a page is organised, and where wire shapes live. | Everything I38's first question asks is unwritten, so each sprint decides it again in code. | R-073 (A1-01), R-074 (A1-02), R-075 (A1-05), R-078 (A2-08), R-079 (A4-04), R-080 (A4-05), R-081 (A5-02), R-082 (A5-03), R-083 (A5-05), R-106 (A5-08), R-084 (A6-01), R-085 (A6-02), R-086 (A6-03), R-124 (O8-03); R-077 (A2-06) for the schema-module rule only |
| **ADR-0010**, one price on a day | One function answers "the price of this security on day D": which observations count (a stored close, a booking's price, a priced delivery), whose bookings, and the order among them. The valuation reads it for today, the walk for each day. | Two engines answer it by two rules today, and the Wealth total and the walk's end value differ on one page. Needs AD-2. | R-001 (D2-01), R-138 (O8-06) |
| **ADR-0004**, a booking counts from its date | One "counts as of" cut in the Ledger that every current read and the walk share; a read names the bookings dated after today. | A booking dated ahead is in the balance, the holdings and the valuation today and on no day of the walk. Needs AD-1. | R-002 (D1-01). R-093 (D4-06) rides the same cut and needs no amendment. |
| **ADR-0027** (one sentence in ADR-0051 §1), a view's trade costs | A trade's fee is a transaction cost of a view when the shares it bought or sold are in the view, which is exactly when it reduced the view's return. | The comparison removes a fee twice in one shape and not at all in the mirror shape. Decided as AD-6. | R-004 (D4-01) |
| **ADR-0040** and **ADR-0030**, the plan's sum and its write rules | One function in the context sums a plan; the editor and the engine both call it. What a blank parent over targeted children counts as is AD-3. The plan save's rules move into `Targets`, so the API writes the plan by the same rules: a category follows its positions; a category whose last position target is cleared loses its row; a blank category field clears its row; an unchanged stale position row is left as it is. | The editor says 100 % where every other surface says 60 % and divides by it; a copy over an existing plan stores 140 %. | R-003 (O4-01), R-057 (O4-03), R-014 (G1-01). R-015 (O4-02), the 110 % case, is a stale copy of the tree in the editor and is fixed without an amendment. |
| **ADR-0039** and **ADR-0049 §5**, what a stored answer depends on | The policy findings are keyed under the global basis. The exchange-rate radius includes portfolios with a booking in a foreign currency. The freshness test reads the registry instead of a hand-kept list. The activation measurement is renewed and its table recorded. A journaled kind is classified when it is introduced. | Two stored answers outlive a write that changes them. | R-007 (V1-01), R-008 (V1-02), R-152 (V1-04), R-067 (V1-06), R-061 (A1-03). R-153 (V1-05) needs no amendment. |

Three more add a rule with an S2 fix and are decided with that fix: ADR-0023
(R-012 (D2-03): a category without a target has no drift and no hint), ADR-0047
(R-021 (O1-01): no trailing return when the newest close is older than the window;
R-025 (O1-04), only if the API is to serve the series: the averages are computed
over the stored history) and ADR-0046
(R-022 (G2-01): which figure is printed beside a benchmark whose history starts
inside the period).

The plan family has one more record to bring up to the code: ADR-0027 §3 and
the API reference still speak of a cash target per plan version, while the
built and documented rule is that the cash target is the view's (R-136 (G1-02)).
"Delete plan" then has to say what it leaves behind (R-027 (G1-03)).

ADR-0050 changes no decision. It gets dated notes: under §16 invariant 9,
that a flow across a view's boundary counts for all three merges (R-016 (G4-03));
under §1, that the two account merges are one protocol and the cash merge
reads `MergeFigures` as the depot merge does (R-110 (G4-01)); optionally in §10, that
the digest covers the third depots' rows the cost fold reads. The fixes of
R-005 (A4-01) and R-006 (G4-02) need no amendment: invariant 12 already asks for them.

All amendments by ADR, generated from the findings:

| ADR | Findings | What each asks of it (first six) |
|---|---|---|
| ADR-0001 | R-044, R-073, R-074, R-075, R-078, R-079, R-080, R-081, R-082, R-083, R-084, R-085, R-086, R-088, R-106, R-111, R-113, R-114, R-118, R-120, R-124, R-141 | R-044: ADR-0001; R-073: ADR-0001; R-074: ADR-0001; R-075: ADR-0001; R-078: ADR-0001; R-079: ADR-0001 (direction between contexts), with a note in ADR-0050 §4/§9/§11 … |
| ADR-0002 | R-097, R-112, R-147 | R-097: ADR-0002; R-112: ADR-0002; R-147: ADR-0026 (compensating controls); one sentence in ADR-0002 |
| ADR-0004 | R-002 | R-002: ADR-0004 (or ADR-0010) |
| ADR-0007 | R-036 | R-036: ADR-0007 |
| ADR-0008 | R-028 | R-028: ADR-0008 only if plans on built-in trees are refused; otherwise none (design record and pinned test change) |
| ADR-0010 | R-001, R-002, R-131, R-138 | R-001: ADR-0010; R-002: ADR-0004 (or ADR-0010); R-131: ADR-0010; R-138: ADR-0010 (dated note correcting :129-130) |
| ADR-0011 | R-128, R-134 | R-128: ADR-0011; R-134: ADR-0011 |
| ADR-0015 | R-017, R-043, R-133 | R-017: ADR-0015 (a note naming the preview as a reader); ADR-0050 §9 only if the preview also states the base-currency result …; R-043: ADR-0015 (dated note: the function's new name at :231 and :377, the unreachable branch); R-133: ADR-0015 |
| ADR-0016 | R-042, R-060, R-135 | R-042: ADR-0016 §3 (one sentence); R-060: none for the moves; ADR-0016 §3 only if the rounding stays API-side; R-135: ADR-0016 (amend §4 and §6) |
| ADR-0020 | R-136 | R-136: ADR-0027 §3 (and one sentence of ADR-0020) |
| ADR-0023 | R-012 | R-012: ADR-0023 |
| ADR-0026 | R-147 | R-147: ADR-0026 (compensating controls); one sentence in ADR-0002 |
| ADR-0027 | R-004, R-027, R-136 | R-004: ADR-0027 (one sentence in ADR-0051 §1); R-027: none beyond R-136 (G1-02)'s ADR-0027 amendment; the cash-only drift arithmetic is a question for ADR-0040; R-136: ADR-0027 §3 (and one sentence of ADR-0020) |
| ADR-0028 | R-009, R-033 | R-009: ADR-0028 §3 (dated note: its "ends in a catch-all" is out of date); otherwise none if the fold moves into the Ledger; R-033: None if the walk rounds per depot; ADR-0028 §3 if the per-security rounding is kept |
| ADR-0029 | R-102 | R-102: ADR-0029 section 3 |
| ADR-0030 | R-003, R-014, R-057 | R-003: ADR-0040 (§1, §2), with a note on ADR-0030 §4; R-014: none on its own; one sentence in R-057 (O4-03)'s ADR-0030 amendment; R-057: ADR-0030 (§2, §3, §4) |
| ADR-0031 | R-041, R-100, R-120 | R-041: ADR-0031; R-100: ADR-0031 section 6; R-120: ADR-0001 (where wire shapes live); a note on ADR-0031; architecture.md:610, :829, :896-900 |
| ADR-0032 | R-008, R-071, R-072 | R-008: ADR-0039 (dated note widening the exchange-rate row carried from ADR-0032 §3.2); R-071: ADR-0039 (ADR-0032 §5 by reference); R-072: ADR-0039 (ADR-0032 §5 by reference) |
| ADR-0033 | R-124 | R-124: ADR-0001 (dated note, with R-084 (A6-01)'s amendment); ADR-0033 path lines |
| ADR-0034 | R-054 | R-054: ADR-0034 |
| ADR-0035 | R-062, R-081 | R-062: ADR-0035; R-081: ADR-0035 (the holdings and trades reads join the one pricing pass); ADR-0001 for the direction |
| ADR-0037 | R-122 | R-122: ADR-0037 amendment or a new ADR (where the browser client lives and how it is tested) |
| ADR-0039 | R-008, R-061, R-067, R-070, R-071, R-072, R-152 | R-008: ADR-0039 (dated note widening the exchange-rate row carried from ADR-0032 §3.2); R-061: ADR-0039; R-067: ADR-0039 (measurement table amendment) and ADR-0047 (§8); R-070: ADR-0039 (optional: state the fresh case in the amendment I34 step 2 needs); R-071: ADR-0039 (ADR-0032 §5 by reference); R-072: ADR-0039 (ADR-0032 §5 by reference) … |
| ADR-0040 | R-003, R-027 | R-003: ADR-0040 (§1, §2), with a note on ADR-0030 §4; R-027: none beyond R-136 (G1-02)'s ADR-0027 amendment; the cash-only drift arithmetic is a question for ADR-0040 |
| ADR-0044 | R-020, R-045, R-150, R-151 | R-020: ADR-0044 §8 for a summary default; the prompt fix alone (size S) needs none; R-045: ADR-0044 §4 (and ADR-0048 §6 for events); answers #950, the owner's decision; R-150: ADR-0044 §8; R-151: ADR-0044 §8 (a version cursor); tightening the meta-test needs none |
| ADR-0045 | R-089 | R-089: none for the store edge; ADR-0045 §2 only if the secret's configuration moves |
| ADR-0046 | R-022, R-037 | R-022: ADR-0046; R-037: ADR-0055 §3 (or ADR-0046 §2 if one rule is to own both; then size M, risk tier) |
| ADR-0047 | R-021, R-025, R-038, R-046, R-049, R-052, R-067, R-130, R-132, R-152 | R-021: ADR-0047; R-025: ADR-0047 only if the API serves the series; none for a page read; R-038: ADR-0047 §6 (only if the meaning of window.start_date is written into the record); R-046: ADR-0047 §6 (for the move; the two corrections alone need none); R-049: ADR-0047, together with R-021 (O1-01); R-052: ADR-0047 … |
| ADR-0048 | R-045, R-101 | R-045: ADR-0044 §4 (and ADR-0048 §6 for events); answers #950, the owner's decision; R-101: ADR-0048 (what 'by hand' means); planning lines for quotes and the classification rename |
| ADR-0049 | R-007, R-129, R-152 | R-007: ADR-0049 (§5, the basis); R-129: ADR-0049; R-152: ADR-0047 §6 and ADR-0049 §5 (dated notes for the payload additions), or ADR-0039 I4 if its scope is narrowed |
| ADR-0050 | R-016, R-017, R-030, R-055, R-079, R-110, R-115, R-137, R-139 | R-016: ADR-0050 (dated note under §16 invariant 9); R-017: ADR-0015 (a note naming the preview as a reader); ADR-0050 §9 only if the preview also states the base-currency result …; R-030: ADR-0050 §3; R-055: ADR-0050 (note on the 2026-10-09 building order); none for the small alternative of correcting the moduledoc; R-079: ADR-0001 (direction between contexts), with a note in ADR-0050 §4/§9/§11; R-110: ADR-0050 (dated note under §1; no decision changes) … |
| ADR-0051 | R-004, R-066 | R-004: ADR-0027 (one sentence in ADR-0051 §1); R-066: ADR-0051 (§12, dated note) |
| ADR-0053 | R-040 | R-040: ADR-0053 (or a signed plan decision, as Sprint 22's D-5) |
| ADR-0055 | R-037 | R-037: ADR-0055 §3 (or ADR-0046 §2 if one rule is to own both; then size M, risk tier) |
| ADR-0056 | R-086, R-127 | R-086: ADR-0056 (one sentence); the direction in ADR-0001; R-127: ADR-0056 |

## 10. Decisions

AD-1 to AD-4 are put to the owner: AD-4 is scope and the owner's by AGENTS.md
("Ask the owner only what only the owner knows"); AD-1 to AD-3 by the audit's
judgment, because in each two recorded rules disagree and either choice moves
a figure the owner steers by. AD-5 to AD-7 are decided here with their
reasons; a comment flips any of them. AD-8 is a proposal for the filing and
waits for the owner's word. AD-9 concerns R-018 only and was held with it; the
owner decided it on 2026-11-24.

Not needed now, they arrive with the plan that schedules their work: the
boards for the paged Transactions history, for the merge previews' form and
for R-022 (G2-01), R-023 (G2-02) and R-024 (O1-02); and, only if wanted, moving the inline browser
client (AD-7).

**AD-1. A booking dated after today (R-002 (D1-01)). Put to you: nothing written
decides it, and either choice moves a figure you steer by.**

- (a) It counts from its date. Every current read (balance, positions,
  holdings, held set, valuation) folds bookings up to today, as the walk
  already does. Size M, risk tier.
- (b) Every stored booking counts at once, the walk stays the exception, and a
  read names the bookings dated ahead. Size S.
- (c) The writers refuse a date after today. Size S, but rows already stored
  and imported files remain to decide. This is the one option that changes
  how data is booked.
- **Recommended: (a), with a data-quality row that lists the bookings dated
  ahead.** Then the valuation and the walk agree by construction, nothing
  stored has to be refused or migrated, an import file with a date ahead
  still loads, and a mistyped year is visible instead of silent.
- Cost of (a): a booking dated ahead no longer shows in the balance or the
  holdings until its day. That is right for a value-dated booking. It also
  meets a default installation: with `TZ` left empty the server's day is UTC,
  so east of UTC a booking typed with the local date just after local
  midnight is "ahead" until midnight UTC and would not show until then. The
  data-quality row names it, and setting `TZ` removes the case.

**AD-2. Which price is today's price (R-001 (D2-01)). Put to you: two recorded rules
disagree, and either choice moves a served money figure.**

The first choice is the order among the observations of one security:

- (a) The valuation follows the walk: the newest observation by date wins,
  whether it is a stored close, a booking's price or a priced delivery. The
  Wealth total changes for positions traded after their last close: until
  the next close for a synced security, for good where the feed has stopped
  or closes are kept by hand. A position that came in by a priced delivery
  and has no close becomes valued.
- (b) The walk follows the valuation: a stored close of any age wins and is
  flagged when stale; a trade price counts only where no close exists. The
  stored TTWROR history changes, and a test pins the walk's present rule. A
  priced delivery keeps seeding the walk (ADR-0010, amendment of
  2026-09-15), so the valuation's trade fallback has to count it too; that
  step removes the unvalued-delivery shape under either choice.
- **Recommended: (a).** By itself it moves no stored history: the walk keeps
  the order ADR-0010 words and tests.

A second choice rides on it: whose bookings give a price. The valuation takes
the latest trade on the whole instance (#406, on purpose), the walk the
walked portfolio's own (ADR-0010). One recorded rule has to yield.

- (i) The whole instance, in both. A price is a fact about the security, and
  the security page and the totals keep agreeing. Cost: the walk's stored
  history changes for every security whose newest observation is a trade in
  another portfolio, its computation version moves, and a trade in one
  portfolio must then supersede the stored walk of every portfolio that
  holds the security (the dependency R-007 (V1-01) finds missing for the policy
  findings).
- (ii) The portfolio's own, in both. No stored history moves. Cost: #406 is
  taken back; a security held but never traded in a portfolio is unvalued in
  its total while the security page shows a price.
- With one portfolio on the instance the two give the same figures.
- **Recommended: leave this half open for now.** ADR-0024 made the portfolio
  a compatibility entity that no screen creates, so on an instance with one
  portfolio nothing differs. The ADR-0010 amendment records that the two
  engines differ here, and the one price function takes "whose bookings" as
  an argument. Decide between (i) and (ii) the day a second portfolio
  matters.

**AD-3. What a plan sums to when a parent category is blank (R-003 (O4-01)). Put to
you: it moves the base every drift figure is measured against.** A plan with a
blank parent over targeted children reads 100 % in the editor. The engine,
the API and both pages read the same plan as 60 % with 40 % unallocated, and
divide every target by that 60 %.

- (a) A blank parent counts with the sum of its children's targets, on every
  surface.
- (b) Only targets typed at the top level count, on every surface; the editor
  then shows 60 % and the remainder row. The drift figures do not change:
  the engine still divides a targeted child under a blank parent by the 60 %
  that leaves it out (41.67 % and 25 % in the run), so (b) needs a second
  rule for such a child before the drift is right.
- **Recommended: (a).** The built-in asset-class tree has group roots whose
  children are the only codes a security can carry, so a plan typed where the
  securities sit has this shape on any instance. The editor's own user story
  asks for it. And a plan the operator typed to 100 % should not be measured
  as if 40 % of it were unallocated.
- One decided reading moves under (a): a plan with no top-level target at
  all. The engine reads it today as 0 % at the top level with "targets deeper
  in the tree" beside it (ADR-0030's fix round, pinned in
  `allocation_test.exs`); the editor reads 100 %. Under (a) it reads the
  children's sum on every surface, and its drift figures move when that sum
  is below 100 %. Under (b) it is the editor that changes for such a plan.
- Not decided by (a) or (b), and yours to read with the same ADR-0040
  amendment: a view that steers by a cash target alone. The engine takes the
  cash target as the whole top-level sum and divides by it, so cash held at
  8 % against a stored 5 % reads 92 pp below target (R-027 (G1-03)). ADR-0040 does
  not mention the cash target and no test pins the case. The question is
  whether a cash target alone opens target mode, and what its drift is
  measured against.

**AD-4. Coverage both ways (R-099 (M1-06), R-100 (M2-02) to R-104 (M2-06), R-059 (O4-08)). Yours: three scope
questions; the rest is decided.** AGENTS.md lets a capability ship over API
and MCP alone when its human view lands in the same or the next sprint. For
the rows below no record in the repository gives a reason or a deadline; the
PR bodies, where the rule lets the reason stand, were not read.

Decided, a comment flips:

- The classification rename gets a menu entry (size S).
- The three Transactions figures are served over the API and MCP (R-059 (O4-08)). So
  is the sale preview (R-104 (M2-06)), after a planning line: it borders idea F5
  (limit price and per-trade tax estimate, gated), and the line says that the
  preview is the gross figure the screen already shows, is no tax figure and
  prepares no order.
- The API accepts a colour-only write on a built-in category (R-103 (M2-05), size S).
- The three by-id reads get a tool, or the two sentences that send an agent
  to them are reworded (R-099 (M1-06), size S). The three logo writes of the same
  finding are already issue #1413, and the missing logo-status tool has a
  stated reason.
- The tax path stays agent-side by your decision of 2026-08-05, and ADR-0031
  §6 gains the sentence (R-100 (M2-02)).

Yours, each answered "a screen in a named sprint" or "stays agent-side, with
one sentence in its ADR":

1. Hand entry of security events on the Dates tab (R-101 (M2-03); size M, a board).
2. A row editor for hand-kept quotes (R-101 (M2-03); size M).
3. "Record ISIN change" and "Remove" for a former ISIN on the security page
   (R-102 (M2-04); size M, a board). The screen records a change only inside an
   import or a merge and never deletes an alias, so ADR-0029 §3, which
   promises parity, is amended either way.

**Recommended:** 1 and 2 stay agent-side for now, with the sentence, in the
shape ADR-0056 D8 uses for the feeds ("stays agent-side, to flip: ..."); 3
gets its screen, because ADR-0029 §3 already promised it.

**AD-5. ADR-0001 is amended, not replaced.** The amendment is the first row
of section 9. Reason: the one seam it states holds, so the decision stands;
what is missing is the part it never wrote. The gate comes in the same PR as
the text, with today's violations as its allowlist, so the list can only
shrink. The later `main` already has the gate for one direction (a context
naming the web layer); the amendment builds on it.

**AD-6. In a view, a trade's fee is a transaction cost when the shares it
bought or sold are in the view (R-004 (D4-01)).** Today it counts when the cash
account that paid it is in the view. Reason: the three test worlds of R-004 (D4-01)
show that a fee lowers a view's return exactly when the shares are in the
view; when only the cash account is, the fee has already left the view
inside the outflow and the comparison takes it out a second time. The
narrower alternative (count a fee only when shares and cash account are both
in the view) still states no cost for a fee the view's return did bear.

It is decided here although it moves served figures of view-bound comparisons
(the pre-cost return, the transaction costs, the recovery state), because the
runs leave one rule that makes the arithmetic true. It is risk-tier work and
it moves the computation versions of the two performance analytics. One
consequence: the benchmark comparison's "costs paid" keeps the rule
ADR-0046's amendment of 2026-11-04 gave it (a fee counts where its cash
account counts), so for a trade that straddles a view the Snapshots
comparison and the benchmark card will name different costs. If you want one
rule for both, say so; it then amends ADR-0046 as well.

**AD-7. Splits are lanes a plan schedules, one module at a time, never done
on the way.** Reason: I38's own rule and "Stay in scope". Order: section 11,
step 5. The figure fixes of steps 1 to 3 land before any split; a fix still
open when its module's lane starts lands with its red test before the first
move. What each split needs written down first is in its section; in short:

- The ADR-0001 amendment (AD-5) carries two more paragraphs, so that no page
  split needs an ADR of its own: how a page is organised (a tab body is a
  markup-only module that reads nothing; a figure comes from a context
  function; a handler that writes stays on the page), and where wire shapes
  live (one plain module per resource family beside the controllers, which
  supersedes the single-presenter rule `json.ex` has already left three
  times, R-120 (O6-01)).
- `tools.ts` needs a dated amendment of ADR-0002 (the layout, the import
  rule, the gates that read the file by name). The imports page needs a note
  on ADR-0050 for the one step that moves import rules into the context.
- **The inline browser client of `layout_view.ex` stays where it is.** The
  security triage of 2026-09-05 prescribed moving it to one static file;
  Sprint 11 shipped the per-request nonce instead. A split would reopen that
  Sprint 11 choice and return to the triage's shape, which is the owner's to
  decide; section 7 says what it would need. R-122 (O7-03) stays an S3 until then.

**AD-8. Filing, once adopted. A proposal; it waits for the owner's word.** The
"Stay in scope" rule files an S1 as an issue, an S2 as an issue when a diff's
code reaches it and otherwise as a polish-list line, and an S3 as a
polish-list line. ADR-0026's amendment of 2026-11-01 adds that the severity
decides where a finding is recorded, never whether, and that nothing is
withheld. Proposed:

- **29 issues, 27 of them on adoption**: the 10 S1 and the 19 S2. An audit
  has no diff, so every S2 is an issue, as in lens 1. Two of the S2 are held
  rows and are filed with their fix, so adoption files 27.
- **One line for every S3, 130 in all, 128 of them on adoption.** Two are
  held rows and get their line with their fix, so adoption adds 128. A row
  that a screen shows goes on that screen's polish list. A row no screen
  shows goes on one list of the work that carries it, so that the plan for
  that work finds it:
  - the ADR-0001 amendment: the 14 seam rows;
  - each module's split plan: the "modules with several jobs" rows that
    section 7 carries. Seven have no split section. R-106 (A5-08) gets its line on
    the list of the ADR-0001 amendment, where section 9 names it. R-109 (G1-07),
    `targets.ex`, gets its line with the plan family's work (section 11,
    step 2), which moves more rules into that module. The other five get
    theirs on the list of unpinned copies: R-107 (A6-06), R-108 (D4-07), R-110 (G4-01), R-111 (G4-05),
    R-121 (O6-02). R-122 (O7-03) waits for AD-7;
  - one docs PR: the 12 "records behind the code" rows. Six of them
    state a choice between bringing the record to the code and the code to
    the record, and are filed with their recommended answer, as the rule
    orders: R-127 (A6-08), R-129 (D2-02), R-130 (D3-01), R-133 (D4-02), R-135 (D5-01), R-138 (O8-06). R-136 (G1-02) is not one of
    them: its rule is recorded, and its record follows. Its line names a
    code half that is not small (size M): the plans read stops serving the
    per-version cash column, the duplicate stops copying it, and the two
    option branches only tests reach go with their tests. That half rides
    with step 2 of section 11, beside R-027 (G1-03), not with the docs PR. For
    R-130 (D3-01), and for
    R-041 (D4-05) among the two-path rows, the choice is which formula is the
    decided one. Recommended there: the code, its payload basis and its
    tests stand, and the ADR sentence follows. Five rows carry a small code
    or test half beside their sentence, and their line names it, so that
    the docs PR does not drop it: R-128 (D1-05) (a test that walks every booking
    kind), R-129 (D2-02) (the Risk screen's and the rule dialog's wording), R-131 (D3-02)
    (one shared day-factor function), R-134 (D4-04) (an explicit kind list and a
    meta-test) and R-138 (O8-06) (dead functions removed);
  - one list of unpinned copies and gates: the pin rows of section 6's
    theme, the two-path rows that agree today, and the 5 compile-time rows.
- **Four held rows get their issue or their line with the merge that fixes
  them**, as the security triage's "Disclosure handling" orders: R-018 and
  R-019, both S2 (the class of N-07 and N-08), and R-146 and R-148, both S3
  (they say what passes a gate). Done with #1489: R-018 and R-019 are filed
  as issues closed as completed; R-146 gets its checked line with the pins
  of step 4 and R-148 with the securities page's split in step 5.

Reason: the amendment of 2026-11-01 stopped a full issue and story per
finding. A line per row keeps "never whether"; a list per piece of work is
where the plan for that work will look.

**AD-9. A cap on a word that is no asset class is refused, and the risk read
echoes the caps it applied (R-018 (G3-02)). Put to the owner beside D-4 of the
security triage.** The risk read's `asset_class_caps` refuses a key outside
the 16 asset-class codes with a 422 naming it, as `status=` and `level=` are
refused elsewhere; the payload echoes the caps and the lines applied
(R-095 (G3-01)'s fix); the tool names the codes; the three threshold maps
refuse an unknown inner key the same way. No ADR amendment: ADR-0049 §7 keeps
the parameter as it is, a refusal of a value outside its set is the rule the
API already states, and the new 422 is a contract entry (ADR-0044 §8).
Lens 1's D-4 as worded covers an argument a route does not take; this is a
key the route takes and cannot read, so it needs its own yes. It costs
compatibility as D-4 does: a call that got an empty list gets a 422.
Recommended: yes, beside D-4.

**Decided 2026-11-24 by the owner: yes, as recommended.** Fixed in #1489
(`f07b0d42` for the read, `baf9c5f9` for the tool), in contract version 32:
the read refuses such a key and an unknown inner key of the three threshold
maps, it echoes the caps it applied, and the tool's description says a cap is
keyed by an asset class code. Echoing the lines the lens applied stays with
R-095 (G3-01).

## 11. Proposed order of work

| Step | Theme | Holds | Gate |
|---|---|---|---|
| 1 | One figure, one owner: the domain | The price on a day (R-001 (D2-01)), the as-of cut (R-002 (D1-01), R-093 (D4-06)), a view's trade costs (R-004 (D4-01)), the two invalidations (R-007 (V1-01), R-008 (V1-02)), and the pin that holds the Ledger's twin rules together (R-035 (D1-06)). Risk tier throughout. About 9 agent-days. | AD-1, AD-2 |
| 2 | One figure, one owner: plans and allocation | The plan's sum and write rules into `Targets` (R-003 (O4-01), R-057 (O4-03), R-014 (G1-01), R-015 (O4-02)), "targeted" decided once by the engine's own flag (R-013 (A2-03), R-012 (D2-03)), and the plan's life cycle on the screen: what "Delete plan" leaves and which plan it deletes (R-027 (G1-03), R-029 (G1-05)), the link on a built-in tree (R-028 (G1-04)). About 8 agent-days. | AD-3 |
| 3 | One figure, one owner: previews and pages | The merge previews read the Ledger and `MergeFigures` (R-005 (A4-01), R-006 (G4-02), R-016 (G4-03), R-017 (A4-02)). The pages show the context's figure (R-009 (A2-02), R-010 (O2-01), R-022 (G2-01), R-023 (G2-02), R-021 (O1-01), R-024 (O1-02), R-025 (O1-04), R-026 (O2-04)). The parity pin for page figures (R-048 (D5-04)). About 14 agent-days; the two halves can be two sprints. Six fixes are risk tier. | none now; three boards (R-022 (G2-01), R-023 (G2-02), R-024 (O1-02)) and the ADR-0046 and ADR-0047 notes ride its plan |
| 4 | Seams written down and gated | The ADR-0001 amendment with its gate (AD-5), Gettext out of the web layer or recorded as the exception (R-073 (A1-01)), the pins of section 6 that guard a seam or a contract (R-141 (A5-04), R-142 (A6-04), R-144 (M1-01), R-098 (M1-03), R-145 (M1-04), R-147 (M2-01), R-152 (V1-04), R-153 (V1-05)), and the docs PR for the records behind the code. About 11 agent-days. | AD-5 as written |
| 5 | Splits, one module per sprint | First the Transactions page, because its S2 (R-011 (O4-04)) is fixed only by the split's paging. Then the pages whose figure fixes landed in steps 2 and 3: the plan editor's page, the securities page, the Wealth page, the imports page. Then the companion (`tools.ts`) and the serializer (`json.ex`). The Ledger and the walk last, once the fixes of step 1 have settled. Nine modules are named; the other ten of section 7 follow in a later plan. No size is given: at one module per sprint this is at least nine sprints. | AD-4 for the coverage rows; AD-7 |

An agent-day is one day of one implementation session at the sizes of
section 6 (S under a day, M one to three, L more). It is an estimate, not a
calendar promise.

The repeated reads of section 3.5 ride with the page that makes them where
that page is split (R-062 (O1-03) with securities, R-063 (O2-03) with Wealth). R-066 (V1-03) is I34's
first step and is scheduled with I34. R-068 (V2-02) is a fix of its own, because no
split of the Risk page is proposed.

R-020 (O6-03): its small step (the prompt calls the version read instead) can
ride with Lane C of lens 1's Batch 1; a summary default for the read needs an
amendment of ADR-0044 §8.

Two agent-contract S2 (R-018 (G3-02), R-019 (A3-02)) belong in lens 1's first
sprint, its Batch 1. They are the sibling of its refused instead of
dropped arguments (N-07, N-08), for a value the route takes but cannot read.
Lens 1's decision D-4 as worded covers an argument a route does not take, so
the new refusal of R-018 (G3-02) needs the owner's yes beside it (AD-9). Both
were fixed in #1489, with lens 1's held rows, on 2026-11-25.

Why this order: a wrong figure that two engines disagree on is met every day
and by both users, so it comes first. The plan family is next because a save
can store a plan that sums to 140 %. Previews and pages follow: the page
figures are on the screen only, and the four merge-preview figures (R-005 (A4-01),
R-006 (G4-02), R-016 (G4-03), R-017 (A4-02)), which the API and the MCP tools serve as well, are read
only when a merge is prepared. The seams come before the splits because a
split without the rule would move code across lines nobody has drawn.

## 12. Unconfirmed list

Kept apart from the findings, as the audit's brief orders.

- **Refuted: none. Inconclusive: none.**
  Every candidate was confirmed in some form. Where a verifier confirmed less than the reader
  claimed, the entry says so in its notes; the title is always the
  verifier's.
- **Leads: 261.** Suspicions a reader wrote down and nobody traced to
  the end. They are listed per lane at the end of the private evidence.
- **Six predicted defects and two gate gaps from the split reviews, without a
  key and not run.** None is among the leads. The six defects are stated in
  section 7 only.
  Transactions page: after an edit is saved into a row that is gone, the
  drawer keeps that row's mode, so the next new booking may reach the ledger
  in the deleted row's currency (S2 if it reproduces, S1 if the ledger
  accepts the write). Plan editor: any search text makes it warn "no
  assigned positions" (S2 if it reproduces). Cash flow: "After the sale" may
  keep figures from older rates after a rate backfill (S2 if it reproduces).
  Securities page: the Overview note editor is closed by any reload; a
  refused research entry is drawn into the next security's form; the Quotes
  tab names a range it does not show (none graded). Each needs a
  verification run before it is filed. The two gate gaps are stated in the
  private report only and are input for lens 3 (the review of the tests,
  idea row I39).
- **Severity changed after verification.** The verifier's grade and the final
  one:

| ID | Verifier | Final | Finding |
|---|---|---|---|
| R-021 (O1-01) | S1 | S2 | A security whose newest close is over a year old reads "1Y 0.0%" on the Overview and "Momentum not computable" on the Chart tab; the list's 1M and 1Y columns … |
| R-022 (G2-01) | S1 | S2 | For a benchmark whose stored history starts inside the shown period, the Wealth chart's tooltip and the table's benchmark column print the anchored level (1 + … |
| R-040 (D4-03) | S2 | S3 | A dividend's fee is a cost in the Costs report and no part of Income's gross, so gross is before taxes but after fees and gross minus the booking's costs is … |
| R-053 (O2-02) | S2 | S3 | The Wealth page counts its data-quality rows itself, by another retired rule and another unit (distinct names) than the valuation payload's trade_priced_count … |
| R-066 (V1-03) | S2 | S3 | On Wealth's stacked chart every level, sort, scale and filter change at one period runs a full windowed walk although the walk reads none of them, and each new … |
| R-068 (V2-02) | S2 | S3 | The Risk page computes its lens, its metrics walk and its findings inside mount/3, in the dead render and again on the connected mount, with no pending state … |
| R-100 (M2-02) | S2 | S3 | A statement that shows church tax cannot be recorded on the Tax page: the save is refused for a rate the form does not carry, and the taxpayer profile that … |
| R-129 (D2-02) | S2 | S3 | A weight rule on a security and one on a category are shares of two different totals, while the Risk screen, the rule dialog, the guide, the API reference, the … |
| R-133 (D4-02) | S2 | S3 | A foreign-currency booking on a day without a stored hub rate is a figure in Income, the walk and the contribution (last earlier rate) and excluded in Costs … |
| R-136 (G1-02) | S2 | S3 | A plan's cash target has two stored homes: every computing reader and every door use the view's cash-only plan row, while the plans read, the duplicate and … |
| R-144 (M1-01) | S2 | S3 | The docs gate reads 40 of the 166 MCP tool declarations and 170 of the 182 API routes, so a tool or route declared across two lines can ship without a line in … |
| R-154 (O3-02) | S2 | S3 | A confirm that does not reach the done page drops the mapping's recount flag: a recount still due is never run, and a diverged apply counts again without the … |
| R-157 (O7-01) | S2 | S3 | The x on a Snapshots problem note does nothing: SnapshotsLive renders the shared result slot and has no clause for the dismiss_result event the slot's x sends |

  The two S1 that became S2 are right on a basis of their own or stand beside
  a stale marker; a reader who draws the line of section 2 elsewhere will
  grade them S1. The S2 that became S3 each met a recorded decision the
  verifier had missed, or a reach that needs a refused confirm, an error path
  or a state the page's own flows prevent. R-144 (M1-01) is the exception: nothing
  recorded and no narrow reach, but nothing is undocumented today, and no
  state of `main` kept a gap through the gate's blind spot.
- **Merged duplicates.** The same defect found by two lanes, or by three
  (R-001 (D2-01), R-075 (A1-05)); every later candidate was merged into the one that carries
  the finding:

| Candidate | Merged into | Its title as the lane wrote it |
|---|---|---|
| R-003 (A2-01) | R-003 (O4-01) | The plan editor computes its own sum, complete mark and unallocated remainder in the LiveView by another rule than the allocation read: one stored … |
| R-057 (A2-04) | R-057 (O4-03) | What a plan save writes is decided in the LiveView (the category follows its positions, which rows are cleared, which stale rows are skipped); the … |
| R-048 (A2-07) | R-048 (D5-04) | Eight more figures are derived in LiveViews from context payloads (97 Decimal operations in 21 web files); they agree with the context today and the … |
| R-121 (A3-04) | R-121 (O6-02) | The API layer has no shared answer helpers: 37 private 404 answers, 35 private 422 answers |
| R-120 (A3-05) | R-120 (O6-01) | The serializer is one 3,014-line module over ten namespaces, three sibling modules and local maps in 18 further files; one context result is mapped … |
| R-060 (A3-06) | R-060 (O6-09) | Thirteen places in the serializer and the controllers derive a field instead of serialising one; all agree with their context today |
| R-084 (A5-01) | R-084 (A6-01) | The five contexts have no dependency order: 18 calls, 14 queries and 7 schema references point upwards, and all five sit in one 96-file xref cycle |
| R-073 (A5-06) | R-073 (A1-01) | Seven context files (four in Catalog) compile against the web layer's Gettext backend; the scout's count of contexts into the web layer misses them |
| R-075 (A5-07) | R-075 (A1-05) | ADR-0001 names four contexts and the published overview six; the tree has thirteen, and ADR-0001's line for Portfolios describes 3.7 % of it |
| R-075 (A6-09) | R-075 (A1-05) | The published architecture overview names 6 of 13 contexts and 7 of 19 supervised processes; News, Knowledge, Predictions, Tax, Buckets, Lifecycle … |
| R-001 (D1-02) | R-001 (D2-01) | One holding has two prices today: the valuation reads latest quote, else the last buy or sell of any portfolio; the walk reads the latest of quote … |
| R-145 (O6-06) | R-145 (M1-04) | The companion keeps hand copies of the three fields= whitelists (82 names); its tests check 14 of the 32 security names and none of the 50 … |
| R-152 (O6-07) | R-152 (V1-04) | ADR-0039's freshness meta-test names three serializer functions by hand; four of the eight registered analytics are outside it and three of their … |
| R-001 (O8-01) | R-001 (D2-01) | The performance walk prices a held security by another rule than the valuation, so the walk's value of today and the valuation's total differ for the … |
| R-066 (V2-01) | R-066 (V1-03) | On Wealth's stacked chart one window walk is run for the contribution table, again for the bands, and again for every level, sort, scale, filter or … |

## 13. Limits and what was cut

- **The run was interrupted four times and resumed each time.** Twice the
  working files were gone. After the first loss, the reader files, the nine
  split reviews and the evidence of two lanes (D2 and O1) were
  rebuilt from the agents' transcripts. The evidence of the three other lanes
  verified by then (O4, A2 and A4, three S1 among them) could
  not be rebuilt, so those lanes were verified a second time from the reader
  files. The second verification confirmed the same findings.
- **The second readings of seven findings (ten readings) were written against
  the first verification**, whose files were lost: R-003 (O4-01), R-005 (A4-01), R-009 (A2-02), R-011 (O4-04),
  R-013 (A2-03), R-015 (O4-02), R-017 (A4-02). Where one
  cites a case by number or letter ("case 6", "plan C") or a figure that the
  printed run does not have, that case was in the lost evidence; the entry
  carries a note with the printed run's counterpart.
- **Six candidates reached a verifier only after the report's review.** The
  registry of lane G1 held one of its seven candidates. The review found the
  gap; the six were verified then (all six confirmed: three S2 and three S3 after their second readings. They are R-027 to R-029 and three rows of section 6; the audit lead did not re-run them).
- **119 of the 130 S3 had no second reading.** The others
  are the S2 that a second reading lowered.
- **One completeness round, not two.** The critic's four gaps were all read
  (G1 to G4). Nobody asked afterwards what those four lanes missed.
- **"What holds" is by reading.** The statements of section 8 rest on the
  readers' searches, counts and traces. "Pinned by a test" there means the
  test exists and was read; the lanes did not run the suite.
- **No browser.** Pages were rendered through the LiveView test harness and
  read as HTML. A defect that needs the browser's own behaviour (R-158 (O7-02)'s
  dropped zoom events, the inline client of R-122 (O7-03)) was read in the source and
  traced, not clicked.
- **The companion was not run for this lens.** The test containers have no
  Node. Companion findings rest on reading and on counts executed over its
  source; R-020 (O6-03)'s byte counts were measured on the API.
- **PR bodies were not read.** The containers had no route out. "No record
  gives a reason" in a coverage finding means no record in the repository.
- **Timings are relative.** They were measured in a container on one
  machine, on the synthetic ledger the measure task seeds or on a seeded
  ledger. The verifier of R-066 (V1-03) found that container about four times faster
  than the machine behind ADR-0039's table.
- **The call graph and the xref figures are the test build's.** The dev build
  has 149 compile-time edges against the 119 of section 2 (R-091 (A7-05)), so
  recompile sets in daily work are larger than stated.
- **Not run as gates:** Credo, Dialyzer, coverage and the browser tests. The
  full suite was run in a container copy as the control of a mutation check
  (R-139 (A4-06)): 6,435 tests, 12 failures, the same with and without the mutation
  and all the environment's (tests that call `python3`, `kill` or `git`
  where the container has none, or read files the copy left out). Those
  tests could not serve as evidence in the containers. Lens 3 measures the
  suite.
- **`main` moved on.** Section 4's last column reads `main` as of 2026-11-15
  for the S1 and S2 only. No S3 was held against it, and nothing was run
  there. Two S3 are known to be answered there by the rule review of
  2026-11-12: a test now fails when a context names the web layer outside
  its registered exceptions (R-074 (A1-02)), and the Gettext backend is registered as
  such an exception (R-073 (A1-01)).
  On 2026-11-24 the ten S1 were run again on `a1e54b18` (2026-11-23, 393
  commits after the audited commit) and all ten still stand; the S2 and S3
  were not held against that commit, and no lens read the 46 code files that
  are new since. The private evidence has the detail.
- **Sizes after a split are estimates.** So are the agent-days of section 11.
