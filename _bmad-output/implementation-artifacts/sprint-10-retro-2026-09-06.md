# Sprint 10 Retrospective — the perimeter, and a confirmation that never asked (2026-09-06)

**Status: written at close-out.** PR #773 was rebase-merged 2026-09-06
(07:12 UTC), 25 commits linear on `main`, head `b701613a`. The annotated
`0.10.0` tag is **prepared as an owner action** — the session's git proxy
refused the tag push again, the fourth sprint in a row; command under
"Close-out ledger". Planned, built, reviewed and merged inside 14 hours of
the triage being adopted.

## What shipped

One batch on one branch, one PR (#773), per the adopted plan
(sprint-plan-2026-09-05-sprint10.md) and the decision gate ADR-0045, signed
the same day the triage was adopted. Fourteen issues closed by the merge's
keywords, verified against the post-merge open-issue list: #758–#771. The
origin is a private whole-system security review of 2026-09-03; per the
triage's disclosure rule the public artifacts name fixes, and the fixtures
carry the concrete cases.

- **Lane P — the perimeter (#758, #759, #760, #761):** production binds
  loopback unless `PHX_BIND_ALL` says otherwise and says so in the log when
  it is open without a password; a `Host` outside the instance's own names
  is answered 421 ahead of the router and the static plug; the session
  cookie carries `Lax`/`HttpOnly` and `Secure` behind a TLS proxy, with the
  signing salts derived per installation from the secret instead of a
  literal every checkout shares; `PHX_FORCE_SSL` is a runtime opt-in. The
  documented deployment became a production release image with no secret
  defaults, and the bearer tokens must be at least 32 bytes and not a
  placeholder or the app refuses to boot.
- **Lane S — egress (#762, #763):** one deny-by-default `UrlPolicy` every
  server-side fetch of a caller- or provider-supplied URL passes before a
  socket opens (https only, no userinfo, public addresses only, per-source
  host lists, every redirect hop re-checked), and one bounded `Net.Http`
  every outbound client is built from (a byte cap enforced while the body
  streams, a connect timeout, a deadline on the whole request). Stored logo
  bytes are checked by their magic bytes, not the upstream's header.
- **Lane V — provenance (#766, #767):** `import_hash`, a note's `author`
  and the `machine_generated` marker are the system's to set; the public
  changeset refuses a caller-supplied hash and the API drops the body's
  claim. The tables the journal guard leaves unarmed became one closed,
  named list under the same meta-test.
- **Lane I — imports (#768, #769):** the parsers refuse hostile and
  malformed files as error values rather than exceptions, with a row cap and
  a bounded preview store keyed by a hash of the session token; a re-imported
  file lists every row it skipped, with the reason in the page's language.
- **Lane W — web/API hygiene (#770, #771):** `limit` on four list reads and
  their MCP tools, a cap on the quote upsert, constant-time token comparison
  with a per-source throttle (ten failures, doubling to 300 s, `Retry-After`),
  and generic API errors that no longer leak internal terms.
- **Lane A — authentication (#764, #765):** the optional single-password UI
  login of ADR-0045 — unset changes nothing, set it gates every browser route
  and every LiveView mount — plus confirmations on the four destructive
  controls that had none.
- **Lane M:** nothing applied; `version-report-2026-09-05.md` written at lane
  time with the reasons for every row deliberately left alone.

## What the closing act found

Four roles ran on the branch — correctness hunter, edge-case hunter, design
critic at the section-G conditions, and a risk-tier verification pass on the
four invariants. They produced about thirty confirmed findings, two of them
blocking, all fixed on the branch in five `fix(...)` commits before promotion.
Sprint 9's closing act had degraded to a stated self-review when its agents
died on a session limit; this one earned its cost, and the two blocking
findings are the evidence.

1. **A test that pins an attribute is not a test of the behaviour.** Every
   destructive control carried `data-confirm`, an invariant test asserted it,
   and CI was green — but the page loads no `phoenix_html.js`, so nothing
   honoured the attribute. Seven pre-existing sites had been silently inert
   for the whole life of the feature; the batch's four new ones would have
   joined them. Only the design critic's browser probe (a stubbed
   `window.confirm`, an injected `phx-click`) found it. The root layout now
   carries one capture-phase listener, and the invariant test pins the
   mechanism.
2. **The perimeter refused our own companion.** Inside Compose the MCP
   companion reaches the app as `http://app:4000`; the new Host guard answered
   421. A guard is only as good as the list it is given, and the list was
   written from the operator's names alone. Both Compose files now name `app`,
   `check_origin` is built from the same list, and a CI test pins the contract.

## Process findings

- **The session limit bit again.** The first launch of the review agents died
  on it, exactly as in Sprint 9, and cost a wait for the reset. Sprint 9's
  lesson ("check the budget before fanning out") was recorded and not acted
  on; treat it as a standing pre-flight, not a note.
- **The codecov patch check was the only red check** across the early rounds,
  twice, and it was right both times: it drove real tests onto the default DNS
  resolver, the release-time commands, the ECB fetch and the logo store's
  error branches. Patch coverage ended at 95.6 %.
- **`credo --strict` findings reached CI before they reached me** — the local
  gate order ran it late. Run it before the push, not after.
- **A URL written into a PR description through the API comes back escaped**
  as a code span, so the screenshots the closing act requires did not render.
  They belong in a comment; found late, cost a round.
- **The demo strategies seed still assumes a portfolio named "Demo Depot"** —
  the same stumble Sprint 9 recorded, still unfixed, and it cost the same
  minutes again.
- **The session's own check-in disabled itself after firing**, so the PR watch
  lapsed silently until it was noticed by hand. A watch that stops without
  saying so is worse than no watch.
- **The surface check did its job and found the family half-done** (#776),
  the second read-ergonomics family to ship that way after FR-37 (#740). The
  PR briefing had claimed the surface was complete; the close-out checked it
  against `mix phx.routes` and it was not. The clause earns its place.

## Close-out ledger

- **Merged:** PR #773, 2026-09-06 07:12 UTC, rebase-merge, `main` at
  `b701613a`. Actions on the merge push verified green before this entry:
  CI 1483, Commit authorship 497.
- **Closed by the merge's keywords:** #758 #759 #760 #761 #762 #763 #764
  #765 #766 #767 #768 #769 #770 #771 — verified against the post-merge
  open-issue list, none remained open.
- **Closed by hand:** #757, the E21 tracker, with the evidence.
- **Filed by the close-out:** #776, the `limit` surface gap found by the
  surface check.
- **Stays open with a reason:** #382 (CSP) and #772 (Bandit, which removes
  cowlib and its three advisories) — both the next batch by the triage's own
  ruling; #727 (both toolchain halves still blocked upstream, triggers
  re-checked at lane time, none fired).
- **TAG: `0.10.0` is an OPEN OWNER ITEM.** Created locally as an annotated
  tag object on the merged head `b701613a` and refused by the session's git
  proxy with `HTTP 403` on the push — the fourth sprint in a row (0.8.0,
  0.9.0, and now this one; the proxy's own status shows no relay failure, so
  the refusal is the session credential's branch scope, not an egress block).
  The GitHub API surface available to the session has no create-tag or
  create-release call either. The prepared command, run from a clone with
  push rights:

  ```bash
  git fetch origin
  git tag -a 0.10.0 b701613a -m "0.10.0 — E21 security hardening (Sprint 10)"
  git push origin 0.10.0
  ```

  The push triggers the Release workflow, which creates the GitHub Release
  with generated notes. **Four sprints is a pattern, not an accident:** either
  the session's credential gains tag-push rights, or ADR-0026 step 5 should
  name the tag as an owner action rather than an agent one. That decision is
  the owner's and is not taken here.
