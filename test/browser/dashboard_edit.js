// The dashboard's edit mode (ADR-0062 §7; idea board
// ux-design-2026-11-21-idea-i56 03; Sprint 31 D6), driven in a real
// Chromium by test/browser/dashboard_edit_test.exs, which boots the
// endpoint, seeds one stored dashboard and passes the base URL and its
// path as JSON in the only argument. LiveViewTest runs no client script,
// so this is where the DashboardEdit hook is read: the keyboard on a
// widget's handle (the arrow keys do not scroll the page, the focus stays
// on the handle as its widget moves), a drag of a handle on the wide grid,
// the live regions' sentences — each step's at the widget it acted on
// (Sprint 32 E2), the bar's for its own buttons —, the note of a click at
// the page's foot inside the window (board ux-design-2026-11-25-sprint32/01
// ①, ③), Ctrl+Z, „Fertig“, and the compact class's reorder. The Elixir
// test then reads the stored layout the save wrote.
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

// What the live regions say: the bar's status line and every widget's
// note, each trimmed, the empty left out.
function status(page) {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll("#dashboard-edit-status, [data-role='edit-note']"))
      .map((el) => el.textContent.trim())
      .filter((text) => text !== "")
  );
}

// `text` said in the region `where` names: "bar" (the status line) or a
// widget's kind (its note).
async function said(page, text, where) {
  try {
    await page.waitForFunction(
      ([text, where]) => {
        const region =
          where === "bar"
            ? document.getElementById("dashboard-edit-status")
            : document.querySelector("[data-widget-kind='" + where + "'] [data-role='edit-note']");
        return region !== null && region.textContent.trim() === text;
      },
      [text, where],
      { timeout: 10000 }
    );
  } catch (_) {
    throw new Error("„" + where + "“ did not say „" + text + "“; the regions say " + JSON.stringify(await status(page)));
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

    // Sprint 32 E4: Wertentwicklung and Tops und Flops side by side at L,
    // Crashes im Vergleich under the first.
    await page.focus("[data-widget-kind='crashes'] [data-role='edit-handle']");
    await page.keyboard.press("ArrowRight");
    await said(page, "Crashes compared moved right, column 2, row 5", "crashes");
    check(JSON.stringify(await place(page, "crashes")) === JSON.stringify([2, 5, "L"]),
      "the arrow key did not move Crashes compared to column 2: " + JSON.stringify(await place(page, "crashes")));

    const perfHandle = "[data-widget-kind='performance'] [data-role='edit-handle']";
    await page.focus(perfHandle);
    const scrollBefore = await page.evaluate(() => window.scrollY);
    // Down onto Crashes compared: it makes room (Sprint 32 E2).
    await page.keyboard.press("ArrowDown");
    await said(page, "Performance moved down, column 1, row 2 · 1 widget made room", "performance");
    check(JSON.stringify(await place(page, "crashes")) === JSON.stringify([7, 5, "L"]),
      "Crashes compared did not make room: " + JSON.stringify(await place(page, "crashes")));
    await page.keyboard.press("ArrowUp");
    await said(page, "Performance moved up, column 1, row 1", "performance");
    check((await status(page)).length === 1, "more than the widget's note speaks: " + JSON.stringify(await status(page)));
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
        dy: g.bottom + 40 - w.top,
        rows: rows
      };
    });
    await page.mouse.move(drop.x, drop.y);
    await page.mouse.down();
    await page.mouse.move(drop.x, drop.y + drop.dy / 2, { steps: 5 });
    await page.mouse.move(drop.x, drop.y + drop.dy, { steps: 5 });
    await page.mouse.up();
    // Crashes compared floats up into the place Tops und Flops left.
    await said(page, "Tops and flops placed at column 7, row " + (drop.rows + 1) + " · 1 widget made room", "movers");
    check(JSON.stringify(await place(page, "movers")) === JSON.stringify([7, drop.rows + 1, "L"]),
      "the drag placed Tops and flops at " + JSON.stringify(await place(page, "movers")));

    // Board 01 ①: a click at the page's foot. Scrolled to the end, the size
    // switch of the last widget; its note stands under it, inside the
    // window, with „Undo“; Ctrl+Z takes the step back.
    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    await page.click("[data-widget-kind='movers'] [data-role='edit-size'][data-size='S']");
    await said(page, "Tops and flops set to size S, column 7, row " + (drop.rows + 1), "movers");
    const foot = await page.evaluate(() => {
      const note = document.querySelector("[data-widget-kind='movers'] .widget__note");
      const r = note.getBoundingClientRect();
      const undo = note.querySelector("[data-role='edit-undo']");
      return {
        top: r.top,
        bottom: r.bottom,
        left: r.left,
        right: r.right,
        height: window.innerHeight,
        width: window.innerWidth,
        undo: undo !== null && undo.getBoundingClientRect().height > 0,
        live: note.querySelector("[role='status'][aria-live='polite']") !== null
      };
    });
    console.error("the note at the foot: " + JSON.stringify(foot));
    check(foot.top >= 0 && foot.bottom <= foot.height && foot.left >= 0 && foot.right <= foot.width,
      "the note of a click at the page's foot is outside the window: " + JSON.stringify(foot));
    check(foot.undo, "the note shows no „Undo“");
    check(foot.live, "the note is no polite live region");
    await page.keyboard.press("Control+z");
    await said(page, "Last step undone", "movers");
    check(JSON.stringify(await place(page, "movers")) === JSON.stringify([7, drop.rows + 1, "L"]),
      "Ctrl+Z did not take the size back: " + JSON.stringify(await place(page, "movers")));

    if (shots) {
      await page.screenshot({ path: path.join(shots, "edit-mode-1200.png"), fullPage: true });
    }

    await page.click("[data-role='edit-done']");
    await said(page, "Dashboard saved.", "bar");
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
    await said(page2, "Crashes compared moved up, position 1 of 3", "crashes");
    await page2.click("[data-role='edit-reset']");
    await said(page2, "Unsaved changes discarded.", "bar");
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
