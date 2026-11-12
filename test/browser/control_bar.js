// The shared bar of labelled controls (`PortfolixirWeb.ControlBar.bar/1`;
// issue 1435, Sprint 29 L1; DESIGN.md "Labelled controls start on one edge"
// and its anatomy of the control bar), driven in a real Chromium by
// test/browser/control_bar_test.exs, which boots the endpoint, seeds a
// synthetic world and passes the base URL, the case to run and the paths it
// seeded as JSON in the only argument. LiveViewTest applies no CSS, so where
// a label and its control land is measured here.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "errors":
// ["..."]}; the exit status is 0 either way unless the browser itself fails.
// Every measure goes to stderr as well, so a run before and after a change
// can be compared box by box.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;

async function ready(page, path) {
  await visit(page, base + path);
  await page.waitForSelector("[data-phx-main].phx-connected");
}

async function nextFrame(page) {
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
}

// The stacked chart's bar, the component's first user: its three groups
// (level, classification, sort), measured by the ids and roles the bar
// carried before the component, so a run on either side of the extraction
// reads the same boxes.
const STACK_GROUPS = [
  ["#stack-level-label", "[data-role='stack-level']"],
  ["label[for='stack-classification']", "#stack-classification"],
  ["#stack-sort-label", "[data-role='stack-sort']"]
];

function measure(page, groups, barSelector) {
  return page.evaluate(
    ({ groups, barSelector }) => {
      const round = (n) => Math.round(n * 10) / 10;
      const bar = document.querySelector(barSelector).getBoundingClientRect();
      const box = (selector) => {
        const r = document.querySelector(selector).getBoundingClientRect();
        return {
          left: round(r.left - bar.left),
          right: round(r.right - bar.left),
          top: round(r.top - bar.top),
          bottom: round(r.bottom - bar.top),
          width: round(r.width)
        };
      };
      return {
        bar: { width: round(bar.width), height: round(bar.height) },
        groups: groups.map(([label, control]) => ({ label: box(label), control: box(control) })),
        page: document.documentElement.scrollWidth - document.documentElement.clientWidth
      };
    },
    { groups, barSelector }
  );
}

// Which of the three layouts the boxes show, and whether they show it to
// the pixel (±1 px), from the labels' own widths, so the check holds in any
// font:
// - "line": every label and control on one line, each control 8 px after
//   its label (the group's 6 px gap and the label's 2 px margin);
// - "column" (A): every label at the bar's left edge, every control from
//   one edge 10 px after the widest label;
// - "above" (B): every label above its control, both at the bar's left edge.
function layoutOf(m) {
  const near = (a, b) => Math.abs(a - b) <= 1;
  const g = m.groups;
  const mids = g.flatMap(({ label, control }) => [
    (label.top + label.bottom) / 2,
    (control.top + control.bottom) / 2
  ]);
  if (Math.max(...mids) - Math.min(...mids) <= 3) {
    const exact = g.every(({ label, control }) => near(control.left - label.right, 8));
    return { layout: "line", exact };
  }
  const widest = Math.max(...g.map(({ label }) => label.width));
  const column = g.every(
    ({ label, control }) => near(label.left, 0) && near(control.left, widest + 10) && label.bottom > control.top
  );
  if (column) return { layout: "column", exact: true };
  const above = g.every(
    ({ label, control }) => near(label.left, 0) && near(control.left, 0) && label.bottom <= control.top + 0.5
  );
  if (above) return { layout: "above", exact: true };
  return { layout: "none", exact: false };
}

// Issue 1435 (L1): the stacked chart's bar, now the component's first user,
// keeps its layout to the pixel. At 1200 px one line; at 1024 px, where the
// sidebar leaves the bar under 760 px, the label column (A); at 900 px,
// without the sidebar, one line again; at 390 px the label column; at 320
// px, where the label column and the widest control do not fit the bar,
// every label above its control (B): the container query on the bar
// decides, never the viewport. In English and in
// German, whose „Klassifizierung“ is the longest label; no control leaves
// the bar and the page never scrolls sideways.
async function stackBarLayout(browser) {
  const errors = [];
  const host = new URL(base).hostname;
  const expected = { 1200: "line", 1024: "column", 900: "line", 390: "column", 320: "above" };
  for (const locale of ["en", "de"]) {
    for (const width of [1200, 1024, 900, 390, 320]) {
      const context = await browser.newContext({ viewport: { width, height: 900 } });
      await context.addCookies([
        { name: "portfolixir_locale", value: args.locales[locale], domain: host, path: "/" }
      ]);
      const page = await context.newPage();
      await ready(page, args.path);
      await page.waitForSelector("#stack-legend tbody tr");
      await settle(page);
      await nextFrame(page);
      const m = await measure(page, STACK_GROUPS, "[data-role='stack-bar']");
      const { layout, exact } = layoutOf(m);
      const label = locale + " at " + width + " px: ";
      console.error(label + JSON.stringify({ layout, exact, ...m }));
      if (m.page > 0) errors.push(label + "the page scrolls sideways by " + m.page);
      if (m.groups.some(({ control }) => control.right > m.bar.width + 0.5)) {
        errors.push(label + "a control leaves the bar " + JSON.stringify(m.groups));
      }
      if (layout !== expected[width] || !exact) {
        errors.push(
          label + "expected the " + expected[width] + " layout, measured " + layout +
            (exact ? "" : " (off by more than 1 px)") + " " + JSON.stringify(m.groups)
        );
      }
      await leave(context);
    }
  }
  if (errors.length > 0) throw new Error(errors.join("; "));
}

