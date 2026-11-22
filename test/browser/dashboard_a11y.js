// The dashboard's keyboard, focus and touch paths (ADR-0062 §6, §7; Sprint
// 31 closing act, the accessibility lens's Y1 to Y5; planning board
// ux-design-2026-11-21-sprint31/02 ⑥), driven in a real Chromium by
// test/browser/dashboard_a11y_test.exs, which seeds one dashboard and
// passes the base URL and its path as JSON in the only argument.
//
// Each check answers {id, ok, detail}; the test asserts every one. Prints
// one JSON object on stdout: {"ok": true, "checks": [...]} or
// {"ok": false, "error": "..."}; the exit status is 0 either way unless
// the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;
const board = args.path;
const checks = [];

function check(id, ok, detail) {
  checks.push({ id, ok: Boolean(ok), detail });
}

async function open(page, path) {
  await visit(page, base + path + (path.includes("?") ? "&" : "?") + "locale=de");
  const state = await settle(page);
  if (!(state.connected && state.settled)) throw new Error(path + " did not settle: " + JSON.stringify(state));
}

// Waits until the page has answered the last event: no element carries
// LiveView's loading class, and the focus has had a frame to move.
async function answered(page) {
  await page.waitForFunction(() => document.querySelector(".phx-click-loading, .phx-keydown-loading") === null, null, {
    timeout: 5000,
    polling: 50
  });
  await page.waitForTimeout(150);
}

// Where the focus is: the element, its role and label, whether it is drawn
// on screen.
function focused(page) {
  return page.evaluate(() => {
    const a = document.activeElement;
    const r = a.getBoundingClientRect();
    const shown = r.width > 0 && r.height > 0 && r.right > 0 && r.left < innerWidth && r.bottom > 0 && r.top < innerHeight;
    const widget = a.closest ? a.closest("[data-widget-kind]") : null;
    return {
      tag: a.tagName,
      id: a.id || null,
      role: (a.dataset && a.dataset.role) || null,
      widget: widget ? widget.dataset.widgetKind : null,
      shown,
      label: (a.getAttribute("aria-label") || a.textContent || "").trim().replace(/\s+/g, " ").slice(0, 48)
    };
  });
}

// Y1: the compact edit mode keeps the focus on the control used.
async function compactEdit(browser) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await open(page, board);
  await page.click("[data-role='edit-start']");
  await answered(page);
  await page.focus("[data-widget-kind='crashes'] [data-role='edit-up']");
  await page.keyboard.press("Enter");
  await answered(page);
  let f = await focused(page);
  check("Y1 ↑", f.role === "edit-up" && f.widget === "crashes" && f.shown, "after ↑ on „Crashes“ the focus is on its ↑: " + JSON.stringify(f));
  await page.keyboard.press("Enter");
  await answered(page);
  f = await focused(page);
  check("Y1 ↑ again", f.role === "edit-up" && f.widget === "crashes" && f.shown, "a second ↑ needs no new aim: " + JSON.stringify(f));
  await page.focus("[data-widget-kind='performance'] [data-role='edit-down']");
  await page.keyboard.press("Enter");
  await answered(page);
  f = await focused(page);
  check("Y1 ↓", f.role === "edit-down" && f.widget === "performance" && f.shown, "after ↓ the focus is on the moved widget's ↓: " + JSON.stringify(f));
  await page.focus("[data-widget-kind='movers'] [data-role='edit-remove']");
  await page.keyboard.press("Enter");
  await answered(page);
  f = await focused(page);
  check("Y1 ×", f.tag !== "BODY" && f.shown && f.widget !== null, "after × the focus is on a shown control of the next widget: " + JSON.stringify(f));
  await page.keyboard.press("Tab");
  f = await focused(page);
  check("Y1 Tab", f.shown && f.label !== "Dashboards", "the next Tab stays in the dashboard: " + JSON.stringify(f));
  await leave(ctx);
}

// Y2: where the tab bar (compact) or the rail (short-wide) is the menu,
// and where the burger opens the sidebar (600 to 900 px), no tab stop is
// off screen: the closed sidebar and its toggle take no focus, and the
// closed sidebar casts no shadow into the page.
async function tabStops(browser) {
  for (const vp of [{ width: 393, height: 852 }, { width: 852, height: 393 }, { width: 834, height: 1112 }]) {
    const ctx = await browser.newContext({ viewport: vp });
    const page = await ctx.newPage();
    await open(page, board);
    const off = [];
    for (let i = 0; i < 16; i++) {
      await page.keyboard.press("Tab");
      const f = await focused(page);
      if (!f.shown) off.push(f.id || f.label);
    }
    const at = vp.width + "x" + vp.height;
    check("Y2 " + at, off.length === 0, "the first 16 Tab stops are on screen; off screen: " + JSON.stringify(off));
    const sidebar = await page.evaluate(() => {
      const s = document.getElementById("app-sidebar");
      const cs = getComputedStyle(s);
      const t = getComputedStyle(document.getElementById("app-sidebar-toggle"));
      const toggle = { display: t.display, visibility: t.visibility };
      return { visibility: cs.visibility, display: cs.display, right: Math.round(s.getBoundingClientRect().right), toggle };
    });
    if (vp.width < 600 || vp.height < 540) {
      check("Y2 toggle " + at, sidebar.toggle.visibility === "hidden", "the sidebar's toggle is hidden where the tab bar or the rail is the menu: " + JSON.stringify(sidebar));
    }
    check(
      "Y2 shadow " + at,
      sidebar.display === "none" || sidebar.visibility === "hidden",
      "the closed sidebar is not drawn (its shadow bled into the page): " + JSON.stringify(sidebar)
    );
    await leave(ctx);
  }
}

(async () => {
  const browser = await launchChromium();
  try {
    await compactEdit(browser);
    await tabStops(browser);
    process.stdout.write(JSON.stringify({ ok: true, checks }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.stack), checks }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
