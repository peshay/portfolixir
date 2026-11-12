// Holdings' benchmark picker at 1200 and 390 px (Sprint 29, the closing act
// of #1416; board ux-design-2026-11-12-sprint29/02 ① and ⑥), driven in a
// real Chromium by test/browser/benchmark_picker_layout_test.exs, which
// boots the endpoint and passes the page's URL as one JSON argument. It
// opens „Benchmark…“ and measures the labelled groups: at 1200 px each
// label in one column, beside its options; at 390 px each label above its
// options, and a larger gap before every label after the first than
// between a label and its own options, so a label starts its group instead
// of reading as the last line of the group before it.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "...", "seen": {...}}; the exit status is 0 either way unless the browser
// itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { visit, leave } = require("./settle");

const args = JSON.parse(process.argv[2]);

async function measure(page) {
  return page.evaluate(() => {
    const round = (value) => Math.round(value * 10) / 10;
    const box = (node) => {
      if (!node) return null;
      const b = node.getBoundingClientRect();
      return { top: round(b.top), bottom: round(b.bottom), left: round(b.left), right: round(b.right) };
    };
    const groups = document.querySelector("[data-role=benchmark-groups]");
    if (!groups) return null;
    const labels = Array.from(groups.querySelectorAll(".bm-groups__label"));
    return {
      viewport: window.innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      groups: labels.map((label) => ({
        label: box(label),
        options: box(groups.querySelector(`[aria-labelledby="${label.id}"]`))
      }))
    };
  });
}

function check(seen, width) {
  const errors = [];
  if (!seen) return [width + " px: no labelled groups"];
  if (seen.scrollWidth > seen.viewport) errors.push(width + " px: the page scrolls sideways: " + seen.scrollWidth);
  if (seen.groups.length < 2) return errors.concat([width + " px: fewer than two groups, so the case is not measured"]);

  const lefts = seen.groups.map((g) => g.label.left);
  if (Math.max(...lefts) - Math.min(...lefts) > 1) errors.push(width + " px: the labels start on " + lefts.join(", "));

  for (const [index, g] of seen.groups.entries()) {
    if (width >= 1000) {
      if (g.options.left < g.label.right) errors.push("1200 px: group " + (index + 1) + "'s options are not beside its label");
      if (g.label.top < g.options.top - 4 || g.label.top > g.options.bottom)
        errors.push("1200 px: group " + (index + 1) + "'s label is not on its options' first line");
    } else {
      const within = g.options.top - g.label.bottom;
      if (within < 0) errors.push(width + " px: group " + (index + 1) + "'s options are not under its label");
      if (index > 0) {
        const before = g.label.top - seen.groups[index - 1].options.bottom;
        if (before < 12 || before < within + 6)
          errors.push(
            width + " px: the gap before group " + (index + 1) + "'s label is " + before +
              " px against " + within + " px to its own options"
          );
      }
    }
  }
  return errors;
}

async function run(browser) {
  const errors = [];
  const seenAll = {};
  for (const width of [1200, 390]) {
    const phone = width < 600;
    const context = await browser.newContext({
      viewport: { width, height: phone ? 844 : 900 },
      hasTouch: phone,
      isMobile: phone,
      locale: "de-DE"
    });
    const page = await context.newPage();
    await visit(page, args.url);
    await page.waitForSelector("[data-phx-main].phx-connected");
    await page.evaluate(() => {
      const picker = document.querySelector("[data-role=benchmark-picker]");
      if (picker) picker.open = true;
    });
    await page.waitForSelector("[data-role=benchmark-groups]", { state: "visible" });
    const seen = await measure(page);
    seenAll[width] = seen;
    errors.push(...check(seen, width));
    await leave(context);
  }
  return { errors, seen: seenAll };
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
