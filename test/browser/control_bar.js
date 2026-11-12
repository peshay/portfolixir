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
const { settle, visit, draw, leave } = require("./settle");

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
  return measureBars(page, [roots]).then(([m]) => m);
}

// The same measure for several bars in one call (L3's sweep measures every
// bar of a page at each width).
function measureBars(page, rootsList) {
  return page.evaluate((rootsList) => rootsList.map((roots) => {
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
    // A label's text, the text CSS sets in its ::before and ::after
    // included (L3: a label set in CSS is a label the operator reads).
    const generated = (e) =>
      ["::before", "::after"]
        .map((p) => getComputedStyle(e, p).content)
        .filter((c) => c && c !== "none" && c !== "normal")
        .map((c) => c.replace(/^"(.*)"$/, "$1"))
        .join(" ");
    const labelText = (e) => (e.textContent + " " + generated(e)).trim().replace(/\s+/g, " ");
    const cssLabels = all("*").filter((e) => /\p{L}/u.test(generated(e)) && !e.matches(CONTROL));
    const labels = [...new Set([...all(LABEL), ...cssLabels])].filter(
      (l) =>
        visible(l) && !l.closest(".segmented-control") && labelText(l) &&
        !atomic.some((c) => c.contains(l) || l.contains(c)) && !l.querySelector("select, input")
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
    const text = (e) => labelText(e).slice(0, 30);
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
    // A label around its own field („Seit“ and its input) labels it too: a
    // bar that holds one is a labelled bar (L3), though its label has no
    // box of its own to measure.
    const wrapping = all("label:not(.visually-hidden)").filter(
      (l) =>
        visible(l) && l.querySelector("select, input:not([type=hidden]):not([type=checkbox])") &&
        [...l.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && /\p{L}/u.test(n.textContent))
    );
    return {
      visible: true,
      labelled: labels.length > 0 || wrapping.length > 0,
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
      page: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      // How far the furthest control reaches past the bar or the screen.
      overflow: round(
        Math.max(0, ...atomic.map((c) => c.getBoundingClientRect().right)) -
          Math.min(left + width, document.documentElement.clientWidth)
      )
    };
  }), rootsList);
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
function breaches(m, { everyFamilyNamed, sweep }) {
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
  // The sweep (L3) asks of the bar what is the bar's: a page may scroll
  // sideways at 320 px for a table, never for a bar's control.
  if (sweep) {
    if (m.overflow > 0.5) errors.push("a control reaches " + m.overflow + " px past the bar or the screen");
  } else if (m.page > 0) {
    errors.push("the page scrolls sideways by " + m.page);
  }
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
  },
  prediction_filters: {
    path: "/predictions",
    wait: "#prediction-filters",
    roots: "#prediction-filters",
    shows: [390, 1200],
    everyFamilyNamed: true
  },
  drift_filter: {
    path: "/portfolio?tab=allocation",
    wait: "#allocation-disclosure",
    open: "#allocation-disclosure > summary",
    roots: ".drift-table-actions > .filter-chips, [data-role='drift-filter']",
    shows: [390, 1200],
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

// --- L3 begin: the walk as a gate (issue 1435 (2), Sprint 29 L3) ---

// The bars the walk looks for: every bar on the component, and every older
// bar of controls (the inventory's list, `capture-b-inventory.js`) — one
// that carries a visible label falls under the rule, so a labelled bar
// built beside the component is measured as well as one built on it.
const COMPONENT_BAR = ".control-bar";
const OLDER_BARS = [
  ".filter-chips", ".filter-bar", ".hs-controls", ".section-head-controls",
  ".workspace-section--controls", ".select-toolbar", ".toolbar", ".journal-filters",
  ".detail-pane-toolbar", ".chart-toggles", ".overview-chart__toggles"
].join(", ");

// The widths a labelled bar is measured at: 1440 down to 320 px in steps
// of 8 (768, a tablet's, among them), and 390, the phone the plan names.
const SWEEP = [390];
for (let width = 1440; width >= 320; width -= 8) SWEEP.push(width);
SWEEP.sort((a, b) => b - a);

// Opens each closed disclosure that holds a bar (the allocation's drift
// filter), the way the operator does: its summary pressed.
async function openDisclosures(page) {
  const summaries = await page.evaluate(
    ({ component, older }) => {
      const out = [];
      document.querySelectorAll("details:not([open]):not(.metric-tooltip)").forEach((d, i) => {
        if (d.querySelector(component + ", " + older) && d.querySelector(":scope > summary")) {
          d.setAttribute("data-walk-details", String(i));
          out.push("[data-walk-details='" + i + "'] > summary");
        }
      });
      return out;
    },
    { component: COMPONENT_BAR, older: OLDER_BARS }
  );
  for (const summary of summaries) {
    await page.click(summary).catch(() => {});
    await settle(page);
  }
}

// Finds the bars on the page as it stands and tags each with
// `data-walk-bar`, so it can be measured by that tag; answers each with its
// name and its markup. A bar on the component is measured on its own; an
// older bar only where it neither sits in nor holds one, the outermost of
// nested ones. A bar in a dialog, a filter sheet or an ⓘ is not a bar of
// the page.
function tagBars(page) {
  return page.evaluate(
    ({ component, older }) => {
      const outside = (e) => !e.closest("dialog, .modal, .filter-sheet, details.metric-tooltip");
      const bars = [...document.querySelectorAll(component)].filter(outside);
      const olderBars = [...document.querySelectorAll(older)].filter(
        (e) =>
          outside(e) && !e.closest(component) && !e.querySelector(component) &&
          !(e.parentElement && e.parentElement.closest(older))
      );
      return [...bars, ...olderBars].map((e, i) => {
        e.removeAttribute("data-walk-bar");
        const markup = e.outerHTML;
        e.setAttribute("data-walk-bar", String(i));
        const name = e.getAttribute("data-role") || e.id || [...e.classList].join(".");
        return { selector: "[data-walk-bar='" + i + "']", name, component: e.matches(component), markup };
      });
    },
    { component: COMPONENT_BAR, older: OLDER_BARS }
  );
}

// Sets the width and waits for what it set off: a frame, and every finite
// animation or transition it started (the sidebar folding away), so a bar
// is never measured mid-way.
async function atWidth(page, width) {
  await page.setViewportSize({ width, height: 900 });
  await nextFrame(page);
  await page.evaluate(() =>
    Promise.race([
      Promise.all(
        document
          .getAnimations()
          .filter((a) => a.effect && a.effect.getComputedTiming().endTime !== Infinity)
          .map((a) => a.finished.catch(() => {}))
      ),
      new Promise((resolve) => setTimeout(resolve, 2000))
    ])
  );
}

// The widths as ranges: [764, 772] for 764, 772 and every 8 between.
function ranges(widths) {
  const sorted = [...widths].sort((a, b) => a - b);
  const out = [];
  for (const w of sorted) {
    const last = out[out.length - 1];
    if (last && w - last[1] <= 8) last[1] = w;
    else out.push([w, w]);
  }
  return out.map(([a, b]) => (a === b ? a + " px" : a + "–" + b + " px")).join(", ");
}

// Measures the page's bars: each at 1200 and 390 px to learn whether it is
// labelled, then every labelled bar and every bar on the component at
// every width of the sweep. Answers the bars found and, per bar, the
// widths at which it breaks the rule with the first breach seen at each.
//
// `swept` holds the bars already swept on earlier pages, by their markup
// and their width at 1200 and 390 px: the same bar in the same place (the
// securities' chip row beside each of a security's tabs) is swept once.
async function walkBars(page, where, swept = new Set()) {
  await openDisclosures(page);
  const bars = await tagBars(page);
  const report = [];
  const labelled = new Set();
  const seen = new Set();
  const widths = new Map(bars.map((b) => [b.selector, []]));
  for (const width of [1200, 390]) {
    await atWidth(page, width);
    const ms = await measureBars(page, bars.map((b) => b.selector));
    bars.forEach((bar, i) => {
      widths.get(bar.selector).push(ms[i].visible ? ms[i].width : null);
      if (!ms[i].visible) return;
      seen.add(bar.selector);
      if (ms[i].labelled) labelled.add(bar.selector);
    });
  }
  const measured = bars.filter((b) => {
    if (!b.component && !labelled.has(b.selector)) return false;
    const key = JSON.stringify(widths.get(b.selector)) + b.markup;
    if (swept.has(key)) return false;
    swept.add(key);
    return true;
  });
  const started = Date.now();
  const broken = new Map(measured.map((b) => [b.selector, new Map()]));
  for (const width of measured.length > 0 ? SWEEP : []) {
    await atWidth(page, width);
    const ms = await measureBars(page, measured.map((b) => b.selector));
    measured.forEach((bar, i) => {
      const m = ms[i];
      if (!m.visible) return;
      seen.add(bar.selector);
      const found = breaches(m, { everyFamilyNamed: bar.component, sweep: true });
      if (found.length === 0) return;
      broken.get(bar.selector).set(width, found);
      console.error(where + " " + bar.name + " at " + width + " px: " + JSON.stringify(m));
    });
  }
  console.error(where + ": swept " + measured.map((b) => b.name).join(", ") + " in " + (Date.now() - started) + " ms");
  for (const bar of measured) {
    const at = broken.get(bar.selector);
    if (at.size > 0) {
      const first = [...at.entries()].sort((a, b) => a[0] - b[0])[0];
      report.push({
        bar: bar.name,
        widths: [...at.keys()],
        error:
          where + ": the bar " + bar.name + " breaks the rule at " + ranges([...at.keys()]) +
          "; at " + first[0] + " px: " + first[1].join("; ")
      });
    }
  }
  for (const bar of measured.filter((b) => b.component && !seen.has(b.selector))) {
    report.push({ bar: bar.name, widths: [], error: where + ": the bar " + bar.name + " is never shown, so it was never measured" });
  }
  await atWidth(page, 1200);
  return { bars: bars.filter((b) => seen.has(b.selector)).map((b) => b.name), report };
}

// The area tabs and comparisons a page links in place (a `tab` or a
// `hindsight` in the address), as the privacy walk follows them.
function inPageLinks(page) {
  return page.$$eval("main a[href]", (as) =>
    as
      .map((a) => new URL(a.getAttribute("href"), location.href))
      .filter((u) => u.origin === location.origin && u.pathname === location.pathname)
      .filter((u) => /(^|[?&])(tab|hindsight)=/.test(u.search.slice(1)))
      .map((u) => u.pathname + u.search)
  );
}

// Issue 1435 (2): every page the router serves, in German and in English
// (side by side, a context each), every bar on it, every width. A page's
// detail tabs (buttons, a security's) are pressed one by one and each is
// walked as the privacy walk walks them.
async function everyBar(browser) {
  const errors = [];
  const found = new Set();
  const host = new URL(base).hostname;
  let visited = 0;
  const walkLocale = async (locale) => {
    const context = await browser.newContext({ viewport: { width: 1200, height: 900 } });
    await context.addCookies([
      { name: "portfolixir_locale", value: args.locales[locale], domain: host, path: "/" }
    ]);
    const page = await context.newPage();
    const swept = new Set();
    const queue = [...args.addresses];
    const queued = new Set(queue);
    const walk = async (where) => {
      const { bars, report } = await walkBars(page, where, swept);
      bars.forEach((b) => found.add(b));
      console.error(where + ": " + JSON.stringify(bars));
      for (const r of report) errors.push(r.error);
    };
    while (queue.length > 0) {
      const path = queue.shift();
      const response = await visit(page, base + path);
      const loaded = await settle(page);
      visited += 1;
      const where = locale + " " + path;
      if (!response || response.status() >= 400 || !loaded.settled) {
        errors.push(where + ": the page did not load (" + (response && response.status()) + ", " + JSON.stringify(loaded) + ")");
        continue;
      }
      await walk(where);
      for (const link of await inPageLinks(page)) {
        if (!queued.has(link)) {
          queued.add(link);
          queue.push(link);
        }
      }
      const tabs = await page.$$eval("[data-tab-level='2'] [role='tab']", (bs) =>
        bs.filter((b) => b.getAttribute("aria-selected") !== "true").map((b) => b.id).filter(Boolean)
      );
      for (const id of tabs) {
        const button = await page.$("#" + id);
        if (!button) {
          errors.push(where + " #" + id + ": the tab is gone");
          continue;
        }
        await button.click();
        const pressed = await settle(page);
        visited += 1;
        if (!pressed.settled) {
          errors.push(where + " #" + id + ": the tab did not load (" + JSON.stringify(pressed) + ")");
          continue;
        }
        await walk(where + " #" + id);
      }
    }
    await leave(context);
  };
  await Promise.all(["de", "en"].map(walkLocale));
  return { errors, bars: [...found].sort(), visited };
}

// The gate's own attack: pages drawn here, measured as the app's are.
const FIXTURE_CSS = `
  body { margin: 0; font: 16px/1.4 sans-serif; }
  .bar { padding: 8px; }
  .filter-chip { font: inherit; padding: 2px 8px; }
  select { font: inherit; }
`;

const FIXTURES = {
  // The label column (A) at every width: every control from one edge.
  sound: `
    <div class="bar control-bar"><div class="control-bar__controls"
      style="display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 8px 10px">
      <span class="control-bar__label" id="a">Konto</span>
      <span class="filter-chips" role="group" aria-labelledby="a"><button class="filter-chip">Giro</button></span>
      <label class="control-bar__label" for="k">Anlageklasse</label>
      <select id="k"><option>Alle</option></select>
    </div></div>`,
  // One line at every width but 764 to 772 px, where the groups wrap and
  // each control starts after its own label (a tablet's breakpoint gone
  // wrong).
  wraps_at_768: `
    <style>
      .w { display: flex; gap: 8px; }
      .w > span { display: inline-flex; gap: 6px; align-items: center; }
      @media (min-width: 764px) and (max-width: 772px) { .w { flex-direction: column; align-items: flex-start; } }
    </style>
    <div class="bar control-bar"><div class="control-bar__controls w">
      <span class="control-bar__group"><span class="control-bar__label" id="a">Konto</span>
        <span class="filter-chips" role="group" aria-labelledby="a"><button class="filter-chip">Giro</button></span></span>
      <span class="control-bar__group"><label class="control-bar__label" for="k">Anlageklasse</label>
        <select id="k"><option>Alle</option></select></span>
    </div></div>`,
  // Labels set in CSS: the label's text is nowhere in the document, and
  // each control sits indented under its label, neither beside it nor on
  // its edge.
  css_label: `
    <style>
      .c .control-bar__label { display: block; }
      .c .control-bar__label::before { content: attr(data-text); }
      .c .ctl { display: block; margin-left: 24px; }
    </style>
    <div class="bar control-bar c"><div class="control-bar__controls">
      <span class="control-bar__label" id="a" data-text="Konto"></span>
      <span class="ctl filter-chips" role="group" aria-labelledby="a"><button class="filter-chip">Giro</button></span>
      <span class="control-bar__label" id="b" data-text="Typ"></span>
      <span class="ctl filter-chips" role="group" aria-labelledby="b"><button class="filter-chip">Kauf</button></span>
    </div></div>`
};

async function attack(browser) {
  const context = await browser.newContext({ viewport: { width: 1200, height: 900 } });
  const page = await context.newPage();
  const fixtures = {};
  for (const [name, html] of Object.entries(FIXTURES)) {
    await draw(page, "<!doctype html><html><head><style>" + FIXTURE_CSS + "</style></head><body>" + html + "</body></html>");
    const { report } = await walkBars(page, name);
    fixtures[name] = { widths: report.flatMap((r) => r.widths), errors: report.map((r) => r.error) };
    for (const r of report) console.error(r.error);
  }
  await leave(context);
  return { errors: [], fixtures };
}
// --- L3 end ---

const CASES = {
  stack_bar_layout: stackBarLayout,
  migrated_bar: migratedBar,
  // --- L3 begin ---
  every_bar: everyBar,
  attack: attack
  // --- L3 end ---
};

(async () => {
  const browser = await launchChromium();
  const errors = [];
  let extra = {};
  try {
    // A case may answer its own errors and what it found (L3).
    const answer = (await CASES[args.case](browser)) || {};
    errors.push(...(answer.errors || []));
    extra = { ...answer };
    delete extra.errors;
  } catch (error) {
    errors.push(String(error && error.message));
  } finally {
    await leave(browser);
  }
  const result = errors.length === 0 ? { ok: true, ...extra } : { ok: false, errors, ...extra };
  process.stdout.write(JSON.stringify(result) + "\n");
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
