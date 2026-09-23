# Seeds the review instance for a closing-act walkthrough: the synthetic
# priv/demo dataset plus deliberately finding-triggering rows — an
# unclassified security, a held position with a stale quote, a priceless
# position, a foreign-currency cash account with no FX rate, a snapshot, a tax
# statement, research-log entries, security events, buckets and a view.
# Synthetic all the way down; no real data (AGENTS.md → Privacy And
# Disclosure).
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
alias Portfolixir.{
  Actor,
  Buckets,
  Catalog,
  Classifications,
  Imports,
  Knowledge,
  Ledger,
  Portfolios,
  Tax
}

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
# Strategies tree + target weights.
Code.eval_file("priv/demo/strategies_seed.exs")

# The demo seed's plan is complete: 85 % across the categories plus a 15 %
# cash target. The review instance needs the other state — a plan that does
# not add up — because the walkthrough conditions name it as one of the three
# alarms that must fire (pr-review-checklist.md → G). Lowering the cash target
# leaves five points unallocated and renders the sum warning, without touching
# the demo seed the README screenshots come from.
:ok =
  Portfolixir.Portfolios.Targets.set_cash_target(
    owner,
    portfolio.id,
    Decimal.new("0.10")
  )

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

# 10. Security events (ADR-0048): a calendar the walkthrough can read. Apple is
#     held, the solar name is not — which is the decision the default scope
#     exists for, so both carry dates. All four timing qualifiers appear, plus
#     one past event nobody has confirmed and one nobody has re-read in months,
#     because those are the two reads an empty calendar cannot show.
watch = find_security.("Helios Solar Systems SE")

if Knowledge.Events.list_for_security(apple.id) == [] do
  [
    %{
      security_id: apple.id,
      kind: "earnings",
      date: Date.add(today, 9),
      timing: "exact",
      confirmed: true,
      source_url: "https://example.invalid/ir/calendar",
      source_quality: "primary",
      checked_at: Date.add(today, -2),
      note: "Q4 report, confirmed on the IR page"
    },
    %{
      security_id: apple.id,
      kind: "ex_dividend",
      date: Date.add(today, 23),
      timing: "estimated",
      source_quality: "secondary_multi",
      checked_at: Date.add(today, -20),
      note: "Estimated from the last four quarters"
    },
    %{
      security_id: apple.id,
      kind: "shareholder_meeting",
      date: Date.add(today, -11),
      timing: "exact",
      source_quality: "primary",
      checked_at: Date.add(today, -40),
      note: "Did it happen? Nobody has ticked this off"
    }
  ]
  |> Enum.each(fn attrs -> {:ok, _} = Knowledge.Events.create_event(owner, attrs) end)
end

if watch && Knowledge.Events.list_for_security(watch.id) == [] do
  [
    %{
      security_id: watch.id,
      kind: "lockup_expiry",
      date: Date.add(today, 5),
      date_end: Date.add(today, 12),
      timing: "window",
      source_quality: "awareness",
      checked_at: Date.add(today, -5),
      note: "Prospectus gives a week, not a day"
    },
    %{
      security_id: watch.id,
      kind: "index_review",
      date: Date.add(today, 45),
      timing: "month",
      source_quality: "unverified",
      checked_at: Date.add(today, -140),
      note: "Quarterly review; nobody has re-read this since the last one"
    }
  ]
  |> Enum.each(fn attrs -> {:ok, _} = Knowledge.Events.create_event(owner, attrs) end)
end

# 11. Policy rules (ADR-0049, Sprint 15 Lane A4): one in every state the
#     Risk tab's "Own rules" section has to render — breached with a version
#     history, met, a band on a drift, undetermined for want of a target,
#     undetermined because a metric refused, and a retired rule. Created only
#     when a rule of that name is not there yet; versions are append-style
#     (ADR-0049 §4), so a re-run must not add a second history.
alias Portfolixir.Portfolios.{PolicyRules, Risk}

rule_named = fn name, view_id ->
  Enum.find(
    PolicyRules.list_rules(portfolio.id, view: view_id, include_retired: true),
    &(&1.name == name)
  )
end

seed_rule = fn name, view_id, version, since ->
  case rule_named.(name, view_id) do
    nil ->
      {:ok, rule} =
        PolicyRules.create_rule(
          owner,
          %{
            portfolio_id: portfolio.id,
            view_id: view_id,
            name: name,
            version: Map.put(version, :valid_from, since)
          },
          today: since
        )

      rule

    rule ->
      rule
  end
