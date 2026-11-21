// Sprint 30 W2, the Wealth polish pass (#1366; board
// ux-design-2026-11-15-sprint30/02-wealth-polish), driven in a real
// Chromium by test/browser/wealth_polish_test.exs, which boots the endpoint
// on the review seed and passes the base URL, the case to run and the
// signed locale cookies as JSON in the only argument. LiveViewTest applies
// no CSS and runs no client script, so where a box lands and what a tap
// leaves on the screen is measured here.
//
// - `holdings`: the positions table at 1200 px with the eight columns of
//   #1322 (board 02 ①, answer A): every note and every depot one line, a
//   noted row at most one note line taller than the plainest, the table in
//   its scroller in Inter.
// - `stack_gutter`: the stacked chart beside its legend at 1200 px keeps its
//   values outside the plot (board 02 ②); at 390 px they stand inside.
// - `touch_tooltip`: a tapped sunburst slice leaves no floating tooltip.
// - `warm_switch` (I34 step 2, Sprint 31 P2): a switch to a period whose
//   stack the memo holds draws the chart without the "computing"
//   skeleton; a switch to one it does not hold still shows it.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");
const { FONTS, eachFont } = require("./fonts");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;

const COLUMNS = [
  "depot",
  "security",
  "quantity",
  "avg_cost",
  "latest_price",
  "market_value",
  "unrealized_pnl_abs",
  "unrealized_pnl_pct"
];

async function context(browser, width, locale, options = {}) {
  const host = new URL(base).hostname;
  const phone = width < 600;
  const ctx = await browser.newContext({
    viewport: { width, height: phone ? 844 : 900 },
    hasTouch: phone,
    isMobile: phone,
    ...options
  });
  await ctx.addCookies([{ name: "portfolixir_locale", value: args.locales[locale], domain: host, path: "/" }]);
  return ctx;
}

async function open(page, path) {
  await visit(page, base + path);
  await page.waitForSelector("[data-phx-main].phx-connected");
  await settle(page);
}

// ① Each note and each depot: the lines its text takes (the distinct tops
// of its text's boxes), and each row's height.
function measureHoldings(page) {
  return page.evaluate(() => {
    // The lines a node's text takes: its text boxes' tops, those within
    // 4 px of each other one line (an element's own box and its text's
    // differ by the font's half-leading).
    const lines = (node) => {
      if (!node) return 0;
      const tops = [];
      const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
      for (let text = walker.nextNode(); text; text = walker.nextNode()) {
        if (text.textContent.trim() === "") continue;
        const range = document.createRange();
        range.selectNodeContents(text);
        for (const r of range.getClientRects()) if (r.width > 0) tops.push(r.top);
      }
      tops.sort((a, b) => a - b);
      return tops.filter((top, i) => i === 0 || top - tops[i - 1] > 4).length;
    };
    const wrapper = document.getElementById("holdings-positions-wrapper");
    const rows = Array.from(document.querySelectorAll("#holdings-positions-table tbody tr"));
    return {
      scroll: wrapper.scrollWidth,
      client: wrapper.clientWidth,
      columns: Array.from(document.querySelectorAll("#holdings-positions-table thead th")).length,
      rows: rows.map((row) => {
        const depot = row.querySelector("td[data-column='depot']");
        const titled = depot && depot.querySelector("[title]");
        // The height the name alone asks of the row: its text's box and
        // its cell's padding (a long name wraps in its column, #1322).
        const nameCell = row.querySelector("td[data-column='security']");
        let nameNeeds = 0;
        if (nameCell) {
          const range = document.createRange();
          range.selectNodeContents(nameCell);
          const style = getComputedStyle(nameCell);
          nameNeeds = range.getBoundingClientRect().height + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
        }
        return {
          name: (nameCell || row).textContent.trim().slice(0, 40),
          height: Math.round(row.getBoundingClientRect().height),
          nameNeeds: Math.round(nameNeeds),
          notes: Array.from(row.querySelectorAll(".cell-note")).map((note) => ({
            text: note.textContent.replace(/\s+/g, " ").trim(),
            lines: lines(note),
            lead: note.querySelector(".cell-note__lead") !== null
          })),
          depot: depot && {
            text: depot.textContent.trim(),
            lines: lines(depot),
            title: titled ? titled.getAttribute("title") : null
          }
        };
      })
    };
  });
}

