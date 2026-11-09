# Lifecycle Triage — 2026-11-09 (every implicit state machine)

Source: the owner's ask of 2026-11-09 ("find all of the implicit state
machines in my app; make the best decision that elevates UX, DX and AX
without breaking anything"). Six read-only audit passes, one per domain,
each finding checked against the code on the Sprint 28 planning branch
(`c75fd13`); the claims the decision rests on were re-read by hand. The
decision is [ADR-0059](../../docs/decisions/0059-lifecycles-named-once.md);
this document is its evidence and the migration's inventory. Nothing here
is instance data.

**Reading guide.** An *implicit* state machine is a record or flow whose
state the product shows without naming it in one place: a status inferred
from nullable columns, timestamps or booleans; a guard copied; a state
only one surface knows; or a screen phase spread over several assigns.
*Derived at read* is not a defect — it is the architecture (ADR-0004,
ADR-0039, ADR-0044, ADR-0055); the finding is the missing name, not the
missing column. Line numbers are those of `c75fd13`.

## Part 1 — The domain lifecycles

| # | Lifecycle | Where the state lives | States (as the code treats them) | Surfaces today | What is implicit |
|---|---|---|---|---|---|
| 1 | **Policy rule** (ADR-0049) — *the pilot* | virtual `status` from the versions, `policy_rules.ex` `annotate/2` (816–836) | in_force · scheduled · retired | API `status`, `version_in_force`, `next_version`; MCP prose; UI labels and grouping | the guard three times (`annotate/2`, `maybe_not_retired` 393–404, `in_force/3` 417–422); the dialog re-derives "never started" (`policy_rule_dialog.ex:553`); `scheduled` covers never-started and restart-pending; 409 reasons the payload never names. **Built:** `PolicyRuleStatus`, `permits`, `status_basis`, the dialog's buttons from `permits`, the companion's text, the invariant. |
| 2 | **Policy finding** (ADR-0049 §3) | `policy_evaluation.ex:48,141,151–162` | ok · breached · undetermined (+reason) | API key `state`, filter `status`; MCP `status` param; UI "met" for ok | the key and its filter disagree in name (ADR-0059 C2); "met" vs `ok` |
| 3 | **Prediction resolution** (ADR-0055) | derived per read, `resolution.ex:165–179` | open · resolved(hit/miss) · unresolved(reason); UI-only *waiting* | API `resolution.status/outcome/reason`; MCP enum; UI chips open/due/resolved/unresolved | "past its day" four times (`resolution.ex:170`, `prediction_label.ex:39`, `predictions.ex:424–427`, `predictions.ex:405–411`); *waiting* exists only on the screen; "missed"/"not resolved" labels; no test pins the due boundary at `resolves_on == today` |
| 4 | **Thesis state** (ADR-0044) | projection `thesis_state.ex:68–104` | none · intact · retracted | API `thesis_state.status`; MCP prose; UI private label (`securities_live.ex:3570–3572`) | the model is right; the label is inline, not in a label module; `time_stop` passing and `valid_until` expiring are never named |
| 5 | **Note supersession** | virtual `superseded_by_ids` (`security_note.ex:58`, `knowledge.ex:122,234`) | live · superseded | API list; MCP prose | a client infers "superseded" from a non-empty list |
| 6 | **Security event** (ADR-0048) | `confirmed` boolean + `checked_at` date (`security_event.ex:56,59`); queues in `events.ex:218–305` | upcoming · due · past-unconfirmed · confirmed; never-checked · fresh · stale | API raw fields + queue reads; MCP queue tools; UI "Took place" badge only | the window evaluated twice (SQL then in memory, `events.ex:253,259–262`); the screen shows no queue state; `confirmed` is freely toggled with no date guard (deliberate; untested either way) |
| 7 | **Security retired** | `is_retired` boolean (`security.ex:44`) | live · retired | API, MCP, UI all name the boolean | the merge guard `:retired_target` twice (`security_merge.ex:1207–1215`, `merge_dialog.ex:420`); "retired" also names an import hash's state |
| 8 | **Identity freeze** (ADR-0050 §11) | derived `Freeze.freezing_references/1` (`freeze.ex:86–92`) | unfrozen · frozen | **only** a 422 on a failed write; UI after a failed save (`security_form_dialog.ex:1141–1143`) | no read names it: the agent probes with writes, the operator learns after the save (ADR-0059 §7.1) |
| 9 | **Merged-away record** (ADR-0050) | the row deleted + `merge_records` (`merge_record.ex:143–159,195`); `merge_chain_end/2` (`lifecycle.ex:325–358`) | live · deleted · merged→live · merged→deleted | API 404 with `merged_into`, 409 `already_merged`; UI redirect and lineage | `merged_from` (lineage) is UI-only (§7.7) |
| 10 | **Merge flow** (ADR-0050) | nothing stored; `plan_digest` consent (`merge_flow.ex:271–289`) | preview · refused · consented · applied · already_applied · plan_changed · choice_required | API names each by code; MCP mirrors; UI dialogs | `same_digest`/`fresh_preview` copied per kind (`cash_merge.ex:244`, `depot_merge.ex:258`, `security_merge.ex:532`); `prior_merge` called twice per kind; the UI never tells applied from already_applied (`merge_dialog.ex:329,526`); the accounts dialog folds unmatched refusals into one sentence (394–398) |
| 11 | **Import hash** (ADR-0050 §3) | `transactions.import_hash` nullable + `retired_import_hashes` | hand-entered · held · retired | API/MCP raw `import_hash`; journal rows | only merges retire a hash (`cash_merge.ex:1024`, `depot_merge.ex:925`, `security_merge.ex:2300`); deleting an imported row outside a merge leaves its hash free, so the row returns as `new` on re-import — an implicit, undocumented transition; no read lists retired hashes |
| 12 | **Target plan** | string column `status` (`target_plan.ex:466,471,497`) | active · draft · archived | API/MCP name it; UI | transitions implicit (`targets.ex:853–866, 918–950, 1185–1200`; no direct archive); the changeset casts `status` freely (487–494); string literals compared in six places; **defect:** the security merge preview passes a string (`security_merge.ex:2104,2707`) to clauses matching atoms (`merge_preview.ex:862–865`), which never match — S3, polish list (Part 3) |
| 13 | **Feed fetch health** (ADR-0056 §5–6) | six columns (`feed.ex:44–51`); `fetcher.ex:308–334`; `health.ex:131–137` | never-fetched · ok · failing · backing-off · backoff-expired · disabled · stale | API `/news/health` shows `enabled`, `last_ok_at`, `last_error`, `err_24h`, `stale` — not `failures`, `retry_at`, `last_fetch_at`; MCP prose; no UI yet | backoff invisible to every client; a non-backoff failure during a backoff keeps the old `retry_at` (untested); `run_one/2` ignores `retry_at`; ADR-0056 §5 says a `sec.gov` feed without a user agent "stays disabled" while the code leaves `enabled` true and refuses each tick before any request leaves (wording, S3, Part 3) |
| 14 | **News item status** | `Ecto.Enum` `new · promoted · muted` (`item.ex:82`) | — | API `status`; MCP omits it (`tools.ts:4562`) | no writer in `lib`: both non-default states unreachable by design (ADR-0056 §8, C4 defer promotion); fixtures reach them |
| 15 | **News item assignment** | `Ecto.Enum` + `cluster_id` (`item.ex:80–81`) | assigned · unassigned · ambiguous | API filter; MCP enum of two of the three | the two-to-one collapse twice with different column sets (`news.ex:131–140` vs `591–614`) |
| 16 | **Story (cluster)** | existence + `member_count` (`cluster.ex`; `stories.ex:464–509, 633–661`) | exists · emptied · promoted (derived) | API; health counts | no state column by design; "promoted story" derives from #14 |
| 17 | **Quote freshness** | derived from the latest price date against `stale_days/0 = 7` | fresh · stale · never priced | UI marker and chip; API counts and dates, no per-row flag | **four implementations**: `data_quality.ex:113–116` (nil → false), `:338–343` (nil → true, deliberate), `valuation.ex:685–690`, `portfolio_live.ex:4696`, `securities_live.ex:4753` (§7.5) |
| 18 | **Quote sync run** | `SingleFlight` keys (`quote_sync.ex:72,166`); transient `status ok · skipped · error` | idle · running (+ per-security results) | API 409 while running; MCP prose; UI `sync_running?` | no "last sync" state anywhere; the tick's result is discarded |
| 19 | **FX backfill** | `SingleFlight` + a sought set in Settings (`history_gaps.ex:73–78`); `settlement_legs.status completed · not_run · stopped` | open · due · sought · running | API/MCP name the legs; UI `fx_backfilling` | the UI collapses `backfill_in_progress`, `stopped` and errors into one `:error` (`income_live.ex:193–216`) |
| 20 | **Derived value freshness** (ADR-0039) | `peek/3` fresh · stale · none (`derived.ex:132–152`); Refresher idle · pending · draining (`refresher.ex:114–160`) | — | API `as_of` + `stale` (always `false`, served through `fetch/4`); UI `stale: true` via `previous_analysis` | "refreshing" is never exposed; the API's `stale` key cannot vary |

