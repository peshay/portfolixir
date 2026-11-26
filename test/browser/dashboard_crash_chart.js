// The widget „Crash-Chart“ (Sprint 32 S5; board
// ux-design-2026-11-25-sprint32/11 ① and ②), driven in a real Chromium by
// test/browser/dashboard_crash_chart_test.exs, which boots the endpoint,
// seeds a synthetic crash world and a copy of „Rücksetzer“ (the chart over
// the year and pinned to 1M as the zoom) and passes the base URL and the
// dashboard's path as JSON in the only argument. LiveViewTest lays nothing
// out, so this is where the window labels are measured (the S32 closing
// act): in both charts no two labels overprint, each stays inside its
// chart, and none is drawn under 12 px — an SVG text at its computed size
// times the SVG's scale, which shrank 11 px labels to about 5 px in the L
// tile.
//
// With DASHBOARD_CRASH_CHART_SHOTS naming a directory, it also saves the
// page there.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const path = require("path");
const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;
const board = args.path;
const DESKTOP = { width: 1200, height: 900 };
const shots = process.env.DASHBOARD_CRASH_CHART_SHOTS;
// ADR-0062 §6's floor, in CSS px.
const FLOOR = 12;

function check(condition, message) {
  if (!condition) throw new Error(message);
}

(async () => {
  const browser = await launchChromium();
  try {
    const ctx = await browser.newContext({ viewport: DESKTOP });
    const page = await ctx.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error && error.message)));
    await visit(page, base + board + "?locale=de");
    const state = await settle(page);
    check(state.connected && state.settled, board + " did not settle: " + JSON.stringify(state));
    try {
      await page.waitForFunction(() => document.querySelectorAll("[data-role='crash-chart']").length === 2, null, {
        timeout: 15000
      });
    } catch (_timeout) {
      throw new Error("the two crash charts were not drawn");
    }

    const charts = await page.evaluate(() =>
      [...document.querySelectorAll("[data-role='crash-chart']")].map((figure) => {
        const box = figure.getBoundingClientRect();
        const labels = [...figure.querySelectorAll("[data-role='crash-chart-label']")].map((label) => {
          const r = label.getBoundingClientRect();
          const svg = label.closest("svg");
          const scale = svg ? svg.getScreenCTM().a : 1;
          return {
            text: label.textContent.trim(),
            size: parseFloat(getComputedStyle(label).fontSize) * scale,
            left: r.left,
            right: r.right,
            top: r.top,
            bottom: r.bottom
          };
        });
        return {
          widget: figure.closest(".dashboard-widget").id,
          left: box.left,
          right: box.right,
          labels: labels
        };
      })
    );
    console.error("charts: " + JSON.stringify(charts));
    if (shots) {
      await page.screenshot({ path: path.join(shots, "crash-chart-1200.png"), fullPage: true });
    }

    const broken = [];
    for (const chart of charts) {
      check(chart.labels.length > 0 || chart.widget.endsWith("-2"), chart.widget + " names no window");
      for (const label of chart.labels) {
        if (label.size < FLOOR - 0.05) {
          broken.push(chart.widget + ": „" + label.text + "“ is drawn at " + label.size.toFixed(1) + " px");
        }
        if (label.left < chart.left - 0.5 || label.right > chart.right + 0.5) {
          broken.push(chart.widget + ": „" + label.text + "“ leaves the chart");
        }
      }
      chart.labels.forEach((a, i) =>
        chart.labels.slice(i + 1).forEach((b) => {
          const meet = a.left < b.right - 0.5 && b.left < a.right - 0.5 && a.top < b.bottom - 0.5 && b.top < a.bottom - 0.5;
          if (meet) broken.push(chart.widget + ": „" + a.text + "“ and „" + b.text + "“ overprint");
        })
      );
    }
    check(broken.length === 0, "the crash chart's labels: " + broken.join("; "));

    check(errors.length === 0, "the page raised a script error: " + errors.join(" | "));
    await leave(ctx);
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
