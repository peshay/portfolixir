# Research Digest — UX Best Practices (web subagent, 2026-06-12)

Angles: (1) best-in-class portfolio-tracker UX, (2) "LLM configures, human
views" precedents, (3) animated charts without a JS framework.

## Angle 1 — Portfolio-tracker UX (2024–2026)

1. **Ghostfolio** (closest self-hosted comparable): home = one big
   performance curve with period pills (1D/1W/1M/3M/YTD/1Y/Max), color-coded
   gain/loss; drill-down holdings → position. Notable: **"Zen Mode"** hides
   numbers/percentages, shows only tendency (emotional distance in
   downturns). Reviews praise feature/clarity balance; ~8,100+ GitHub stars.
2. **Maybe Finance / fork "Sure"**: design philosophy "What can we delete?" —
   positioned against apps that "overwhelm the user with dashboards, complex
   UIs, and too much detail". iOS-PWA optimization, theme-aware dark mode.
   (Maybe archived 2025-07; fork "Sure" continues — the prettiest OSS
   finance UI did not survive as a product.)
3. **Copilot Money**: category benchmark for design per several 2025/26
   reviews — "careful attention to typography, motion, color choices, and
   information density". Web app deliberately mirrors the iOS design.
4. **Monarch Money**: configurable dashboard — user picks which
   widgets/goals sit on top; investment drill-down beside budget views.
5. **getquin / Parqet** (DACH): multi-broker aggregation; breakdown by
   geography/sector/asset class as default drill-down. Parqet shows **last
   sync time** prominently — a data-freshness trust indicator.
6. **Snowball Analytics**: clean dashboard + purpose-built tools instead of
   form flood: target allocation with one-click rebalancing suggestions,
   dividend forecast, goal tracking; home-screen widgets for glanceability.
7. **Kubera**: minimalist net-worth balance sheet as home — one table, one
   number; depth on demand. Capitally 2026: Kubera = simplicity, Snowball =
   analytical depth — the two poles of the genre.
8. **Cross-industry guidance** (Eleken, Webstacks, UX4Sight 2025/26):
   card-based layouts with sparklines, visual hierarchy (total big/bold,
   secondary metrics small/light), progressive disclosure (summary →
   drill-down → filters). Responsive: bottom tab bar (max 5) on phone,
   sidebar/rail on tablet/desktop, touch targets ≥44px.

## Angle 2 — "LLM configures, human views" precedents

1. **Kubera is the real-world finance precedent**: 2025/26 repositioning
   "Works for you. Works for your AI." — MCP exposes the portfolio to
   ChatGPT/Claude/Perplexity, "AI Import" reads documents/screenshots; the
   human UI stays the calm balance sheet.
2. **Self-hosted scene follows**: Actual Budget MCP server (read+write,
   2025-08); community MCP server for Ghostfolio (read+write) exists. The
   "agent maintains, app shows" pattern is lived practice among comparables.
3. **Chat-first is considered failed for administration/oversight**
   (HatchWorks, Blake Crosley): chat does not scale for delegation +
   oversight; a 90-minute agent session produces hundreds of events that
   are unreadable as a linear scroll. The gap between "chat with diffs" and
   a real "agent operations dashboard" is called the biggest unsolved UX
   problem in AI tooling.
4. **Smashing Magazine** (2026-02 "Designing For Agentic AI", 2026-05 "AI
   Transparency"): patterns — **action audit log with prominent per-action
   undo** ("dramatically lowers perceived risk of autonomy"), explainable
   rationale, confidence signals, escalation pathway. Audit must answer
   "why", not just "who did what" (also ISACA 2025).
5. **MCP write patterns standardizing**: `readOnlyHint` on tools; MCP Apps
   (official blog 2026-01, Builder.io) establish "agent proposes, UI
   renders diff, human confirms" over blind writes.
6. **Generative/adaptive UI countercurrent**: Google A2UI, CopilotKit
   AG-UI, Builder.io — agents generate situational UI. Mostly
   enterprise/demo stage as of 2026.
7. **Trust flip-side** (Chelsey Qiu, 2026-05): the more trust in the agent,
   the less humans verify — practitioners recommend visible "what changed"
   feeds and review prompts over silent background mutations.

## Angle 3 — Animated charts without a JS framework

1. **Line draw-in via `stroke-dasharray`/`stroke-dashoffset`** is the
   standard technique (CSS-Tricks, SVGenius, portalzine 2025) — purely
   declarative, server-renderable (`pathLength="100"` normalizes).
2. **SMIL is NOT dead**: Chrome's 2015 deprecation was suspended; SVG 2
   keeps animation elements; all modern browsers ship SMIL. Needed for
   `d`-attribute morphing and SVG-in-`<img>`; for simple draw-in/grow CSS
   is considered more maintainable.
3. **Bar grow & staggered build**: `transform: scaleY()` with
   `transform-origin: bottom` plus per-bar `animation-delay`. Toptal
   recommends offset & delay for dataviz — sequential build aids
   comprehension.
4. **Count-up numbers without JS**: CSS `@property` (`<integer>`) +
   `counter-set` + transition. Now in all evergreen browsers (Safari
   16.4+, Firefox 128+); degrades to static number.
5. **Duration/easing conventions**: IBM Carbon classifies chart rendering
   as "productive motion" (fast); micro-interactions 100–200ms, larger
   transitions 500–700ms; chart build-ups in practice ~600ms–1.5s,
   ease-out/deceleration.
6. **`prefers-reduced-motion` is mandatory**: animate only under
   `@media (prefers-reduced-motion: no-preference)` (opt-in pattern);
   legally relevant (ADA / European Accessibility Act). Finance context:
   motion once at build, never looping.
7. **Performance**: `transform`/`opacity` are compositor-accelerated;
   `stroke-dashoffset` triggers repaints — fine for a handful of paths,
   stagger/limit for hundreds.

## Recurring patterns across winners

- **One hero curve + one number as home**, period pills attached; all else
  is drill-down (Ghostfolio, Kubera, Parqet, Copilot).
- **Progressive disclosure as core IA**: summary cards with sparklines →
  detail page → filters; forms/settings deep, not on home.
- **Data-trust indicators**: last sync, freshness, color codes — vital when
  someone else (sync engine or agent) maintains the data.
- **Responsive = tab bar (phone) / rail or sidebar (iPad/desktop)** from
  the same IA, not two designs.
- **Agent writes → human sees diff/feed/undo**: wherever agents may
  mutate, the human UI is primarily a review surface, not an input surface.
- **Motion sparing and one-shot**: fast build (<~1.5s, ease-out,
  staggered), then calm; reduced-motion respected.

## Facilitator questions for the owner

1. Agent writes via MCP: pre-approve each change (diff/confirm) or review
   after the fact ("what changed" feed + undo) — and same for the second household
   portfolio?
2. What is the "one number + one curve" for home — net worth, TTWROR,
   dividend flow? Different between desktop (analysis session) and iPhone
   (glance)?
3. How much classic form UI must remain as fallback when the agent is
   unavailable (fixing one wrong trade without an LLM)?
4. Zen/minimalism vs analytical depth: where on the spectrum on a normal
   day — and on a tax-return day?
5. Should motion carry information (staggered build shows contribution
   order) or be polish only — and how important is identical motion feel
   across iPhone/iPad/desktop?

(Source links preserved in the original digest; see agent transcript.)
