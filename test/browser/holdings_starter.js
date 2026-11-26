// The starter „Bestände“ against Wealth's tab „Bestände“ in a real browser
// (Sprint 32 W1; I57; ADR-0062's amendment of 2026-11-25, point 5; board
// ux-design-2026-11-25-sprint32/02 ①), driven by
// test/browser/holdings_starter_test.exs, which seeds the review seed,
// stores the starters and passes the base URL and the starter's id.
//
// At 1200 px in German the walk reads, on the starter, its widgets in
// reading order and, for each, the figure that names its section; on
// Wealth (/portfolio, the tab „Bestände“), its sections in the page's
// order and the same figures. The test compares the two.
//
// Prints one JSON object on stdout: {"ok": true, "starter": ..., "wealth":
// ...} or {"ok": false, "error": "..."}.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const { base_url: base, id } = JSON.parse(process.argv[2]);

// Each section: Wealth's selector and the selector of its figure on each
// page, as the widget draws it and as Wealth draws it.
const SECTIONS = [
  { kind: "wealth_key_figures", wealth: "#portfolio-kpis", figure: ["[data-role='kf-total'] .widget-figure__value", "#kpi-total strong"] },
  // The notes by their finding: the remedy beside a note is Wealth's
  // control on the tab and a link to it on the dashboard.
  {
    kind: "data_notes",
    wealth: "#portfolio-data-quality",
    figure: ["[data-form='wide'] .data-note[data-role]", ".data-note[data-role]"],
    attr: "role"
  },
  { kind: "performance", wealth: "#portfolio-performance", figure: ["[data-form='wide'] [data-role='period-badge']", "[data-role='period-badge']"] },
  { kind: "contribution", wealth: "#performance-contribution", figure: ["[data-role='contribution-sum-figure']", "[data-role='contribution-sum-figure']"] },
  { kind: "positions", wealth: "#portfolio-positions", figure: ["table [data-role='holdings-position']", "#holdings-positions-table [data-role='holdings-position']"] },
  { kind: "cash_accounts", wealth: "#portfolio-cash", figure: ["[data-form='wide'] [data-role='cash-account']", "[data-role='cash-account']"] }
];

const read = (page, side) =>
  page.evaluate(
    ([sections, side]) => {
      const clean = (node) => (node ? node.textContent.replace(/\s+/g, " ").trim() : null);
      const pick = (root, sel, attr) =>
        Array.from(root.querySelectorAll(sel))
          .map((n) => (attr ? n.dataset[attr] : clean(n)))
          .join(" | ");
      if (side === 0) {
        return Array.from(document.querySelectorAll("#dashboard-grid > [data-widget-kind]")).map((w) => {
          const s = sections.find((x) => x.kind === w.dataset.widgetKind);
          return { kind: w.dataset.widgetKind, size: w.dataset.size, figure: s ? pick(w, s.figure[0], s.attr) : null };
        });
      }
      return sections
        .map((s) => ({ s, node: document.querySelector(s.wealth) }))
        .filter((x) => x.node)
        .sort((a, b) => (a.node.compareDocumentPosition(b.node) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1))
        .map(({ s, node }) => ({ kind: s.kind, figure: pick(node, s.figure[1], s.attr) }));
    },
    [SECTIONS, side]
  );

(async () => {
  const browser = await launchChromium();
  try {
    const context = await browser.newContext({
      viewport: { width: 1200, height: 900 },
      locale: "de-DE",
      reducedMotion: "reduce"
    });
    const page = await context.newPage();
    await visit(page, base + "/dashboards/" + id + "?locale=de");
    await settle(page);
    const starter = await read(page, 0);
    await visit(page, base + "/portfolio?locale=de");
    await settle(page);
    // The count-up of Wealth's totals ends before its figure is read.
    await page.waitForTimeout(1600);
    const wealth = await read(page, 1);
    await leave(context);
    process.stdout.write(JSON.stringify({ ok: true, starter, wealth }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