// --- L2 begin: the migrated bars (issue 1435, Sprint 29 L2; board 06 and
// its inventory §1, rows 2, 3, 5, 7 to 10) ---

// Measures a bar the way the inventory measured it
// (`capture-b-inventory.js`), so a run before the migration and one after
// read the same things: the bar's controls (a segmented control, a select, a
// chip, a field, a checkbox with its own label, a button), its visible
// labels, the rows its controls fall on, and its groups (a visible label and
// the controls after it up to the next one; controls before the first label
// are a group without a label). `roots` may name more than one element: the
// journal's chips and its form are measured as one bar, which they become.
function measureBar(page, roots) {
  return page.evaluate((roots) => {
    const round = (n) => Math.round(n * 10) / 10;
    const visible = (e) => {
      const r = e.getBoundingClientRect();
      const s = getComputedStyle(e);
      return (
        r.width > 0 && r.height > 0 && s.visibility !== "hidden" && s.display !== "none" &&
        !e.closest(".visually-hidden, [hidden], details:not([open]) > :not(summary)")
      );
    };
    const CONTROL =
      ".segmented-control, select, .filter-chip, input:not([type=hidden]):not([type=checkbox]), " +
      "label:has(input[type=checkbox]), .more-filters-link, button:not(.segmented-control button):not(.filter-chip)";
    const LABEL =
      ".control-bar__label, .filter-chips__family, .hs-controls__label, " +
      "label:not(:has(input[type=checkbox])):not(.visually-hidden)";
    const rootEls = [...document.querySelectorAll(roots)].filter(visible);
    if (rootEls.length === 0) return { visible: false };
    const left = Math.min(...rootEls.map((r) => r.getBoundingClientRect().left));
    const top = Math.min(...rootEls.map((r) => r.getBoundingClientRect().top));
    const width = Math.max(...rootEls.map((r) => r.getBoundingClientRect().right)) - left;
    const all = (selector) => [...new Set(rootEls.flatMap((r) => [...r.querySelectorAll(selector)]))];
    const controls = all(CONTROL).filter((c) => visible(c) && !c.parentElement.closest(".segmented-control"));
    const atomic = controls.filter((c) => !controls.some((o) => o !== c && o.contains(c)));
    const labels = all(LABEL).filter(
      (l) =>
        visible(l) && !l.closest(".segmented-control") && l.textContent.trim() &&
        !atomic.some((c) => c.contains(l)) && !l.querySelector("select, input")
    );
    const box = (e) => {
      const r = e.getBoundingClientRect();
      return {
        left: round(r.left - left),
        right: round(r.right - left),
        top: round(r.top - top),
        bottom: round(r.bottom - top)
      };
    };
    const text = (e) => e.textContent.trim().replace(/\s+/g, " ").slice(0, 30);
    const rows = [];
    for (const c of [...atomic].sort((a, b) => box(a).top - box(b).top || box(a).left - box(b).left)) {
      const b = box(c);
      const mid = (b.top + b.bottom) / 2;
      const row = rows.find((r) => mid > r.top && mid < r.bottom);
      if (row) {
        row.items.push({ text: text(c), ...b });
        row.top = Math.min(row.top, b.top);
        row.bottom = Math.max(row.bottom, b.bottom);
      } else {
        rows.push({ top: b.top, bottom: b.bottom, items: [{ text: text(c), ...b }] });
      }
    }
    const order = [...labels.map((l) => ({ l })), ...atomic.map((c) => ({ c }))].sort((a, b) =>
      (a.l || a.c).compareDocumentPosition(b.l || b.c) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1
    );
    const groups = [];
    let cur = { label: null, first: null, chips: 0 };
    for (const o of order) {
      if (o.l) {
        if (cur.first || cur.label) groups.push(cur);
        cur = { label: o.l, first: null, chips: 0 };
      } else {
        if (!cur.first) cur.first = o.c;
        if (o.c.matches(".filter-chip")) cur.chips += 1;
      }
    }
    if (cur.first || cur.label) groups.push(cur);
    return {
      visible: true,
      width: round(width),
      rows: rows
        .sort((a, b) => a.top - b.top)
        .map((r) => ({ top: r.top, first: r.items.sort((a, b) => a.left - b.left)[0] })),
      groups: groups
        .filter((g) => g.first)
        .map((g) => ({
          label: g.label ? { text: text(g.label), ...box(g.label) } : null,
          control: { text: text(g.first), ...box(g.first) },
          chips: g.chips
        })),
      page: document.documentElement.scrollWidth - document.documentElement.clientWidth
    };
  }, roots);
}

