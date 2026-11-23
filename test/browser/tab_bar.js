// The menu by the window's size (ADR-0022's amendment of 2026-11-21, point
// 5; ADR-0062 §6; planning board ux-design-2026-11-21-sprint31/01 ④;
// Sprint 31 D7), driven in a real Chromium by test/browser/tab_bar_test.exs,
// which boots the endpoint, seeds two dashboards and passes the base URL
// and their paths as JSON in the only argument. LiveViewTest applies no
// CSS, so this is where the class each window falls into is measured:
//
// - 393 x 852 (compact): the tab bar at the foot, four tabs of at least
//   44 px, no burger, the page never scrolls sideways and its end is not
//   under the bar; the title switches dashboards; „Mehr“ opens a sheet
//   above the bar whose rows are at least 44 px, and its link opens the
//   page, „Mehr“ marked.
// - 844 x 390 (short-wide): the bar is a 96 px rail at the side, its
//   labels one line each, unhyphenated, no subtitle in the top bar; its tabs one
//   under the other, the page beside it, „Mehr“ opening beside the rail,
//   inside the window and scrolling within it to its last entry.
// - 915 x 412 and 1200 x 800: the sidebar is the menu; no bar, no switcher.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, follow, leave } = require("./settle");
const { eachFont } = require("./fonts");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;
const [alpha, beta] = args.paths;
const PHONE = { width: 393, height: 852 };
const SIDEWAYS = { width: 844, height: 390 };
const SIDEWAYS_WIDE = { width: 915, height: 412 };
const DESKTOP = { width: 1200, height: 800 };
// --sidebar-rail in app.css: the sidebar's own rail.
const RAIL = 72;
// --tabbar-rail in app.css: the short-wide window's rail, wide enough for
// each label on one line (Sprint 31 UAT, finding 10).
const TABBAR_RAIL = 96;

function check(condition, message) {
  if (!condition) throw new Error(message);
}

async function open(page, path) {
  await visit(page, base + path + (path.includes("?") ? "&" : "?") + "locale=de");
  await settle(page);
}

// The boxes the walk measures, in one read.
function measure(page) {
  return page.evaluate(() => {
    const box = (el) => {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      const shown = getComputedStyle(el).display !== "none" && r.width > 0 && r.height > 0;
      return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height, shown };
    };
    const bar = document.getElementById("app-tabbar");
    return {
      vw: window.innerWidth,
      vh: window.innerHeight,
      scrollWidth: document.documentElement.scrollWidth,
      bar: box(bar),
      tabs: [...bar.querySelectorAll(".app-tab")].map((t) => ({ id: t.id, ...box(t) })),
      burger: box(document.querySelector(".sidebar-toggle")),
      sidebar: box(document.getElementById("app-sidebar")),
      main: box(document.querySelector("main.app-main")),
      switcher: box(document.querySelector(".topbar-switcher")),
      plainTitle: box(document.querySelector("#app-topbar-title .topbar-title-text"))
    };
  });
}

async function openSheet(page, trigger, id) {
  await page.tap(trigger);
  try {
    await page.waitForFunction((sheet) => document.getElementById(sheet).matches(":popover-open"), id, {
      timeout: 5000
    });
  } catch (_) {
    throw new Error(trigger + " did not open #" + id);
  }
  return page.evaluate((sheet) => {
    const el = document.getElementById(sheet);
    const r = el.getBoundingClientRect();
    return {
      left: r.left,
      top: r.top,
      bottom: r.bottom,
      rows: [...el.querySelectorAll("a")].map((a) => ({
        href: a.getAttribute("href"),
        height: a.getBoundingClientRect().height,
        text: a.textContent.trim()
      }))
    };
  }, id);
}

async function closeSheet(page, id) {
  await page.keyboard.press("Escape");
  await page.waitForFunction((sheet) => !document.getElementById(sheet).matches(":popover-open"), id, {
    timeout: 5000
  });
}