end

top =
  portfolio.id
  |> Risk.for_portfolio(metrics: false)
  |> Map.fetch!(:top_holdings)
  |> List.first()

strategies = Enum.find(Classifications.list_classifications(), &(&1.name == "Strategies"))

growth =
  strategies && Enum.find(Classifications.list_categories(strategies.id), &(&1.name == "Growth"))

# Breached, with a history: 8 % a month ago, tightened to 5 % today.
cap = %{
  subject_type: "security",
  security_id: top.security_id,
  measure: "weight",
  kind: "cap",
  severity: "hard"
}

single =
  seed_rule.(
    "Einzeltitel höchstens 5 %",
    nil,
    Map.put(cap, :threshold, "8"),
    Date.add(today, -30)
  )

if length(PolicyRules.get_rule(single.id).versions) == 1 do
  {:ok, _} = PolicyRules.add_version(owner, single, Map.put(cap, :threshold, "5"))
end

seed_rule.(
  "Barreserve mindestens 1 %",
  nil,
  %{subject_type: "cash", measure: "weight", kind: "floor", threshold: "1", severity: "warn"},
  Date.add(today, -30)
)

seed_rule.(
  "Schwankung 90 Tage unter 30 %",
  nil,
  %{
    subject_type: "basis",
    measure: "volatility",
    window: "90d",
    kind: "cap",
    threshold: "30",
    severity: "warn"
  },
  Date.add(today, -30)
)

if growth do
  seed_rule.(
    "Wachstum im Band",
    nil,
    %{
      subject_type: "category",
      classification_id: strategies.id,
      category_id: growth.id,
      measure: "drift",
      kind: "band",
      lower: "-50",
      upper: "50",
      severity: "warn"
    },
    Date.add(today, -30)
  )

  # Undetermined: Helios is on the watch list, not in the plan — no target.
  seed_rule.(
    "Helios nahe am Ziel",
    nil,
    %{
      subject_type: "security",
      security_id: watch.id,
      classification_id: strategies.id,
      measure: "drift",
      kind: "band",
      lower: "-2",
      upper: "2",
      severity: "warn"
    },
    Date.add(today, -30)
  )
end

# Retired: a cap that was the standard for three months, retired as of
# yesterday and readable behind the disclosure. It cannot be retired "sixty
# days ago": a period already measured is never shortened after the fact, and
# the database refuses the backdated end (ADR-0049 §4).
old_cap =
  seed_rule.("Alter Deckel 12 %", nil, Map.put(cap, :threshold, "12"), Date.add(today, -90))

if PolicyRules.get_rule(old_cap.id).status != :retired do
  {:ok, _} = PolicyRules.retire_rule(owner, old_cap, %{})
end

# Undetermined because a metric refused: a position bought three days ago in
# its own bucket, and a view over only that bucket, whose walk is three days
# long — volatility needs 20 return observations. Switch to the view
# "Nur Neuzugang" to read it.
{_kestrel_state, kestrel} =
  seed_position.(
    "Kestrel Industrial Group NV",
    %{ticker_symbol: "KIGN", isin: "NL0000000019", currency_code: "EUR", asset_class: "equity"},
    fn security ->
      %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        security_id: security.id,
        type: "buy",
        date: Date.add(today, -3),
        quantity: "10",
        price: "24.00",
        currency_code: "EUR"
      }
    end
  )

{:ok, _} =
  Quotes.upsert_many(
    kestrel.id,
    for(
      back <- 3..0//-1,
      do: %{date: Date.add(today, -back), close: "24.#{back}0", source: "manual"}
    )
  )

neu = bucket.("Neuzugang")
:ok = Buckets.set_position_override(owner, depot, kestrel, [neu.id])

young_view =
  case Enum.find(Buckets.list_views(), &(&1.name == "Nur Neuzugang")) do
    nil ->
      {:ok, v} = Buckets.create_view(owner, %{name: "Nur Neuzugang", include_all: false})
      v

    v ->
      v
  end

:ok = Buckets.set_view_buckets(owner, young_view, [neu.id], [])

seed_rule.(
  "Neuzugang: Schwankung unter 20 %",
  young_view.id,
  %{
    subject_type: "basis",
    measure: "volatility",
    window: "30d",
    kind: "cap",
    threshold: "20",
    severity: "warn"
  },
  today
)

IO.puts("review seed done (timber position: #{timber_state})")
