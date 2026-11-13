// The range „Zyklus“, the dashboard card „‹Name›-Zyklus“ and „Halving-Kette“
// in a real browser (Sprint 29 H8; ADR-0060 §11, ADR-0059 §4, §8, §11;
// board ux-design-2026-11-12-sprint29/07 ①, ②, ⑤, ⑧; idea board
// ux-design-2026-11-10-idea-i12/01, A's shortcut), driven by
// test/browser/cycle_card_test.exs, which boots the endpoint and passes its
// base URL and the coin's id. For each theme at 1200 and 390 px it does
// what the operator does: opens the Übersicht, reads the coin's card,
// follows „Im Chart öffnen →“ to the chart with „Zyklen“ on and „Zyklus“
// chosen, then opens „Bearbeiten“, chooses no halving chain and reads the
// question, and cancels. After each step it checks that the page does not
// scroll sideways, that the card, the cycle bar with „Jetzt lesen“ and the
// dialog stay inside the viewport, that the axis reaches past today (both
// bands and the „heute“ line drawn) and that the save button names the
// count. CYCLE_CARD_SHOTS=<dir> also writes a screenshot of each step.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const path = require("path");
const { launchChromium } = require("./launch");
const { settle, visit, follow, leave } = require("./settle");

const base = process.argv[2];
const coinId = process.argv[3];
const PANEL = "#detail-tab-panel-chart";
const CARD = "[data-role='cycle-card'][data-security-id='" + coinId + "']";
const THEMES = ["light", "dark"];
const WIDTHS = [
  { width: 1200, height: 900 },
  { width: 390, height: 844 }
];
const shots = process.env.CYCLE_CARD_SHOTS || null;

async function shot(page, tag, step, fullPage = true) {
  if (shots) await page.screenshot({ path: path.join(shots, tag.replace(/ /g, "-") + "-" + step + ".png"), fullPage });
}

// Where an element sits, in CSS pixels, and how far the page scrolls sideways.
async function measure(page, selector) {
  return page.evaluate((sel) => {
    const node = document.querySelector(sel);
    const rect = node && node.getBoundingClientRect();
    return {
      overflow: document.documentElement.scrollWidth - window.innerWidth,
      box: rect && { left: rect.left, right: rect.right, width: rect.width, height: rect.height },
      text: node ? node.textContent.replace(/\s+/g, " ").trim() : ""
    };
  }, selector);
}

function inside(tag, what, m, viewport, errors) {
  if (m.overflow > 1) errors.push(tag + ": the page scrolls sideways by " + m.overflow + " px");
  if (!m.box) errors.push(tag + ": " + what + " is missing");
  else if (m.box.left < -1 || m.box.right > viewport.width + 1) errors.push(tag + ": " + what + " leaves the viewport");
}

async function walk(browser, theme, viewport, errors) {
  const tag = theme + " " + viewport.width;
  const context = await browser.newContext({ viewport, locale: "de-DE" });
  await context.addInitScript((th) => {
    try {
      localStorage.setItem("portfolixir-theme", th);
    } catch (_) {}
  }, theme);
  const page = await context.newPage();

  await visit(page, base + "/");
  await settle(page);
  const card = await measure(page, CARD);
  inside(tag + " Übersicht", "the card", card, viewport, errors);
  if (!/-Zyklus/.test(card.text)) errors.push(tag + ": the card is not named „‹Name›-Zyklus“");
  if (!/Nächstes Tief/.test(card.text) || !/Nächstes Top/.test(card.text)) errors.push(tag + ": the card lacks an event");
  await shot(page, tag, "card");

  await follow(page, () => page.click(CARD + " a[data-role='cycle-card-open']"));
  await page.waitForURL(/cycles=1/);
  await settle(page);
  await page.waitForSelector(PANEL + " g.cycle-layer");
  const range = await measure(page, PANEL + " button[phx-value-range='CYCLE'].is-active");
  if (!range.box) errors.push(tag + ": „Zyklus“ is not chosen after the card's link");
  const bar = await measure(page, "[data-role='cycle-bar']");
  inside(tag + " Zyklus", "the cycle bar", bar, viewport, errors);
  inside(tag + " Zyklus", "„Jetzt lesen“", await measure(page, "[data-role='cycle-bar'] [data-role='chain-read']"), viewport, errors);
  const drawn = await page.evaluate((panel) => ({
    bands: document.querySelectorAll(panel + " rect.cycle-band").length,
    today: document.querySelectorAll(panel + " line.cycle-today").length
  }), PANEL);
  if (drawn.bands !== 2) errors.push(tag + ": expected both bands on „Zyklus“, saw " + drawn.bands);
  if (drawn.today !== 1) errors.push(tag + ": the „heute“ line is not drawn");
  await shot(page, tag, "range");

  await page.click("#detail-edit");
  await page.waitForSelector("#security-dialog-form select[name='security[halving_chain]']");
  await settle(page);
  inside(tag + " Bearbeiten", "„Halving-Kette“", await measure(page, "[data-role='halving-chain']"), viewport, errors);
  await page.selectOption("#security-dialog-form select[name='security[halving_chain]']", "");
  await page.waitForSelector("[data-role='halving-delete-warning']");
  await settle(page);
  inside(tag + " Frage", "the warning", await measure(page, "[data-role='halving-delete-warning']"), viewport, errors);
  const submit = await measure(page, "#security-dialog-form button[type='submit']");
  inside(tag + " Frage", "the save button", submit, viewport, errors);
  if (!/Speichern und 5 Ereignisse löschen/.test(submit.text)) errors.push(tag + ": the save button reads „" + submit.text + "“");
  if (shots) {
    await page.locator("[data-role='halving-delete-warning']").scrollIntoViewIfNeeded();
    await shot(page, tag, "question", false);
  }
  await page.click("#security-dialog-form button.button-ghost[phx-click='close']");
  await page.waitForSelector("#security-dialog-form", { state: "detached" });
  await settle(page);

  await leave(context);
}

(async () => {
  const browser = await launchChromium();
  const errors = [];
  try {
    for (const theme of THEMES) {
      for (const viewport of WIDTHS) {
        await walk(browser, theme, viewport, errors);
      }
    }
    process.stdout.write(JSON.stringify(errors.length === 0 ? { ok: true } : { ok: false, error: errors.join("; ") }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message), before: errors }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
