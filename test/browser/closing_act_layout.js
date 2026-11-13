// Layout checks from Sprint 26's closing act (the design critic's and the
// UAT persona's findings), driven in a real Chromium by
// test/browser/closing_act_layout_test.exs, which boots the endpoint, seeds
// a synthetic world and passes the base URL, the case to run and the ids it
// seeded as JSON in the only argument. LiveViewTest applies no CSS, so where
// a box lands on the screen is measured here.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "errors":
// ["..."]}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");
const { eachFont } = require("./fonts");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;

function check(condition, message) {
  if (!condition) throw new Error(message);
}

// Goes to `path` once the page before has settled (settle.js): leaving a
// page mid-load stops its LiveView and kills a load task mid-query, which
// the sandbox logs as a dropped connection, and the log noise rule fails
// the run (CI's browser job on #1447).
async function ready(page, path) {
  await visit(page, base + path);
  await page.waitForSelector("[data-phx-main].phx-connected");
}

async function nextFrame(page) {
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
}

// V4: the delete dialog opens centred, not pinned to the page's left gutter.
async function dialogCentred(page, label) {
  await page.waitForSelector("#delete-preview-dialog[open]");
  await nextFrame(page);
  const box = await page.evaluate(() => {
    const r = document.querySelector("#delete-preview-dialog").getBoundingClientRect();
    return { left: r.left, right: document.documentElement.clientWidth - r.right };
  });
  check(
    Math.abs(box.left - box.right) <= 1,
    label + ": the dialog is not centred " + JSON.stringify(box)
  );
  await page.keyboard.press("Escape");
  await page.waitForSelector("#delete-preview-dialog", { state: "detached" });
}

async function deleteDialogs(browser) {
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  await ready(page, "/classifications/" + args.classification_id);

  await page.click("header.detail-head button.button-danger");
  await dialogCentred(page, "the classification's delete dialog at 1200");

  await page.click(
    "button[phx-click='ask_delete_category'][phx-value-id='" + args.category_id + "']"
  );
  await dialogCentred(page, "the category's delete dialog at 1200");
  await leave(page);
}

// V3: "After the sale"'s table wrapper on a security's Trades tab is as tall
// as its table, so the legend follows it, and in fullscreen it is no nested
// scroll box.
async function hindsightWrapper(page, label) {
  await page.waitForSelector(".hs-detail-section .hs-table-wrapper");
  await nextFrame(page);
  const m = await page.evaluate(() => {
    const wrapper = document.querySelector(".hs-detail-section .hs-table-wrapper");
    const table = wrapper.querySelector("table");
    const legend = document.querySelector(".hs-detail-section .hs-legend");
    const w = wrapper.getBoundingClientRect();
    return {
      wrapper: w.height,
      table: table.getBoundingClientRect().height,
      gap: legend ? legend.getBoundingClientRect().top - w.bottom : null,
      scroll: wrapper.scrollHeight - wrapper.clientHeight
    };
  });
  check(m.wrapper - m.table <= 2, label + ": the wrapper is taller than its table " + JSON.stringify(m));
  check(m.gap === null || m.gap <= 16, label + ": the legend is pushed away " + JSON.stringify(m));
  check(m.scroll <= 1, label + ": the wrapper scrolls on its own " + JSON.stringify(m));
}

// V1: an ⓘ panel on a short tab in fullscreen opens whole: no box between
// it and the scrolling pane cuts it.
async function tipWhole(page, tipSelector, label) {
  await page.waitForSelector(tipSelector + " > summary");
  await page.click(tipSelector + " > summary");
  await page.waitForFunction((s) => document.querySelector(s).open, tipSelector);
  await nextFrame(page);
  const cut = await page.evaluate((s) => {
    const tip = document.querySelector(s);
    const panel = tip.querySelector("p[role='tooltip']") || tip.querySelector("p");
    const r = panel.getBoundingClientRect();
    const cuts = [];
    for (let el = tip.parentElement; el && el !== document.body; el = el.parentElement) {
      const style = getComputedStyle(el);
      if (style.overflowY === "visible" && style.overflowX === "visible") continue;
      const c = el.getBoundingClientRect();
      const yClipped = style.overflowY !== "visible" && (r.bottom > c.bottom + 0.5 || r.top < c.top - 0.5);
      const xClipped = r.left < c.left - 0.5 || r.right > c.right + 0.5;
      if (yClipped || xClipped) {
        cuts.push({ box: el.className || el.tagName, panel: [r.top, r.bottom], clip: [c.top, c.bottom] });
      }
      if (el.classList.contains("detail-pane")) break;
    }
    return cuts;
  }, tipSelector);
  check(cut.length === 0, label + ": the panel is cut " + JSON.stringify(cut));
}

