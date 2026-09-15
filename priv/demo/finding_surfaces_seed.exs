# Seeds the review instance for a closing-act walkthrough: the synthetic
# priv/demo dataset plus deliberately finding-triggering rows — an
# unclassified security, a held position with a stale quote, a priceless
# position, a foreign-currency cash account with no FX rate, a snapshot, a tax
# statement, research-log entries, buckets and a view. Synthetic all the way
# down; no real data (AGENTS.md → Privacy And Disclosure).
#
# The #706 walkthrough conditions with a script (Sprint 12, D-4): it lives here
# rather than beside one review's mockups so every later walkthrough exercises
# it and it does not rot the way the Sprint 5 retrospective found the other two
# seeds rotting. `review-rubric.md` names it.
#
#   DATABASE_NAME=portfolixir_review PORT=4003 mix ecto.create
#   DATABASE_NAME=portfolixir_review PORT=4003 mix ecto.migrate
#   DATABASE_NAME=portfolixir_review PORT=4003 mix run priv/demo/finding_surfaces_seed.exs
#
# **Idempotent**: every step asks whether its row is already there and skips
# it, so a re-run on a seeded database adds nothing and raises nothing. Rerun
# it after a migration rather than dropping the database.
alias Portfolixir.{Actor, Buckets, Catalog, Imports, Knowledge, Ledger, Portfolios, Tax}
alias Portfolixir.Catalog.Quotes
alias Portfolixir.Portfolios.Snapshots

owner = Actor.owner_ui()
today = Date.utc_today()

find_security = fn name ->
  Enum.find(Catalog.list_securities(), &(&1.name == name))
end

# A security plus its opening booking, created only when the security is not
# already there — the booking would otherwise double on every re-run.
seed_position = fn name, attrs, booking ->
  case find_security.(name) do
    nil ->
      {:ok, security} = Catalog.create_security(owner, Map.put(attrs, :name, name))
      {:ok, _} = Ledger.create_transaction(owner, booking.(security))
      {:new, security}

    security ->
      {:existing, security}
  end
end

portfolio =
  case Enum.find(Portfolios.list_portfolios(), &(&1.name == "Demo Depot")) do
    nil ->
      {:ok, p} =
        Portfolios.create_portfolio(owner, %{name: "Demo Depot", base_currency_code: "EUR"})

      p

    p ->
      p
  end

# The import is the only step that cannot ask about a single row: it either ran
# or it did not, and the portfolio's own ledger says which.
if Ledger.list_transactions(portfolio_id: portfolio.id) == [] do
  body = File.read!("priv/demo/portfolio_performance_demo.json")

  {:ok, preview} =
    Imports.parse_portfolio_performance(body, filename: "portfolio_performance_demo.json")

  {:ok, result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

  IO.puts(
    "import: #{result.created_securities} securities, #{result.created_transactions} transactions"
  )
else
  IO.puts("import: already present, skipped")
end

# Offline quote history for every imported security; both of these seeds are
# idempotent in their own right (the quote upsert replaces, the Strategies tree
# is dropped and rebuilt).
Code.eval_file("priv/demo/quotes_seed.exs")
# Strategies tree + target weights (sums to 85 % at the top level on purpose —
# an unallocated remainder, one of the review's finding surfaces).
Code.eval_file("priv/demo/strategies_seed.exs")

depot = Enum.find(Portfolios.list_securities_accounts(), &(&1.name == "Demo Depot"))
cash = Enum.find(Portfolios.list_cash_accounts(), &(&1.name == "Demo Cash"))
unless depot && cash, do: raise("demo depot/cash not found")

# 1. A held position whose quote feed went stale five weeks ago.
{timber_state, timber} =
  seed_position.(
    "Nordic Timber Holdings AB",
    %{
      ticker_symbol: "NTHB",
      isin: "SE0000000012",
      currency_code: "EUR",
      asset_class: "equity"
    },
    fn security ->
      %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        security_id: security.id,
        type: "buy",
        date: Date.add(today, -200),
        quantity: "30",
        price: "42.10",
        currency_code: "EUR"
      }
    end
  )

# The closes are an upsert keyed by date, so writing them is safe to repeat.
# Dropping the newer ones is what makes the *surface* idempotent: the quote
# seed above prices every security up to today, this one included, which would
# silently un-stale the one row the stale finding exists to show. A demo seed
# owns its own data, so it clears them directly rather than growing a
# delete-quotes API the product does not otherwise need.
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

import Ecto.Query, only: [from: 2]

stale_cutoff = Date.add(today, -5 * 7)

{dropped, _} =
  Portfolixir.Repo.delete_all(
    from(q in Portfolixir.Catalog.Quote,
      where: q.security_id == ^timber.id and q.date > ^stale_cutoff
    )
  )

