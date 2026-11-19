// The app's own Inter (Sprint 30 F1, #1221; plan D-4, D-1 criterion 1),
// driven in a real Chromium by test/browser/shipped_font_test.exs, which
// boots the endpoint and passes its base URL as the only argument.
//
// - own: the Overview draws in the Inter it loaded from its own /fonts/,
//   the walks' font check (fonts.js) passes, and no request leaves the
//   app's origin.
// - blocked: with every request under /fonts/ refused, the page still
//   connects and draws its text in the fallback (the stack after Inter),
//   and the walks' font check refuses the page: a walk never measures the
//   fallback as if it were Inter.
// - attacks on the check itself: a page that declares Inter from
//   `local()`, a page that declares none, and a page whose face names a
//   file the app does not serve are each refused.
//
// Prints one JSON object on stdout: {"ok": true, ...} with what each case
// found, or {"ok": false, "error": "..."}; the exit status is 0 either way
// unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { visit, draw, leave } = require("./settle");
const { FONT_FACES, ownFont, checkFonts } = require("./fonts");

const base = process.argv[2];
const SAMPLE = "Klassifizierung · Wertpapiere 0123456789 mmWWll Größe";

async function connected(page) {
  await page.waitForSelector("[data-phx-main].phx-connected", { timeout: 15000 });
  return true;
}

// The check's verdict: null when it passes, its message when it refuses.
async function verdict(page) {
  try {
    await checkFonts(page);
    return null;
  } catch (error) {
    return String(error.message);
  }
}

// The sample's width in the page's `--font-sans` and in the stack after
// its first family, each drawn in a span of the page.
function widths(page) {
  return page.evaluate((sample) => {
    const stack = getComputedStyle(document.documentElement).getPropertyValue("--font-sans").trim();
    const rest = stack.split(",").slice(1).join(",").trim();
    const width = (family) => {
      const span = document.createElement("span");
      span.style.cssText = "position: absolute; white-space: nowrap; font: 16px " + family + ";";
      span.textContent = sample;
      document.body.appendChild(span);
      const w = span.getBoundingClientRect().width;
      span.remove();
      return Math.round(w * 100) / 100;
    };
    return { own: width("var(--font-sans)"), rest: width(rest), restStack: rest };
  }, SAMPLE);
}

async function ownCase(browser) {
  const context = await browser.newContext({ viewport: { width: 1200, height: 900 } });
  const page = await context.newPage();
  const foreign = [];
  page.on("request", (request) => {
    const url = request.url();
    if (!url.startsWith(base + "/") && !url.startsWith("data:")) foreign.push(url);
  });
  await visit(page, base + "/");
  await connected(page);
  const font = await ownFont(page);
  const result = { check: await verdict(page), font, widths: await widths(page), foreign };
  await leave(context);
  return result;
}

async function blockedCase(browser) {
  const context = await browser.newContext({ viewport: { width: 1200, height: 900 } });
  const blocked = [];
  await context.route("**/fonts/**", (route) => {
    blocked.push(new URL(route.request().url()).pathname);
    return route.abort();
  });
  const page = await context.newPage();
  await visit(page, base + "/");
  const result = { connected: await connected(page) };
  result.font = await ownFont(page);
  result.check = await verdict(page);
  result.widths = await widths(page);
  result.blocked = [...new Set(blocked)].sort();
  result.heading = await page.evaluate(() => {
    const h = document.querySelector("h1");
    return h ? h.getBoundingClientRect().width > 0 : false;
  });
  await leave(context);
  return result;
}

async function attackCases(browser) {
  const context = await browser.newContext({ viewport: { width: 1200, height: 900 } });
  const page = await context.newPage();
  const body = "<body><p style='font: 16px var(--font-sans)'>" + SAMPLE + "</p></body>";
  const root = ":root { --font-sans: Inter, sans-serif; }";
  const fixtures = {
    // The app's own faces, drawn by the walk: passes (the control).
    own: FONT_FACES + root,
    // Inter from the machine, not from the page.
    local: '@font-face { font-family: "Inter"; src: local("Inter"); }' + root,
    // No face at all: an installed Inter, if any, is not the page's own.
    none: root,
    // A face that names a file the app does not serve: it fails to load.
    missing: '@font-face { font-family: "Inter"; src: url("/fonts/inter-latin-nowhere.woff2") format("woff2"); }' + root
  };
  const result = {};
  for (const [name, css] of Object.entries(fixtures)) {
    await draw(page, "<!doctype html><html><head><style>" + css + "</style></head>" + body + "</html>", { origin: base });
    result[name] = await verdict(page);
  }
  await leave(context);
  return result;
}

(async () => {
  const browser = await launchChromium();
  try {
    const own = await ownCase(browser);
    const blocked = await blockedCase(browser);
    const attacks = await attackCases(browser);
    console.error(JSON.stringify({ own, blocked, attacks }, null, 2));
    console.log(JSON.stringify({ ok: true, own, blocked, attacks }));
  } catch (error) {
    console.log(JSON.stringify({ ok: false, error: String((error && error.stack) || error) }));
  } finally {
    await leave(browser);
  }
})();
