// A research entry's headline, label and link on a 390 px phone (Sprint 29
// N3; board ux-design-2026-11-12-sprint29/03, ④ „A bei 390 px“), driven in
// a real Chromium by test/browser/research_entry_phone_test.exs, which
// boots the endpoint and passes the security's Research tab URL and the
// entry's id as one JSON argument. It measures where the pin's glyph sits
// against the headline once it wraps, and whether the entry and the page
// keep within the phone's width.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "...", "seen": {...}}; the exit status is 0 either way unless the browser
// itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { visit, leave } = require("./settle");

const args = JSON.parse(process.argv[2]);

async function measure(page, entryId) {
  return page.evaluate((id) => {
    const entry = document.getElementById("research-entry-" + id);
    if (!entry) return null;
    const rect = (node) => (node ? node.getBoundingClientRect() : null);
    const headline = entry.querySelector(".research-entry__headline");
    const text = headline && headline.querySelector("span");
    const glyph = headline && headline.querySelector(".note-glyph");
    const label = entry.querySelector(".research-entry__label");
    const link = entry.querySelector(".research-entry__facts a");
    const lineHeight = text ? parseFloat(getComputedStyle(text).lineHeight) : 0;
    const box = rect(entry);
    const round = (value) => Math.round(value * 10) / 10;
    const r = (node) => {
      const b = rect(node);
      return b && { top: round(b.top), bottom: round(b.bottom), left: round(b.left), right: round(b.right) };
    };
    return {
      viewport: window.innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      lineHeight,
      entry: r(entry),
      text: r(text),
      glyph: r(glyph),
      label: r(label),
      link: r(link),
      linkText: link ? link.textContent.trim() : null,
      inside: [label, link, text].every((node) => node && rect(node).right <= box.right + 0.5)
    };
  }, entryId);
}

async function run(browser) {
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    hasTouch: true,
    isMobile: true,
    locale: "de-DE"
  });
  const page = await context.newPage();
  await visit(page, args.url);
  await page.waitForSelector("[data-phx-main].phx-connected");
  await page.waitForSelector("#research-entry-" + args.entry_id + " .research-entry__headline");

  const seen = await measure(page, args.entry_id);
  const errors = [];

  if (!seen) {
    errors.push("no entry #" + args.entry_id);
  } else {
    if (seen.scrollWidth > seen.viewport) errors.push("the page scrolls sideways: " + seen.scrollWidth);
    if (!seen.text || seen.text.bottom - seen.text.top < 1.5 * seen.lineHeight)
      errors.push("the headline does not wrap at 390 px, so the case is not measured");
    if (!seen.glyph) {
      errors.push("no glyph before the headline");
    } else {
      const middle = (seen.glyph.top + seen.glyph.bottom) / 2;
      if (middle < seen.text.top || middle > seen.text.top + seen.lineHeight)
        errors.push("the glyph is not on the headline's first line");
      if (seen.glyph.right > seen.text.left) errors.push("the glyph is not before the headline");
    }
    if (!seen.inside) errors.push("the headline, its label or the link runs past the entry");
    if (seen.linkText !== args.domain) errors.push("the link reads " + JSON.stringify(seen.linkText));
  }

  await leave(context);
  return { errors, seen };
}

(async () => {
  const browser = await launchChromium();
  try {
    const { errors, seen } = await run(browser);
    process.stdout.write(
      JSON.stringify(errors.length === 0 ? { ok: true } : { ok: false, error: errors.join("; "), seen }) + "\n"
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
