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

const CASES = {
  stack_bar_layout: stackBarLayout
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
