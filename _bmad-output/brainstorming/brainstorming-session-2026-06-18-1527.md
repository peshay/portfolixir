---
stepsCompleted: [1, 2]
inputDocuments: []
session_topic: 'A sensible on-page indicator for pending background actions, replacing the intrusive top-right status_toast that must be dismissed manually and gives no completion signal'
session_goals: 'Converge on one clear favorite solution to implement'
selected_approach: 'ai-recommended'
techniques_used: ['First Principles Thinking', 'Analogical Thinking / Cross-Pollination', 'Morphological Analysis']
ideas_generated: []
context_file: ''
---

# Brainstorming Session Results

**Facilitator:** Andi
**Date:** 2026-06-18

## Session Overview

**Topic:** A sensible on-page indicator for pending background actions in portfolixir, replacing the current `AppShell.status_toast` (fixed top-right, overlaps content, manual dismiss only, no completion signal).

**Goals:** Converge on one clear favorite solution to implement.

### Context Guidance (codebase findings)

- Stack: Phoenix 1.7.14, Phoenix LiveView 0.20.17.
- The "popup" is a custom component `AppShell.status_toast/1` (`lib/portfolixir_web/components/app_shell.ex:411`), not the standard Phoenix flash.
- It renders a fixed top-right `div.status-toast` with an `aria-live` region, a message span, and a manual dismiss button (`phx-click="dismiss_toast"`, the `&times;` / X).
- No auto-dismiss: the message stays until the user clicks X (`dismiss_toast` sets `flash_message` to `nil`).
- The same component is overloaded for two very different purposes:
  - **In-progress / pending actions:** e.g. "Syncing prices…", "Recalculating figures…", "Syncing %{name}…", "Looking up logo…".
  - **Transient confirmations:** e.g. "Notes saved.", "Security updated.", "ISIN copied", "Deleted %{name}".
- Used in both `securities_live.ex` and `portfolio_live.ex`.
- Action durations vary: some near-instant (balance / "Saldo aktualisieren"), some longer (price sync, FX-rate sync, recalculation).

### Core problem framing

A single notification component conflates **"a background task is running (and you should know when it's done)"** with **"a one-shot action succeeded/failed."** The most user-noticed symptom is the instant balance update: a "running/done" style message appears but never resolves or clears itself.

### Session Setup

**Approach selected:** [2] AI-Recommended Techniques.

## Technique Selection

**Approach:** AI-Recommended Techniques
**Analysis Context:** On-page indicator for pending background actions, with the explicit goal of converging on one clear favorite to implement.

**Recommended sequence:**

- **Phase 1 — First Principles Thinking (creative):** Strip the "we have a top-right toast" assumption; define what feedback a background action fundamentally needs (states, location, audience, timing). Produces the evaluation criteria.
- **Phase 2 — Analogical Thinking / Cross-Pollination (creative):** Survey how other apps/domains signal background work (inline button spinners, "Sending… Undo", optimistic UI, progress bars, skeletons, embedded status badges) and map onto portfolixir's actions.
- **Phase 3 — Morphological Analysis (deep):** Build a parameter grid (location · trigger · duration-awareness · self-dismiss · error handling) × action types (instant vs. long) and combine systematically to converge on the favorite.

**AI Rationale:** Concrete/familiar UX topic favors creative + analogical divergence; the "one clear favorite" goal demands a structured convergence step at the end; codebase grounding keeps ideas implementable.

## Outcome — Decision & Implementation

The session was deliberately cut short: the user already had a clear, well-formed
opinion, so we pivoted from divergent ideation straight to a grounded decision.

**Chosen favorite (scope: Priority 1 + Priority 2):**

1. **The button is the indicator (Priority 1).** For background actions the
   triggering control shows its own state instead of a separate popup.
   - Sync buttons (`#sync-prices`, `#detail-sync`) already bind `sync_running?`
     → `is-busy` + `disabled`; added a real CSS spinner so the refresh icon
     literally spins (`.icon-button.is-busy svg` reuses `@keyframes import-spin`).
   - Synchronous form/button actions (e.g. `set_balance`, `sync_rates`) already
     use `phx-disable-with`, which disables the button for the whole round-trip.
   - Dropped the redundant in-progress "Syncing…" toasts; the spinning button
     carries the running state.
2. **Confirmation toasts auto-dismiss (fixes the core annoyance).** The shared
   `AppShell.status_toast` now carries `data-auto-dismiss` and a new
   `AutoDismissToast` JS hook clears success toasts after ~4.5s (no more manual
   X, no more "it never goes away"). Errors stay until acknowledged.
3. **OS notifications for long async actions (Priority 2).** On completion of
   price sync (`{:sync_done}`) and logo lookup (`{:logo_update_done}`) the
   server `push_event`s `"os-notify"`; the client shows a Web Notification, but
   only when the tab is in the background (`document.hidden`) so it never
   duplicates on-page feedback. Permission is requested in the click handler of
   the sync buttons.

**Files touched:**

- `lib/portfolixir_web/components/app_shell.ex` — toast id + `AutoDismissToast` hook + docs.
- `lib/portfolixir_web/live/securities_live.ex` — drop in-progress sync toasts, `notify_os/4`, OS-notify on completion, request permission on sync buttons.
- `lib/portfolixir_web/layout_view.ex` — `AutoDismissToast` hook, `phx:os-notify` listener, `Portfolixir.osNotify` / `ensureNotifyPermission`.
- `priv/static/app.css` — spinner for `.icon-button.is-busy`.

**Verification:** `mix compile` clean; 118 LiveView/quote-sync tests pass (0 failures).

**Possible follow-ups (not done):** reposition the toast so it never overlaps
content even before it fades; per-row busy state for individual logo/sync menu
actions; surface a notification permission affordance in settings.

## Technique Execution Results

