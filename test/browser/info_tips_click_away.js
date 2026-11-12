// The ⓘ panels as one popover (Sprint 23 C1, the owner's report of
// 2026-11-02), driven in a real Chromium by
// test/browser/info_tips_click_away_test.exs, which boots the endpoint and
// passes the page's URL as the only argument. LiveViewTest runs no client
// script, so this is where the behaviour itself is checked.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { visit, leave } = require("./settle");

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

// Waits until exactly `expected` (e.g. ["B"], or [] for none) is open, and
// fails naming what is open after `timeout` ms. The `toggle` event that
// closes the other ⓘ fires as its own task after the native toggle, so an
// Enter or a click can return before it has run; the state is polled for,
// never slept for.
async function expectOpen(page, expected, message, timeout = 5000) {
  try {
    await page.waitForFunction(([a, b, want]) => {
      const open = Array.from(document.querySelectorAll("details.metric-tooltip[open]"));
      const names = open.map((tip) => (tip.matches(a) ? "A" : tip.matches(b) ? "B" : "other"));
      return JSON.stringify(names) === JSON.stringify(want);
    }, [A, B, expected], { timeout, polling: "raf" });
  } catch (_) {
    throw new Error(message + ": " + JSON.stringify(await openTips(page)) + " open");
  }
}

async function activeIs(page, selector) {
  return page.evaluate((s) => document.activeElement === document.querySelector(s), selector);
}

async function ready(page) {
  await visit(page, url);
  await page.waitForSelector("[data-phx-main].phx-connected");
  await page.waitForSelector(A + " > summary");
  await page.waitForSelector(B + " > summary");
}

async function pointer(browser) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await ready(page);

  // Opening one closes any other.
  await page.click(A + " > summary");
  await expectOpen(page, ["A"], "A did not open alone");
  await page.click(B + " > summary");
  await expectOpen(page, ["B"], "opening B left");

  // A click inside the open panel leaves it open.
  await page.click(B + " > p[role='tooltip']");
  await expectOpen(page, ["B"], "a click inside B's panel left");

  // A click elsewhere closes it, and the click still lands where it was
  // aimed: the focus goes where the click put it, never back to the ⓘ.
  await page.evaluate(() => {
    const input = document.createElement("input");
    input.id = "click-away-target";
    input.setAttribute("aria-label", "click-away target");
    document.querySelector("main, body").prepend(input);
  });
  await page.click("#click-away-target");
  await expectOpen(page, [], "a click elsewhere left");
  check(await activeIs(page, "#click-away-target"), "the click-away moved the focus off the clicked field");

  // The keyboard opens one and closes the other too.
  await page.click(A + " > summary");
  await page.focus(B + " > summary");
  await page.keyboard.press("Enter");
  await expectOpen(page, ["B"], "Enter on B left");
  check(await activeIs(page, B + " > summary"), "Enter on B moved the focus off its summary");

  // Two opens inside one task, before either toggle event has run: the
  // later one stays open. When the deferred toggle closed the others, A's
  // late toggle closed B and B's own was dropped (B went closed, open,
  // closed), so a fast second open lost; the open is now settled
  // synchronously on the summary's click.
  await page.click(B + " > summary");
  await expectOpen(page, [], "closing B left");
  await page.evaluate(([a, b]) => {
    document.querySelector(a + " > summary").click();
    document.querySelector(b + " > summary").click();
  }, [A, B]);
  await expectOpen(page, ["B"], "two opens in one task left");
  await page.click(B + " > summary");
  await expectOpen(page, [], "closing B again left");

  // Escape still closes it and returns the focus to its summary (#1342).
  await page.click(A + " > summary");
  await page.keyboard.press("Escape");
  await expectOpen(page, [], "Escape left");
  check(await activeIs(page, A + " > summary"), "Escape did not return the focus to A's summary");

  await leave(page);
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
  await expectOpen(page, ["B"], "the tap did not open B");
  await page.tap(B + " > p[role='tooltip']");
  await expectOpen(page, ["B"], "a tap inside B's panel left");
  await page.tap("h1");
  await expectOpen(page, [], "a tap elsewhere left");

  await leave(context);
}

(async () => {
  const browser = await launchChromium();
  try {
    await pointer(browser);
    await touch(browser);
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
