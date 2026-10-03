// Regenerates docs/screenshots/*.png from a review instance seeded with the
// synthetic demo dataset (#1034). Never point it at a live instance: it
// screenshots whatever the instance shows, and the screenshots are committed
// to a public repository (AGENTS.md -> Privacy And Disclosure).
//
// Recipe (priv/demo/README.md -> "Regenerating the screenshots"):
//
//   1. Seed a throwaway database with finding_surfaces_seed.exs and start the
//      server on it, offline and with a throwaway UI password:
//
//        DATABASE_NAME=portfolixir_review PORT=4003 PORTFOLIXIR_BACKGROUND_FETCH=off \
//          PORTFOLIXIR_UI_PASSWORD=demo-only-password mix phx.server
//
//   2. Run this script with Node 22 or newer and Playwright's Chromium:
//
//        PORT=4003 PORTFOLIXIR_UI_PASSWORD=demo-only-password \
//          node priv/demo/screenshots.mjs
//
//      `PLAYWRIGHT_MODULE` names the Playwright entry point when the package
//      is not resolvable from this directory, for example a global install:
//      PLAYWRIGHT_MODULE=/usr/lib/node_modules/playwright/index.mjs.
//      `SCREENSHOTS_DIR` overrides the output directory (default
//      docs/screenshots). With no `PORTFOLIXIR_UI_PASSWORD` the instance is
//      expected to run without a UI password.
//
// It only ever talks to http://127.0.0.1:$PORT: every request to another host
// or port, a logo provider included, is aborted in the browser, so a capture
// sends nothing out and does not vary with any provider.
//
// Conventions, so the set stays one set: 1440 px wide at device scale 1, the
// light theme with the default violet accent, German UI (the locale every
// earlier screenshot used). A page shot is the browser window: 1440 x 900, or
// the page's whole height where the docs describe the page top to bottom; a
// dialog or a tab is the 1440 x 900 window with it open. A section of a
// longer page (the contribution table, the merge list) is cropped to that
// section in the main column, sidebar and top bar left out. Dialogs are
// opened and photographed, never confirmed: the script changes nothing on
// the instance.

import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const port = process.env.PORT ?? "4003";
if (!/^\d{2,5}$/.test(port)) {
  throw new Error(`PORT must be a port number, got ${JSON.stringify(port)}`);
}

const BASE = `http://127.0.0.1:${port}`;
const OUT =
  process.env.SCREENSHOTS_DIR ?? fileURLToPath(new URL("../../docs/screenshots/", import.meta.url));
const PASSWORD = process.env.PORTFOLIXIR_UI_PASSWORD ?? "";
const WIDTH = 1440;
const HEIGHT = 900;

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? "playwright");

// Only the instance under 127.0.0.1:$PORT is reachable; data: URLs are inline.
function allowed(raw) {
  const url = new URL(raw);
  if (url.protocol === "data:" || url.protocol === "blob:") return true;
  return url.hostname === "127.0.0.1" && url.port === port;
}

async function settle(page) {
  await page.waitForSelector("[data-phx-main].phx-connected", { timeout: 15_000 });
  await page.waitForLoadState("networkidle");
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(400);
}

async function visit(page, address) {
  await page.setViewportSize({ width: WIDTH, height: HEIGHT });
  await page.goto(BASE + address);
  await settle(page);
}

async function save(page, file) {
  await page.mouse.move(0, 0);
  await page.waitForTimeout(200);
  const target = path.join(OUT, file);
  await page.screenshot({ path: target, animations: "disabled", caret: "hide" });
  const { width, height } = page.viewportSize();
  console.log(`${target}  ${width}x${height}`);
}

// The window at 1440 x 900, as it opens.
async function windowShot(page, file) {
  await page.setViewportSize({ width: WIDTH, height: HEIGHT });
  await page.evaluate(() => window.scrollTo(0, 0));
  await save(page, file);
}

// The window as tall as the page, so the fixed sidebar runs its full height
// (a full-page screenshot of a 900 px window cuts it off at 900 px). `until`
// stops the window above that element instead.
async function pageShot(page, file, { until } = {}) {
  await page.evaluate(() => window.scrollTo(0, 0));
  const height = await page.evaluate((selector) => {
    if (selector) {
      const element = document.querySelector(selector);
      if (!element) throw new Error(`no ${selector} on ${location.pathname}`);
      return Math.ceil(element.getBoundingClientRect().top + window.scrollY - 8);
    }
    return document.documentElement.scrollHeight;
  }, until ?? null);
  await page.setViewportSize({ width: WIDTH, height: Math.max(height, HEIGHT) });
  await page.waitForTimeout(300);
  await save(page, file);
}

