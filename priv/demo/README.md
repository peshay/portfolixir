# Demo data

`portfolio_performance_demo.json` is a **synthetic** Portfolio Performance
JSON v1 export used to seed a demo instance for screenshots and documentation.
It contains no personal data — only well-known public companies/ETFs with full
legal names (so asset-class inference reads them as it would real holdings, and
the screenshots look like a real instance) and round, made-up amounts.

Contents: one cash account ("Demo Cash"), one depot ("Demo Depot"), and ~12
transactions (deposit, purchases, dividends, a sale, interest) across 7
securities (equities, two ETFs, Bitcoin).

## Seeding a demo instance

Use a throwaway database/port so your real dev data is untouched (dev config
honors `DATABASE_NAME` and `PORT`, and `DATABASE_HOST` and `DATABASE_PORT` for
a PostgreSQL other than the one on `127.0.0.1:5432` — prefix every command of
a recipe with the same values):

```bash
DATABASE_NAME=portfolixir_demo PORT=4003 mix ecto.create
DATABASE_NAME=portfolixir_demo PORT=4003 mix ecto.migrate
```

Then import the file through the Imports view (drag & drop, map everything as
"create new", apply), or via the JSON API / a small `mix run` script that calls
`Portfolixir.Imports.parse_portfolio_performance/2` and `Imports.apply/2`.

### The seeds make no outbound calls