## Part 2 — The screen flows (web layer)

| # | Flow | Where the phase lives | What is implicit |
|---|---|---|---|
| 21 | UI login session (ADR-0045) | `UiAuth.enabled?/0` + three session keys (`ui_auth.ex:25–27,79–82,164`) | the phases (open, unauthenticated, fresh, expired, unbound, logged out) are combinations; with `PORTFOLIXIR_SESSION_DAYS=0` the per-event re-check is not attached (`live_ui_auth.ex:35–38`) — no exposure, because the password is boot-time configuration and a restart drops every socket |
| 22 | Login throttle | ETS rows (`auth/throttle.ex:107–135`) | counting · locked · scope-locked · forgotten; the scope ceiling locks every source until buckets age (documented) |
| 23 | Privacy mode | cookie + process dictionary + assign (`privacy_mode.ex`) | three copies of one bit, by design (a full navigation toggles it) |
| 24 | Destructive confirm | three mechanisms: native `data-confirm` only (nine call sites); `DeletePreviewDialog` with a state atom (`delete_preview_dialog.ex:55–71`, its events copied verbatim into `buckets_live.ex:747–789` and `classifications_live.ex:1692–1761, 3381–3434`); `BookingDeleteDialog` under two assign names (`:deleting`, `:deleting_split`) | the explicit one is the model (ADR-0059 §9) |
| 25 | One dialog at a time | accounts enforce it (`close_lifecycle/1`, `portfolio_accounts_live.ex:1251`); securities keep about ten independent dialog assigns (`securities_live.ex:120–180`) | a pushed `merge` while the edit dialog is open leaves both set |
| 26 | Booking drawer | seven assigns (`transaction_management_live.ex:95–107`) | `save_transaction` is not gated on `booking_open?` |
| 27 | Inline edit | four encodings (buckets: two independent ids; tax: id + boolean; classifications: id + set; securities note: boolean) | no "saving" phase anywhere |
| 28 | Merge wizards | `step` + seven assigns (`portfolio_accounts/merge_dialog.ex:57`, `securities/merge_dialog.ex:61`) | `pick_target` unguarded on step; `back` and `close` accepted while applying (the result and its notice are lost); after `back`, a `plan_changed` result sets `preview` in `:target`, and `confirm` checks `preview`, not `step` — S3, polish list |
| 29 | Security form dialog | `step` + `mode` string + `editing` (`security_form_dialog.ex:64–75`) | `back_from_confirm` is accepted in edit mode though its button is not rendered; `editing` survives into `:choose`, and a later `save` would update the edited security from the manual form — reachable by a pushed event only; S3, polish list |
| 30 | Split wizard | no step atom; `preview`/`booked_split`/`error` act as the phase | — |
| 31 | Imports page | `stage` restoring · idle · preview · done (+ `applying`, `result`, `error`; `imports_live.ex:62–66`) | `apply` is not guarded on the stage and `preview` stays set on `:done` (harmless only by the hash idempotency); `reset` while applying is overridden by the task's success; S3, polish list. Inside the page: the parked preview's ETS lifecycle (`preview_store.ex`), the dry-run refinement (`pending` cleared in three places with different guards), the row layer verdict written twice with two vocabularies (`applier.ex:921–1148` vs `1847–1968`), the cash correction's five item states (`correction.ex:132–133`; `:claimed` has no test), the correction section's four assigns with inconsistent guards |
| 32 | Busy and loading | four encodings: a boolean with a server guard (`sync_running?`), a `{:busy, msg}` result slot (logo lookup, correction), booleans without a server guard (`fx_syncing` in `portfolio_live.ex:4484`, `fx_backfilling` in `income_live.ex:189`: a second push re-runs the sync), nil-or-`:error` on the data (two encodings in one dashboard) | S3, polish list for the two unguarded buttons |