async function tradesTab(browser) {
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  await ready(page, "/securities/" + args.security_id + "?tab=trades");
  await hindsightWrapper(page, "the Trades tab at 1200");

  await page.click("#detail-pane-fullscreen-toggle");
  await page.waitForSelector(".detail-pane--fullscreen");
  await hindsightWrapper(page, "the Trades tab in fullscreen");

  await page.click("#detail-tab-predictions");
  await page.waitForSelector("#detail-tab-panel-predictions");
  await tipWhole(
    page,
    "[data-role='predictions-basis'] details.metric-tooltip",
    "the Predictions tab's ⓘ in fullscreen"
  );
  await leave(page);
}

// P1: at 390 px, beside the privacy switch, the top bar's title shows
// whole on the pages with the longest German titles.
async function topbarTitles(browser) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const host = new URL(base).hostname;
  await context.addCookies(
    args.cookies.map(([name, value]) => ({ name, value, domain: host, path: "/" }))
  );
  const page = await context.newPage();
  const errors = [];
  for (const path of args.paths) {
    await ready(page, path);
    await page.waitForSelector("#privacy-mode");
    const m = await page.evaluate(() => {
      const title = document.querySelector("#app-topbar-title");
      return {
        text: title.textContent.trim(),
        scroll: title.scrollWidth,
        client: title.clientWidth,
        page: document.documentElement.scrollWidth - document.documentElement.clientWidth
      };
    });
    if (m.scroll > m.client || m.page > 0) {
      errors.push(path + ": the title is cut " + JSON.stringify(m));
    }
    // The attack case: no web font ships, so the title is drawn in the
    // device's font. A wide monospace font stands in for a wider device
    // font than this machine's; the title must still show whole.
    const wide = await page.evaluate(() => {
      const style = document.createElement("style");
      style.textContent = "#app-topbar-title { font-family: monospace !important; }";
      document.head.appendChild(style);
      const title = document.querySelector("#app-topbar-title");
      const result = {
        text: title.textContent.trim(),
        scroll: title.scrollWidth,
        client: title.clientWidth,
        page: document.documentElement.scrollWidth - document.documentElement.clientWidth
      };
      style.remove();
      return result;
    });
    if (wide.scroll > wide.client || wide.page > 0) {
      errors.push(path + ": in a wide font the title is cut " + JSON.stringify(wide));
    }
  }
  await leave(context);
  check(errors.length === 0, "at 390 px: " + errors.join("; "));
}