`mix run` boots the application, and the dev configuration starts logo
discovery and the quote and FX sync: on its own, a seed run would send a logo
lookup and a quote backfill for every demo security to the public providers.
Every seed command below therefore sets `PORTFOLIXIR_BACKGROUND_FETCH=off`,
which leaves all three off from boot, so a seed run makes **no outbound
calls** and the seeded data does not depend on any provider being reachable
(#963). `finding_surfaces_seed.exs` refuses to run without it. A server
started on the seeded database (`mix phx.server`) fetches as usual; give it the
same switch to keep a walkthrough instance offline too.

## Quote history (offline)

The demo export carries transactions only. To render charts and valuations
without any market-data sync, seed deterministic synthetic weekly closes
(seeded RNG, anchored at each security's last trade price):

```bash
DATABASE_NAME=portfolixir_demo PORT=4003 PORTFOLIXIR_BACKGROUND_FETCH=off mix run priv/demo/quotes_seed.exs
```

## Strategies + target weights (optional)

To reproduce the target-vs-actual rebalancing view shown in the README, seed a
small "Strategies" classification with target weights after importing:

```bash
DATABASE_NAME=portfolixir_demo PORT=4003 PORTFOLIXIR_BACKGROUND_FETCH=off mix run priv/demo/strategies_seed.exs
```

It builds a Stability / Growth / Crypto tree fitted to the demo securities,
assigns each holding to a category, and sets target weights plus a cash target,
so the portfolio allocation view (classification "Strategies") shows
per-category drift.

## Review walkthrough surfaces (agentic review, UAT)

The closing act of an epic batch walks the app on data that fires every alarm
surface. `finding_surfaces_seed.exs` builds exactly that instance: it imports
the demo dataset, seeds the quote history and the Strategies tree, and adds a
held position whose quote went stale, a delivered position with no price
("Placeholder Anleihe 2031 3,25%", stored as a bond since #1127 reads its
bond word; the held security with no asset class is "Ostsee Logistik 4,10%
2028/2033", below), a watch-list security with no classification, a USD cash
account with a balance and no exchange rate, recent bookings, buckets and a
view, a depot snapshot, a tax profile with a recorded statement, a
research log whose risk entry is superseded by a retraction, and a
security-event calendar on both a held and a watch-list security (all four
timing qualifiers, one unconfirmed past date, one nobody has re-read).

The Sprint 19 PR α stories added their surfaces (step 16 of the seed):

- **Foreign cash before its first rate (#1055):** "Tagesgeld CHF" receives
  2,000.00 CHF four weeks before CHF's first stored rate, so Wealth's
  contribution table (default period, one year) names it as counting zero on
  some days and says that its whole balance entered "Currency effect on cash"
  with the first rate.
- **Cross-currency fees and taxes (#1051):** "Larkspur Robotics Inc", priced
  in USD, bought through the EUR Demo Cash with fees and taxes in EUR; the
  contribution table shows them as the position's costs. The seed stores no
  USD rate, so this is the no-rate case; step 12's CHF buy is the converted
  one.
- **Category result across base currencies (#1048):** a second portfolio,
  "Dollar Depot", with base currency USD, holds Harborline Freight Inc and
  Larkspur, both filed in the Strategies tree; the classification screen's
  EUR result leaves both out and names them, Harborline with its native cost
  ("Einstand … USD") and Larkspur, held in a EUR and the USD portfolio, with
  its reason.
- **Bonds on two scales (#1068):** "Kestrel Anleihe 2030 2,75%" (quotes near
  100, booked near 1: the nominal booked as the quantity, 50 pieces at
  0.985, so the bond page shows a 5,000.00 EUR nominal and the value counts
  a hundredfold too high), "Birkenhain Wasser Anleihe 2029 1,50%" (the
  reverse) and "Ostsee Logistik 4,10% 2028/2033" (no asset class, a coupon
  and a maturity date, booked as Kestrel is), all held: Wealth names them,
  the unclassed one with its "ohne Anlageklasse" badge, and the Overview's
  data-quality line counts them.
- **What the total leaves out (#1081):** the USD cash with no rate and the
  delivered position with no price are named under the Overview's "Alles"
  card.
- **Gesamtpreis row error (#1076):** `pp_csv_gesamtpreis_demo.csv` is a small
  Portfolio Performance CSV whose sell row's Gesamtpreis contradicts Betrag −
  (Gebühren + Steuern). The seed does not import it: drop it into Imports by
  hand and the preview names the row as not imported. Discard the preview
  afterwards.

```bash
DATABASE_NAME=portfolixir_review PORT=4003 mix ecto.create
DATABASE_NAME=portfolixir_review PORT=4003 mix ecto.migrate
DATABASE_NAME=portfolixir_review PORT=4003 PORTFOLIXIR_BACKGROUND_FETCH=off mix run priv/demo/finding_surfaces_seed.exs
```

It is **idempotent**: every step asks whether its rows are already there, so a
second run adds nothing. The quote history is written with the import, on the
first run only: a second run leaves every quote as the first left it, so a
re-seeded database shows the figures a fresh one shows (#1126). It makes **no outbound calls** (see "The seeds make
no outbound calls" above) and refuses to run without the switch. Synthetic all
the way down — no real holdings, no real institution, no real person.

The screenshots and the tour GIF under `docs/screenshots/` were produced from
this dataset.

## Regenerating the screenshots

`screenshots.mjs` rewrites every PNG under `docs/screenshots/` from an
instance seeded as above — **never from a live instance**: the images are
committed to a public repository, and the script photographs whatever the
instance shows. It needs Node 22 or newer and Playwright with its Chromium.
The tour GIF (`tour.gif`) is not produced by the script.

Seed a throwaway database as in "Review walkthrough surfaces", then start the
server on it, offline and with a throwaway UI password:

```bash
DATABASE_NAME=portfolixir_review PORT=4003 PORTFOLIXIR_BACKGROUND_FETCH=off PORTFOLIXIR_UI_PASSWORD=demo-only-password mix phx.server
```

and, in a second shell from the repository root:

```bash
PORT=4003 PORTFOLIXIR_UI_PASSWORD=demo-only-password node priv/demo/screenshots.mjs
```

`PLAYWRIGHT_MODULE` names Playwright's entry point when the package is not
resolvable from the repository (a global install, for example
`PLAYWRIGHT_MODULE=/usr/lib/node_modules/playwright/index.mjs`), and
`SCREENSHOTS_DIR` writes somewhere other than `docs/screenshots/`.

The script talks to `http://127.0.0.1:$PORT` only — the browser aborts every
request to another host or port — and changes nothing on the instance: the
dialogs it photographs are opened, never confirmed. Every image is 1440 px
wide (the contribution table and the merge list are cropped to their section
of the page, 1220 px), in the light theme with the violet accent, and in
German, the locale the set has always used.
