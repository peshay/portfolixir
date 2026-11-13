// Where an ⓘ panel opens, driven in a real Chromium by
// test/browser/info_tips_placement_test.exs, which boots the endpoint and
// passes the base URL and the ids it seeded as JSON in the only argument.
// LiveViewTest runs no client script, so the measured placement
// (`window.Portfolixir.placeInfoTip`) is checked here.
//
// Each case opens one ⓘ and asserts its open panel lies inside the box it
// can be read in: the nearest ancestor that clips it (a dialog's scrolling
// body, issue V2 of the stacked PR's closing act), and below the sticky top
// bar outside a dialog (the closing act's Lane I finding), each within the
// viewport.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "errors":
// ["..."]}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;

function check(condition, message) {
  if (!condition) throw new Error(message);
}

async function ready(page, path) {
  await visit(page, base + path);
  await page.waitForSelector("[data-phx-main].phx-connected");
}

// Opens the ⓘ, waits for its panel, and returns the panel's rect beside the
// box it must stay inside (half a pixel of rounding allowed).
async function openAndMeasure(page, tipSelector) {
  await page.waitForSelector(tipSelector + " > summary");
  await page.click(tipSelector + " > summary");
  await page.waitForFunction((s) => document.querySelector(s).open, tipSelector);
  // The placement runs on the toggle event; one frame later it has landed.
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));

  return page.evaluate((s) => {
    const tip = document.querySelector(s);
    const panel = tip.querySelector("p[role='tooltip']") || tip.querySelector("p");
    const r = panel.getBoundingClientRect();
    const box = {
      top: 0,
      left: 0,
      right: document.documentElement.clientWidth,
      bottom: document.documentElement.clientHeight,
      clip: "viewport"
    };
    for (let el = tip.parentElement; el && el !== document.body; el = el.parentElement) {
      const style = getComputedStyle(el);
      if (style.overflowX !== "visible" || style.overflowY !== "visible") {
        const c = el.getBoundingClientRect();
        box.top = Math.max(box.top, c.top);
        box.left = Math.max(box.left, c.left);
        box.right = Math.min(box.right, c.right);
        box.bottom = Math.min(box.bottom, c.bottom);
        box.clip = el.className || el.tagName;
        break;
      }
    }
    const topbar = document.querySelector(".topbar");
    if (topbar && !tip.closest("dialog")) {
      box.top = Math.max(box.top, topbar.getBoundingClientRect().bottom);
    }
    return {
      panel: { top: r.top, left: r.left, right: r.right, bottom: r.bottom },
      box,
      place: tip.getAttribute("data-place")
    };
  }, tipSelector);
}

function assertInside(label, measured) {
  const { panel, box } = measured;
  const inside =
    panel.top >= box.top - 0.5 &&
    panel.left >= box.left - 0.5 &&
    panel.right <= box.right + 0.5;
  check(inside, label + ": the panel leaves its box " + JSON.stringify(measured));
}

// V2: the external flows' ⓘ inside the depot merge preview's dialog.
async function mergeDialog(browser) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await ready(page, "/portfolios");
  await page.click("#account-kebab-" + args.source_id);
  await page.click("#account-row-menu-" + args.source_id + " [data-role='menu-merge']");
  await page.check("#merge-target-" + args.target_id);
  await page.waitForSelector("#merge-dialog [data-role='merge-continue']:not([disabled])");
  await page.click("#merge-dialog [data-role='merge-continue']");
  await page.waitForSelector("#merge-dialog [data-role='merge-flows']");

  const tip = "#merge-dialog [data-role='merge-flows'] details.metric-tooltip";
  assertInside("the merge dialog's external flows ⓘ at 1280", await openAndMeasure(page, tip));
  await leave(page);
}

// Lane I: a heading's ⓘ near the top of the page, under the top bar.
async function headingNearTop(browser, path, tip, viewport, label) {
  const page = await browser.newPage({ viewport });
  await ready(page, path);
  assertInside(label, await openAndMeasure(page, tip));
  await leave(page);
}

// PR 2's closing act (board ux-design-2026-11-12-sprint29/06 ⑬): a
// section's ⓘ on its basis line (Wealth's positions at 390 px) opens under
// its line, so it never covers the sentence it explains; where the window
// has no room under the line, it opens above, as every other ⓘ does.
async function basisLine(browser) {
  const tip = "[data-role='positions-basis'] details.metric-tooltip";
  const lineOf = (page) =>
    page.evaluate((s) => {
      const r = document.querySelector(s).closest(".summary-basis").getBoundingClientRect();
      return { top: r.top, bottom: r.bottom, docBottom: r.bottom + window.scrollY };
    }, tip);
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await ready(page, "/portfolio");
  await page.waitForSelector(tip);
  // The page's figures land after it connects and move the line: placed
  // once they have.
  await settle(page);
  await page.evaluate((s) => document.querySelector(s).scrollIntoView({ block: "center" }), tip);
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
  const open = await openAndMeasure(page, tip);
  const line = await lineOf(page);
  check(
    open.place === "below" && open.panel.top >= line.bottom - 0.5,
    "Wealth's positions ⓘ at 390: the panel does not open under its line " + JSON.stringify({ open, line })
  );
  assertInside("Wealth's positions ⓘ at 390", open);
  await page.click(tip + " > summary");

  // No room under the line: from the page's top, a window that ends 12 px
  // under it (scrolling there depends on how long the page below is).
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.setViewportSize({ width: 390, height: Math.round(line.docBottom + 12) });
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
  const above = await openAndMeasure(page, tip);
  const lineNow = await lineOf(page);
  check(
    above.place !== "below" && above.panel.bottom <= lineNow.bottom + 0.5,
    "Wealth's positions ⓘ without room below: the panel does not open above " + JSON.stringify({ above, lineNow })
  );
  await leave(page);
}

// Every case runs, so a failure names each box an ⓘ leaves.
(async () => {
  const browser = await launchChromium();
  const cases = [
    () => mergeDialog(browser),
    () =>
      headingNearTop(
        browser,
        "/snapshots",
        "[data-role='snapshots-info']",
        { width: 1280, height: 900 },
        "Snapshots' heading ⓘ at 1280"
      ),
    () =>
      headingNearTop(
        browser,
        "/risk",
        "#policy-rules .section-title details.metric-tooltip",
        { width: 390, height: 844 },
        "Risk's Own rules ⓘ at 390"
      ),
    () => basisLine(browser)
  ];
  const errors = [];
  try {
    for (const run of cases) {
      try {
        await run();
      } catch (error) {
        errors.push(String(error && error.message));
      }
    }
  } finally {
    await leave(browser);
  }
  const result = errors.length === 0 ? { ok: true } : { ok: false, errors };
  process.stdout.write(JSON.stringify(result) + "\n");
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
