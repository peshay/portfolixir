# UX-review seed (provenance for the 2026-09-12 review shots): the synthetic
# priv/demo dataset plus deliberately
# finding-triggering rows (an unclassified security, a held position with a
# stale quote, a priceless position, a foreign-currency cash account with no
# FX rate, a snapshot, a tax statement, research-log entries, buckets and a
# view). Synthetic all the way down — no real data.
alias Portfolixir.{Actor, Buckets, Catalog, Imports, Knowledge, Ledger, Portfolios, Tax}
alias Portfolixir.Catalog.Quotes
alias Portfolixir.Portfolios.Snapshots

owner = Actor.owner_ui()
today = Date.utc_today()

portfolio =
  case Enum.find(Portfolios.list_portfolios(), &(&1.name == "Demo Depot")) do
    nil ->
      {:ok, p} =
        Portfolios.create_portfolio(owner, %{name: "Demo Depot", base_currency_code: "EUR"})

      p

    p ->
      p
  end

body = File.read!("priv/demo/portfolio_performance_demo.json")

{:ok, preview} =
  Imports.parse_portfolio_performance(body, filename: "portfolio_performance_demo.json")

{:ok, result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

IO.puts(
  "import: #{result.created_securities} securities, #{result.created_transactions} transactions"
)

# Offline quote history for every imported security.
Code.eval_file("priv/demo/quotes_seed.exs")
# Strategies tree + target weights (sums to 85 % at the top level on purpose —
# an unallocated remainder, one of the review's finding surfaces).
Code.eval_file("priv/demo/strategies_seed.exs")

depot = Enum.find(Portfolios.list_securities_accounts(), &(&1.name == "Demo Depot"))
cash = Enum.find(Portfolios.list_cash_accounts(), &(&1.name == "Demo Cash"))
unless depot && cash, do: raise("demo depot/cash not found")

# 1. A held position whose quote feed went stale five weeks ago.
{:ok, timber} =
  Catalog.create_security(owner, %{
    name: "Nordic Timber Holdings AB",
    ticker_symbol: "NTHB",
    isin: "SE0000000012",
    currency_code: "EUR",
    asset_class: "equity"
  })

{:ok, _} =
  Ledger.create_transaction(owner, %{
    portfolio_id: portfolio.id,
    securities_account_id: depot.id,
    security_id: timber.id,
    type: "buy",
    date: Date.add(today, -200),
    quantity: "30",
    price: "42.10",
    currency_code: "EUR"
  })

:rand.seed(:exsss, {7, 7, 7})

stale_rows =
  for back <- 60..5//-1 do
    %{
      date: Date.add(today, -back * 7),
      close: Float.to_string(Float.round(38.0 + :rand.uniform() * 8, 2)),
      source: "manual"
    }
  end

{:ok, _} = Quotes.upsert_many(timber.id, stale_rows)

# 2. A position delivered in with no quote at all and no asset class (fires
#    "no price", "unclassified" and "no logo").
{:ok, bond} =
  Catalog.create_security(owner, %{
    name: "Placeholder Anleihe 2031 3,25%",
    currency_code: "EUR"
  })

{:ok, _} =
  Ledger.create_transaction(owner, %{
    portfolio_id: portfolio.id,
    securities_account_id: depot.id,
    security_id: bond.id,
    type: "inbound_delivery",
    date: Date.add(today, -40),
    quantity: "5",
    currency_code: "EUR"
  })

# 3. A watch-list security (not held, unclassified).
{:ok, _watch} =
  Catalog.create_security(owner, %{
    name: "Helios Solar Systems SE",
    ticker_symbol: "HLSO",
    isin: "DE000HLSO0001",
    currency_code: "EUR"
  })

# 4. A USD cash account with a balance and no FX rate (fires "cash with no FX").
{:ok, usd} =
  Portfolios.create_cash_account(owner, %{
    portfolio_id: portfolio.id,
    name: "USD Settlement",
    currency_code: "USD"
  })

{:ok, _} = Ledger.set_cash_balance(owner, usd, %{date: Date.add(today, -3), amount: "1850.00"})

# 5. Recent bookings so the history has entries this year.
{:ok, _} =
  Ledger.create_transaction(owner, %{
    portfolio_id: portfolio.id,
    cash_account_id: cash.id,
    type: "deposit",
    date: Date.add(today, -12),
    gross_amount: "1500.00",
    currency_code: "EUR"
  })

apple = Enum.find(Catalog.list_securities(), &String.contains?(&1.name, "Apple"))

{:ok, _} =
  Ledger.create_transaction(owner, %{
    portfolio_id: portfolio.id,
    securities_account_id: depot.id,
    cash_account_id: cash.id,
    security_id: apple.id,
    type: "dividend",
    date: Date.add(today, -9),
    quantity: "50",
    gross_amount: "12.50",
    currency_code: "EUR"
  })

# 6. Buckets and a view.
{:ok, household} = Buckets.create_bucket(owner, %{name: "Household"})
{:ok, crypto_b} = Buckets.create_bucket(owner, %{name: "Crypto"})
:ok = Buckets.set_depot_default_buckets(owner, depot, [household.id])
:ok = Buckets.set_cash_account_buckets(owner, cash, [household.id])
btc = Enum.find(Catalog.list_securities(), &(&1.name == "Bitcoin"))
:ok = Buckets.set_position_override(owner, depot, btc, [crypto_b.id])
{:ok, view} = Buckets.create_view(owner, %{name: "Ohne Krypto", include_all: true})
:ok = Buckets.set_view_buckets(owner, view, [], [crypto_b.id])

# 7. A depot snapshot 90 days back.
{:ok, _snap} =
  Snapshots.create_snapshot(owner, %{name: "Vor Umschichtung", as_of: Date.add(today, -90)})

# 8. A tax profile and a recorded statement for the prior tax year.
{:ok, _} =
  Tax.create_profile(owner, %{
    holder: "Owner",
    valid_from: ~D[2024-01-01],
    church_tax_liable: false
  })

{:ok, _} =
  Tax.create_snapshot(
    owner,
    %{
      institution: "Example Bank",
      holder: "Owner",
      tax_year: today.year - 1,
      as_of: Date.new!(today.year - 1, 12, 31),
      taxable_income: Decimal.new("4200.00"),
      allowance_granted: Decimal.new("1000.00"),
      allowance_used: Decimal.new("640.00"),
      loss_pot_equities: Decimal.new("2500.00"),
      loss_pot_other: Decimal.new("300.00"),
      loss_carryforward_prior_years: Decimal.new("0"),
      withholding_tax_pot: Decimal.new("45.00"),
      withholding_tax_credited: Decimal.new("12.00"),
      capital_gains_tax_withheld: Decimal.new("800.00"),
      solidarity_surcharge_withheld: Decimal.new("44.00"),
      church_tax_withheld: Decimal.new("0")
    },
    today: today
  )

# 9. Research log on Apple: thesis, evidence, a risk and the retraction that
#    supersedes it (a retraction must name the entry it withdraws).
notes = [
  {"thesis",
   "Services mix keeps margins above 40% through the cycle; hold while capex stays flat.",
   Date.add(today, -120), "primary", nil},
  {"evidence", "Q2 filing: services revenue +14% y/y, hardware flat.", Date.add(today, -60),
   "primary", nil},
  {"risk", "Regulatory case on the app store fee could compress services margin.",
   Date.add(today, -30), "secondary_multi", :risk},
  {"retraction",
   "The margin-compression forecast is withdrawn: the ruling did not touch fee levels.",
   Date.add(today, -4), "primary", :supersedes_risk}
]

Enum.reduce(notes, nil, fn {kind, body, as_of, q, tag}, risk_id ->
  attrs = %{
    security_id: apple.id,
    author: "agent",
    kind: kind,
    body: body,
    source_quality: q,
    as_of: as_of
  }

  attrs = if tag == :supersedes_risk, do: Map.put(attrs, :supersedes_id, risk_id), else: attrs
  {:ok, note} = Knowledge.append_note(owner, attrs)
  if tag == :risk, do: note.id, else: risk_id
end)

IO.puts("review seed done")
