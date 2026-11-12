// The chart's note pins on a 390 px phone (Sprint 28 closing act, ND3),
// driven in a real Chromium by test/browser/note_pins_phone_test.exs, which
// boots the endpoint and passes the security's chart URL as the only
// argument. It measures each pin's head and glyph in CSS pixels once the
// ChartCrosshair hook has written --chart-upx on the frame.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "...", "pins": [...]}; the exit status is 0 either way unless the browser
// itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { visit, leave } = require("./settle");

const url = process.argv[2];
const PANEL = "#detail-tab-panel-chart";

async function measure(page) {
  return page.evaluate((panel) => {
    const size = (node) => {
      if (!node) return null;
      const rect = node.getBoundingClientRect();
      return { width: Math.round(rect.width * 10) / 10, height: Math.round(rect.height * 10) / 10 };
    };
    return Array.from(document.querySelectorAll(panel + " g.note-pin")).map((pin) => ({
      tone: Array.from(pin.classList).find((name) => name.startsWith("note-pin--")),
      head: size(pin.querySelector(".note-pin__head")),
      glyph: size(pin.querySelector(".note-pin__glyph"))
    }));
  }, PANEL);
}

async function run(browser) {
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    hasTouch: true,
    isMobile: true
  });
  const page = await context.newPage();
  await visit(page, url);
  await page.waitForSelector("[data-phx-main].phx-connected");
  await page.waitForSelector(PANEL + " g.note-pin");
  // The hook writes the scale on mount; until then the factor is 1.
  await page.waitForFunction(
    (panel) => {
      const frame = document.querySelector(panel + " .chart-frame");
      return frame && frame.style.getPropertyValue("--chart-upx") !== "";
    },
    PANEL,
    { timeout: 10000, polling: "raf" }
  );

  const pins = await measure(page);
  const errors = [];
  const byTone = (tone) => pins.filter((pin) => pin.tone === tone);

  if (pins.length !== 4) errors.push("expected 4 pins, saw " + pins.length);

  for (const pin of pins) {
    if (!pin.head || pin.head.width < 10) errors.push(pin.tone + ": head under 10 px");
  }

  for (const tone of ["note-pin--pos", "note-pin--neg", "note-pin--mixed"]) {
    const [pin] = byTone(tone);
    if (!pin) errors.push("no " + tone + " pin");
    else if (!pin.glyph || Math.max(pin.glyph.width, pin.glyph.height) < 5)
      errors.push(tone + ": glyph under 5 px or missing");
  }

  for (const pin of byTone("note-pin--neu")) {
    if (pin.glyph) errors.push("a neutral pin carries a glyph");
  }

  await leave(context);
  return { errors, pins };
}

(async () => {
  const browser = await launchChromium();
  try {
    const { errors, pins } = await run(browser);
    process.stdout.write(
      JSON.stringify(errors.length === 0 ? { ok: true } : { ok: false, error: errors.join("; "), pins }) + "\n"
    );
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