if dropped > 0 do
  Portfolixir.Derived.Invalidation.after_quote_write(timber.id)
  IO.puts("stale surface: dropped #{dropped} quote(s) newer than #{stale_cutoff}")
end

# 2. A position delivered in with no quote at all and no asset class (fires
#    "no price", "unclassified" and "no logo").
{_bond_state, _bond} =
  seed_position.(
    "Placeholder Anleihe 2031 3,25%",
    %{currency_code: "EUR"},
    fn security ->
      %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        security_id: security.id,
        type: "inbound_delivery",
        date: Date.add(today, -40),
        quantity: "5",
        currency_code: "EUR"
      }
    end
  )

# 3. A watch-list security (not held, unclassified).
unless find_security.("Helios Solar Systems SE") do
  {:ok, _watch} =
    Catalog.create_security(owner, %{
      name: "Helios Solar Systems SE",
      ticker_symbol: "HLSO",
      isin: "DE000HLSO0001",
      currency_code: "EUR"
    })
end

# 4. A USD cash account with a balance and no FX rate (fires "cash with no FX").
usd =
  case Enum.find(Portfolios.list_cash_accounts(), &(&1.name == "USD Settlement")) do
    nil ->
      {:ok, account} =
        Portfolios.create_cash_account(owner, %{
          portfolio_id: portfolio.id,
          name: "USD Settlement",
          currency_code: "USD"
        })

      account

    account ->
      account
  end

# A balance is a booked adjustment, not an upsert, so it is written only when
# the account has none — a second one would stack a duplicate on every re-run.
usd_booked? =
  Ledger.list_transactions(portfolio_id: portfolio.id)
  |> Enum.any?(&(&1.cash_account_id == usd.id))

unless usd_booked? do
  {:ok, _} = Ledger.set_cash_balance(owner, usd, %{date: Date.add(today, -3), amount: "1850.00"})
end

apple = Enum.find(Catalog.list_securities(), &String.contains?(&1.name, "Apple"))

# 5. Recent bookings so the history has entries this year. Both carry a note
#    that names them as the seed's, which is also how the re-run finds them.
seed_marker = "review seed"

recent_bookings =
  Ledger.list_transactions(portfolio_id: portfolio.id)
  |> Enum.filter(&(&1.notes == seed_marker))

if recent_bookings == [] do
  {:ok, _} =
    Ledger.create_transaction(owner, %{
      portfolio_id: portfolio.id,
      cash_account_id: cash.id,
      type: "deposit",
      date: Date.add(today, -12),
      gross_amount: "1500.00",
      currency_code: "EUR",
      notes: seed_marker
    })

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
      currency_code: "EUR",
      notes: seed_marker
    })
end

# 6. Buckets and a view.
bucket = fn name ->
  case Enum.find(Buckets.list_buckets(), &(&1.name == name)) do
    nil ->
      {:ok, b} = Buckets.create_bucket(owner, %{name: name})
      b

    b ->
      b
  end
end

household = bucket.("Household")
crypto_b = bucket.("Crypto")
:ok = Buckets.set_depot_default_buckets(owner, depot, [household.id])
:ok = Buckets.set_cash_account_buckets(owner, cash, [household.id])
btc = Enum.find(Catalog.list_securities(), &(&1.name == "Bitcoin"))
:ok = Buckets.set_position_override(owner, depot, btc, [crypto_b.id])

view =
  case Enum.find(Buckets.list_views(), &(&1.name == "Ohne Krypto")) do
    nil ->
      {:ok, v} = Buckets.create_view(owner, %{name: "Ohne Krypto", include_all: true})
      v

    v ->
      v
  end

:ok = Buckets.set_view_buckets(owner, view, [], [crypto_b.id])

# 7. A depot snapshot 90 days back.
unless Enum.find(Snapshots.list_snapshots(), &(&1.name == "Vor Umschichtung")) do
  {:ok, _snap} =
    Snapshots.create_snapshot(owner, %{name: "Vor Umschichtung", as_of: Date.add(today, -90)})
end

# 8. A tax profile and a recorded statement for the prior tax year.
if Tax.list_profiles("Owner") == [] do
  {:ok, _} =
    Tax.create_profile(owner, %{
      holder: "Owner",
      valid_from: ~D[2024-01-01],
      church_tax_liable: false
    })
end

if Tax.list_snapshots() == [] do
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
end

# 9. Research log on Apple: thesis, evidence, a risk and the retraction that
#    supersedes it (a retraction must name the entry it withdraws). The log is
#    append-only, so a re-run must not add a second round of entries.
if Knowledge.list_notes(apple.id) == [] do
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
end

IO.puts("review seed done (timber position: #{timber_state})")
