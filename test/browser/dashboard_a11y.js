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

(async () => {
  const browser = await launchChromium();
  try {
    await compactEdit(browser);
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