// Sprint 27's closing act on the stacked chart (I23), the design critic's
// D1, D2 and D5: at 390 px, the category stack and a drilled category keep
// every legend figure inside the legend's box and the page, the axis
// labels are 9 CSS px, and a drill leaves the focus on the breadcrumb.
async function stackPhone(browser) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  const errors = [];
  for (const path of args.paths) {
    await ready(page, path);
    await page.waitForSelector("#stack-legend tbody tr");
    await nextFrame(page);
    const m = await page.evaluate(() => {
      const legend = document.querySelector("#stack-legend");
      const box = legend.getBoundingClientRect();
      const width = document.documentElement.clientWidth;
      const cells = Array.from(legend.querySelectorAll("td.num")).map((cell) => {
        const r = cell.getBoundingClientRect();
        return { text: cell.textContent.trim(), left: r.left, right: r.right };
      });
      // The label's size in viewBox units, drawn at the svg's scale: CSS px.
      const label = document.querySelector("#performance-figure-stack .chart-axis-labels text");
      const svg = label.ownerSVGElement.getBoundingClientRect();
      const scale = Math.min(svg.width / 960, svg.height / 320);
      return {
        scroll: legend.scrollWidth - legend.clientWidth,
        page: document.documentElement.scrollWidth - width,
        outside: cells.filter((c) => c.right > Math.min(box.right, width) + 0.5 || c.left < box.left - 0.5),
        axis: parseFloat(window.getComputedStyle(label).fontSize) * scale
      };
    });
    if (m.scroll > 0) errors.push(path + ": the legend scrolls " + JSON.stringify(m.scroll));
    if (m.page > 0) errors.push(path + ": the page scrolls sideways by " + m.page);
    if (m.outside.length > 0) {
      errors.push(path + ": figures outside the legend " + JSON.stringify(m.outside));
    }
    if (Math.abs(m.axis - 9) > 0.25) errors.push(path + ": the axis label is " + m.axis + " px");
  }
  // D5: a drill by keyboard leaves the focus on the breadcrumb's current
  // item, not on <body>.
  await ready(page, args.paths[0]);
  await page.waitForSelector(".stack-legend__drill");
  await page.focus(".stack-legend__drill");
  await page.keyboard.press("Enter");
  await page.waitForFunction(
    () => document.activeElement && document.activeElement.id === "stack-crumbs-current",
    null,
    { timeout: 5000 }
  ).catch(() => {});
  const focused = await page.evaluate(() => document.activeElement && document.activeElement.id);
  if (focused !== "stack-crumbs-current") {
    errors.push("after a drill the focus is on " + JSON.stringify(focused));
  }
  await leave(context);
  check(errors.length === 0, "at 390 px: " + errors.join("; "));
}

// Issue 1366, the line of 2026-11-08 (Sprint 28 plan amendment D-A5,
// board 07 ④; DESIGN.md "Labelled controls start on one edge"): the stacked
// chart's bar is one line while its groups fit, and every control starts on
// one edge when it wraps, the labels in a column beside them (A) or above
// them (B). Measured in English and in German, whose „Klassifizierung“ is
// the longest label.
async function stackBarEdge(browser) {
  const errors = [];
  const host = new URL(base).hostname;
  for (const [locale, width] of [["en", 1200], ["de", 1200], ["en", 390], ["de", 390]]) {
    const context = await browser.newContext({ viewport: { width, height: 900 } });
    await context.addCookies([
      { name: "portfolixir_locale", value: args.locales[locale], domain: host, path: "/" }
    ]);
    const page = await context.newPage();
    await ready(page, args.path);
    await page.waitForSelector("#stack-legend tbody tr");
    await nextFrame(page);
    // In Inter and in the fallback font (fonts.js).
    await eachFont(page, async (font) => {
      const m = await page.evaluate(() => {
        const box = (selector) => {
          const r = document.querySelector(selector).getBoundingClientRect();
          return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, mid: (r.top + r.bottom) / 2 };
        };
        return {
          labels: ["#stack-level-label", "label[for='stack-classification']", "#stack-sort-label"].map(box),
          controls: ["[data-role='stack-level']", "#stack-classification", "[data-role='stack-sort']"].map(box),
          bar: box("[data-role='stack-bar']"),
          page: document.documentElement.scrollWidth - document.documentElement.clientWidth
        };
      });
      const label = locale + " at " + width + " px in " + font.name + ": ";
      if (m.page > 0) errors.push(label + "the page scrolls sideways by " + m.page);
      if (m.controls.some((c) => c.right > m.bar.right + 0.5)) {
        errors.push(label + "a control leaves the bar " + JSON.stringify(m.controls));
      }
      if (width === 1200) {
        const mids = m.labels.concat(m.controls).map((r) => r.mid);
        if (Math.max(...mids) - Math.min(...mids) > 3) {
          errors.push(label + "the bar is not one line " + JSON.stringify(mids));
        }
      } else {
        const lefts = m.controls.map((c) => c.left);
        if (Math.max(...lefts) - Math.min(...lefts) > 1) {
          errors.push(label + "the controls start at " + JSON.stringify(lefts));
        }
        // Each label beside its control in one column (A), or above it (B).
        const placed = m.labels.every((l, i) => {
          const c = m.controls[i];
          const beside = l.right <= c.left + 0.5 && l.bottom > c.top && l.top < c.bottom;
          const above = l.bottom <= c.top + 0.5 && Math.abs(l.left - c.left) <= 1;
          return beside || above;
        });
        if (!placed) errors.push(label + "a label is not beside or above its control " + JSON.stringify(m));
        console.error(label + JSON.stringify({ lefts, labels: m.labels.map((l) => [l.left, l.right]) }));
      }
    });
    await leave(context);
  }
  if (errors.length > 0) throw new Error(errors.join("; "));
}

