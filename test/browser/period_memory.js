// Wealth's period, remembered per browser (#1432, Sprint 28 S5; plan
// amendment D-A1), driven in a real Chromium by
// test/browser/period_memory_test.exs, which boots the endpoint and passes
// its base URL and a custom range (from, to) as the arguments. LiveViewTest
// runs no client script, so this is where the PeriodMemory hook's storage
// is read.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, follow, leave } = require("./settle");

const [base, from, to] = process.argv.slice(2);
const DESKTOP = { width: 1200, height: 800 };

function check(condition, message) {
  if (!condition) throw new Error(message);
}

// Every read and write of the period's key throws, as in a browser whose
// site data is blocked. Only that key: the page's other scripts (the
// theme's boot script, the LiveView client, which clears its own keys on
// join) read the storage without a guard, so with every access throwing
// no page connects at all and nothing of this hook would be tested.
function blockStorage() {
  const getItem = Storage.prototype.getItem;
  const setItem = Storage.prototype.setItem;
  Storage.prototype.getItem = function (key) {
    if (key === "wealth.period") throw new DOMException("blocked", "SecurityError");
    return getItem.call(this, key);
  };
  Storage.prototype.setItem = function (key, value) {
    if (key === "wealth.period") throw new DOMException("blocked", "SecurityError");
    return setItem.call(this, key, value);
  };
}

// Waits until the page at `path` is connected.
async function connected(page, path) {
  try {
    await page.waitForFunction(
      (p) => location.pathname === p && document.querySelector("[data-phx-main].phx-connected") !== null,
      path,
      { timeout: 10000 }
    );
  } catch (_) {
    const state = await page.evaluate(() => {
      const main = document.querySelector("[data-phx-main]");
      return location.href + " " + (main ? main.className : "no main");
    });
    throw new Error(path + " did not connect: at " + state);
  }
}

async function oneYear(page) {
  return page.evaluate(
    () => document.querySelector("button[phx-value-period='1y']").getAttribute("aria-pressed") === "true"
  );
}

// Picks the range in the custom popover and waits for the address to name it.
async function pickRange(page) {
  await page.click("#period-custom > summary");
  await page.fill("#performance-from", from);
  await page.fill("#performance-to", to);
  await page.click("[data-role='period-range'] button[type='submit']");
  try {
    await page.waitForFunction(
      ([f, t]) => {
        const q = new URLSearchParams(location.search);
        return q.get("from") === f && q.get("to") === t && document.querySelector("[data-role='custom-period-chip']") !== null;
      },
      [from, to],
      { timeout: 10000 }
    );
  } catch (_) {
    throw new Error("the range pick did not reach the address: " + (await page.evaluate(() => location.href)));
  }
}

// Away through the sidebar and back to Wealth through the sidebar, each
// page's loads landed before it is left and Wealth's before it is read
// (settle.js): leaving a page mid-load stops its LiveView and kills a load
// task mid-query, which drops the shared sandbox's connection and fails
// every later request with an ownership error (the Sprint 28 closing act,
// CI's browser job on the integrated head).
async function awayAndBack(page) {
  await follow(page, () => page.click("#nav-securities"));
  await connected(page, "/securities");
  await follow(page, () => page.click("#nav-portfolio"));
  await connected(page, "/portfolio");
  await settle(page);
}

(async () => {
  const browser = await launchChromium();
  try {
    const errors = [];

    // The browser remembers the pick.
    const context = await browser.newContext({ viewport: DESKTOP });
    const page = await context.newPage();
    page.on("pageerror", (error) => errors.push(String(error && error.message)));

    await visit(page, base + "/portfolio");
    await connected(page, "/portfolio");
    check(await oneYear(page), "a first visit did not open at 1 year");
    await pickRange(page);

    await awayAndBack(page);
    try {
      await page.waitForFunction(
        ([f, t]) => {
          const q = new URLSearchParams(location.search);
          return (
            q.get("from") === f &&
            q.get("to") === t &&
            document.querySelector("[data-role='custom-period-chip']") !== null &&
            document.querySelector("#performance-from").value === f
          );
        },
        [from, to],
        { timeout: 10000 }
      );
    } catch (_) {
      throw new Error("the return through the sidebar did not reopen the range: " + (await page.evaluate(() => location.href)));
    }
    check(!(await oneYear(page)), "the return reopened the range but 1 year is still pressed");
    await leave(context);

    // Blocked storage: 1 year, a pick that works, 1 year again on return,
    // and no script error.
    for (const [name, init] of [["blocked", blockStorage]]) {
      const blocked = await browser.newContext({ viewport: DESKTOP });
      await blocked.addInitScript(init);
      const page2 = await blocked.newPage();
      page2.on("pageerror", (error) => errors.push(String(error && error.message)));

      await visit(page2, base + "/portfolio");
      await connected(page2, "/portfolio");
      check(await oneYear(page2), "with storage " + name + " the page did not open at 1 year");
      await pickRange(page2);

      await awayAndBack(page2);
      // Nothing is to happen: the server's answer to a restore arrives
      // within milliseconds of the connect, so a short settle shows its
      // absence.
      await page2.waitForTimeout(750);
      check(await oneYear(page2), "with storage " + name + " the return did not open at 1 year");
      check(
        !(await page2.evaluate(() => /[?&](from|to|year|period)=/.test(location.search))),
        "with storage " + name + " the return's address names a period: " + (await page2.evaluate(() => location.href))
      );
      await leave(blocked);
    }

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
