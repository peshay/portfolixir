// The sunburst's centre comes back to its total (Sprint 24 P1, #1366's
// first line), driven in a real Chromium on a phone viewport by
// test/browser/sunburst_centre_return_test.exs, which boots the endpoint
// and passes the Allocation tab's URL as the only argument. LiveViewTest
// runs no client script and does no hit testing, so this is where a tap on
// the centre (whose text lets the pointer through to the chart) and a tap
// outside the chart are checked.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");

const url = process.argv[2];
const CENTRE = "[data-role='sunburst-centre']";

// The label the centre shows: the server's (its data-label, what a patch
// wrote) and the painted text (what the reader sees), as one string.
async function centre(page) {
  return page.evaluate((sel) => {
    const c = document.querySelector(sel);
    const text = c.querySelector(".sunburst-centre__label").textContent.trim();
    return c.getAttribute("data-label") + " | " + text;
  }, CENTRE);
}

// Waits until the centre reads `label` in both, and fails naming what it
// reads after `timeout` ms. The patch arrives over the socket, so the state
// is polled for, never slept for.
async function expectCentre(page, label, message, timeout = 5000) {
  try {
    await page.waitForFunction(([sel, want]) => {
      const c = document.querySelector(sel);
      const text = c.querySelector(".sunburst-centre__label").textContent.trim();
      return c.getAttribute("data-label") === want && text === want;
    }, [CENTRE, label], { timeout, polling: "raf" });
  } catch (_) {
    throw new Error(message + ": the centre reads " + JSON.stringify(await centre(page)));
  }
}

// A point inside the named slice: the middle of the points of its box that
// hit it, so a tap lands on the slice and not in the hole or a neighbour.
async function slicePoint(page, label) {
  return page.evaluate((name) => {
    const seg = Array.from(document.querySelectorAll("path.sunburst-seg"))
      .find((p) => p.getAttribute("data-label") === name);
    if (!seg) return null;
    const box = seg.getBoundingClientRect();
    const hits = [];
    for (let y = box.top + 1; y < box.bottom; y += 3) {
      for (let x = box.left + 1; x < box.right; x += 3) {
        if (document.elementFromPoint(x, y) === seg) hits.push([x, y]);
      }
    }
    return hits.length ? hits[Math.floor(hits.length / 2)] : null;
  }, label);
}

// The middle of an element's box.
async function middle(page, selector) {
  const box = await page.locator(selector).first().boundingBox();
  return [box.x + box.width / 2, box.y + box.height / 2];
}

async function tapSlice(page, label) {
  const point = await slicePoint(page, label);
  if (!point) throw new Error("no point inside the slice " + label);
  await page.touchscreen.tap(point[0], point[1]);
}

async function run() {
  const browser = await launchChromium();
  try {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      hasTouch: true,
      isMobile: true
    });
    const page = await context.newPage();
    await page.goto(url);
    await page.waitForSelector("[data-phx-main].phx-connected");
    await page.waitForSelector("path.sunburst-seg[data-label='Core']");
    await page.locator(".sunburst-figure").scrollIntoViewIfNeeded();

    const total = await page.getAttribute(CENTRE, "data-label");
    if (total === "Core") throw new Error("the centre starts on a slice");

    // A tap on the centre: its text lets the tap through to the chart.
    await tapSlice(page, "Core");
    await expectCentre(page, "Core", "a tap on Core did not select it");
    const [cx, cy] = await middle(page, ".sunburst-figure");
    await page.touchscreen.tap(cx, cy);
    await expectCentre(page, total, "a tap on the centre left the slice");

    // A tap on the selected slice again.
    await tapSlice(page, "Satellite");
    await expectCentre(page, "Satellite", "a tap on Satellite did not select it");
    await tapSlice(page, "Satellite");
    await expectCentre(page, total, "a second tap on the selected slice left it");

    // A tap outside the chart: on the section's heading.
    await tapSlice(page, "Core");
    await expectCentre(page, "Core", "a tap on Core did not select it again");
    const [hx, hy] = await middle(page, "#portfolio-allocation h2");
    await page.touchscreen.tap(hx, hy);
    await expectCentre(page, total, "a tap outside the chart left the slice");

    // Escape.
    await tapSlice(page, "Core");
    await expectCentre(page, "Core", "a tap on Core did not select it a third time");
    await page.keyboard.press("Escape");
    await expectCentre(page, total, "Escape left the slice");

    // Another slice while one is selected selects that one (no return).
    await tapSlice(page, "Core");
    await expectCentre(page, "Core", "a tap on Core did not select it a fourth time");
    await tapSlice(page, "Satellite");
    await expectCentre(page, "Satellite", "a tap on another slice did not move the selection");

    await context.close();
  } finally {
    await browser.close();
  }
}

run()
  .then(() => console.log(JSON.stringify({ ok: true })))
  .catch((error) => console.log(JSON.stringify({ ok: false, error: String(error.message || error) })));
