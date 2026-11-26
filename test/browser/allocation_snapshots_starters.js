// The starters „Allokation & Ziele“ and „Snapshots“ against Wealth's tabs in
// a real browser (Sprint 32 W2, W3; I57; plan D-7; board
// ux-design-2026-11-25-sprint32/02 ②), driven by
// test/browser/allocation_snapshots_starters_test.exs, which boots the
// endpoint, seeds the review seed, stores each starter as the boot does and
// passes, per starter, its dashboard's id, the Wealth tab's address and its
// sections in order: the widget's kind, the section's root on Wealth and
// the parts of it to compare.
//
// For each starter it opens the dashboard and the tab in German at 1200 px,
// waits until every read has landed, and reads:
//   - the kinds of the dashboard's widgets in the grid's order;
//   - whether the tab's section roots stand in the same order;
//   - each part's text, in the widget and in the tab's section, its
//     whitespace collapsed (a part found in neither is reported missing).
//
// With `tamper` set it changes the first part's text on the tab before
// reading it, so the test sees its comparison name a difference.
//
// Prints one JSON object on stdout: {"ok": true, "starters": [...]} or
// {"ok": false, "error": "..."}; the exit status is 0 either way unless the
// browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const { base_url: base, starters, tamper } = JSON.parse(process.argv[2]);
const VIEWPORT = { width: 1200, height: 900 };

// Each part's text inside `rootSelector` (the element itself where it
// matches), whitespace collapsed; null where the root or the part is
// missing.
async function read(page, rootSelector, parts, change) {
  return page.evaluate(
    ([rootSel, partSels, changeFirst]) => {
      const root = document.querySelector(rootSel);
      if (!root) return { root: false, texts: partSels.map(() => null) };
      const within = (sel) => (root.matches(sel) ? root : root.querySelector(sel));
      if (changeFirst) {
        const first = within(partSels[0]);
        if (first) first.textContent = "0" + first.textContent;
      }
      const texts = partSels.map((sel) => {
        const node = within(sel);
        return node ? node.textContent.replace(/\s+/g, " ").trim() : null;
      });
      return { root: true, texts };
    },
    [rootSelector, parts, change]
  );
}

// Whether the roots stand in the document in the order given.
async function inOrder(page, roots) {
  return page.evaluate((sels) => {
    const nodes = sels.map((sel) => document.querySelector(sel));
    if (nodes.some((n) => !n)) return false;
    for (let i = 1; i < nodes.length; i++) {
      if (!(nodes[i - 1].compareDocumentPosition(nodes[i]) & Node.DOCUMENT_POSITION_FOLLOWING)) {
        return false;
      }
    }
    return true;
  }, roots);
}

async function compare(page, starter) {
  await visit(page, base + "/dashboards/" + starter.id + "?locale=de");
  await settle(page);
  const kinds = await page
    .locator("#dashboard-grid > .dashboard-widget")
    .evaluateAll((nodes) => nodes.map((n) => n.getAttribute("data-widget-kind")));
  const widgets = [];
  for (const section of starter.sections) {
    widgets.push(await read(page, "[data-widget-kind='" + section.kind + "']", section.parts, false));
  }

  await visit(page, base + starter.wealth + (starter.wealth.includes("?") ? "&" : "?") + "locale=de");
  await settle(page);
  const ordered = await inOrder(page, starter.sections.map((s) => s.wealth_root));
  const wealth = [];
  for (let i = 0; i < starter.sections.length; i++) {
    const section = starter.sections[i];
    wealth.push(await read(page, section.wealth_root, section.parts, Boolean(tamper) && i === 0));
  }

  return { key: starter.key, kinds, ordered, widgets, wealth };
}

(async () => {
  const browser = await launchChromium();
  try {
    const context = await browser.newContext({ viewport: VIEWPORT, locale: "de-DE" });
    const page = await context.newPage();
    const results = [];
    for (const starter of starters) results.push(await compare(page, starter));
    await leave(context);
    process.stdout.write(JSON.stringify({ ok: true, starters: results }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
