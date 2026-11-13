// The halving cycles on the security chart in a real browser (Sprint 29 H7;
// ADR-0060 §11; board ux-design-2026-11-12-sprint29/07, ③ and ⑧), driven
// by test/browser/cycle_chart_test.exs, which boots the endpoint and passes
// the coin's chart URL. For each theme at 1200 and 390 px, and once more
// in the privacy mode at each width, it does what the operator does: „Max“,
// „Zyklen“, „Top – Top“, „Ausgerichtet“ and back, then opens „Bänder und
// ihre Teile“, and checks after each step that the page does not scroll
// sideways, that the bar's labels stand over their controls at 390 px, that
// the cycle labels keep a legible size, and that the privacy mode shows no
// price. CYCLE_CHART_SHOTS=<dir> also writes a screenshot of each run.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const path = require("path");
const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const url = process.argv[2];
const PANEL = "#detail-tab-panel-chart";
const THEMES = ["light", "dark"];
const WIDTHS = [
  { width: 1200, height: 900 },
  { width: 390, height: 844 }
];
const shots = process.env.CYCLE_CHART_SHOTS || null;

async function click(page, selector) {
  await page.click(selector);
  await settle(page);
}

// What the page shows at this step, measured in CSS pixels.
async function measure(page) {
  return page.evaluate((panel) => {
    const root = document.querySelector(panel);
    const rect = (node) => node && node.getBoundingClientRect();
    const groups = Array.from(root.querySelectorAll(".cycle-bar__group")).map((group) => {
      const label = rect(group.querySelector(".cycle-bar__label"));
      const control = rect(group.querySelector("button"));
      return { labelBottom: label && label.bottom, labelRight: label && label.right, controlTop: control && control.top, controlLeft: control && control.left };
    });
    const labels = Array.from(root.querySelectorAll("text.cycle-label"))
      .filter((node) => getComputedStyle(node).display !== "none")
      .map((node) => ({ text: node.textContent.replace(/\s+/g, " ").trim(), height: rect(node).height }));
    const band = rect(root.querySelector("rect.cycle-band"));
    return {
      overflow: document.documentElement.scrollWidth - window.innerWidth,
      bar: rect(root.querySelector("[data-role='cycle-bar']")),
      groups,
      labels,
      band: band && { width: band.width, height: band.height },
      halvings: root.querySelectorAll("line.cycle-halving").length,
      axis: Array.from(root.querySelectorAll(".chart-axis-y")).map((node) => node.textContent.trim()),
      // What the cycles add: their bar, labels, tables and the aligned
      // chart; the pane's other lines name the currency, which is no price.
      text: Array.from(
        root.querySelectorAll(
          "[data-role='cycle-bar'], text.cycle-label, .cycle-intervals, [data-role='cycle-bands'], [data-role='cycle-aligned']"
        )
      )
        .map((node) => node.textContent)
        .join(" ")
    };
  }, PANEL);
}

function check(tag, m, viewport, privacy, errors) {
  if (m.overflow > 1) errors.push(tag + ": the page scrolls sideways by " + m.overflow + " px");
  if (!m.bar || m.bar.right > viewport.width + 1) errors.push(tag + ": the cycle bar leaves the viewport");
  if (viewport.width <= 560) {
    for (const g of m.groups) {
      if (g.labelBottom > g.controlTop + 1) errors.push(tag + ": a bar label does not stand over its controls");
    }
  }
  for (const label of m.labels) {
    if (label.height < 7) errors.push(tag + ": the label „" + label.text + "“ is under 7 px");
  }
  if (privacy) {
    if (/USD|\d[.,]\d\d\b/.test(m.text.replace(/\d{2}\.\d{2}\.\d{4}/g, "").replace(/×[\d.,]+/g, "")))
      errors.push(tag + ": a price shows in the privacy mode");
  }
}

