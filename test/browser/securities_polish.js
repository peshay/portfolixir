// The polish pass on "Securities and the security page" (#1365), driven in
// a real Chromium by test/browser/securities_polish_test.exs, which boots
// the endpoint, seeds the world and passes one JSON argument: the base URL
// and the ids of the booked security, its depot and a Buckets view.
//
// Checks, at 1200 px and at 390 px, that a dialog opened from a row menu
// gives the focus back to the row's kebab (#1340), and at 1200 px the
// thesis card's label break and the Termine entry's meta line. Every check
// runs and each failure is named, so one run shows every line's state.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false,
// "errors": [...]}; the exit status is 0 either way unless the browser
// itself fails.
"use strict";

const { launchChromium } = require("./launch");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;
const errors = [];

async function connected(page, url) {
  await page.goto(base + url);
  await page.waitForSelector("[data-phx-main].phx-connected");
}

// The first of the selectors whose element is on the page and visible: the
// table's kebab on the desktop, the card's on the phone.
async function visibleId(page, selectors) {
  return page.evaluate((list) => {
    for (const sel of list) {
      for (const el of document.querySelectorAll(sel)) {
        if (el.getClientRects().length > 0) return el.id;
      }
    }
    return null;
  }, selectors);
}

async function activeDescription(page) {
  return page.evaluate(() => {
    const a = document.activeElement;
    if (!a || a === document.body) return "<body>";
    return a.tagName.toLowerCase() + (a.id ? "#" + a.id : "") +
      (a.className ? "." + String(a.className).split(" ").join(".") : "");
  });
}

// Opens the dialog from the row menu, closes it the way `close` says, and
// expects the focus on the kebab that opened the menu.
async function dialogReturnsFocus(page, spec, close, width) {
  const label = spec.name + " (" + close + ", " + width + " px)";
  await connected(page, spec.url);
  const kebab = await visibleId(page, spec.kebabs);
  if (!kebab) {
    errors.push(label + ": no visible kebab among " + spec.kebabs.join(", "));
    return;
  }
  // The keyboard path: the kebab takes the focus and Enter opens the menu.
  await page.focus("#" + kebab);
  await page.keyboard.press("Enter");
  await page.waitForSelector(spec.item, { state: "visible" });
  await page.click(spec.item);
  try {
    await page.waitForSelector(spec.dialog + "[open]", { timeout: 5000 });
  } catch (_) {
    errors.push(label + ": the dialog " + spec.dialog + " did not open");
    return;
  }
  if (close === "Escape") {
    await page.keyboard.press("Escape");
  } else {
    await page.click(spec.dialog + " " + spec.closers[close]);
  }
  await page.waitForSelector(spec.dialog, { state: "detached" });
  try {
    // The hook returns the focus as the dialog leaves the page.
    await page.waitForFunction((id) => document.activeElement &&
      document.activeElement.id === id, kebab, { timeout: 2000, polling: "raf" });
  } catch (_) {
    errors.push(label + ": the focus is on " + (await activeDescription(page)) +
      ", not on #" + kebab);
  }
}

const SECURITY_ROW = {
  url: "/securities",
  kebabs: ["#row-kebab-" + args.security_id, "#phone-kebab-" + args.security_id]
};

const DIALOGS = [
  Object.assign({}, SECURITY_ROW, {
    name: "Securities: Cannot delete",
    item: "#row-menu-" + args.security_id + " [phx-value-action='delete']",
    dialog: "#delete-blocked-dialog",
    // "Retire instead" toggles the flag and keeps the row (a retired row
    // stays listed), so the kebab is still there to take the focus.
    closes: ["Escape", "x", "Cancel", "Retire"],
    closers: {
      x: ".modal-head .icon-button",
      Cancel: ".modal-footer .button-ghost",
      Retire: ".modal-footer .button-primary"
    }
  }),
  Object.assign({}, SECURITY_ROW, {
    name: "Securities: Manage logo",
    item: "#row-menu-" + args.security_id + " [phx-value-action='manage_logo']",
    dialog: "#logo-override-dialog",
    closes: ["Escape", "x"],
    closers: { x: ".modal-head .icon-button" }
  }),
  {
    name: "Accounts: Cannot delete",
    url: "/portfolios",
    kebabs: ["#account-kebab-" + args.depot_id],
    item: "#account-row-menu-" + args.depot_id + " [data-role='menu-delete']",
    dialog: "#delete-blocked-dialog",
    closes: ["Escape", "x", "Cancel"],
    closers: { x: ".modal-head .icon-button", Cancel: ".modal-footer .button-ghost" }
  },
  {
    name: "Buckets: Edit buckets",
    url: "/buckets",
    kebabs: ["#view-kebab-" + args.view_id],
    item: "#view-row-menu-" + args.view_id + " [phx-click='edit_view_buckets']",
    dialog: "#view-bucket-modal",
    closes: ["Escape", "x"],
    closers: { x: ".modal-head .icon-button" }
  }
];

// The thesis card at 1200 px: its longest label breaks at a syllable, which
// `hyphens: auto` asks of the browser under the page's language.
async function thesisLabel(page) {
  await connected(page, "/securities/" + args.security_id + "?tab=research");
  const found = await page.evaluate(() => {
    const dt = Array.from(document.querySelectorAll(".research-thesis__facts dt"))
      .find((el) => el.textContent.trim() === "Invalidierungsbedingung");
    if (!dt) return null;
    return { hyphens: getComputedStyle(dt).hyphens, lang: document.documentElement.lang };
  });
  if (!found) {
    errors.push("thesis card: no label „Invalidierungsbedingung“");
    return;
  }
  if (!/^de\b/.test(found.lang)) errors.push("thesis card: the page's lang is " + found.lang);
  if (found.hyphens !== "auto") {
    errors.push("thesis card: „Invalidierungsbedingung“ has hyphens: " + found.hyphens +
      ", so it breaks anywhere, not at a syllable");
  }
}

// A Termine entry's meta line: no paragraph margins, and its two facts
// separated as every meta line in the app separates them.
async function eventMeta(page) {
  await connected(page, "/securities/" + args.security_id + "?tab=events");
  const meta = await page.evaluate(() => {
    const p = document.querySelector("[data-role='event-entry'] .research-entry__meta");
    if (!p) return null;
    const style = getComputedStyle(p);
    return {
      top: style.marginTop,
      bottom: style.marginBottom,
      text: p.innerText.replace(/\s+/g, " ").trim()
    };
  });
  if (!meta) {
    errors.push("Termine: no meta line in the event entry");
    return;
  }
  if (meta.top !== "0px" || meta.bottom !== "0px") {
    errors.push("Termine: the meta line keeps margins " + meta.top + " / " + meta.bottom);
  }
  if (meta.text !== "Quelle · Zuletzt geprüft 04.11.2026") {
    errors.push("Termine: the meta line reads " + JSON.stringify(meta.text));
  }
}

async function run() {
  const browser = await launchChromium();
  try {
    for (const width of [1200, 390]) {
      const context = await browser.newContext({
        viewport: { width, height: 900 },
        locale: "de-DE"
      });
      const page = await context.newPage();
      // The row menu's Delete asks first (data-confirm): yes.
      page.on("dialog", (dialog) => dialog.accept());
      for (const spec of DIALOGS) {
        for (const close of spec.closes) {
          await dialogReturnsFocus(page, spec, close, width);
        }
      }
      if (width === 1200) {
        await thesisLabel(page);
        await eventMeta(page);
      }
      await context.close();
    }
  } finally {
    await browser.close();
  }
  console.log(JSON.stringify(errors.length ? { ok: false, errors } : { ok: true }));
}

run().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
