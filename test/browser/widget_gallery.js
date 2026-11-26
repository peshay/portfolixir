// The widget gallery for the docs (Sprint 32 L4; D-13; board
// ux-design-2026-11-25-sprint32/08), driven by
// test/browser/widget_gallery_test.exs, which boots the endpoint, seeds the
// review seed and stores throwaway dashboards holding every registered kind
// in every grid size it takes (read from the registry, so a kind added
// later is photographed with no change here), and passes their ids.
//
// For each theme, light and dark, at 1200 px wide (the wide grid) and a
// device scale factor of 2, it opens each dashboard in English, waits until
// every read has landed, and photographs each widget cropped to its tile:
// `<out>/<kind>-<size>-<theme>.png`, the size in lower case (`s`, `m`, `l`,
// `xl`, `row`). The theme is set as the app sets it, before the page loads.
//
// Prints one JSON object on stdout: {"ok": true, "files": [...]} or
// {"ok": false, "error": "..."}; the exit status is 0 either way unless
// the browser itself fails.
"use strict";

const path = require("path");
const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const { base_url: base, ids, out } = JSON.parse(process.argv[2]);
const THEMES = ["light", "dark"];
const VIEWPORT = { width: 1200, height: 900 };

async function shoot(browser, theme) {
  const files = [];
  const context = await browser.newContext({ viewport: VIEWPORT, deviceScaleFactor: 2, locale: "en-US" });
  await context.addInitScript((th) => {
    try {
      localStorage.setItem("portfolixir-theme", th);
    } catch (_) {}
  }, theme);
  const page = await context.newPage();

  for (const id of ids) {
    await visit(page, base + "/dashboards/" + id + "?locale=en");
    await settle(page);
    // The theme forced on the page as well, whatever the machine's own
    // colour scheme: a dark shot drawn light would pass unnoticed.
    await page.evaluate((th) => document.documentElement.setAttribute("data-theme", th), theme);
    // Sprint 32 W3: the top bar stays where it stands instead of sticking
    // over a widget taller than the window (a „Zeile“ section, such as
    // the snapshot comparison), whose head it covered in the picture. A
    // sticky bar takes the same room in the flow, so nothing else moves.
    await page.addStyleTag({ content: ".topbar { position: static !important; }" });
    const widgets = page.locator("#dashboard-grid > .dashboard-widget");
    const count = await widgets.count();
    for (let i = 0; i < count; i++) {
      const widget = widgets.nth(i);
      const kind = await widget.getAttribute("data-widget-kind");
      const size = (await widget.getAttribute("data-size")).toLowerCase();
      const file = kind + "-" + size + "-" + theme + ".png";
      await widget.scrollIntoViewIfNeeded();
      await widget.screenshot({ path: path.join(out, file), animations: "disabled" });
      files.push(file);
    }
  }

  await leave(context);
  return files;
}

(async () => {
  const browser = await launchChromium();
  try {
    const files = [];
    for (const theme of THEMES) files.push(...(await shoot(browser, theme)));
    process.stdout.write(JSON.stringify({ ok: true, files }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
