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

  // The group headings are the board's small muted labels (04 ②), not
  // the section headings an older, stronger rule (`.workspace-section
  // h3`) drew at 17 px (the S32 closing act).
  const heads = await page.evaluate(() =>
    [...document.querySelectorAll("#dashboard-period-menu .dashboard-period-menu__head")].map((h) => {
      const style = getComputedStyle(h);
      return { text: h.textContent.trim(), size: parseFloat(style.fontSize), color: style.color };
    })
  );
  const bodyColor = await page.evaluate(() => getComputedStyle(document.body).color);
  check(heads.length === 4, at + ": the menu does not show its four groups: " + JSON.stringify(heads));
  const loud = heads.filter((h) => h.size > 12.5 || h.color === bodyColor);
  check(loud.length === 0, at + ": a group heading is not a small muted label: " + JSON.stringify(loud));
  check(box.left >= -1 && box.right <= box.vw + 1, at + ": the menu leaves the window: " + JSON.stringify(box));
  check(box.page <= 0, at + ": the page scrolls sideways by " + box.page + " px");

  if (viewport === PHONE) {
    // The compact class: a sheet on the bottom edge, standing on the tab
    // bar where one is shown (the S32 closing act: it ended behind the bar,
    // whose z-index is higher, so the last row of years could never be
    // tapped), the window's width, every target in it a thumb's.
    const floor = await page.evaluate(() => {
      const bar = document.querySelector(".app-tabbar");
      if (!bar || getComputedStyle(bar).display === "none") return window.innerHeight;
      return bar.getBoundingClientRect().top;
    });
    check(floor < box.vh, at + ": no tab bar is shown at the phone's width");
    check(
      Math.abs(box.bottom - floor) <= 1.5,
      at + ": the sheet does not stand on the tab bar (its top at " + floor + "): " + JSON.stringify(box)
    );
    check(box.right - box.left >= box.vw - 1.5, at + ": the sheet is not the window's width: " + JSON.stringify(box));
    // Every target, scrolled into the sheet's view, is the element a tap at
    // its centre reaches: nothing lies over it.
    const covered = await page.evaluate(() =>
      [...document.querySelectorAll("#dashboard-period-menu button:not([disabled])")].flatMap((b) => {
        b.scrollIntoView({ block: "nearest" });
        const r = b.getBoundingClientRect();
        const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
        return hit && (hit === b || b.contains(hit))
          ? []
          : [(b.dataset.period || b.textContent.trim()) + " under " + (hit ? hit.className || hit.tagName : "nothing")];
      })
    );
    check(covered.length === 0, at + ": a target in the sheet cannot be tapped: " + JSON.stringify(covered));
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

// At the phone's width the last row of the sheet, the oldest year, is
// tapped with a thumb and applied (the S32 closing act).
async function lastYearByTap(browser) {
  const ctx = await browser.newContext({ viewport: PHONE, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error && error.message)));
  await open(page, board);

  await page.tap("#dashboard-period-menu-toggle");
  await until(page, "393: the tap did not open the menu", () => document.getElementById("dashboard-period-menu") !== null);
  const last = await page.evaluate(() => {
    const years = [...document.querySelectorAll("[aria-labelledby='period-group-year'] [data-role='period-option']")];
    return years[years.length - 1].dataset.period;
  });
  const selector = "#dashboard-period-menu [data-role='period-option'][data-period='" + last + "']";
  await page.locator(selector).scrollIntoViewIfNeeded();
  // A tap lands where the finger is, on whatever lies on top there; the
  // trial run refuses a target something else covers.
  await page.locator(selector).tap({ trial: true, timeout: 5000 }).catch((error) => {
    throw new Error("393: the last year " + last + " cannot be tapped: " + String(error && error.message).split("\n")[0]);
  });
  await page.locator(selector).tap();
  await until(
    page,
    "393: the tap on " + last + " did not apply it",
    (key) => new URLSearchParams(location.search).get("period") === key && document.getElementById("dashboard-period-menu") === null,
    last
  );
  check((await active(page)) === last, "393: the bar does not name " + last);

  check(errors.length === 0, "393: the page raised a script error: " + errors.join(" | "));
  await leave(ctx);
}

