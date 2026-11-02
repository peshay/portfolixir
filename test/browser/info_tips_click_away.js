// The ⓘ panels as one popover (Sprint 23 C1, the owner's report of
// 2026-11-02), driven in a real Chromium by
// test/browser/info_tips_click_away_test.exs, which boots the endpoint and
// passes the page's URL as the only argument. LiveViewTest runs no client
// script, so this is where the behaviour itself is checked.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { chromium } = require("playwright");

const url = process.argv[2];
// Two ⓘ on Wealth whose open panels cover neither the other's summary nor
// the page title: the view switcher's (its panel opens below, #1336) and
// Invested capital's.
const A = "details.view-switcher__help.metric-tooltip";
const B = "#kpi-invested details.metric-tooltip";

function check(condition, message) {
  if (!condition) throw new Error(message);
}

// The ⓘ open on the page, each named by the selector it matched.
async function openTips(page) {
  return page.evaluate(([a, b]) => {
    const open = Array.from(document.querySelectorAll("details.metric-tooltip[open]"));
    return open.map((tip) => (tip.matches(a) ? "A" : tip.matches(b) ? "B" : "other"));
  }, [A, B]);
}

async function activeIs(page, selector) {
  return page.evaluate((s) => document.activeElement === document.querySelector(s), selector);
}

async function ready(page) {
  await page.goto(url);
  await page.waitForSelector("[data-phx-main].phx-connected");
  await page.waitForSelector(A + " > summary");
  await page.waitForSelector(B + " > summary");
}

async function pointer(browser) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await ready(page);

  // Opening one closes any other.
  await page.click(A + " > summary");
  check(JSON.stringify(await openTips(page)) === '["A"]', "A did not open alone: " + (await openTips(page)));
  await page.click(B + " > summary");
  check(JSON.stringify(await openTips(page)) === '["B"]', "opening B left " + (await openTips(page)) + " open");

  // A click inside the open panel leaves it open.
  await page.click(B + " > p[role='tooltip']");
  check(JSON.stringify(await openTips(page)) === '["B"]', "a click inside B's panel left " + (await openTips(page)));

  // A click elsewhere closes it, and the click still lands where it was
  // aimed: the focus goes where the click put it, never back to the ⓘ.
  await page.evaluate(() => {
    const input = document.createElement("input");
    input.id = "click-away-target";
    input.setAttribute("aria-label", "click-away target");
    document.querySelector("main, body").prepend(input);
  });
  await page.click("#click-away-target");
  check(JSON.stringify(await openTips(page)) === "[]", "a click elsewhere left " + (await openTips(page)) + " open");
  check(await activeIs(page, "#click-away-target"), "the click-away moved the focus off the clicked field");

  // The keyboard opens one and closes the other too.
  await page.click(A + " > summary");
  await page.focus(B + " > summary");
  await page.keyboard.press("Enter");
  check(JSON.stringify(await openTips(page)) === '["B"]', "Enter on B left " + (await openTips(page)) + " open");
  check(await activeIs(page, B + " > summary"), "Enter on B moved the focus off its summary");

  // Escape still closes it and returns the focus to its summary (#1342).
  await page.click(B + " > summary");
  await page.click(A + " > summary");
  await page.keyboard.press("Escape");
  check(JSON.stringify(await openTips(page)) === "[]", "Escape left " + (await openTips(page)) + " open");
  check(await activeIs(page, A + " > summary"), "Escape did not return the focus to A's summary");

  await page.close();
}

// A tap outside closes the panel on a touch screen.
async function touch(browser) {
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    hasTouch: true,
    isMobile: true
  });
  const page = await context.newPage();
  await ready(page);

  await page.tap(B + " > summary");
  check(JSON.stringify(await openTips(page)) === '["B"]', "the tap did not open B: " + (await openTips(page)));
  await page.tap(B + " > p[role='tooltip']");
  check(JSON.stringify(await openTips(page)) === '["B"]', "a tap inside B's panel left " + (await openTips(page)));
  await page.tap("h1");
  check(JSON.stringify(await openTips(page)) === "[]", "a tap elsewhere left " + (await openTips(page)) + " open");

  await context.close();
}

(async () => {
  const browser = await chromium.launch();
  try {
    await pointer(browser);
    await touch(browser);
    process.stdout.write(JSON.stringify({ ok: true }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await browser.close();
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