async function walk(browser, theme, viewport, privacy, errors) {
  const tag = theme + " " + viewport.width + (privacy ? " privacy" : "");
  const context = await browser.newContext({ viewport, locale: "de-DE" });
  await context.addInitScript((th) => {
    try {
      localStorage.setItem("portfolixir-theme", th);
    } catch (_) {}
  }, theme);
  const page = await context.newPage();
  await visit(page, url + (privacy ? "&privacy=on" : ""));
  await settle(page);
  await click(page, PANEL + " button[phx-click='set_detail_range'][phx-value-range='MAX']");
  await click(page, "#toggle-cycles");
  await page.waitForSelector(PANEL + " g.cycle-layer");
  await page.waitForFunction(
    (panel) => {
      const frame = document.querySelector(panel + " .chart-frame");
      return frame && frame.style.getPropertyValue("--chart-upx") !== "";
    },
    PANEL,
    { timeout: 10000, polling: "raf" }
  );

  const timeline = await measure(page);
  check(tag + " Zeitachse", timeline, viewport, privacy, errors);
  if (timeline.halvings !== 4) errors.push(tag + ": expected 4 halvings, saw " + timeline.halvings);
  if (!timeline.band || timeline.band.width < 2 || timeline.band.height < 2) errors.push(tag + ": the band is not drawn");
  if (privacy && !timeline.axis.every((value) => value.includes("%"))) errors.push(tag + ": the axis is not in percent");

  await click(page, "#cycle-line-top_top");
  await page.waitForSelector(PANEL + " g.cycle-cone[data-line='top_top']");
  check(tag + " Top – Top", await measure(page), viewport, privacy, errors);
  if (shots) await page.screenshot({ path: path.join(shots, tag.replace(/ /g, "-") + "-timeline.png"), fullPage: true });

  await click(page, "#cycle-mode-aligned");
  await page.waitForSelector("[data-role='cycle-aligned'] polyline.cycle-aligned__line");
  const aligned = await measure(page);
  check(tag + " Ausgerichtet", aligned, viewport, privacy, errors);
  if (shots) await page.screenshot({ path: path.join(shots, tag.replace(/ /g, "-") + "-aligned.png"), fullPage: true });

  await click(page, "#cycle-mode-timeline");
  await page.click("details[data-role='cycle-bands'] > summary");
  await page.waitForSelector("details[data-role='cycle-bands'][open] table", { state: "visible" });
  check(tag + " Bänder", await measure(page), viewport, privacy, errors);
  // The closing act (board 07 ⑨): at 1200 px the bands table fits its
  // frame, no column behind a scroll; under the chart the basis line ends
  // „keine Prognose“ (the labels' anchors are pinned in
  // security_cycle_design_test.exs).
  const fit = await page.evaluate((panel) => {
    const table = document.querySelector(panel + " table.cycle-bands-table");
    const wrapper = table && table.closest(".data-table-wrapper");
    const basis = document.querySelector(panel + " [data-role='cycle-basis']");
    return {
      excess: table && wrapper ? table.scrollWidth - wrapper.clientWidth : null,
      basis: basis && basis.textContent.replace(/\s+/g, " ").trim()
    };
  }, PANEL);
  if (viewport.width >= 1200 && fit.excess > 1) errors.push(tag + ": the bands table is " + fit.excess + " px wider than its frame");
  if (!fit.basis || !/keine Prognose\.$/.test(fit.basis)) errors.push(tag + ": no basis line ending „keine Prognose“ under the chart");
  if (shots) await page.screenshot({ path: path.join(shots, tag.replace(/ /g, "-") + "-bands.png"), fullPage: true });

  await leave(context);
}

(async () => {
  const browser = await launchChromium();
  const errors = [];
  try {
    for (const theme of THEMES) {
      for (const viewport of WIDTHS) {
        await walk(browser, theme, viewport, false, errors);
      }
    }
    for (const viewport of WIDTHS) {
      await walk(browser, "light", viewport, true, errors);
    }
    process.stdout.write(JSON.stringify(errors.length === 0 ? { ok: true } : { ok: false, error: errors.join("; ") }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message), before: errors }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