async function holdings(browser) {
  const errors = [];
  for (const locale of ["de", "en"]) {
    const ctx = await context(browser, 1200, locale);
    await ctx.addInitScript((columns) => {
      try {
        window.localStorage.setItem("wealth.holdings.columns", JSON.stringify(columns));
      } catch (_) {}
    }, COLUMNS);
    const page = await ctx.newPage();
    await open(page, "/portfolio");
    await page.waitForSelector("#holdings-positions-table td[data-column='unrealized_pnl_pct']");
    await settle(page);
    await eachFont(page, async (font) => {
      const m = await measureHoldings(page);
      const label = locale + " in " + font.name + ": ";
      if (m.columns !== COLUMNS.length) errors.push(label + m.columns + " columns, not " + COLUMNS.length);
      const plain = m.rows.filter((r) => r.notes.length === 0).map((r) => r.height);
      const noted = m.rows.filter((r) => r.notes.length > 0);
      if (plain.length === 0 || noted.length === 0) errors.push(label + "the seed shows no plain or no noted row");
      const floor = Math.min(...plain);
      for (const row of noted) {
        for (const note of row.notes) {
          if (note.lines !== 1) errors.push(label + "„" + note.text + "“ on " + row.name + " takes " + note.lines + " lines");
          if (!note.lead) errors.push(label + "„" + note.text + "“ has no first phrase that never breaks");
        }
        // One note line (17 px at its 12 px) over the plainest row, unless
        // the row's name alone asks for more.
        if (row.height > Math.max(floor + 18, row.nameNeeds + 3))
          errors.push(
            label + row.name + " is " + row.height + " px, the plainest row " + floor + " px, its name needs " + row.nameNeeds
          );
      }
      for (const row of m.rows) {
        if (!row.depot) continue;
        if (row.depot.lines !== 1) errors.push(label + "the depot „" + row.depot.text + "“ takes " + row.depot.lines + " lines");
        if (row.depot.title !== row.depot.text) errors.push(label + "the depot „" + row.depot.text + "“ has no whole title");
      }
      // The table's width is fractional (922.8 px on the seed in a 922 px
      // scroller, the board's „922 in 922“): one pixel is its rounding.
      if (font === FONTS[0] && m.scroll > m.client + 1)
        errors.push(label + "the table scrolls sideways: " + m.scroll + " in " + m.client);
      console.error(label + JSON.stringify({ scroll: m.scroll, client: m.client, floor, noted: noted.map((r) => r.height) }));
    });
    await leave(ctx);
  }
  if (errors.length > 0) throw new Error(errors.slice(0, 12).join("; "));
}

// ② Where the stack's values stand: the frame's flag, each value's box and
// the plot's left edge (the first grid line's) and the chart's box.
function measureStack(page) {
  return page.evaluate(() => {
    const frame = document.getElementById("stack-figure-chart");
    const svg = frame.querySelector("svg");
    const grid = frame.querySelector("g.chart-axes line").getBoundingClientRect();
    const box = svg.getBoundingClientRect();
    return {
      inside: frame.hasAttribute("data-axis-inside"),
      plotLeft: grid.left,
      svgLeft: box.left,
      svgWidth: box.width,
      labels: Array.from(frame.querySelectorAll(".chart-axis-labels .chart-axis-y")).map((t) => {
        const r = t.getBoundingClientRect();
        return { text: t.textContent.trim(), left: r.left, right: r.right };
      })
    };
  });
}

async function stackGutter(browser) {
  const errors = [];
  for (const width of [1200, 390]) {
    const ctx = await context(browser, width, "de");
    const page = await ctx.newPage();
    await open(page, "/portfolio?level=category");
    await page.waitForSelector("#stack-figure-chart .chart-axis-y");
    await eachFont(page, async (font) => {
      await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
      const m = await measureStack(page);
      const label = width + " px in " + font.name + ": ";
      console.error(label + JSON.stringify(m));
      if (m.labels.length < 2) errors.push(label + "fewer than two axis values");
      if (width === 1200) {
        if (m.inside) errors.push(label + "the values stand inside the plot (a " + Math.round(m.svgWidth) + " px chart)");
        for (const l of m.labels) {
          if (l.right > m.plotLeft + 0.5) errors.push(label + "„" + l.text + "“ reaches into the plot");
          if (l.left < m.svgLeft - 0.5) errors.push(label + "„" + l.text + "“ leaves the chart");
        }
      } else if (!m.inside) {
        errors.push(label + "the values stand outside the plot on a phone");
      }
    });
    await leave(ctx);
  }
  if (errors.length > 0) throw new Error(errors.join("; "));
}

