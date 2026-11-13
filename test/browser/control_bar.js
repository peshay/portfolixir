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
const { FONTS, useFont, eachFont, fontsHere } = require("./fonts");

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
// sidebar leaves the bar under its fold, the label column (A); at 900 px,
// without the sidebar, one line again; at 390 and 320 px, where the label
// column and the widest control do not fit the bar with room in every font
// (its floor of 380 px since PR 2's closing act, board 06 ⑮; the label
// column at 390 px until then), every label above its control (B): the
// container query on the bar decides, never the viewport. In English and
// in German, whose „Klassifizierung“ is the longest label, each in Inter
// and in DejaVu Sans (fonts.js); no control leaves the bar and the page
// never scrolls sideways.
async function stackBarLayout(browser) {
  const errors = [];
  const host = new URL(base).hostname;
  const expected = { 1200: "line", 1024: "column", 900: "line", 390: "above", 320: "above" };
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
      // In each font (fonts.js): the layout a width shows is the bar's
      // fold and floor, so it is the same in both.
      await eachFont(page, async (font) => {
        const m = await measure(page, STACK_GROUPS, "[data-role='stack-bar']");
        const { layout, exact } = layoutOf(m);
        const label = locale + " at " + width + " px in " + font.name + ": ";
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
      });
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
    // Visible to the eye: a screen reader's label (`.sr-only`, a box of a
    // pixel or less) names nothing on the screen (PR 2 closing act).
    const visible = (e) => {
      const r = e.getBoundingClientRect();
      const s = getComputedStyle(e);
      return (
        r.width > 1 && r.height > 1 && s.visibility !== "hidden" && s.display !== "none" &&
        !e.closest(".visually-hidden, .sr-only, [hidden], details:not([open]) > :not(summary)")
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
    // Any element in the bar that a control or a family names by its
    // aria-labelledby is a label, whatever its class (PR 2 closing act: a
    // plain span named so was read as no label, and its bar went unmeasured).
    const inBar = (e) => rootEls.some((r) => r.contains(e));
    const named = all("[aria-labelledby]")
      .flatMap((e) => e.getAttribute("aria-labelledby").split(/\s+/))
      .map((id) => document.getElementById(id))
      .filter((e) => e && inBar(e));
    const labels = [...new Set([...all(LABEL), ...cssLabels, ...named])].filter(
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
      // A bar on the component: the width its container queries read (its
      // content box) and the named widths it switches at, its fold and its
      // floor (PR 2 closing act: the sweep steps to each crossing).
      ...(() => {
        const e = rootEls[0];
        if (!e.matches(".control-bar")) return { container: null, folds: [] };
        const s = getComputedStyle(e);
        const px = (v) => parseFloat(v) || 0;
        return {
          container: (
            e.getBoundingClientRect().width - px(s.paddingLeft) - px(s.paddingRight) -
              px(s.borderLeftWidth) - px(s.borderRightWidth)
          ),
          folds: [...e.classList]
            .map((c) => /^control-bar--(?:fold|floor)-(\d+)$/.exec(c))
            .filter(Boolean)
            .map((match) => Number(match[1]))
        };
      })(),
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
      await eachFont(page, async (font) => {
        const m = await measureBar(page, bar.roots);
        const label = args.bar + ", " + locale + " at " + width + " px in " + font.name + ": ";
        console.error(label + JSON.stringify(m));
        if (!m.visible) {
          if (bar.shows.includes(width)) errors.push(label + "the bar is not shown");
        } else {
          for (const e of breaches(m, bar)) errors.push(label + e);
        }
      });
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
// of 8 (768, a tablet's, among them), 390, the phone the plan names, and
// 1680 and 1920, the wide screens past them (PR 2 closing act). Between two
// steps the sweep adds, per page, both sides of each width its stylesheets'
// media queries switch at (`mediaSides`), and per bar on the component both
// sides of where the bar crosses its own fold and floor (`crossings`): a
// break in a band narrower than a step sits at one of those.
const WIDEST = 1920;
const NARROWEST = 320;
const SWEEP = [390, 1680, WIDEST];
for (let width = 1440; width >= NARROWEST; width -= 8) SWEEP.push(width);
SWEEP.sort((a, b) => b - a);

// Both sides of every window width a media query of the page's stylesheets
// switches at: `(max-width: 720px)` holds at 720 and not at 721,
// `(min-width: 721px)` at 721 and not at 720; rem and em at 16 px.
function mediaSides(page) {
  return page.evaluate(
    ({ narrowest, widest }) => {
      const sides = new Set();
      const read = (rules) => {
        for (const rule of rules) {
          if (rule instanceof CSSMediaRule) {
            const text = rule.conditionText || rule.media.mediaText;
            const forms = [
              [/\((min|max)-width:\s*([\d.]+)(px|r?em)\)/g, (m) => [m[1] === "min" ? ">=" : "<=", m[2], m[3]]],
              [/\(width\s*(<=|>=|<|>)\s*([\d.]+)(px|r?em)\)/g, (m) => [m[1], m[2], m[3]]]
            ];
            for (const [pattern, parts] of forms) {
              for (const m of text.matchAll(pattern)) {
                const [op, value, unit] = parts(m);
                const n = parseFloat(value) * (unit === "px" ? 1 : 16);
                // The last width that holds and the first that does not.
                const edge = op === "<=" ? Math.floor(n) : op === "<" ? Math.ceil(n) - 1 : op === ">=" ? Math.ceil(n) - 1 : Math.floor(n);
                sides.add(edge);
                sides.add(edge + 1);
              }
            }
          }
          if (rule.cssRules) read(rule.cssRules);
        }
      };
      for (const sheet of document.styleSheets) {
        try {
          read(sheet.cssRules);
        } catch (_error) {
          // A stylesheet of another origin cannot be read; the app has none.
        }
      }
      return [...sides].filter((w) => w >= narrowest && w <= widest);
    },
    { narrowest: NARROWEST, widest: WIDEST }
  );
}

// The window widths, among `measures` (width → the bar's measure), between
// which a bar on the component crosses one of its fold and floor: pairs of
// neighbouring widths with its container on either side of the named width.
function crossingPairs(measures) {
  const seen = [...measures.entries()].filter(([, m]) => m.visible && m.container != null).sort((a, b) => a[0] - b[0]);
  const pairs = [];
  for (let i = 1; i < seen.length; i += 1) {
    const [low, a] = seen[i - 1];
    const [high, b] = seen[i];
    for (const fold of a.folds) {
      if ((a.container > fold) !== (b.container > fold) && high - low > 1) pairs.push({ low, high, fold, above: b.container > fold });
    }
  }
  return pairs;
}

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
//
// `strays` (PR 2 closing act), when given, gathers the labelled controls
// that stand outside every bar found, over a whole walk; without it, the
// page's own are reported with its bars.
async function walkBars(page, where, swept = new Set(), onWidth = null, strays = null) {
  await openDisclosures(page);
  const bars = await tagBars(page);
  const report = [];
  const labelled = new Set();
  const seen = new Set();
  const widths = new Map(bars.map((b) => [b.selector, []]));
  const ownStrays = strays || new Strays([]);
  for (const width of [1200, 390]) {
    await atWidth(page, width);
    if (onWidth) await onWidth(width);
    await ownStrays.read(page, where + " at " + width + " px");
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
  // Per bar and font, the widths it breaks at (fonts.js: every width is
  // measured in Inter and in the fallback font, the fallback drawn on the
  // bars and what stands beside them, not on the whole page).
  const broken = new Map(measured.map((b) => [b.selector, new Map(FONTS.map((f) => [f.name, new Map()]))]));
  const byWidth = new Map(measured.map((b) => [b.selector, new Map()]));
  // The fonts in turn at each width, the one the last width ended in
  // first, so the page changes font once per width, not twice.
  const scope = measured.map((b) => b.selector);
  let fonts = FONTS;
  const sweepAt = async (width) => {
    await atWidth(page, width);
    for (const [i, font] of fonts.entries()) {
      if (i > 0) await useFont(page, font, scope);
      const ms = await measureBars(page, measured.map((b) => b.selector));
      measured.forEach((bar, i) => {
        const m = ms[i];
        // The fold and the floor are crossed where the container is, the
        // same in every font: the page's own font's measure finds them.
        if (font === FONTS[0]) byWidth.get(bar.selector).set(width, m);
        if (!m.visible) return;
        seen.add(bar.selector);
        const found = breaches(m, { everyFamilyNamed: bar.component, sweep: true });
        if (found.length === 0) return;
        broken.get(bar.selector).get(font.name).set(width, found);
        console.error(where + " " + bar.name + " at " + width + " px in " + font.name + ": " + JSON.stringify(m));
      });
    }
    fonts = [...fonts].reverse();
  };
  if (measured.length > 0) {
    const widths = [...new Set([...SWEEP, ...(await mediaSides(page))])].sort((a, b) => b - a);
    for (const width of widths) await sweepAt(width);
    // Where a bar on the component crosses its fold or its floor between
    // two steps: halved down to the two neighbouring widths on either side,
    // then one more on each side (PR 2 closing act).
    for (const bar of measured) {
      const measures = byWidth.get(bar.selector);
      for (const { low, high, fold, above } of crossingPairs(measures)) {
        let lo = low;
        let hi = high;
        while (hi - lo > 1) {
          const mid = Math.floor((lo + hi) / 2);
          await sweepAt(mid);
          const m = measures.get(mid);
          if (!m.visible || m.container == null) break;
          if (m.container > fold === above) hi = mid;
          else lo = mid;
        }
        for (const width of [lo - 1, lo, hi, hi + 1]) {
          if (width >= NARROWEST && width <= WIDEST && !measures.has(width)) await sweepAt(width);
        }
      }
    }
  }
  if (measured.length > 0) await useFont(page, FONTS[0]);
  console.error(where + ": swept " + measured.map((b) => b.name).join(", ") + " in " + (Date.now() - started) + " ms");
  for (const bar of measured) {
    // A break at the same widths in every font is one break, named once
    // with every font; one that differs is named per font.
    const inFonts = [...broken.get(bar.selector)].filter(([, at]) => at.size > 0);
    const key = (at) => [...at.keys()].sort((a, b) => a - b).join(",");
    const everywhere = inFonts.length === FONTS.length && inFonts.every(([, at]) => key(at) === key(inFonts[0][1]));
    const breaks = everywhere ? [[FONTS.map((f) => f.name).join(" and "), inFonts[0][1]]] : inFonts;
    for (const [font, at] of breaks) {
      const first = [...at.entries()].sort((a, b) => a[0] - b[0])[0];
      report.push({
        bar: bar.name,
        font,
        widths: [...at.keys()],
        error:
          where + ": the bar " + bar.name + " breaks the rule in " + font + " at " + ranges([...at.keys()]) +
          "; at " + first[0] + " px: " + first[1].join("; ")
      });
    }
  }
  for (const bar of measured.filter((b) => b.component && !seen.has(b.selector))) {
    report.push({ bar: bar.name, widths: [], error: where + ": the bar " + bar.name + " is never shown, so it was never measured" });
  }
  if (!strays) for (const error of ownStrays.breaches) report.push({ bar: "outside", widths: [], error });
  await atWidth(page, 1200);
  return { bars: bars.filter((b) => seen.has(b.selector)).map((b) => b.name), report };
}

// --- PR 2 closing act begin (the attack lens of Lane L, S1) ---
// A labelled control the walk finds outside every bar it tagged: a bar
// under a class no list above holds is no bar to the walk, and so it was
// never measured. Its controls are found by what they are instead: a
// control (`CONTROL` of the measure) or a chip family (an element with
// role="group", or the parent, holding a `.filter-chip`) with a visible
// label of its own: an element its aria-labelledby names, a `<label for>`
// its id names, or a `<label>` around it with text of its own. One outside
// every tagged bar, a dialog, a filter sheet and an ⓘ breaks the rule
// unless an exception below names it with its reason.
// The reasons, as L4's static check gives them for the same markup
// (test/invariants/control_bar_labelled_controls_test.exs).
const FORM_FIELDS =
  "a form's fields, each label above its field, one field under another or in a grid of fields: a form, not a bar of controls side by side";
const SINGLE =
  "one labelled control on a line of its own, with no second labelled control beside or under it to share an edge with: not a bar";
const STRAY_EXCEPTIONS = [
  { selector: "#research-entry-form", reason: FORM_FIELDS + " (a security's Research tab, „Eintrag anhängen“)" },
  { selector: ".category-form", reason: FORM_FIELDS + " (a classification's new category: name, parent, colour, description)" },
  { selector: "#classification-form", reason: SINGLE + " (a new classification's name, then „Klassifizierung anlegen“)" },
  { selector: "#soll-plan-picker-form", reason: SINGLE + " (a classification's target plan version)" },
  { selector: "[id^='liquidity-role-form-']", reason: SINGLE + " (a cash account's liquidity role, one per account row)" }
];

// The labelled controls outside every tagged bar on the page as it stands,
// each with the exceptions it falls under (by index).
function strayControls(page, exceptions) {
  return page.evaluate(
    ({ selectors }) => {
      const visible = (e) => {
        const r = e.getBoundingClientRect();
        const s = getComputedStyle(e);
        return (
          r.width > 1 && r.height > 1 && s.visibility !== "hidden" && s.display !== "none" &&
          !e.closest(".visually-hidden, .sr-only, [hidden], details:not([open]) > :not(summary)")
        );
      };
      const CONTROL =
        ".segmented-control, select, input:not([type=hidden]):not([type=checkbox]):not([type=radio]), " +
        "[role='group']:has(.filter-chip), :has(> .filter-chip)";
      const letters = (t) => /\p{L}/u.test(t);
      // The text a label shows, its control's own text (a select's options)
      // and a screen reader's text left out.
      const shown = (label, control) => {
        let text = "";
        const walker = document.createTreeWalker(label, NodeFilter.SHOW_TEXT);
        for (let n = walker.nextNode(); n; n = walker.nextNode()) {
          const parent = n.parentElement;
          if (control.contains(n) || parent.closest("select, option, button, .visually-hidden, .sr-only")) continue;
          text += n.data + " ";
        }
        return text.replace(/\s+/g, " ").trim();
      };
      const labelOf = (c) => {
        for (const id of (c.getAttribute("aria-labelledby") || "").split(/\s+/).filter(Boolean)) {
          const l = document.getElementById(id);
          if (l && !l.contains(c) && visible(l) && letters(shown(l, c))) return { el: l, text: shown(l, c) };
        }
        if (c.id) {
          for (const l of document.querySelectorAll("label[for='" + CSS.escape(c.id) + "']")) {
            if (visible(l) && letters(shown(l, c))) return { el: l, text: shown(l, c) };
          }
        }
        const around = c.parentElement && c.parentElement.closest("label");
        if (around && visible(around) && letters(shown(around, c))) return { el: around, text: shown(around, c) };
        return null;
      };
      const out = [];
      for (const c of document.querySelectorAll(CONTROL)) {
        if (c.closest("dialog, .modal, .filter-sheet, details.metric-tooltip")) continue;
        // A family's own chips, or a control inside a family, are the family's.
        if (c.parentElement && c.parentElement.closest(".segmented-control, [role='group']:has(.filter-chip)")) continue;
        if (!visible(c)) continue;
        const label = labelOf(c);
        if (!label) continue;
        // In a bar the walk tagged with its label, it is that bar's: the
        // bar is labelled and measured. A label outside its control's bar
        // leaves the bar read as unlabelled, so the control is a stray.
        const bar = c.closest("[data-walk-bar]");
        if (bar && bar.contains(label.el)) continue;
        const html = c.outerHTML.slice(0, c.outerHTML.indexOf(">") + 1).slice(0, 160);
        out.push({
          label: label.text.slice(0, 40),
          html,
          matches: selectors.map((s, i) => (c.closest(s) ? i : -1)).filter((i) => i >= 0)
        });
      }
      return out;
    },
    { selectors: exceptions.map((x) => x.selector) }
  );
}

// Gathers the stray controls of a walk, once per control and label, and
// answers its errors: each stray no exception excuses, each exception
// without a reason, and each that excused nothing.
class Strays {
  constructor(exceptions = STRAY_EXCEPTIONS) {
    this.exceptions = exceptions;
    this.used = new Set();
    this.seen = new Set();
    this.breaches = [];
  }

  async read(page, where) {
    for (const s of await strayControls(page, this.exceptions)) this.add(s, where);
  }

  add(s, where) {
    if (s.matches.length > 0) {
      s.matches.forEach((i) => this.used.add(i));
      return;
    }
    const key = s.html + "\n" + s.label;
    if (this.seen.has(key)) return;
    this.seen.add(key);
    this.breaches.push(
      where + ": a control labelled „" + s.label + "“ stands outside every bar of labelled controls (" + s.html +
        "): build it as a group of PortfolixirWeb.ControlBar.bar/1, or register an exception with its reason in STRAY_EXCEPTIONS"
    );
  }

  errors() {
    const stale = this.exceptions
      .map((x, i) => (this.used.has(i) ? null : "outside the bars: the exception " + x.selector + " excuses no control on any page; remove it"))
      .filter(Boolean);
    return [...invalidExceptions(this.exceptions, "outside the bars"), ...this.breaches, ...stale];
  }
}
// --- PR 2 closing act end ---

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
  // PR 2 closing act: the labelled controls outside every bar, over the walk.
  const strays = new Strays();
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
      const { bars, report } = await walkBars(page, where, swept, readProse, strays);
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
  errors.push(...strays.errors());
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
  :root { --font-sans: Inter, sans-serif; }
  body { margin: 0; font: 16px/1.4 sans-serif; }
  .bar { padding: 8px; }
  .filter-chip { font: inherit; padding: 2px 8px; }
  select { font: inherit; }
`;

// --- PR 2 closing act begin (the attack lens of Lane L, pr2-l-attack) ---
// Two chip families, each indented under its label: neither beside it nor
// on its edge. `label(id, text)` draws the label; `family` is the class of
// the chips' element.
const brokenPairs = (cls, label, family = "chip-row") => `
  <style>.${cls} .grp { display: block; } .${cls} .ctl { display: block; margin-left: 24px; }</style>
  <div class="bar ${cls}">
    <span class="grp">${label("a1", "Konto")}
      <span class="ctl ${family}" role="group" aria-labelledby="a1"><button class="filter-chip">Giro</button></span></span>
    <span class="grp">${label("b1", "Typ")}
      <span class="ctl ${family}" role="group" aria-labelledby="b1"><button class="filter-chip">Kauf</button></span></span>
  </div>`;
// A bar on the component, one line, whose chip family's only label is
// `label`, hidden from the eye as a screen reader's label is.
const srOnlyBar = (label) => `
  <style>.sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden;
    clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }</style>
  <div class="bar control-bar"><div class="control-bar__controls" style="display: flex; gap: 8px; align-items: center">
    <span class="control-bar__group">${label}
      <span class="filter-chips" role="group" aria-labelledby="a"><button class="filter-chip">Giro</button><button class="filter-chip">Depot</button></span></span>
    <span class="control-bar__group"><label class="control-bar__label" for="k">Typ</label>
      <select id="k"><option>Alle</option></select></span>
  </div></div>`;
// One line at every width but in the windows `media` names, where the
// groups stack and each control starts after its own label.
const viewportBand = (media) => `
  <style>
    .w { display: flex; gap: 8px; }
    .w > span { display: inline-flex; gap: 6px; align-items: center; }
    @media ${media} { .w { flex-direction: column; align-items: flex-start; } }
  </style>
  <div class="bar control-bar"><div class="control-bar__controls w">
    <span class="control-bar__group"><span class="control-bar__label" id="a">Konto</span>
      <span class="filter-chips" role="group" aria-labelledby="a"><button class="filter-chip">Giro</button></span></span>
    <span class="control-bar__group"><label class="control-bar__label" for="k">Anlageklasse</label>
      <select id="k"><option>Alle</option></select></span>
  </div></div>`;
// --- PR 2 closing act end ---

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
    </div></div>`,
  // --- PR 2 closing act begin (the attack lens of Lane L, pr2-l-attack) ---
  // A labelled chip bar under a class no list of the walk holds, its labels
  // plain elements named by the families' aria-labelledby: neither found
  // as a bar nor read as labelled, so it was never measured (S1).
  unlisted_class: brokenPairs("period-bar", (id, text) => `<span id="${id}">${text}</span>`),
  unlisted_class_label: brokenPairs("period-bar", (id, text) => `<label id="${id}">${text}</label>`),
  // The same pairs in a bar the walk knows (`.toolbar`), their labels
  // named only by aria-labelledby: found, but read as unlabelled (S1).
  unnamed_labels: brokenPairs("toolbar", (id, text) => `<span id="${id}">${text}</span>`, "filter-chips"),
  // A family on the component named only by a screen reader's label (S2).
  sr_only_family: srOnlyBar(`<span class="control-bar__label sr-only" id="a">Konto</span>`),
  sr_only_label: srOnlyBar(`<label class="sr-only" id="a">Konto</label>`),
  // The component's own fold set 7 px too low: its line wraps while the
  // bar is 761 to 766 px wide, just above the fold, between two of the
  // sweep's 8 px steps (S3).
  fold_crossing: `
    <style>
      .control-bar { container: control-bar / inline-size; }
      .f .control-bar__controls { display: flex; flex-wrap: wrap; gap: 8px 0; }
      .f .control-bar__group { display: inline-flex; gap: 6px; align-items: center; }
      .f .one { width: 400px; } .f .two { width: 359px; margin-left: 8px; }
      @container control-bar (max-width: 760px) {
        .control-bar--fold-760 > .control-bar__controls { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 8px 10px; }
        .control-bar--fold-760 .control-bar__group { display: contents; }
        .f .one, .f .two { width: auto; margin: 0; }
      }
    </style>
    <div class="bar control-bar control-bar--fold-760 control-bar--floor-330 f"><div class="control-bar__controls">
      <span class="control-bar__group one"><span class="control-bar__label" id="a">Konto</span>
        <span class="filter-chips" role="group" aria-labelledby="a"><button class="filter-chip">Giro</button></span></span>
      <span class="control-bar__group two"><label class="control-bar__label" for="k">Anlageklasse</label>
        <select id="k"><option>Alle</option></select></span>
    </div></div>`,
  // Breaks only in a band of windows narrower than a step, at a tablet's
  // 761 to 767 px and at 321 to 327 px, and only past 1440 px (S3).
  band_761_767: viewportBand("(min-width: 761px) and (max-width: 767px)"),
  band_321_327: viewportBand("(min-width: 321px) and (max-width: 327px)"),
  wide_1441: viewportBand("(min-width: 1441px)"),
  // --- PR 2 closing act end ---
  // --- PR 2 closing act, the fallback font begin (fonts.js) ---
  // A fold measured in Inter alone: the line needs 668 px in Inter and 706
  // px in DejaVu Sans, the fold is 680, so the line holds in Inter at every
  // width and wraps in DejaVu Sans while the bar is 681 to 706 px wide
  // (697 to 722 px windows), as CI's runner, without Inter, drew the
  // Crashes bar.
  fallback_font: `
    <style>
      .control-bar { container: control-bar / inline-size; }
      .ff { font: 14px/1.4 var(--font-sans); }
      .ff select, .ff .filter-chip { font: inherit; }
      .ff .control-bar__controls { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
      .ff .control-bar__group { display: inline-flex; gap: 6px; align-items: center; }
      @container control-bar (max-width: 680px) {
        .control-bar--fold-680 > .control-bar__controls { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 8px 10px; }
        .control-bar--fold-680 .control-bar__group { display: contents; }
        .control-bar--fold-680 select { max-width: 100%; }
      }
    </style>
    <div class="bar control-bar control-bar--fold-680 ff"><div class="control-bar__controls">
      <span class="control-bar__group"><label class="control-bar__label" for="w">Fenster</label>
        <select id="w"><option>Synthetic dip · 15.08.2022–29.08.2022 · manuell</option></select></span>
      <span class="control-bar__group"><span class="control-bar__label" id="l">Liste</span>
        <span class="filter-chips" role="group" aria-labelledby="l"><button class="filter-chip">Verlierer</button><button
          class="filter-chip">Gewinner</button><button class="filter-chip">Erholer</button></span></span>
    </div></div>`
  // --- PR 2 closing act, the fallback font end ---
};

async function attack(browser) {
  const context = await browser.newContext({ viewport: { width: 1200, height: 900 } });
  const page = await context.newPage();
  const fixtures = {};
  for (const [name, html] of Object.entries(FIXTURES)) {
    await draw(page, "<!doctype html><html><head><style>" + FIXTURE_CSS + "</style></head><body>" + html + "</body></html>");
    const { report } = await walkBars(page, name);
    fixtures[name] = {
      widths: report.flatMap((r) => r.widths),
      errors: report.map((r) => r.error),
      fonts: [...new Set(report.map((r) => r.font).filter(Boolean))]
    };
    for (const r of report) console.error(r.error);
  }
  // PR 2 closing act: the strays' own exception list, one that excuses the
  // unlisted bar, one without a reason and one that excuses nothing.
  const strays = new Strays([
    { selector: ".excused", reason: "a probe that excuses the bar it wraps" },
    { selector: ".no-reason" },
    { selector: ".nowhere", reason: "an entry that matches no control" }
  ]);
  await draw(page, "<!doctype html><html><head><style>" + FIXTURE_CSS + "</style></head><body><div class='excused'>" + FIXTURES.unlisted_class + "</div></body></html>");
  await walkBars(page, "excused", new Set(), null, strays);
  // The fonts' own check (fonts.js): both fonts the walk measures in are
  // found, and a family no machine has is not.
  const fonts = await fontsHere(page, [...FONTS.map((f) => f.name), "Synthetic Missing Sans"]);
  await leave(context);
  return { errors: [], fixtures, strays: strays.errors(), fonts };
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
      // Two blocks, one right under the other on the same left edge with
      // no paragraph spacing, in the same voice: one paragraph to the
      // reader, siblings or not (PR 2 closing act: two cousins, each in a
      // wrapper of its own, read as two).
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
            !prev.contains(b.e) &&
            !b.e.contains(prev) &&
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
// („3. Juni“) too. A number ends its sentence („seit 2019. Ältere …“,
// „Offen: 3. Aufgelöste …“) unless the next word is lower case, a month
// or „Quartal“: then it is an ordinal (PR 2 closing act).
const ABBREVIATIONS = [
  "z", "u", "d", "o", "v", "bzw", "ggf", "ggü", "inkl", "exkl", "ca", "Nr", "vgl", "etc", "evtl",
  "max", "min", "bspw", "Pp", "Mio", "Mrd", "Tsd", "Std", "Jan", "Feb", "Apr", "Jun", "Jul", "Aug",
  "Sep", "Sept", "Okt", "Nov", "Dez", "vs", "approx", "incl", "excl", "e\\.g", "i\\.e", "cf", "Mr", "Dr"
];
const ORDINAL_NEXT =
  "\\p{Ll}|(?:Jan(?:uar|uary)?|Feb(?:ruar|ruary)?|März|Mär|March|Mar|Apr(?:il)?|Mai|May|Jun[ie]?|Jul[iy]?|" +
  "Aug(?:ust)?|Sept?(?:ember)?|Okt(?:ober)?|Oct(?:ober)?|Nov(?:ember)?|Dez(?:ember)?|Dec(?:ember)?|Quartal)(?=[\\s.,;:)]|$)";
const GUARD = new RegExp("(^|[\\s(„\"])(" + ABBREVIATIONS.join("|") + "|\\p{L})\\.(?=\\s)", "giu");
// Case-sensitive, so „\\p{Ll}“ reads lower case only.
const ORDINAL = new RegExp("(^|[\\s(„\"])(\\d+)\\.(?=\\s+(?:" + ORDINAL_NEXT + "))", "gu");

function words(text) {
  return text.split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)).length;
}

function sentences(text) {
  const guarded = text.replace(GUARD, "$1$2§").replace(ORDINAL, "$1$2§");
  return guarded
    .split(/(?<=[.!?])["“”»)]*\s+(?=[\p{Lu}„"“(\d])/u)
    .filter((s) => /\p{L}/u.test(s)).length;
}

// Validates a list of exceptions: each needs a selector and a reason.
function invalidExceptions(exceptions, what = "open prose") {
  return exceptions
    .map((x, i) => {
      if (!x || typeof x.selector !== "string" || x.selector.trim() === "")
        return what + ": exception " + i + " names no selector";
      if (typeof x.reason !== "string" || x.reason.trim().split(/\s+/).length < 3)
        return what + ": the exception " + x.selector + " gives no reason";
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
  empty_state_long: `<p class="empty-state">Noch nichts erfasst. Erfassen über die API. Oder hier.</p>`,
  // --- PR 2 closing act begin (the attack lens of Lane L, pr2-l-attack) ---
  // Two sentences in two blocks set as one, each in a wrapper of its own:
  // cousins, not siblings (S2).
  nested_split: `<div><div><p style="margin: 0">Ein Satz steht hier.</p></div><div><p style="margin: 0">Ein anderer folgt ihm.</p></div></div>`,
  // A sentence that ends in a year or a count, then the next one (S3).
  year_end: `<p>Die Kursreihe beginnt im Jahr 2019. Ältere Kurse fehlen noch.</p>`,
  count_end: `<p>Offene Prognosen: 3. Aufgelöste folgen nach dem Stichtag.</p>`,
  en_year_end: `<p>Quotes start in 2019. Older quotes are missing.</p>`,
  // An ordinal before a month or a quarter stays inside its sentence.
  ordinals: `<p>Fällig am 3. Juni, gezahlt am 1. Mai, gebucht im 2. Quartal, gemeldet am 4. Dezember.</p>`
  // --- PR 2 closing act end ---
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
