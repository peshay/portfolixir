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
//
// `onWidth` (L5), when given, reads the page at 1200 and at 390 px, the
// widths every page is set to here anyway: the open prose check rides on
// these visits instead of making its own.
async function walkBars(page, where, swept = new Set(), onWidth = null) {
  await openDisclosures(page);
  const bars = await tagBars(page);
  const report = [];
  const labelled = new Set();
  const seen = new Set();
  const widths = new Map(bars.map((b) => [b.selector, []]));
  for (const width of [1200, 390]) {
    await atWidth(page, width);
    if (onWidth) await onWidth(width);
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
  // --- L5 begin ---
  const prose = new Prose();
  const started = Date.now();
  let proseMs = 0;
  // --- L5 end ---
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
      // --- L5 begin ---
      const readProse = async (width) => {
        const t = Date.now();
        await prose.read(page, where + " at " + width + " px");
        proseMs += Date.now() - t;
      };
      // --- L5 end ---
      const { bars, report } = await walkBars(page, where, swept, readProse);
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
    // --- L5 begin ---
    // Pages the walk opens for their prose alone (a bond's overview, its
    // strip's basis line): read at 1200 and 390 px, no bar swept, no tab
    // followed, so a page added for one paragraph costs a page's visit.
    for (const path of args.prose_addresses || []) {
      const response = await visit(page, base + path);
      const loaded = await settle(page);
      visited += 1;
      const where = locale + " " + path;
      if (!response || response.status() >= 400 || !loaded.settled) {
        errors.push(where + ": the page did not load (" + (response && response.status()) + ", " + JSON.stringify(loaded) + ")");
        continue;
      }
      for (const width of [1200, 390]) {
        await atWidth(page, width);
        const t = Date.now();
        await prose.read(page, where + " at " + width + " px");
        proseMs += Date.now() - t;
      }
      await atWidth(page, 1200);
    }
    // --- L5 end ---
    await leave(context);
  };
  await Promise.all(["de", "en"].map(walkLocale));
  // --- L5 begin ---
  const proseErrors = prose.errors();
  console.error("open prose: " + prose.checked + " paragraphs read in " + proseMs + " ms of a walk of " + (Date.now() - started) + " ms");
  for (const e of proseErrors) console.error(e);
  return {
    errors,
    bars: [...found].sort(),
    visited,
    prose: { errors: proseErrors, checked: prose.checked, ms: proseMs, walk_ms: Date.now() - started }
  };
  // --- L5 end ---
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

// --- L5 begin: open prose (issue 1435 (4), Sprint 29 L5) ---
// Open prose (DESIGN.md, amendment 2026-11-02, I1; the inventory
// `ux-design-2026-11-12-sprint29/06-control-bar-inventory.md` §3; board 06
// ⑤ to ⑩): no visible free paragraph runs past one sentence of at most 25
// words. A section's method sentences sit behind
// its ⓘ; what stays on the page is its basis line.
//
// The check rides on the walk above (L3), in the same page visits:
// `collect(page)` reads the paragraphs of the page as it stands, `Prose`
// gathers them over the whole walk and answers the breaches and the stale
// exceptions at its end.
//
// A *paragraph* is what a reader sees as one: a block-level box in `main`
// and the text of its inline content, across every inline element in it
// (a paragraph split into two spans, or into two gettext calls, is one),
// and two block siblings set one under the other with no paragraph spacing
// between them read as one as well. A paragraph is *free* outside:
//
// - an ⓘ (`details.metric-tooltip`): the method's place, the rule's target;
// - a data note (`.data-note`): it clamps to two lines (UX-DR17, I1);
// - a table, a list or a description list: rows and records, data;
// - a dialog, a filter sheet, a chart's tooltip: overlays the walk does
//   not measure as the page;
// - a stored record's own text (a research entry, a phone row, the
//   attention list): written by the operator or the agent, not the app;
// - a heading, a label, a legend, a button, a link: names, not prose.
//
// Sentences are counted with the abbreviations kept inside („z. B.“,
// „ggü.“, „p. a.“, „e.g.“, an ordinal, a single letter as „J.“ and „M.“ in
// a term), in German and in English. A basis line of facts joined by „·“
// is one sentence.

// The threshold (inventory §3, from the measured data): one sentence of at
// most 25 words.
const MAX_SENTENCES = 1;
const MAX_WORDS = 25;

// The registered exceptions: free paragraphs past the threshold that stay,
// each with its reason. An entry without a reason fails the walk, and so
// does one that excuses nothing over the threshold during the whole walk (a
// stale entry hides the next paragraph that lands where it points).
// `limit` bounds an excused paragraph still: past it, it breaks the rule.
//
// An alert (an error and its remedy, `p.alert-error`, `[role=alert]`) is
// not registered: the walk takes no action, so it shows none, and an entry
// that excuses nothing is stale. One a seed state shows is registered then.
const EMPTY_STATE = { sentences: 2, words: 50 };
const PROSE_EXCEPTIONS = [
  {
    selector: ".empty-state",
    reason:
      "an empty state: the state and where to act (EXPERIENCE.md on empty states), two sentences of at most 25 words each",
    limit: EMPTY_STATE
  },
  {
    selector: "[data-role='unassigned-hint']",
    reason: "an empty state's two parts: the share no category holds, and the link that assigns it",
    limit: EMPTY_STATE
  },
  {
    selector: "[data-role='no-plan-hint']",
    reason: "an empty state's two parts: no target plan for the view, and the link that creates one",
    limit: EMPTY_STATE
  },
  {
    selector: ".prediction-bands__why",
    reason:
      "an empty state's two parts: no band has the 20 resolved predictions a hit rate needs yet, and where the finding stands meanwhile",
    limit: EMPTY_STATE
  },
  {
    selector: "[data-role='assignment-basis']",
    reason: "a list of names (the accounts a bucket holds): data, not prose"
  },
  {
    selector: "[data-role='cost-recovery']",
    reason: "a figure's label: a question and its answer beside the figure"
  },
  {
    selector: "[data-role='trades-basis']",
    reason:
      "a registered basis line: facts joined by „·“ (depots, where fees and taxes count, income left out), each a parameter of the figures (UX-DR11), none a method",
    limit: { sentences: 1, words: 30 }
  },
  // Sprint 29 C6, integrated with Lane L: the review seed's crash window
  // (step 23) shows the Crashes list and this line under it.
  {
    selector: "[data-role='crash-unanswered']",
    reason:
      "a count line: the securities the list answers and, joined by „·“, how many lack an answer for each of at most three reasons (ADR-0058's answers counted), with „anzeigen“; figures, none a method",
    limit: { sentences: 1, words: 45 }
  },
  {
    selector: "form .hint",
    reason: "a form field's help: what the field takes, beside it (DESIGN.md I1 leaves a form's field help in place)",
    limit: EMPTY_STATE
  }
];

// The containers whose text is not a free paragraph (see the head).
const NOT_FREE = [
  "details.metric-tooltip",
  ".data-note",
  "table", "ul", "ol", "dl",
  "dialog", ".modal", ".filter-sheet", ".chart-tip", ".chart-tooltip", "[role='tooltip']",
  ".research-entry", ".phone-row", ".attention-list",
  "h1", "h2", "h3", "h4", "h5", "h6", "label", "legend", "summary", "button", "a", "select",
  "option", "textarea", "svg", "nav", "[role='tablist']"
].join(", ");

// Answers the visible free paragraphs of the page as it stands: their text,
// what they are (tag, class, data-role) and which exceptions they fall
// under (by index). Read in the page; counted in Node.
function collect(page, exceptions = PROSE_EXCEPTIONS) {
  return page.evaluate(
    ({ notFree, selectors }) => {
      const main = document.querySelector("main") || document.body;
      const BLOCK = /^(block|flex|grid|list-item|flow-root|table|table-caption)$/;
      const SKIP = "details, script, style, template, svg, .visually-hidden, .sr-only, [hidden]";
      const shown = (e) =>
        e.getClientRects().length > 0 &&
        e.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true });
      const isBlock = (e) => BLOCK.test(getComputedStyle(e).display);
      // The text of a block's inline content: its text nodes and every
      // inline element in it, never a block inside it (a block of its own).
      const runOf = (block) => {
        let text = "";
        const walk = (node) => {
          for (const child of node.childNodes) {
            if (child.nodeType === Node.TEXT_NODE) text += child.data;
            else if (child.nodeType === Node.ELEMENT_NODE) {
              if (child.matches(SKIP) || isBlock(child)) continue;
              const style = getComputedStyle(child);
              if (style.display === "none" || style.visibility === "hidden") continue;
              if (child.matches("br")) text += " ";
              walk(child);
            }
          }
        };
        walk(block);
        return text.replace(/\s+/g, " ").trim();
      };
      // In document order, never into a container that is not free nor
      // into one not displayed: a long table costs one test, not a style
      // per cell.
      const blocks = [];
      const PRUNE = "script, style, template, svg, .visually-hidden, .sr-only, [hidden], " + notFree;
      const visit = (e) => {
        if (e.matches(PRUNE)) return;
        const display = getComputedStyle(e).display;
        if (display === "none") return;
        if (BLOCK.test(display) && shown(e)) {
          const text = runOf(e);
          if (/[\p{L}\p{N}]/u.test(text)) blocks.push({ e, text });
        }
        for (const child of e.children) visit(child);
      };
      for (const child of main.children) visit(child);
      // Two block siblings, one right under the other with no paragraph
      // spacing, in the same voice: one paragraph to the reader.
      const merged = [];
      for (const b of blocks) {
        const last = merged[merged.length - 1];
        if (last) {
          const prev = last.els[last.els.length - 1];
          const a = prev.getBoundingClientRect();
          const r = b.e.getBoundingClientRect();
          const sa = getComputedStyle(prev);
          const sb = getComputedStyle(b.e);
          const lineHeight = parseFloat(sb.lineHeight) || parseFloat(sb.fontSize) * 1.2;
          if (
            prev.nextElementSibling === b.e &&
            Math.abs(a.left - r.left) <= 1 &&
            r.top - a.bottom >= -1 &&
            r.top - a.bottom < lineHeight / 2 &&
            sa.fontSize === sb.fontSize &&
            sa.color === sb.color
          ) {
            last.els.push(b.e);
            last.text += " " + b.text;
            continue;
          }
        }
        merged.push({ els: [b.e], text: b.text });
      }
      return merged.map(({ els, text }) => {
        const e = els[0];
        return {
          text,
          what: e.tagName.toLowerCase() + (e.className && typeof e.className === "string" ? "." + e.className.trim().split(/\s+/).join(".") : "") +
            (e.getAttribute("data-role") ? "[data-role='" + e.getAttribute("data-role") + "']" : "") +
            (els.length > 1 ? " + " + (els.length - 1) + " sibling(s)" : ""),
          matches: selectors
            .map((s, i) => (els.some((x) => x.closest(s)) ? i : -1))
            .filter((i) => i >= 0)
        };
      });
    },
    { notFree: NOT_FREE, selectors: exceptions.map((x) => x.selector) }
  );
}

