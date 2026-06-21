# Demo data

`portfolio_performance_demo.json` is a **synthetic** Portfolio Performance
JSON v1 export used to seed a demo instance for screenshots and documentation.
It contains no personal data — only well-known public companies/ETFs with full
legal names (so asset-class inference and logo lookup behave realistically) and
round, made-up amounts.

Contents: one cash account ("Demo Cash"), one depot ("Demo Depot"), and ~12
transactions (deposit, purchases, dividends, a sale, interest) across 7
securities (equities, two ETFs, Bitcoin).

## Seeding a demo instance

Use a throwaway database/port so your real dev data is untouched (dev config
honors `DATABASE_NAME` and `PORT`):

```bash
DATABASE_NAME=portfolixir_demo PORT=4003 mix ecto.create
DATABASE_NAME=portfolixir_demo PORT=4003 mix ecto.migrate
```

Then import the file through the Imports view (drag & drop, map everything as
"create new", apply), or via the JSON API / a small `mix run` script that calls
`Portfolixir.Imports.parse_portfolio_performance/2` and `Imports.apply/2`.

The screenshots under `docs/screenshots/` were produced from this dataset.
