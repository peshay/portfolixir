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

const args = JSON.parse(process.argv[2]);
const base = args.base_url;

function check(condition, message) {
  if (!condition) throw new Error(message);
}

async function ready(page, path) {
  await page.goto(base + path);
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
  await page.close();
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
  await page.close();
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
  await context.close();
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
  await context.close();
  check(errors.length === 0, "at 390 px: " + errors.join("; "));
}

const CASES = {
  delete_dialogs: deleteDialogs,
  trades_tab: tradesTab,
  topbar_titles: topbarTitles,
  stack_phone: stackPhone
};

(async () => {
  const browser = await launchChromium();
  const errors = [];
  try {
    await CASES[args.case](browser);
  } catch (error) {
    errors.push(String(error && error.message));
  } finally {
    await browser.close();
  }
  const result = errors.length === 0 ? { ok: true } : { ok: false, errors };
  process.stdout.write(JSON.stringify(result) + "\n");
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