function checkTabs(m, at) {
  check(m.bar && m.bar.shown, at + ": no tab bar");
  check(m.tabs.length === 4, at + ": " + m.tabs.length + " tabs");
  for (const tab of m.tabs) {
    check(tab.height >= 44 && tab.width >= 44, at + ": #" + tab.id + " is " + tab.width + " x " + tab.height);
  }
  check(!(m.burger && m.burger.shown), at + ": the burger shows beside the tab bar");
  check(m.sidebar.right <= 0, at + ": the off-canvas sidebar is open");
  check(m.scrollWidth <= m.vw, at + ": the page scrolls sideways (" + m.scrollWidth + " > " + m.vw + ")");
  check(m.switcher && m.switcher.shown, at + ": the title is no dashboard switcher");
  check(!(m.plainTitle && m.plainTitle.shown), at + ": the plain title shows beside the switcher");
}

(async () => {
  const browser = await launchChromium();
  try {
    const phone = await browser.newContext({ viewport: PHONE, hasTouch: true, isMobile: true });
    const page = await phone.newPage();

    // Compact: the bar at the foot.
    await open(page, alpha);
    let m = await measure(page);
    checkTabs(m, "393 px");
    check(Math.abs(m.bar.bottom - m.vh) < 1 && m.bar.left === 0 && Math.abs(m.bar.width - m.vw) < 1, "393 px: the bar is not at the foot: " + JSON.stringify(m.bar));
    const tops = m.tabs.map((t) => Math.round(t.top));
    check(new Set(tops).size === 1, "393 px: the tabs are not in one row: " + tops);

    // The page's end stays above the bar.
    const end = await page.evaluate(() => {
      window.scrollTo(0, document.documentElement.scrollHeight);
      const main = document.querySelector("main.app-main");
      const last = main.lastElementChild;
      return { lastBottom: last.getBoundingClientRect().bottom, barTop: document.getElementById("app-tabbar").getBoundingClientRect().top };
    });
    check(end.lastBottom <= end.barTop + 1, "393 px: the page's end is under the bar: " + JSON.stringify(end));

    // The title switches dashboards.
    const switcher = await openSheet(page, ".topbar-switcher", "dashboard-switcher");
    check(
      JSON.stringify(switcher.rows.map((r) => r.href)) === JSON.stringify([alpha, beta, "/dashboards/new"]),
      "393 px: the switcher lists " + JSON.stringify(switcher.rows.map((r) => r.href))
    );
    check(switcher.rows.every((r) => r.height >= 44), "393 px: a switcher row is under 44 px");
    await closeSheet(page, "dashboard-switcher");

    // „Mehr“: the sheet above the bar.
    let sheet = await openSheet(page, "#tab-more", "app-more");
    m = await measure(page);
    check(sheet.bottom <= m.bar.top + 1, "393 px: the sheet covers the bar: " + sheet.bottom + " > " + m.bar.top);
    check(
      JSON.stringify(sheet.rows.map((r) => r.href)) ===
        JSON.stringify(["/portfolio", "/widgets", "/transactions", "/portfolios", "/buckets", "/classifications", "/journal"]),
      "393 px: „Mehr“ lists " + JSON.stringify(sheet.rows.map((r) => r.href))
    );
    check(sheet.rows.every((r) => r.height >= 44), "393 px: a row of „Mehr“ is under 44 px");

    await follow(page, () => page.tap("#app-more a[href='/widgets']"));
    await page.waitForURL((url) => url.pathname === "/widgets");
    await settle(page);
    check(
      await page.evaluate(() => document.getElementById("tab-more").classList.contains("is-active")),
      "393 px: on „Alle Widgets“ „Mehr“ is not marked"
    );
    m = await measure(page);
    check(m.scrollWidth <= m.vw, "393 px: „Alle Widgets“ scrolls sideways");
    check(!(m.switcher && m.switcher.shown), "393 px: a page that is no dashboard has a switcher");

    // Short-wide: the rail at the side.
    await page.setViewportSize(SIDEWAYS);
    await open(page, beta);
    m = await measure(page);
    checkTabs(m, "844 x 390");
    check(m.bar.left === 0 && Math.abs(m.bar.height - m.vh) < 1, "844 x 390: the bar is no rail at the side: " + JSON.stringify(m.bar));
    check(Math.abs(m.bar.width - TABBAR_RAIL) < 1, "844 x 390: the rail is " + m.bar.width + " px wide");
    for (let i = 1; i < m.tabs.length; i++) {
      check(m.tabs[i].top >= m.tabs[i - 1].bottom - 1, "844 x 390: the rail's tabs are not one under the other");
    }
    check(m.main.left >= m.bar.right - 1, "844 x 390: the page is under the rail: " + m.main.left);
    // The top bar keeps one line: no 11 px subtitle dropping under the
    // title; the rail's labels one line each, unhyphenated, inside their
    // tab, in Inter and in DejaVu Sans, the current one bold (Sprint 31
    // UAT, finding 10: „Wertpa-piere“, „Nachrich-ten“).
    const subtitle = await page.evaluate(() => {
      const el = document.getElementById("app-topbar-subtitle");
      return el && getComputedStyle(el).display !== "none" && el.getBoundingClientRect().height > 0;
    });
    check(!subtitle, "844 x 390: the top bar's subtitle shows under the title");
    for (const labels of await eachFont(page, () =>
      page.evaluate(() =>
        [...document.querySelectorAll("#app-tabbar .app-tab__label")].map((el) => {
          const cs = getComputedStyle(el);
          const r = el.getBoundingClientRect();
          const tab = el.closest(".app-tab").getBoundingClientRect();
          return {
            text: el.textContent.trim(),
            hyphens: cs.hyphens,
            lines: Math.round(r.height / parseFloat(cs.lineHeight)),
            inside: r.left >= tab.left - 0.5 && r.right <= tab.right + 0.5 && el.scrollWidth <= el.clientWidth + 1
          };
        })
      )
    )) {
      for (const l of labels) {
        check(l.hyphens !== "auto", "844 x 390: the rail hyphenates " + JSON.stringify(l.text));
        check(l.lines === 1, "844 x 390: the rail's label " + JSON.stringify(l.text) + " takes " + l.lines + " lines");
        check(l.inside, "844 x 390: the rail's label " + JSON.stringify(l.text) + " reaches past its tab");
      }
    }
    sheet = await openSheet(page, "#tab-more", "app-more");
    check(sheet.left >= m.bar.right - 1, "844 x 390: „Mehr“ opens over the rail: " + sheet.left);
    // The sheet stays inside the window and scrolls within it, so its last
    // entry is reached (Sprint 31 UAT, finding 2: 431 px tall in a 390 px
    // window, „Audit-Journal“ under the window's edge).
    check(sheet.top >= -1 && sheet.bottom <= m.vh + 1, "844 x 390: „Mehr“ reaches past the window: " + sheet.top + " to " + sheet.bottom + " of " + m.vh);
    const last = await page.evaluate(() => {
      const el = document.getElementById("app-more");
      el.scrollTop = el.scrollHeight;
      const links = el.querySelectorAll("a");
      const r = links[links.length - 1].getBoundingClientRect();
      const s = el.getBoundingClientRect();
      return { top: r.top, bottom: r.bottom, sheetBottom: s.bottom, text: links[links.length - 1].textContent.trim() };
    });
    check(last.bottom <= Math.min(last.sheetBottom, m.vh) + 1, "844 x 390: „Mehr“'s last entry " + JSON.stringify(last.text) + " cannot be scrolled into the window: " + JSON.stringify(last));
    await closeSheet(page, "app-more");

    await leave(phone);

    // From 900 px wide the sidebar is the menu, short or not.
    const desk = await browser.newContext({ viewport: SIDEWAYS_WIDE });
    const wide = await desk.newPage();
    for (const size of [SIDEWAYS_WIDE, DESKTOP]) {
      const at = size.width + " x " + size.height;
      await wide.setViewportSize(size);
      await open(wide, alpha);
      m = await measure(wide);
      check(!m.bar.shown, at + ": the tab bar shows beside the sidebar");
      check(m.sidebar.shown && m.sidebar.left === 0 && m.sidebar.width > RAIL + 40, at + ": the sidebar is not the menu: " + JSON.stringify(m.sidebar));
      check(!(m.switcher && m.switcher.shown) && m.plainTitle.shown, at + ": the title is a switcher");
      check(m.scrollWidth <= m.vw, at + ": the page scrolls sideways");
    }
    await leave(desk);

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