// The owner's report of 2026-11-11: switching the level from Total to
// Categories moved the level's control from the bar's right edge to its
// left one. Measured at every width from the desktop to the phone, in both
// languages: at Total and at Categories the level's label starts at the
// bar's left edge, and while the bar is no label column (A) the level's
// control starts at the same place at both levels, so a switch leaves it
// where it was. In the label column the control follows the column's
// width, the longest label's (DESIGN.md, "Labelled controls start on one
// edge"), so there it is not compared. A breadcrumb only exists where it
// has a step to show.
async function stackBarSwitch(browser) {
  const errors = [];
  const host = new URL(base).hostname;
  for (const locale of ["en", "de"]) {
    for (const width of [1200, 1100, 1024, 900, 390]) {
      const context = await browser.newContext({ viewport: { width, height: 900 } });
      await context.addCookies([
        { name: "portfolixir_locale", value: args.locales[locale], domain: host, path: "/" }
      ]);
      const page = await context.newPage();
      // Per font (fonts.js), each level's measure.
      const seenIn = {};
      for (const [level, path] of Object.entries(args.paths)) {
        await ready(page, path);
        await page.waitForSelector("[data-role='stack-level']");
        if (level !== "total") await page.waitForSelector("#stack-legend tbody tr");
        await settle(page);
        await nextFrame(page);
        await eachFont(page, async (font) => {
          const seen = (seenIn[font.name] = seenIn[font.name] || {});
          const m = await page.evaluate(() => {
            const left = (selector) => document.querySelector(selector).getBoundingClientRect().left;
            const bar = left("[data-role='stack-bar']");
            return {
              label: left("#stack-level-label") - bar,
              control: left("[data-role='stack-level']") - bar,
              column: getComputedStyle(document.querySelector("[data-role='stack-bar'] .control-bar__controls")).display === "grid",
              crumbs: document.querySelectorAll("[data-role='stack-crumbs']").length
            };
          });
          seen[level] = m;
          const label = locale + " at " + width + " px in " + font.name + ", " + level + ": ";
          if (Math.abs(m.label) > 1) {
            errors.push(label + "the level's label starts " + m.label + " px from the bar's left edge");
          }
          if (level === "total" && m.crumbs !== 0) {
            errors.push(label + "an empty breadcrumb is rendered");
          }
        });
      }
      for (const [font, seen] of Object.entries(seenIn)) {
        const { total, category } = seen;
        if (!total.column && !category.column && Math.abs(total.control - category.control) > 1) {
          errors.push(
            locale + " at " + width + " px in " + font + ": the level's control moves from " + total.control +
              " to " + category.control + " px"
          );
        }
      }
      console.error(locale + " at " + width + " px: " + JSON.stringify(seenIn));
      await leave(context);
    }
  }
  if (errors.length > 0) throw new Error(errors.join("; "));
}

const CASES = {
  delete_dialogs: deleteDialogs,
  trades_tab: tradesTab,
  topbar_titles: topbarTitles,
  stack_phone: stackPhone,
  stack_bar_edge: stackBarEdge,
  stack_bar_switch: stackBarSwitch
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
