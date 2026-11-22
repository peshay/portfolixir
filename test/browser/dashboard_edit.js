// The dashboard's edit mode (ADR-0062 §7; idea board
// ux-design-2026-11-21-idea-i56 03; Sprint 31 D6), driven in a real
// Chromium by test/browser/dashboard_edit_test.exs, which boots the
// endpoint, seeds one stored dashboard and passes the base URL and its
// path as JSON in the only argument. LiveViewTest runs no client script,
// so this is where the DashboardEdit hook is read: the keyboard on a
// widget's handle (the arrow keys do not scroll the page, the focus stays
// on the handle as its widget moves), a drag of a handle on the wide grid,
// the live region's sentences, „Fertig“, and the compact class's reorder.
// The Elixir test then reads the stored layout the save wrote.
//
// With DASHBOARD_EDIT_SHOTS naming a directory, it also saves the edit
// mode at 1200 and 393 px there.
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
const shots = process.env.DASHBOARD_EDIT_SHOTS;
const DESKTOP = { width: 1200, height: 900 };
const PHONE = { width: 393, height: 852 };

function check(condition, message) {
  if (!condition) throw new Error(message);
}

async function open(page, at) {
  await visit(page, base + at);
  await settle(page);
}

function status(page) {
  return page.evaluate(() => document.getElementById("dashboard-edit-status").textContent.trim());
}

async function said(page, text) {
  try {
    await page.waitForFunction(
      (text) => document.getElementById("dashboard-edit-status").textContent.trim() === text,
      text,
      { timeout: 10000 }
    );
  } catch (_) {
    throw new Error("the live region did not say „" + text + "“ but „" + (await status(page)) + "“");
  }
}

function place(page, kind) {
  return page.evaluate((kind) => {
    const w = document.querySelector("[data-widget-kind='" + kind + "']");
    return w ? [Number(w.dataset.col), Number(w.dataset.row), w.dataset.size] : null;
  }, kind);
}

async function startEditing(page) {
  await page.click("[data-role='edit-start']");
  await page.waitForSelector("[data-role='dashboard-grid'][data-editing='true'] [data-role='edit-handle']", {
    state: "attached",
    timeout: 10000
  });
}

(async () => {
  const browser = await launchChromium();
  try {
    const errors = [];

    // The wide grid: keyboard first.
    const context = await browser.newContext({ viewport: DESKTOP });
    const page = await context.newPage();
    page.on("pageerror", (error) => errors.push(String(error && error.message)));
    await open(page, board);
    await startEditing(page);

    const live = await page.evaluate(() => {
      const region = document.getElementById("dashboard-edit-status");
      return region.getAttribute("role") + "/" + region.getAttribute("aria-live");
    });
    check(live === "status/polite", "the edit region is " + live + ", not a polite status");

    const perfHandle = "[data-widget-kind='performance'] [data-role='edit-handle']";
    await page.focus(perfHandle);
    const scrollBefore = await page.evaluate(() => window.scrollY);
    await page.keyboard.press("ArrowRight");
    await said(page, "Performance moved right, column 2, row 1");
    check(JSON.stringify(await place(page, "performance")) === JSON.stringify([2, 1, "L"]),
      "the arrow key did not move Performance to column 2: " + JSON.stringify(await place(page, "performance")));
    await page.keyboard.press("ArrowDown");
    await said(page, "Performance can't move down: it would overlap Tops and flops.");
    const kept = await page.evaluate(() => {
      const a = document.activeElement;
      return a && a.dataset.role === "edit-handle" && a.closest("[data-widget-kind]").dataset.widgetKind;
    });
    check(kept === "performance", "the focus left Performance's handle: " + kept);
    const scrollAfter = await page.evaluate(() => window.scrollY);
    check(scrollAfter === scrollBefore, "the arrow keys scrolled the page by " + (scrollAfter - scrollBefore) + " px");

    // A drag of Tops und Flops' handle below the last row of the grid.
    const drop = await page.evaluate(() => {
      const grid = document.querySelector("[data-role='dashboard-grid']");
      const widget = document.querySelector("[data-widget-kind='movers']");
      const handle = widget.querySelector("[data-role='edit-handle']");
      const g = grid.getBoundingClientRect();
      const w = widget.getBoundingClientRect();
      const h = handle.getBoundingClientRect();
      const rows = getComputedStyle(grid).gridTemplateRows.split(" ").filter((v) => v.endsWith("px")).length;
      return {
        x: h.left + h.width / 2,
        y: h.top + h.height / 2,
        dy: g.bottom + 12 - w.top,
        rows: rows
      };
    });
    await page.mouse.move(drop.x, drop.y);
    await page.mouse.down();
    await page.mouse.move(drop.x, drop.y + drop.dy / 2, { steps: 5 });
    await page.mouse.move(drop.x, drop.y + drop.dy, { steps: 5 });
    await page.mouse.up();
    await said(page, "Tops and flops placed at column 1, row " + (drop.rows + 1));
    check(JSON.stringify(await place(page, "movers")) === JSON.stringify([1, drop.rows + 1, "M"]),
      "the drag placed Tops and flops at " + JSON.stringify(await place(page, "movers")));

    if (shots) {
      await page.screenshot({ path: path.join(shots, "edit-mode-1200.png"), fullPage: true });
    }

    await page.click("[data-role='edit-done']");
    await said(page, "Dashboard saved.");
    check((await page.$("[data-role='edit-handle']")) === null, "the edit mode stayed open after „Done“");
    await leave(context);

    // The compact class: reorder, size and remove only.
    const phone = await browser.newContext({ viewport: PHONE, hasTouch: true });
    const page2 = await phone.newPage();
    page2.on("pageerror", (error) => errors.push(String(error && error.message)));
    await open(page2, board);
    await startEditing(page2);
    const compact = await page2.evaluate(() => {
      const shown = (el) => el !== null && getComputedStyle(el).display !== "none" && el.getBoundingClientRect().height > 0;
      const up = document.querySelector("[data-widget-kind='crashes'] [data-role='edit-up']");
      const remove = document.querySelector("[data-widget-kind='crashes'] [data-role='edit-remove']");
      return {
        handle: shown(document.querySelector("[data-role='edit-handle']")),
        catalogue: shown(document.querySelector("[data-role='edit-catalogue']")),
        up: shown(up),
        upHeight: up.getBoundingClientRect().height,
        removeHeight: remove.getBoundingClientRect().height,
        page: document.documentElement.scrollWidth - document.documentElement.clientWidth
      };
    });
    console.error("compact edit: " + JSON.stringify(compact));
    check(!compact.handle, "the compact class shows the grid handle");
    check(!compact.catalogue, "the compact class shows the catalogue");
    check(compact.up, "the compact class shows no reorder");
    check(compact.upHeight >= 44 && compact.removeHeight >= 44, "a compact edit control is under 44 px: " + JSON.stringify(compact));
    check(compact.page <= 0, "the page scrolls sideways by " + compact.page + " px at 393 px");

    if (shots) {
      await page2.screenshot({ path: path.join(shots, "edit-mode-393.png"), fullPage: true });
    }

    await page2.click("[data-widget-kind='crashes'] [data-role='edit-up']");
    await said(page2, "Crashes compared moved up, position 1 of 3");
    await page2.click("[data-role='edit-reset']");
    await said(page2, "Unsaved changes discarded.");
    await leave(phone);

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