function round1(n) {
  return Math.round(n * 10) / 10;
}

// The rule (DESIGN.md, amendment of 2026-11-08, "Labelled controls start on
// one edge"; the inventory's measure): once a bar has more than one row,
// the first control of every row and of every labelled group start on one
// edge (±1 px). Every labelled group's control sits after its label on the
// label's line (the one line, or the label column A) or under it on the
// label's edge (labels above, B). Where a bar names every family, no chip
// family stands without a visible label.
function breaches(m, { everyFamilyNamed }) {
  const errors = [];
  const near = (a, b) => Math.abs(a - b) <= 1;
  if (m.rows.length > 1) {
    const lefts = [
      ...m.rows.map((r) => r.first.left),
      ...m.groups.filter((g) => g.label).map((g) => g.control.left)
    ];
    const spread = round1(Math.max(...lefts) - Math.min(...lefts));
    if (spread > 1) {
      errors.push(
        m.rows.length + " rows whose controls start " + spread + " px apart: rows at " +
          JSON.stringify(m.rows.map((r) => r.first.left)) + ", groups at " +
          JSON.stringify(m.groups.map((g) => (g.label ? g.label.text : "-") + "@" + g.control.left))
      );
    }
  }
  for (const { label, control } of m.groups.filter((g) => g.label)) {
    const beside = control.left >= label.right - 0.5 && control.top < label.bottom && control.bottom > label.top;
    const under = control.top >= label.bottom - 0.5 && near(control.left, label.left);
    if (!beside && !under) {
      errors.push(
        "„" + control.text + "“ sits neither after nor under its label „" + label.text + "“ " +
          JSON.stringify({ label, control })
      );
    }
  }
  if (everyFamilyNamed) {
    for (const g of m.groups.filter((g) => !g.label && g.chips > 0)) {
      errors.push("a chip family without a visible label, from „" + g.control.text + "“");
    }
  }
  if (m.page > 0) errors.push("the page scrolls sideways by " + m.page);
  return errors;
}

// One bar per case: the page, what the walk waits for and opens to reach
// the state the bar shows in, the element(s) it is, the widths at which it
// shows (the chip rows of Wertpapiere and Transaktionen give way to the
// phone's filter sheet at 390 px, which holds by construction, inventory
// rows 4 and 6), and whether it names every family.
const BARS = {
  journal: {
    path: "/journal",
    roots: "#journal-chips, #journal-filters",
    shows: [390, 1200]
  },
  sale_comparison: {
    path: "/cashflow?tab=realized&hindsight=rate",
    wait: "[data-role='hindsight-rate-form']",
    roots: "[data-role='hindsight-compare']",
    shows: [390, 1200]
  },
  securities_chips: {
    path: "/securities",
    roots: "#securities-filter-chips",
    shows: [1200],
    everyFamilyNamed: true
  },
  transaction_chips: {
    path: "/transactions",
    roots: "#transaction-chips",
    shows: [1200],
    everyFamilyNamed: true
  }
};

// Issue 1435 (L2): one migrated bar, in German and in English, at 390 and
// 1200 px, holds the rule; every measure goes to stderr.
async function migratedBar(browser) {
  const bar = BARS[args.bar];
  const errors = [];
  const host = new URL(base).hostname;
  for (const locale of ["de", "en"]) {
    for (const width of [390, 1200]) {
      const context = await browser.newContext({ viewport: { width, height: 900 } });
      await context.addCookies([
        { name: "portfolixir_locale", value: args.locales[locale], domain: host, path: "/" }
      ]);
      const page = await context.newPage();
      await ready(page, bar.path);
      if (bar.wait) await page.waitForSelector(bar.wait, { state: "attached" });
      await settle(page);
      if (bar.open) {
        await page.click(bar.open);
        await settle(page);
      }
      await nextFrame(page);
      const m = await measureBar(page, bar.roots);
      const label = args.bar + ", " + locale + " at " + width + " px: ";
      console.error(label + JSON.stringify(m));
      if (!m.visible) {
        if (bar.shows.includes(width)) errors.push(label + "the bar is not shown");
      } else {
        for (const e of breaches(m, bar)) errors.push(label + e);
      }
      await leave(context);
    }
  }
  if (errors.length > 0) throw new Error(errors.join("; "));
}
// --- L2 end ---

const CASES = {
  stack_bar_layout: stackBarLayout,
  migrated_bar: migratedBar
};

(async () => {
  const browser = await launchChromium();
  const errors = [];
  try {
    await CASES[args.case](browser);
  } catch (error) {
    errors.push(String(error && error.message));
  } finally {
    await leave(browser);
  }
  const result = errors.length === 0 ? { ok: true } : { ok: false, errors };
  process.stdout.write(JSON.stringify(result) + "\n");
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