// One section of a longer page, cropped to the main column: from 24 px above
// `from` to 24 px below `to` (default: the same element), at the page's own
// side margins. The window is as tall as the page, so nothing is scrolled and
// no sticky header or translucent top bar overlaps the section.
async function sectionShot(page, file, { from, to = from }) {
  await page.evaluate(() => window.scrollTo(0, 0));
  const pageHeight = await page.evaluate(() => document.documentElement.scrollHeight);
  await page.setViewportSize({ width: WIDTH, height: pageHeight });
  await page.waitForTimeout(300);

  const clip = await page.evaluate(
    ({ start, end }) => {
      const first = document.querySelector(start);
      const last = document.querySelector(end);
      if (!first || !last) throw new Error(`no ${start} or ${end} on ${location.pathname}`);
      const sidebar = document.querySelector(".app-sidebar");
      const left = sidebar ? Math.ceil(sidebar.getBoundingClientRect().right) : 0;
      const top = Math.max(0, Math.floor(first.getBoundingClientRect().top) - 24);
      const bottom = Math.ceil(last.getBoundingClientRect().bottom) + 24;
      return {
        x: left,
        y: top,
        width: document.documentElement.clientWidth - left,
        height: bottom - top,
      };
    },
    { start: from, end: to },
  );

  await page.mouse.move(0, 0);
  await page.waitForTimeout(200);
  const target = path.join(OUT, file);
  await page.screenshot({ path: target, clip, animations: "disabled", caret: "hide" });
  console.log(`${target}  ${clip.width}x${clip.height}`);
}

// The security detail page of the security named `name`, on `tab`.
async function securityTab(page, name, tab) {
  await visit(page, `/securities?q=${encodeURIComponent(name)}`);
  const link = page.locator('a[href^="/securities/"]', { hasText: name }).first();
  const href = await link.getAttribute("href");
  const id = href.match(/^\/securities\/(\d+)/)[1];
  await visit(page, `/securities/${id}?tab=${tab}`);
}

async function login(page) {
  await page.goto(`${BASE}/login`);
  const field = page.locator('input[name="session[password]"]');
  if ((await field.count()) === 0) return;
  if (PASSWORD === "") {
    throw new Error("the instance asks for a UI password: set PORTFOLIXIR_UI_PASSWORD");
  }
  await field.fill(PASSWORD);
  await Promise.all([
    page.waitForURL((url) => url.pathname !== "/login"),
    page.locator('form.login-form button[type="submit"]').click(),
  ]);
}

await mkdir(OUT, { recursive: true });

const browser = await chromium.launch();

try {
  const context = await browser.newContext({
    viewport: { width: WIDTH, height: HEIGHT },
    deviceScaleFactor: 1,
    locale: "de-DE",
    colorScheme: "light",
    reducedMotion: "reduce",
  });

  await context.route("**/*", (route) =>
    allowed(route.request().url()) ? route.continue() : route.abort(),
  );

  await context.addInitScript(() => {
    try {
      window.localStorage.setItem("portfolixir-theme", "light");
      window.localStorage.setItem("portfolixir-accent", "violet");
    } catch (_) {
      // A blocked storage leaves the system theme, which colorScheme makes light.
    }
  });

  const page = await context.newPage();
  await login(page);

  // Overview: the value card, the key figures, the closed trades card, the
  // off-target list, the due dates and the data-quality line.
  await visit(page, "/");
  await pageShot(page, "dashboard.png");

  // Wealth -> Holdings, down to the performance chart; then the contribution
  // table under it (FR-41), once its asynchronous computation has landed.
  await visit(page, "/portfolio");
  await page.waitForSelector("#contribution-table", { timeout: 30_000 });
  await pageShot(page, "portfolio.png", { until: "#performance-contribution" });
  await sectionShot(page, "contribution.png", { from: "#performance-contribution" });

  // Cash flow -> Trades.
  await visit(page, "/cashflow?tab=realized");
  await pageShot(page, "income.png");

  await visit(page, "/securities");
  await windowShot(page, "securities.png");

  // A security's own Trades tab: a closed trade held over a year.
  await securityTab(page, "Wrenfield Gardens AG", "trades");
  await windowShot(page, "trades-tab.png");

  // The Quotes tab's release dialog for manual quotes, opened, not confirmed.
  await securityTab(page, "Sable Point Energy ASA", "quotes");
  await page.locator('[data-role="release-manual-quotes"]').click();
  await page.waitForSelector("#quote-release-dialog", { state: "visible" });
  await settle(page);
  await windowShot(page, "quote-release.png");

  await visit(page, "/transactions");
  await windowShot(page, "transactions.png");

  // The booking delete dialog from a row's menu, opened, not confirmed.
  const row = page.locator("tr", { hasText: "Kestrel Industrial Group NV" }).first();
  await row.locator('[id^="tx-kebab-"]').click();
  await page.locator('[id^="tx-delete-"]').first().click();
  await page.waitForSelector('[role="dialog"], dialog[open]', { state: "visible" });
  await settle(page);
  await windowShot(page, "booking-delete.png");

  // Accounts & depots -> Merges, opened, with the security merge's result.
  await visit(page, "/portfolios");
  await page.locator('[data-role="merge-records-summary"]').click();
  const securityMerge = page
    .locator('[data-role="merge-records-table"] tr', { hasText: "Wertpapier" })
    .first();
  await securityMerge.locator(".merge-manifest > summary").click();
  await page.waitForTimeout(300);
  await sectionShot(page, "merges.png", {
    from: "#merge-records-title",
    to: "#merge-records-disclosure",
  });

  await visit(page, "/imports");
  await windowShot(page, "imports.png");

  await visit(page, "/buckets");
  await windowShot(page, "buckets.png");

  await visit(page, "/classifications");
  await windowShot(page, "classifications.png");

  await context.close();
} finally {
  await browser.close();
}