// Abbreviations that end in a full stop inside a sentence, German and
// English; a single letter („J.“, „M.“, „S.“, „p. a.“) and an ordinal
// („3. Juni“) too.
const ABBREVIATIONS = [
  "z", "u", "d", "o", "v", "bzw", "ggf", "ggü", "inkl", "exkl", "ca", "Nr", "vgl", "etc", "evtl",
  "max", "min", "bspw", "Pp", "Mio", "Mrd", "Tsd", "Std", "Jan", "Feb", "Apr", "Jun", "Jul", "Aug",
  "Sep", "Sept", "Okt", "Nov", "Dez", "vs", "approx", "incl", "excl", "e\\.g", "i\\.e", "cf", "Mr", "Dr"
];
const GUARD = new RegExp("(^|[\\s(„\"])(" + ABBREVIATIONS.join("|") + "|\\p{L}|\\d+)\\.(?=\\s)", "giu");

function words(text) {
  return text.split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)).length;
}

function sentences(text) {
  const guarded = text.replace(GUARD, "$1$2§");
  return guarded
    .split(/(?<=[.!?])["“”»)]*\s+(?=[\p{Lu}„"“(\d])/u)
    .filter((s) => /\p{L}/u.test(s)).length;
}

// Validates a list of exceptions: each needs a selector and a reason.
function invalidExceptions(exceptions) {
  return exceptions
    .map((x, i) => {
      if (!x || typeof x.selector !== "string" || x.selector.trim() === "")
        return "open prose: exception " + i + " names no selector";
      if (typeof x.reason !== "string" || x.reason.trim().split(/\s+/).length < 3)
        return "open prose: the exception " + x.selector + " gives no reason";
      return null;
    })
    .filter(Boolean);
}

