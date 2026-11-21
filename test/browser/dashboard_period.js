// The dashboard's period, remembered per browser and kept across
// dashboards (ADR-0062 §5, §6; idea board ux-design-2026-11-21-idea-i56
// 05, A; Sprint 31 D5), driven in a real Chromium by
// test/browser/dashboard_period_test.exs, which boots the endpoint, seeds
// two stored dashboards and passes the base URL and their paths as JSON in
// the only argument. LiveViewTest runs no client script, so this is where
// the PeriodMemory hook's storage under `dashboard.period` is read, and
// where the compact class's period strip is measured.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;
const [alpha, beta] = args.paths;
const DESKTOP = { width: 1200, height: 800 };
const PHONE = { width: 393, height: 852 };
const KEY = "dashboard.period";

function check(condition, message) {
  if (!condition) throw new Error(message);
}

// Every read and write of the period's key throws, as in a browser whose
// site data is blocked; only that key, as period_memory.js does, so the
// LiveView client still connects.
function blockStorage() {
  const getItem = Storage.prototype.getItem;
  const setItem = Storage.prototype.setItem;
  Storage.prototype.getItem = function (key) {
    if (key === "dashboard.period") throw new DOMException("blocked", "SecurityError");
    return getItem.call(this, key);
  };
  Storage.prototype.setItem = function (key, value) {
    if (key === "dashboard.period") throw new DOMException("blocked", "SecurityError");
    return setItem.call(this, key, value);
  };
}

// Opens `path` as a fresh page (a new LiveView mount) and waits until it is
// connected and its loads have landed.
async function open(page, path) {
  await visit(page, base + path);
  await settle(page);
}

function pressed(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll("[data-role='dashboard-period'] button[aria-pressed='true']")].map(
      (b) => b.dataset.period
    )
  );
}

// Waits until the address names `period` (none for 1J), the selector
// presses it and the performance widget follows it.
async function onPeriod(page, path, period, tag) {
  try {
    await page.waitForFunction(
      ([p, period, tag]) => {
        const named = new URLSearchParams(location.search).get("period");
        const button = document.querySelector("[data-role='dashboard-period'] button[aria-pressed='true']");
        const perf = document.querySelector("[data-widget-kind='performance'] [data-role='widget-period']");
        return (
          location.pathname === p &&
          named === (period === "1y" ? null : period) &&
          button !== null &&
          button.dataset.period === period &&
          perf !== null &&
          perf.textContent.trim() === tag
        );
      },
      [path, period, tag],
      { timeout: 10000 }
    );
  } catch (_) {
    const at = await page.evaluate(() => location.href);
    throw new Error(path + " did not show the period " + period + ": at " + at + ", pressed " + (await pressed(page)));
  }
}

async function pick(page, period) {
  await page.click("[data-role='dashboard-period'] button[data-period='" + period + "']");
}

(async () => {
  const browser = await launchChromium();
  try {
    const errors = [];

    // A pick is remembered and kept on another dashboard opened fresh.
    const context = await browser.newContext({ viewport: DESKTOP });
    const page = await context.newPage();
    page.on("pageerror", (error) => errors.push(String(error && error.message)));

    await open(page, alpha);
    await onPeriod(page, alpha, "1y", "follows · 1Y");
    await pick(page, "3m");
    await onPeriod(page, alpha, "3m", "follows · 3M");
    const kept = await page.evaluate((key) => window.localStorage.getItem(key), KEY);
    check(kept === JSON.stringify({ period: "3m" }), "the pick was not kept under " + KEY + ": " + kept);

    await open(page, beta);
    await onPeriod(page, beta, "3m", "follows · 3M");
    // The pinned widget keeps its own period whatever the top bar says.
    const pinned = await page.evaluate(
      () => document.querySelector("[data-widget-kind='movers'] [data-role='widget-period']").textContent.trim()
    );
    check(pinned === "📌 own: Max → 1Y", "the pinned widget reads „" + pinned + "“");

    // 1J picked is kept too: the next dashboard opens on 1J, its address
    // naming none.
    await pick(page, "1y");
    await onPeriod(page, beta, "1y", "follows · 1Y");
    await open(page, alpha);
    await page.waitForTimeout(750);
    await onPeriod(page, alpha, "1y", "follows · 1Y");

    // A link that names a period wins over the kept one.
    await pick(page, "1w");
    await onPeriod(page, alpha, "1w", "follows · 1W");
    await open(page, beta + "?period=ytd");
    await page.waitForTimeout(750);
    await onPeriod(page, beta, "ytd", "follows · YTD");
    await leave(context);

    // The compact class: the period is a strip of its own row that the
    // thumb swipes sideways, its chips tap-sized; the page never scrolls
    // sideways.
    const phone = await browser.newContext({ viewport: PHONE, hasTouch: true });
    const page3 = await phone.newPage();
    page3.on("pageerror", (error) => errors.push(String(error && error.message)));
    await open(page3, alpha + "?period=3m");
    await onPeriod(page3, alpha, "3m", "follows · 3M");
    const strip = await page3.evaluate(() => {
      const strip = document.querySelector("[data-role='dashboard-period-strip']");
      const chips = [...strip.querySelectorAll("button")];
      const before = strip.getBoundingClientRect();
      strip.scrollLeft = strip.scrollWidth;
      const last = chips[chips.length - 1].getBoundingClientRect();
      return {
        overflow: getComputedStyle(strip).overflowX,
        stripRight: before.right,
        stripWidth: before.width,
        lastRight: last.right,
        minChip: Math.min(...chips.map((c) => c.getBoundingClientRect().height)),
        page: document.documentElement.scrollWidth - document.documentElement.clientWidth
      };
    });
    console.error("compact strip: " + JSON.stringify(strip));
    check(strip.overflow === "auto", "the compact period strip does not scroll: " + JSON.stringify(strip));
    check(strip.page <= 0, "the page scrolls sideways by " + strip.page + " px at 393 px");
    check(strip.minChip >= 44, "a compact period chip is " + strip.minChip + " px tall, under 44");
    check(strip.lastRight <= strip.stripRight + 1, "„Max“ is not reachable in the strip: " + JSON.stringify(strip));
    await pick(page3, "max");
    await onPeriod(page3, alpha, "max", "follows · Max");
    await leave(phone);

    // Blocked storage: 1J, a pick that works, 1J again on a fresh page, and
    // no script error.
    const blocked = await browser.newContext({ viewport: DESKTOP });
    await blocked.addInitScript(blockStorage);
    const page2 = await blocked.newPage();
    page2.on("pageerror", (error) => errors.push(String(error && error.message)));
    await open(page2, alpha);
    await onPeriod(page2, alpha, "1y", "follows · 1Y");
    await pick(page2, "3m");
    await onPeriod(page2, alpha, "3m", "follows · 3M");
    await open(page2, beta);
    await page2.waitForTimeout(750);
    await onPeriod(page2, beta, "1y", "follows · 1Y");
    await leave(blocked);

    check(errors.length === 0, "the page raised a script error: " + errors.join(" | "));
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
