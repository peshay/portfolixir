// The fonts a layout walk measures every bar in (issue 1435, PR 2's closing
// act). The app ships no web font: `--font-sans` in app.css names Inter
// first, and a device without Inter draws the app in its own sans. The
// folds and floors Lane L chose were measured in Inter alone, on a machine
// that has it, and CI's runner, which had no Inter, drew the app in DejaVu
// Sans, where the Crashes bar's line and the stacked chart's label column
// no longer fit: the rule broke for every operator without Inter, and the
// walk could not see it. So every walk that measures a bar measures it
// twice, once in each font below, and fails unless both are installed (CI's
// browser job installs Inter for it; DejaVu Sans comes with the runner).
//
// - `FONTS`: the page's own font (`stack: null`, Inter, the first family of
//   the page's `--font-sans`), then DejaVu Sans, Linux's default sans and
//   the widest of the common ones, which stands in for every fallback.
// - `useFont(page, font, scope)` draws the page in `font`: the page's own,
//   or `--font-sans` forced to the font's stack. A measure forces layout, so
//   nothing is waited for. On a page's first call it checks the fonts and
//   throws, naming what is wrong, unless the page's own font is the first
//   of `FONTS` and every font is installed.
// - `eachFont(page, measure, scope)` runs `measure(font)` in each font and
//   leaves the page in its own; answers the results in `FONTS`' order.
//   `scope` (selectors) draws only those elements' parents in the font
//   (`useFont`), the sweep's way to stay fast.
// - `fontsHere(page, names)` answers {missing, own}: which of `names` are
//   not installed, and the first family of the page's `--font-sans` (the
//   attack case checks the check with a family no machine has).
"use strict";

const FONTS = [
  { name: "Inter", stack: null },
  { name: "DejaVu Sans", stack: '"DejaVu Sans"' }
];

const STYLE_ID = "walk-font";
const checked = new WeakSet();

// Which of `names` are not installed (a family that is not draws a test
// string exactly as the generic family after it does, in both generics),
// and the first family the page's `--font-sans` names.
function fontsHere(page, names = FONTS.map((font) => font.name)) {
  return page.evaluate((names) => {
    const context = document.createElement("canvas").getContext("2d");
    const width = (family) => {
      context.font = "16px " + family;
      return context.measureText("Klassifizierung · Wertpapiere 0123456789 mmWWll").width;
    };
    const missing = names.filter((name) =>
      ["monospace", "serif"].every((generic) => width(JSON.stringify(name) + ", " + generic) === width(generic))
    );
    const own = getComputedStyle(document.documentElement)
      .getPropertyValue("--font-sans")
      .split(",")[0]
      .trim()
      .replace(/^["']|["']$/g, "");
    return { missing, own };
  }, names);
}

async function checkFonts(page) {
  const { missing, own } = await fontsHere(page);
  if (missing.length > 0) {
    throw new Error(
      "the walk measures every bar in " + FONTS.map((f) => f.name).join(" and ") + ", and " +
        missing.join(" and ") + " is not installed here (CI's browser job installs fonts-inter)"
    );
  }
  if (own !== FONTS[0].name) {
    throw new Error("the page's own font is " + JSON.stringify(own) + ", the walk measures it as " + FONTS[0].name);
  }
}

// `scope`, when given, names the elements to draw in `font` instead of the
// whole page: each one's parent, so the bar and what stands beside it (a
// heading in a flex row) take the font, and the page around them does not.
// Restyling the whole page in another font at every width of the sweep
// made the walk of every page 2.8 times as slow; a bar's parent is
// restyled in a fraction of that. A bar whose width depends on text
// further out than its parent is measured in its page's font there.
async function useFont(page, font, scope = null) {
  if (!checked.has(page)) {
    await checkFonts(page);
    checked.add(page);
  }
  await page.evaluate(
    ({ id, stack, scope }) => {
      document.querySelectorAll("[data-walk-font]").forEach((e) => e.removeAttribute("data-walk-font"));
      let style = document.getElementById(id);
      if (stack === null) {
        if (style) style.remove();
        return;
      }
      if (!style) {
        style = document.createElement("style");
        style.id = id;
        document.head.appendChild(style);
      }
      if (scope === null) {
        style.textContent = ":root, :root[data-theme] { --font-sans: " + stack + " !important; }";
        return;
      }
      // A parent drawn in the page's sans takes the font itself, so what
      // inherits from it follows; one in another family (the mono) keeps it.
      const sans = getComputedStyle(document.body).fontFamily;
      for (const selector of scope) {
        const bar = document.querySelector(selector);
        if (!bar) continue;
        const target = bar.parentElement || bar;
        target.setAttribute("data-walk-font", getComputedStyle(target).fontFamily === sans ? "sans" : "other");
      }
      style.textContent =
        "[data-walk-font] { --font-sans: " + stack + " !important; } " +
        "[data-walk-font='sans'] { font-family: var(--font-sans) !important; }";
    },
    { id: STYLE_ID, stack: font.stack, scope }
  );
}

async function eachFont(page, measure, scope = null) {
  const results = [];
  try {
    for (const font of FONTS) {
      await useFont(page, font, scope);
      results.push(await measure(font));
    }
  } finally {
    await useFont(page, FONTS[0]);
  }
  return results;
}

module.exports = { FONTS, useFont, eachFont, fontsHere };