// Gathers the paragraphs of a walk, page by page, and answers its errors:
// each paragraph past the threshold that no exception excuses (once per
// text, at the first page it was seen on), each exception without a
// reason, and each that excused nothing.
class Prose {
  constructor(exceptions = PROSE_EXCEPTIONS) {
    this.exceptions = exceptions;
    this.used = new Set();
    this.seen = new Map();
    this.breaches = [];
    this.checked = 0;
  }

  async read(page, where) {
    for (const p of await collect(page, this.exceptions)) this.add(p, where);
  }

  add(p, where) {
    const key = p.what + "\n" + p.text;
    if (this.seen.has(key)) return;
    this.seen.set(key, where);
    this.checked += 1;
    const s = sentences(p.text);
    const w = words(p.text);
    if (s <= MAX_SENTENCES && w <= MAX_WORDS) return;
    const excusing = p.matches.map((i) => [i, this.exceptions[i]]);
    const within = excusing.filter(([, x]) => !x.limit || (s <= x.limit.sentences && w <= x.limit.words));
    if (within.length > 0) {
      within.forEach(([i]) => this.used.add(i));
      return;
    }
    this.breaches.push(
      where + ": the free paragraph " + p.what + " runs " + s + " sentence(s), " + w +
        " words (at most " + MAX_SENTENCES + " of " + MAX_WORDS + "): „" + p.text.slice(0, 160) +
        (p.text.length > 160 ? "…" : "") + "“"
    );
  }

