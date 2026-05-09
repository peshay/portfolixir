# First-Run Reference Data and Localization

## First-Run Reference Data

Fresh local and Docker development setups initialize MVP currency reference data after migrations.

The seeded reference currencies are:

- EUR
- USD
- GBP
- CHF
- SEK
- JPY
- DKK
- NOK

This setup is idempotent. Running `Portfolixir.Catalog.ensure_mvp_currencies!/0` or `mix run
priv/repo/seeds.exs` multiple times does not duplicate currencies.

Docker development startup runs migrations and then `mix run priv/repo/seeds.exs`, so a fresh local
Docker setup can create portfolios, securities and accounts without a manual currency setup step.

## Supported Languages

The UI supports English and German through Gettext.

Locale selection order:

1. `?locale=de` or `?locale=en`
2. `portfolixir_locale` cookie
3. Browser `Accept-Language`
4. English fallback

The app shell exposes a `DE` / `EN` toggle. Selecting a language stores the locale in a cookie.
Theme selection remains independent and continues to use local storage.

## German Portfolio Performance Terminology

The German UI uses terminology close to German Portfolio Performance:

| English | German |
| --- | --- |
| Securities | Wertpapiere |
| All Securities | Alle Wertpapiere |
| Watchlist | Watchlist |
| Master data | Stammdaten |
| Accounts | Konten |
| Securities accounts | Depots |
| Deposit accounts | Verrechnungskonten |
| Ledger | Buchungen |
| Transactions | Buchungen |
| Classifications | Klassifizierungen |
| Reports | Berichte |
| Holdings | Bestand |
| Performance | Performance |
| Imports | Import |
| Settings | Einstellungen |

Important page titles:

| Route | English | German |
| --- | --- | --- |
| `/securities` | All Securities | Alle Wertpapiere |
| `/accounts` | Accounts Overview | Kontenübersicht |
| `/transactions` | Transactions | Buchungen |
| `/taxonomies` | Classifications | Klassifizierungen |

Transaction type labels are localized in the UI while stored transaction type values remain the
existing English strings:

| Stored value | German label |
| --- | --- |
| `deposit` | Einzahlung |
| `withdrawal` | Auszahlung |
| `buy` | Kauf |
| `sell` | Verkauf |
| `dividend` | Dividende |

## Classification Presets

The classifications page includes an idempotent Portfolio Performance preset action.

German button:

- Portfolio-Performance-Vorlagen anlegen

English button:

- Create Portfolio Performance presets

The action creates missing taxonomy systems only:

- Strategien
- Regionen
- Branchen
- Wertpapierarten

The current taxonomy schema has a single `name` field, so the preset names are German to support the
primary Portfolio Performance comparison experience. The action intentionally creates empty
taxonomies only; users define their own categories.

## Intentionally Not Included

This first-run setup does not create:

- fake securities
- fake accounts
- fake portfolios
- fake transactions
- market-data providers
- market-data network calls
- API endpoints
- AI or MCP functionality
- prompt files
