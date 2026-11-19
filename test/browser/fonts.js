// The fonts a layout walk measures every bar in (issue 1435, PR 2's closing
// act; Sprint 30 F1, #1221). `--font-sans` in app.css names Inter first,
// and since F1 the app ships it: the variable Inter, latin and latin-ext,
// as woff2 under /fonts/, declared by app.css's `@font-face` rules. Before
// F1 a device without Inter drew the app in its own sans: the folds and
// floors Lane L chose were measured in Inter alone, and CI's runner, which
// had no Inter, drew the app in DejaVu Sans, where the Crashes bar's line
// and the stacked chart's label column no longer fit. A font file that
// fails to load is still a real state (`font-display: swap` draws the
// fallback), so every walk that measures a bar measures it twice, once in
// the page's own Inter and once in DejaVu Sans, and fails unless the page
// loaded its own Inter and DejaVu Sans is installed (CI's browser job
// installs fonts-dejavu-core).
//
// - `FONTS`: the page's own font (`stack: null`, Inter, the first family of
//   the page's `--font-sans`), then DejaVu Sans, Linux's default sans and
//   the widest of the common ones, which stands in for every fallback.
// - `useFont(page, font, scope)` draws the page in `font`: the page's own,
//   or `--font-sans` forced to the font's stack. A measure forces layout, so
//   nothing is waited for. On a page's first call it checks the fonts and
//   throws, naming what is wrong, unless the page's own font is the first
//   of `FONTS`, the page loaded it from its own /fonts/ (`ownFont`), and
//   every other font is installed.
// - `eachFont(page, measure, scope)` runs `measure(font)` in each font and
//   leaves the page in its own; answers the results in `FONTS`' order.
//   `scope` (selectors) draws only those elements' parents in the font
//   (`useFont`), the sweep's way to stay fast.
// - `fontsHere(page, names)` answers {missing, own}: which of `names` are
//   not installed, and the first family of the page's `--font-sans` (the
//   attack case checks the check with a family no machine has).
// - `ownFont(page)` answers {loaded, faces, rules, fetched, error}: whether
//   the page drew its own Inter, loaded from a woff2 under its own origin's
//   /fonts/, and what it found; `error` names why not.
// - `FONT_FACES`: app.css's `@font-face` rules, for a page a walk draws
//   itself (`draw(page, html, {origin})`), so it loads the app's Inter.
"use strict";

const FONTS = [
  { name: "Inter", stack: null },
  { name: "DejaVu Sans", stack: '"DejaVu Sans"' }
];

const STYLE_ID = "walk-font";

// app.css's @font-face rules, as the app serves them.
const FONT_FACES = (
  require("fs")
    .readFileSync(require("path").join(__dirname, "..", "..", "priv", "static", "app.css"), "utf8")
    .match(/@font-face\s*\{[^}]*\}/g) || []
).join("\n");
const checked = new WeakSet();

// Which of `names` are not installed (a family that is not draws a test
// string exactly as the generic family after it does, in both generics),
// and the first family the page's `--font-sans` names. A family the page
// declares (`@font-face`, the app's Inter) counts once the page loaded it:
// each is asked for first, as a canvas does not ask for a face itself.
function fontsHere(page, names = FONTS.map((font) => font.name)) {
  return page.evaluate(async (names) => {
    for (const name of names) await document.fonts.load("16px " + JSON.stringify(name)).catch(() => []);
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

// Whether the page drew its own Inter: every `@font-face` rule for Inter
// on the page names only woff2 files under its own origin's /fonts/ (no
// `local()`, no other host); the page holds no other Inter face (one a
// script added); at least one Inter face loaded; and the page fetched a
// woff2 from its /fonts/. A face that loaded from elsewhere, a file that
// failed (`error`), or a page that declares none is not the page's own.
function ownFont(page) {
  return page.evaluate(async () => {
    const family = "Inter";
    const unquote = (s) => s.trim().replace(/^["']|["']$/g, "");
    const ours = (href) => {
      const url = new URL(href, document.baseURI);
      return url.origin === location.origin && /^\/fonts\/[^/]+\.woff2$/.test(url.pathname);
    };
    if (document.body) document.body.getBoundingClientRect();
    await document.fonts.load("16px " + family).catch(() => []);
    await document.fonts.ready;
    const rules = [];
    for (const sheet of document.styleSheets) {
      let list = [];
      try {
        list = sheet.cssRules;
      } catch (_) {
        continue;
      }
      for (const rule of list) {
        if (rule instanceof CSSFontFaceRule && unquote(rule.style.getPropertyValue("font-family")) === family) {
          rules.push(rule.style.getPropertyValue("src"));
        }
      }
    }
    const faces = [...document.fonts].filter((face) => unquote(face.family) === family).map((face) => face.status);
    const fetched = performance
      .getEntriesByType("resource")
      .filter((entry) => ours(entry.name) && (entry.responseStatus === undefined || entry.responseStatus === 200))
      .map((entry) => new URL(entry.name).pathname);
    const foreign = rules.filter((src) => {
      const urls = [...src.matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/g)].map((m) => m[1]);
      return /local\(/.test(src) || urls.length === 0 || !urls.every(ours);
    });
    let error = null;
    if (rules.length === 0) error = "the page declares no @font-face for " + family;
    else if (foreign.length > 0) error = "an @font-face for " + family + " loads from elsewhere than /fonts/: " + foreign.join(" | ");
    else if (faces.length !== rules.length) error = "the page holds " + family + " faces its stylesheets do not declare";
    else if (!faces.includes("loaded")) error = "no " + family + " face loaded (" + faces.join(", ") + ")";
    else if (fetched.length === 0) error = "the page fetched no woff2 from its /fonts/";
    return { loaded: error === null, faces, rules, fetched, error };
  });
}

async function checkFonts(page) {
  const own = await ownFont(page);
  const { missing, own: first } = await fontsHere(
    page,
    FONTS.filter((font) => font.stack !== null).map((font) => font.name)
  );
  if (first !== FONTS[0].name) {
    throw new Error("the page's own font is " + JSON.stringify(first) + ", the walk measures it as " + FONTS[0].name);
  }
  if (!own.loaded) {
    throw new Error(
      "the walk measures every bar in the page's own " + FONTS[0].name + ", and the page did not load it: " + own.error
    );
  }
  if (missing.length > 0) {
    throw new Error(
      "the walk measures every bar in the fallback " + missing.join(" and ") +
        " as well, and it is not installed here (CI's browser job installs fonts-dejavu-core)"
    );
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

module.exports = { FONTS, FONT_FACES, useFont, eachFont, fontsHere, ownFont, checkFonts };
