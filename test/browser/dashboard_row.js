// The size „Zeile“ in a real browser (Sprint 32 S2; ADR-0062's amendment
// of 2026-11-25, point 3; board ux-design-2026-11-25-sprint32/02 ①, ③),
// driven by test/browser/dashboard_row_test.exs, which boots the endpoint,
// stores a dashboard with an S on the first rows, „Verkaufsrückblick“ as
// „Zeile“ under it and an S under that, and passes its base URL and the
// dashboard's id.
//
// At 1200 px (the wide grid) and at 393 px (a phone held upright, the
// compact forms), in the page's own Inter and in DejaVu Sans (fonts.js),
// the walk measures that the „Zeile“ widget is as tall as its content —
// nothing cut inside it (its scroll height is its client height) and no
// blank band in it (its height is its visible parts' heights, the gaps
// between them, its padding and its border, within a pixel) — and that the
// widget after it starts below it. At 1200 px it also checks the S above
// it keeps its fixed tile (two 7rem rows and the gap between them).
//
// Mode "attack" checks the check: at 1200 px the grid's row template set
// to fixed rows only (the „Zeile“ then cut to one 7rem row), and at 393 px
// the widget drawn 400 px tall (a blank band); each must be named.
//
// Prints one JSON object on stdout: {"ok": true, ...} or {"ok": false,
// "error": "..."}; the exit status is 0 either way unless the browser
// itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");
const { eachFont } = require("./fonts");

const { base_url: base, id, mode } = JSON.parse(process.argv[2]);
const ROW = "[data-widget-kind='sale_review']";
const BEFORE = "[data-widget-kind='due']";
const AFTER = "[data-widget-kind='data_quality']";
const WIDTHS = [
  { width: 1200, height: 900 },
  { width: 393, height: 852 }
];

// The „Zeile“ widget against its content, and its neighbours' boxes.
async function measure(page) {
  return page.evaluate(([row, before, after]) => {
    const node = document.querySelector(row);
    if (!node) return { missing: true };
    const box = node.getBoundingClientRect();
    const style = getComputedStyle(node);
    const parts = Array.from(node.children).filter((child) => {
      const s = getComputedStyle(child);
      return s.display !== "none" && s.visibility !== "hidden" && child.getClientRects().length > 0;
    });
    // Its parts stacked with the frame's gap, and its padding and border:
    // the height it needs, whatever pushes its footer to its foot.
    const stacked = parts.reduce((sum, child) => sum + child.getBoundingClientRect().height, 0);
    const gaps = Math.max(parts.length - 1, 0) * (parseFloat(style.rowGap) || 0);
    const frame = ["paddingTop", "paddingBottom", "borderTopWidth", "borderBottomWidth"]
      .reduce((sum, key) => sum + parseFloat(style[key]), 0);
    const expected = box.top + stacked + gaps + frame;
    const rect = (sel) => {
      const n = document.querySelector(sel);
      return n && n.getBoundingClientRect().toJSON();
    };
    return {
      missing: false,
      height: box.height,
      bottom: box.bottom,
      blank: box.bottom - expected,
      cut: node.scrollHeight - node.clientHeight,
      wideCut: Array.from(node.querySelectorAll(".widget__wide, .widget__compact"))
        .filter((part) => getComputedStyle(part).display !== "none")
        .map((part) => part.scrollHeight - part.clientHeight),
      before: rect(before),
      after: rect(after),
      rowHeight: parseFloat(getComputedStyle(document.documentElement).fontSize) * 7,
      gap: parseFloat(getComputedStyle(document.querySelector("#dashboard-grid")).rowGap) || 0
    };
  }, [ROW, BEFORE, AFTER]);
}

function check(tag, viewport, m, errors) {
  if (m.missing) return errors.push(tag + ": the „Zeile“ widget is missing");
  if (m.cut > 1) errors.push(tag + ": the „Zeile“ widget cuts " + m.cut + " px of its content");
  for (const cut of m.wideCut) if (cut > 1) errors.push(tag + ": the „Zeile“ widget's body cuts " + cut + " px");
  if (Math.abs(m.blank) > 1) {
    errors.push(tag + ": the „Zeile“ widget is " + m.blank.toFixed(1) + " px taller than its content");
  }
  if (!m.after) errors.push(tag + ": the widget after the „Zeile“ is missing");
  else if (m.after.top < m.bottom - 1) errors.push(tag + ": the widget after the „Zeile“ starts above its bottom");
  if (viewport.width >= 1000 && m.before) {
    const tile = 2 * m.rowHeight + m.gap;
    if (Math.abs(m.before.height - tile) > 1) {
      errors.push(tag + ": the S above the „Zeile“ is " + m.before.height + " px, not its tile of " + tile);
    }
  }
}

async function walk(browser, viewport, errors, attack) {
  const tag = viewport.width + " px";
  const context = await browser.newContext({ viewport, locale: "de-DE" });
  const page = await context.newPage();
  await visit(page, base + "/dashboards/" + id);
  await settle(page);

  if (attack) {
    await page.evaluate(([row, wide]) => {
      if (wide) document.querySelector("#dashboard-grid").style.setProperty("--dashboard-rows", "7rem 7rem 7rem 7rem 7rem");
      else document.querySelector(row).style.height = "400px";
    }, [ROW, viewport.width >= 1000]);
  }

  const measured = await eachFont(page, async (font) => {
    const m = await measure(page);
    check(tag + " " + font.name, viewport, m, errors);
    return m;
  });

  await leave(context);
  return measured[0];
}

(async () => {
  const browser = await launchChromium();
  const errors = [];
  const measured = {};
  try {
    for (const viewport of WIDTHS) {
      const caught = [];
      const m = await walk(browser, viewport, mode === "attack" ? caught : errors, mode === "attack");
      measured[viewport.width] = mode === "attack" ? { caught } : { height: m.height };
    }
    process.stdout.write(
      JSON.stringify(errors.length === 0 ? { ok: true, measured } : { ok: false, error: errors.join("; ") }) + "\n"
    );
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message), before: errors }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
