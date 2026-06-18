---
stepsCompleted: [1]
inputDocuments: []
session_topic: 'A sensible on-page indicator for pending background actions, replacing the intrusive top-right status_toast that must be dismissed manually and gives no completion signal'
session_goals: 'Converge on one clear favorite solution to implement'
selected_approach: 'ai-recommended'
techniques_used: []
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