// A star puts Vorquartal into the bar; „Eigenen Zeitraum anlegen …“ opens
// the native dialog, whose save stores the period and applies it, its
// dates beside its name.
async function starAndDialog(browser) {
  const ctx = await browser.newContext({ viewport: { width: 1200, height: 900 } });
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error && error.message)));
  await open(page, args.own || board);

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
  // The footer's buttons keep the dialog's padding (board 04 ②): the
  // footer sits inside the form, where `.modal > .modal-footer` never
  // reached it, so the buttons touched the dialog's edges and the focus
  // ring was cut (the S32 closing act).
  const footer = await page.evaluate(() => {
    const dialog = document.getElementById("period-dialog").getBoundingClientRect();
    const save = document.querySelector("#period-form [data-role='period-save']").getBoundingClientRect();
    return { right: dialog.right - save.right, bottom: dialog.bottom - save.bottom };
  });
  console.error("dialog footer: " + JSON.stringify(footer));
  check(footer.right >= 16 && footer.bottom >= 16, "the dialog's buttons touch its edges: " + JSON.stringify(footer));

  await page.fill("#period-form input[name='period[name]']", "Seit Umschichtung");
  // Under a year ago, so the money-weighted return is the period's MWR,
  // whose labels are the longest (the UAT's „Seit Juni“).
  const from = new Date(Date.now() - 170 * 86400000);
  const pad = (n) => String(n).padStart(2, "0");
  const fromDe = pad(from.getUTCDate()) + "." + pad(from.getUTCMonth() + 1) + "." + from.getUTCFullYear();
  // Typed as a German screen writes it (the S32 closing act's UAT,
  // finding 9); the field's pattern lets it through and the server stores
  // the ISO day.
  check(
    (await page.getAttribute("#period-form input[name='period[from]']", "placeholder")) === "TT.MM.JJJJ",
    "the dialog asks for another date format than TT.MM.JJJJ"
  );
  await page.fill("#period-form input[name='period[from]']", fromDe);
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

  // The S32 closing act's UAT, finding 7: the bar stays one line with the
  // own period, its dates and its status, and the result keeps its EUR.
  await settle(page);
  // The result as the UAT read it on the review seed (+3.947,56), whatever
  // this walk's small world books: the tile holds a figure that long.
  await page.evaluate(() => {
    const value = document.querySelector("[data-role='kf-result-value']");
    if (value) value.textContent = "+3.947,56";
  });
  const bar = await page.evaluate(() => {
    const top = (sel) => {
      const el = document.querySelector(sel);
      return el ? el.getBoundingClientRect().top : null;
    };
    const unit = document.querySelector("[data-role='kf-result'] .widget-figure__unit");
    const value = document.querySelector("[data-role='kf-result-value']");
    return {
      toggle: top("#dashboard-period-menu-toggle"),
      scope: top(".dashboard-bar__row > .dashboard-scope, .dashboard-bar__row > .dashboard-scope--own"),
      edit: top("[data-role='edit-start']"),
      say: (document.getElementById("dashboard-period-status") || { textContent: "" }).textContent.trim(),
      unit: unit ? unit.getBoundingClientRect().bottom : null,
      value: value ? value.getBoundingClientRect().bottom : null
    };
  });
  console.error("bar with the own period: " + JSON.stringify(bar));
  check(bar.say !== "", "the status sentence is gone: " + JSON.stringify(bar));
  check(
    bar.edit !== null && bar.scope !== null && Math.abs(bar.edit - bar.toggle) < 12 && Math.abs(bar.toggle - bar.scope) < 12,
    "the bar is not one line (the scope, the period button and „Bearbeiten“): " + JSON.stringify(bar)
  );
  check(bar.unit !== null && Math.abs(bar.unit - bar.value) < 12, "the result's EUR is not on its figure's line: " + JSON.stringify(bar));
  check(named.dates.startsWith(fromDe + " – "), "the dates beside it read „" + named.dates + "“");

  check(errors.length === 0, "the page raised a script error: " + errors.join(" | "));
  await leave(ctx);
}

(async () => {
  const browser = await launchChromium();
  try {
    await keyboardPath(browser, WIDE, "1280");
    await keyboardPath(browser, PHONE, "393");
    await lastYearByTap(browser);
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
