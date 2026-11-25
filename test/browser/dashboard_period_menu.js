// The period menu above every dashboard (Sprint 32 T4; ADR-0062's
// amendment of 2026-11-25, point 6; board ux-design-2026-11-25-sprint32/04
// ① and ②), driven in a real Chromium by
// test/browser/dashboard_period_menu_test.exs, which boots the endpoint,
// seeds a synthetic world and passes the base URL and the dashboard's path
// as JSON in the only argument. LiveViewTest runs no client script and
// lays nothing out, so this is where the keyboard's path through the menu,
// the focus that comes back to its button, the native dialog and the
// sheet at a phone's width are measured.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;
const board = args.path;
const WIDE = { width: 1280, height: 800 };
const PHONE = { width: 393, height: 852 };

function check(condition, message) {
  if (!condition) throw new Error(message);
}

async function open(page, path) {
  await visit(page, base + path + (path.includes("?") ? "&" : "?") + "locale=de");
  const state = await settle(page);
  check(state.connected && state.settled, path + " did not settle: " + JSON.stringify(state));
}

const menuOpen = (page) => page.evaluate(() => document.getElementById("dashboard-period-menu") !== null);
const focusedId = (page) => page.evaluate(() => document.activeElement && document.activeElement.id);
const active = (page) =>
  page.evaluate(() => document.querySelector("[data-role='period-menu-root']").dataset.activePeriod);

async function until(page, what, fn, arg) {
  try {
    await page.waitForFunction(fn, arg, { timeout: 10000 });
  } catch (_timeout) {
    throw new Error(what);
  }
}

// The menu at one width: opened from the keyboard, a period picked with
// Enter, the focus back on the button; Escape closes it; the panel lies
// inside the window and the page never scrolls sideways.
async function keyboardPath(browser, viewport, at) {
  const ctx = await browser.newContext({ viewport, hasTouch: viewport === PHONE });
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error && error.message)));
  await open(page, board);

  await page.focus("#dashboard-period-menu-toggle");
  await page.keyboard.press("Enter");
  await until(page, at + ": Enter did not open the menu", () => document.getElementById("dashboard-period-menu") !== null);
  check(
    (await page.getAttribute("#dashboard-period-menu-toggle", "aria-expanded")) === "true",
    at + ": the open menu's button does not say it is expanded"
  );

  const box = await page.evaluate(() => {
    const r = document.getElementById("dashboard-period-menu").getBoundingClientRect();
    return {
      left: r.left,
      right: r.right,
      top: r.top,
      bottom: r.bottom,
      vw: document.documentElement.clientWidth,
      vh: window.innerHeight,
      page: document.documentElement.scrollWidth - document.documentElement.clientWidth
    };
  });
  console.error(at + " menu: " + JSON.stringify(box));
  check(box.left >= -1 && box.right <= box.vw + 1, at + ": the menu leaves the window: " + JSON.stringify(box));
  check(box.page <= 0, at + ": the page scrolls sideways by " + box.page + " px");

  if (viewport === PHONE) {
    // The compact class: a sheet on the bottom edge, the window's width,
    // every target in it a thumb's.
    check(Math.abs(box.bottom - box.vh) <= 1.5, at + ": the menu is no sheet on the bottom edge: " + JSON.stringify(box));
    check(box.right - box.left >= box.vw - 1.5, at + ": the sheet is not the window's width: " + JSON.stringify(box));
    const small = await page.evaluate(() =>
      [...document.querySelectorAll("#dashboard-period-menu button:not([disabled])")]
        .map((b) => b.getBoundingClientRect())
        .filter((r) => r.height > 0 && r.height < 43.5)
        .map((r) => Math.round(r.width) + "x" + Math.round(r.height))
    );
    check(small.length === 0, at + ": a target in the sheet is under 44 px: " + JSON.stringify(small));
  }

  // Tab walks into the menu; 3M is picked with Enter, the menu closes and
  // the focus is back on its button, which names the period.
  await page.focus("[data-role='period-option'][data-period='3m']");
  await page.keyboard.press("Enter");
  await until(page, at + ": Enter on 3M did not apply it", () =>
    new URLSearchParams(location.search).get("period") === "3m" && document.getElementById("dashboard-period-menu") === null
  );
  await until(page, at + ": the focus did not come back to the menu's button", () =>
    document.activeElement && document.activeElement.id === "dashboard-period-menu-toggle"
  );
  check((await active(page)) === "3m", at + ": the bar does not name 3M");

  // Escape closes it without a pick, the focus back on the button.
  await page.keyboard.press("Enter");
  await until(page, at + ": Enter did not open the menu again", () => document.getElementById("dashboard-period-menu") !== null);
  await page.focus("[data-role='period-option'][data-period='1m']");
  await page.keyboard.press("Escape");
  await until(page, at + ": Escape did not close the menu", () => document.getElementById("dashboard-period-menu") === null);
  await until(page, at + ": after Escape the focus is not on the menu's button", () =>
    document.activeElement && document.activeElement.id === "dashboard-period-menu-toggle"
  );
  check((await active(page)) === "3m", at + ": Escape changed the period");

  check(errors.length === 0, at + ": the page raised a script error: " + errors.join(" | "));
  await leave(ctx);
}

// A star puts Vorquartal into the bar; „Eigenen Zeitraum anlegen …“ opens
// the native dialog, whose save stores the period and applies it, its
// dates beside its name.
async function starAndDialog(browser) {
  const ctx = await browser.newContext({ viewport: WIDE });
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error && error.message)));
  await open(page, board);

  await page.click("#dashboard-period-menu-toggle");
  await until(page, "the click did not open the menu", () => document.getElementById("dashboard-period-menu") !== null);
  await page.click("[data-role='period-star'][data-period='prev_quarter']");
  await until(page, "the star did not put Vorquartal into the bar", () =>
    document.querySelector("[data-role='dashboard-period'] button[data-period='prev_quarter']") !== null
  );

  await page.click("[data-role='period-add']");
  await until(page, "the dialog did not open", () => {
    const d = document.getElementById("period-dialog");
    return d !== null && d.open;
  });
  await page.fill("#period-form input[name='period[name]']", "Seit Umschichtung");
  await page.fill("#period-form input[name='period[from]']", "2025-03-01");
  await page.click("#period-form [data-role='period-save']");
  await until(page, "the saved period was not applied", () =>
    (new URLSearchParams(location.search).get("period") || "").startsWith("saved:")
  );
  await until(page, "the dialog did not close", () => document.getElementById("period-dialog") === null);
  const named = await page.evaluate(() => ({
    label: document.querySelector("[data-role='period-menu-label']").textContent.trim(),
    dates: (document.querySelector("[data-role='period-dates']") || { textContent: "" }).textContent.trim()
  }));
  console.error("own period: " + JSON.stringify(named));
  check(named.label === "Seit Umschichtung", "the button reads „" + named.label + "“");
  check(named.dates.startsWith("01.03.2025 – "), "the dates beside it read „" + named.dates + "“");

  check(errors.length === 0, "the page raised a script error: " + errors.join(" | "));
  await leave(ctx);
}

(async () => {
  const browser = await launchChromium();
  try {
    await keyboardPath(browser, WIDE, "1280");
    await keyboardPath(browser, PHONE, "393");
    await starAndDialog(browser);
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