  errors() {
    const stale = this.exceptions
      .map((x, i) => (this.used.has(i) ? null : "open prose: the exception " + x.selector + " excuses no paragraph on any page; remove it"))
      .filter(Boolean);
    return [...invalidExceptions(this.exceptions), ...this.breaches, ...stale];
  }
}

// The prose check's own attack: paragraphs drawn here, read as the app's
// are, with an exception list of its own (one without a reason, one that
// matches nothing).
const PROSE_FIXTURES = {
  // Two sentences in two spans of one paragraph (two gettext calls).
  split_spans: `<p><span>Der erste Satz steht hier.</span> <span>Der zweite folgt ihm.</span></p>`,
  // Two sentences in two paragraphs set as one: no spacing between them.
  split_blocks: `<div><p style="margin: 0">Der erste Satz steht hier.</p><p style="margin: 0">Der zweite folgt ihm.</p></div>`,
  // Two paragraphs with a paragraph's spacing: two, each one sentence.
  spaced: `<div><p style="margin: 0 0 1em">Der erste Satz steht hier.</p><p style="margin: 0">Der zweite folgt ihm.</p></div>`,
  // One sentence with its abbreviations, German and English.
  abbreviations: `<p>Kupon 2,5 % p. a. ggü. dem Vorjahr, z. B. im 3. Quartal, Restlaufzeit 4 J. 7 M. ab heute.</p><p>Counts per kind, e.g. buys and sells, i.e. what the filter selects.</p>`,
  // One sentence of 26 words.
  long_sentence: `<p>${Array.from({ length: 26 }, (_, i) => "Wort" + i).join(" ")}.</p>`,
  // Two sentences behind the ⓘ and in a data note: not free.
  behind_info: `<div>Kursbasis: splitbereinigt.<details class="metric-tooltip" open><summary>i</summary><p role="tooltip">Erster Satz der Methode. Zweiter Satz der Methode.</p></details></div><div class="data-note">Ein Hinweis. Mit seiner Abhilfe.</div>`,
  // An empty state: two sentences, excused; three, not.
  empty_state: `<p class="empty-state">Noch nichts erfasst. Erfassen über die API.</p>`,
  empty_state_long: `<p class="empty-state">Noch nichts erfasst. Erfassen über die API. Oder hier.</p>`
};

async function proseAttack(browser) {
  const context = await browser.newContext({ viewport: { width: 1200, height: 900 } });
  const page = await context.newPage();
  const prose = new Prose([
    { selector: ".empty-state", reason: "an empty state: the state and where to act", limit: { sentences: 2, words: 50 } },
    { selector: ".no-reason" },
    { selector: ".nowhere", reason: "an entry that matches no paragraph" }
  ]);
  for (const [name, html] of Object.entries(PROSE_FIXTURES)) {
    await draw(page, "<!doctype html><html><head><style>body { margin: 0; font: 16px/1.4 sans-serif; }</style></head><body><main>" + html + "</main></body></html>");
    await prose.read(page, name);
  }
  await leave(context);
  const errors = prose.errors();
  const fixtures = Object.fromEntries(
    Object.keys(PROSE_FIXTURES).map((name) => [name, errors.filter((e) => e.startsWith(name + ":"))])
  );
  for (const e of errors) console.error(e);
  return { errors: [], fixtures, registry: errors.filter((e) => e.startsWith("open prose:")) };
}
// --- L5 end ---

const CASES = {
  stack_bar_layout: stackBarLayout,
  migrated_bar: migratedBar,
  // --- L3 begin ---
  every_bar: everyBar,
  attack: attack,
  // --- L3 end ---
  // --- L5 begin ---
  prose_attack: proseAttack
  // --- L5 end ---
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