// A point inside the named slice, as sunburst_centre_return.js finds it.
async function slicePoint(page) {
  return page.evaluate(() => {
    const seg = Array.from(document.querySelectorAll("path.sunburst-seg")).find((p) => p.getBoundingClientRect().width > 20);
    if (!seg) return null;
    const box = seg.getBoundingClientRect();
    const hits = [];
    for (let y = box.top + 1; y < box.bottom; y += 3) {
      for (let x = box.left + 1; x < box.right; x += 3) {
        if (document.elementFromPoint(x, y) === seg) hits.push([x, y]);
      }
    }
    return hits.length ? { label: seg.getAttribute("data-label"), point: hits[Math.floor(hits.length / 2)] } : null;
  });
}

const tooltipShown = (page) =>
  page.evaluate(() => Array.from(document.querySelectorAll(".sunburst-tooltip")).some((t) => !t.hidden));

async function touchTooltip(browser) {
  const ctx = await context(browser, 390, "de");
  const page = await ctx.newPage();
  await open(page, "/portfolio?tab=allocation");
  await page.waitForSelector("path.sunburst-seg");
  await page.locator(".sunburst-figure").scrollIntoViewIfNeeded();
  const slice = await slicePoint(page);
  if (!slice) throw new Error("no slice to tap");

  await page.touchscreen.tap(slice.point[0], slice.point[1]);
  await page.waitForFunction(
    (label) => document.querySelector("[data-role='sunburst-centre']").getAttribute("data-label") === label,
    slice.label,
    { timeout: 5000 }
  );
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
  const errors = [];
  if (await tooltipShown(page)) errors.push("a tap on „" + slice.label + "“ leaves a floating tooltip");

  await page.keyboard.press("Escape");
  await page.waitForFunction(
    (label) => document.querySelector("[data-role='sunburst-centre']").getAttribute("data-label") !== label,
    slice.label,
    { timeout: 5000 }
  );
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
  if (await tooltipShown(page)) errors.push("the tooltip stays once the selection is cleared");
  await leave(ctx);
  if (errors.length > 0) throw new Error(errors.join("; "));
}

// Clicks a period token and waits until the stack shows that period's
// chart: the token pressed, the chart drawn and no skeleton left. Answers
// whether a stack skeleton appeared at any moment in between, as a
// MutationObserver installed before the click saw it.
async function switchTo(page, period) {
  await page.evaluate(() => {
    window.__stackSkeletonSeen = false;
    if (window.__stackSkeletonWatch) window.__stackSkeletonWatch.disconnect();
    window.__stackSkeletonWatch = new MutationObserver(() => {
      if (document.querySelector("[data-role='stack-skeleton']")) window.__stackSkeletonSeen = true;
    });
    window.__stackSkeletonWatch.observe(document.body, { childList: true, subtree: true });
  });
  await page.click("[data-role='period-tokens'] button[phx-value-period='" + period + "']");
  await page.waitForFunction(
    (p) =>
      document.querySelector("[data-role='period-tokens'] button[aria-pressed='true']")?.getAttribute("phx-value-period") === p &&
      document.querySelector("#performance-figure-stack svg") !== null &&
      document.querySelector("[data-role='stack-skeleton']") === null,
    period,
    { timeout: 30000 }
  );
  await settle(page);
  return page.evaluate(() => window.__stackSkeletonSeen);
}

async function warmSwitch(browser) {
  const ctx = await context(browser, 1200, "de");
  const page = await ctx.newPage();
  await open(page, "/portfolio?level=category&period=1y");
  await page.waitForSelector("#performance-figure-stack svg");
  const errors = [];
  // 3 years is not remembered yet: the skeleton shows while it walks.
  if (!(await switchTo(page, "3y"))) errors.push("a cold switch to 3y showed no skeleton (the walk was not watched)");
  // Both periods are remembered now.
  if (await switchTo(page, "1y")) errors.push("a warm switch to 1y showed the skeleton");
  if (await switchTo(page, "3y")) errors.push("a warm switch to 3y showed the skeleton");
  await leave(ctx);
  if (errors.length > 0) throw new Error(errors.join("; "));
}

const CASES = { holdings, stack_gutter: stackGutter, touch_tooltip: touchTooltip, warm_switch: warmSwitch };

(async () => {
  const browser = await launchChromium();
  try {
    await CASES[args.case](browser);
    process.stdout.write(JSON.stringify({ ok: true }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