## Part 3 — Defects found on the way, by severity

Recorded as the sprint workflow orders it: an S1 anywhere or an S2 in code
this PR reaches as an issue; everything else as a line on its screen's
polish list. This PR reaches the policy rules only.

| Finding | Severity | Where recorded |
|---|---|---|
| The security merge preview's `plan_status` is a string matched against atoms (`merge_preview.ex:862–865`), so the raw slug is shown untranslated | S3 | Polish: Merge pages (#1363) |
| The merge dialogs accept `back` and `close` while applying; a `plan_changed` after `back` lands a preview in the target step | S3 | Polish: Merge pages (#1363) |
| The security form dialog accepts `back_from_confirm` in edit mode and keeps `editing` set | S3 (pushed event only) | Polish: Securities and the security page (#1365) |
| The imports page's `apply` is not guarded on the stage; `reset` while applying is overridden | S3 | Polish: Imports (#1355) |
| `sync_rates` and `backfill_rates` have no server-side guard, so a second push re-runs them; Income collapses `stopped` and in-progress into one error | S3 | Polish: Cash flow and Income (#1359), Polish: Wealth (#1366) |
| ADR-0056 §5 says a `sec.gov` feed without a user agent "stays disabled"; the code leaves `enabled` true and refuses each tick before any request leaves | S3 (wording) | Polish: API and MCP (#1356) |
| Deleting an imported transaction outside a merge leaves its hash free, so the row returns as `new` on the next re-import | not a defect: the documented reimport contract covers merges only; named in #11 for the lane that takes ADR-0059 §7 | — |
| `PORTFOLIXIR_SESSION_DAYS=0` leaves a mounted page without the per-event re-check | not a defect: the password is boot-time configuration, and a restart drops every socket | — |
| `privacy_mode_test.exs:77` fails on the base branch (a leaked figure on the connected render) | pre-existing, reproduced alone on `c75fd13`; outside this PR's scope | named on the PR |

## Part 4 — What the decision takes from this

ADR-0059 §1–§6 are the rule; §7 is the order, drawn from the "What is
implicit" column: the freeze (no read names it), the events (the screen
shows nothing), the predictions (four copies), the feed health (backoff
invisible), the quote freshness (four implementations), the target plan
(the one stored status, with a defect beside it), the merged lineage (one
key). The screen flows (§9) migrate as their screens are touched; the
explicit `DeletePreviewDialog` is the model.
