# Seeds the review instance for a closing-act walkthrough: the synthetic
# priv/demo dataset plus deliberately finding-triggering rows — an
# unclassified security, a held position with a stale quote, a priceless
# position, a foreign-currency cash account with no FX rate, a snapshot, a tax
# statement, research-log entries, security events, buckets and a view, policy
# rules in every state, a cross-currency buy, position targets in one
# category, and the lifecycle merges: merged and renamed accounts, a merged
# depot, a merged security, and a refused merge of each kind a seed can reach
# (the two legacy import-hash states need a database from before the
# import-hash check and are left to the tests).
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
  Fx,
  Imports,
  Knowledge,
  Ledger,
  Portfolios,
  Tax
}

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
# Releasing the newer ones is what makes the *surface* idempotent: the quote
# seed above prices every security up to today, this one included, which would
# silently un-stale the one row the stale finding exists to show. Both go
# through the authored, journaled quote paths (E25 S6, T-9), and the demo is
# offline, so every row here is manual and the release clears it.
:rand.seed(:exsss, {7, 7, 7})

stale_rows =
  for back <- 60..5//-1 do
    %{
      date: Date.add(today, -back * 7),
      close: Float.to_string(Float.round(38.0 + :rand.uniform() * 8, 2))
    }
  end

{:ok, _} = Catalog.upsert_quotes(owner, timber.id, stale_rows)

stale_cutoff = Date.add(today, -5 * 7)

{:ok, %{released: dropped}} =
  Catalog.release_manual_quotes(owner, timber.id, Date.add(stale_cutoff, 1), Date.add(today, 1))

if dropped != [] do
  IO.puts("stale surface: released #{length(dropped)} quote(s) newer than #{stale_cutoff}")
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
  Catalog.upsert_quotes(
    owner,
    kestrel.id,
    for(back <- 3..0//-1, do: %{date: Date.add(today, -back), close: "24.#{back}0"})
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

# 12. A cross-currency buy (#395, Sprint 15 Lane D2): a CHF security bought
# through the EUR depot, its settlement meeting the guard (960.00 EUR for
# 912.00 CHF at 1 EUR = 0.95 CHF, plus 4.90 EUR fees). CHF rather than USD on
# purpose: the USD Settlement account above must keep firing "cash with no
# FX", so this seed never stores a USD rate. The CHF rate on the booking date
# is also what the booking form suggests when the walkthrough books another
# CHF trade on that date — open the drawer, pick the depot and this security.
alpine_date = Date.add(today, -10)

{:ok, _} =
  Fx.upsert_many([
    %{
      base_currency: "EUR",
      quote_currency: "CHF",
      date: alpine_date,
      rate: "0.95",
      source: "manual"
    }
  ])

{_alpine_state, alpine} =
  seed_position.(
    "Alpine Test Werke AG",
    %{ticker_symbol: "ATW", isin: "CH0000000017", currency_code: "CHF", asset_class: "equity"},
    fn security ->
      %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        security_id: security.id,
        type: "buy",
        date: alpine_date,
        quantity: "20",
        price: "45.60",
        currency_code: "CHF",
        security_amount: "912.00",
        settlement_amount: "960.00",
        fees: "4.90",
        gross_amount: "964.90"
      }
    end
  )

{:ok, _} =
  Catalog.upsert_quotes(owner, alpine.id, [
    %{date: alpine_date, close: "45.60"},
    %{date: today, close: "46.10"}
  ])

# 13. Position targets in one category (#481, Sprint 15 Lane D1): the three
# Platforms securities carry their own targets, summing to the category's
# 30 %, so the Classifications SOLL editor shows the category as the read-only
# "Σ positions" with its position rows open. An upsert, safe to repeat.
strategies = Enum.find(Classifications.list_classifications(), &(&1.name == "Strategies"))
platforms = Enum.find(Classifications.list_categories(strategies.id), &(&1.name == "Platforms"))

platform_targets =
  for {fragment, weight} <- [{"apple", "0.12"}, {"microsoft", "0.10"}, {"nvidia", "0.08"}],
      security =
        Enum.find(
          Catalog.list_securities(),
          &String.contains?(String.downcase(&1.name), fragment)
        ),
      security do
    %{category_id: platforms.id, security_id: security.id, target_weight: weight}
  end

{:ok, _} =
  Portfolixir.Portfolios.Targets.set_targets(
    owner,
    portfolio.id,
    strategies.id,
    platform_targets
  )

# 14. Lifecycle merges (ADR-0050, Sprint 16 Lane L; plan D-10): what the
#     closing act's UAT persona runs #328's five-step plan on. Done merges:
#     a cash account merged into another (the survivor shows "merged from" and
#     the source's name as a former name), a renamed account (a plain former
#     name), a depot merged into another, and a duplicate security merged
#     with its ISIN adopted and its duplicates removed (the survivor names its
#     former ISIN and the merge). Left un-merged and ready to try, one refusal
#     of each kind a seed can reach: another currency, research notes on the
#     source, a policy rule reading the source, and a split one side lacks
#     (14e–14h); a position whose buckets differ between two depots, a
#     name-only security whose name would stop resolving, two split ratios on
#     one day, and a set balance a buy booked without its amount makes
#     unstorable (14i–14l); and, in step 1 of "Merge into…" on Kestrel, a
#     benchmark, a retired and a raw-quote look-alike, each disabled with its
#     reason (14m). Not seeded, because they need a database from before the
#     import-hash check: a set balance or a split that still carries an
#     import hash (legacy_hashed_anchor, legacy_hashed_split; the tests pin
#     both). Every scenario is created only when its survivor is not there
#     yet, so a re-run adds nothing; a merge is never replayed. Synthetic
#     names and ISINs only.
alias Portfolixir.Lifecycle

cash_named = fn name -> Enum.find(Portfolios.list_cash_accounts(), &(&1.name == name)) end
depot_named = fn name -> Enum.find(Portfolios.list_securities_accounts(), &(&1.name == name)) end

new_cash = fn name ->
  {:ok, account} =
    Portfolios.create_cash_account(owner, %{
      portfolio_id: portfolio.id,
      name: name,
      currency_code: "EUR"
    })

  account
end

cash_booking = fn account, type, amount, date, extra ->
  {:ok, tx} =
    Ledger.create_transaction(
      owner,
      Map.merge(
        %{
          portfolio_id: portfolio.id,
          cash_account_id: account.id,
          type: type,
          date: date,
          gross_amount: amount,
          currency_code: "EUR"
        },
        extra
      )
    )

  tx
end

buy = fn {depot_account, cash_account}, security, quantity, price, date ->
  {:ok, tx} =
    Ledger.create_transaction(owner, %{
      portfolio_id: portfolio.id,
      securities_account_id: depot_account.id,
      cash_account_id: cash_account.id,
      security_id: security.id,
      type: "buy",
      date: date,
      quantity: quantity,
      price: price,
      currency_code: security.currency_code
    })

  tx
end

new_security = fn name, isin, currency ->
  {:ok, security} =
    Catalog.create_security(owner, %{
      name: name,
      isin: isin,
      currency_code: currency,
      asset_class: "etf"
    })

  security
end

# The pair a security scenario seeds, looked up by ISIN (the two share a
# name on purpose: that is the duplicate the merge repairs).
security_by_isin = fn isin -> Enum.find(Catalog.list_securities(), &(&1.isin == isin)) end

# 14a. A cash account merged into another, with a transfer between the two
#      and one equal interest booking removed as a duplicate.
if cash_named.("Tagesgeld") == nil do
  old = new_cash.("Tagesgeld (alt)")
  survivor = new_cash.("Tagesgeld")
  cash_booking.(old, "deposit", "1000.00", ~D[2025-01-02], %{})
  cash_booking.(survivor, "deposit", "500.00", ~D[2025-01-03], %{})

  cash_booking.(old, "cash_transfer", "200.00", ~D[2025-02-01], %{
    counter_cash_account_id: survivor.id
  })

  cash_booking.(old, "interest", "12.40", ~D[2025-03-31], %{})
  cash_booking.(survivor, "interest", "12.40", ~D[2025-03-31], %{})

  {:ok, preview} = Lifecycle.preview_cash_merge(old.id, survivor.id)

  {:ok, _record, :applied} =
    Lifecycle.merge_cash_account(owner, old.id, survivor.id, %{
      plan_digest: preview.plan_digest,
      collapse_key_equal: true
    })

  IO.puts("merges: Tagesgeld (alt) merged into Tagesgeld")
end

# 14b. A renamed account: "Haushalt" stays its former name.
if cash_named.("Haushaltskonto") == nil do
  household = new_cash.("Haushalt")
  cash_booking.(household, "deposit", "250.00", ~D[2025-04-01], %{})
  {:ok, _} = Portfolios.update_cash_account(owner, household, %{name: "Haushaltskonto"})
end

# 14c. A depot merged into another: two depots at one broker, each with its
#      own cash account, one security held in both.
if depot_named.("Depot 1") == nil do
  cash_1 = new_cash.("Broker Verrechnung 1")
  cash_2 = new_cash.("Broker Verrechnung 2")
  cash_booking.(cash_1, "deposit", "3000.00", ~D[2025-01-02], %{})
  cash_booking.(cash_2, "deposit", "2000.00", ~D[2025-01-02], %{})

  {:ok, depot_1} =
    Portfolios.create_securities_account(owner, %{
      portfolio_id: portfolio.id,
      cash_account_id: cash_1.id,
      name: "Depot 1"
    })

  {:ok, depot_2} =
    Portfolios.create_securities_account(owner, %{
      portfolio_id: portfolio.id,
      cash_account_id: cash_2.id,
      name: "Depot 2"
    })

  # Its own synthetic name: a second "Kestrel Industrial Group NV" would make
  # the name lookup of block 12 pick either on a re-run (review finding M-2).
  cobalt = new_security.("Cobalt Ridge Logistics SE", "XS0000000041", "EUR")
  buy.({depot_1, cash_1}, cobalt, "20", "40.00", ~D[2025-02-10])
  buy.({depot_2, cash_2}, cobalt, "10", "42.50", ~D[2025-03-12])

  {:ok, preview} = Lifecycle.preview_depot_merge(depot_2.id, depot_1.id)

  {:ok, _record, :applied} =
    Lifecycle.merge_depot(owner, depot_2.id, depot_1.id, %{plan_digest: preview.plan_digest})

  IO.puts("merges: Depot 2 merged into Depot 1")
end

demo = {depot, cash}

# 14d. A duplicate security merged: imported under its old ISIN, then a
#      second copy under the new one; the merge adopts the new ISIN and
#      removes the duplicated bookings (ADR-0029 §3's wrong-order repair).
if security_by_isin.("XS0000000025") == nil and security_by_isin.("XS0000000017") == nil do
  meridian = new_security.("Meridian Global Equity ETF", "XS0000000017", "EUR")
  copy = new_security.("Meridian Global Equity ETF", "XS0000000025", "EUR")
  buy.(demo, meridian, "40", "62.00", ~D[2024-03-02])
  buy.(demo, meridian, "20", "65.50", ~D[2024-09-02])
  buy.(demo, copy, "40", "62.00", ~D[2024-03-02])
  buy.(demo, copy, "20", "65.50", ~D[2024-09-02])
  buy.(demo, copy, "5", "71.00", ~D[2025-07-01])

  {:ok, preview} = Lifecycle.preview_security_merge(copy.id, meridian.id)

  {:ok, _record, :applied} =
    Lifecycle.merge_security(owner, copy.id, meridian.id, %{
      plan_digest: preview.plan_digest,
      collapse_key_equal: true,
      identity_choice: :adopt_source_isin,
      isin_changed_on: ~D[2025-06-15]
    })

  IO.puts("merges: the duplicate Meridian Global Equity ETF merged, its ISIN adopted")
end

# 14e. Ready to try, refused: another currency. The USD line is disabled as
#      a target of the EUR one in step 1, with its reason.
if security_by_isin.("XS0000000058") == nil do
  kestrel_usd = new_security.("Kestrel Industrial Group NV (USD)", "XS0000000058", "USD")
  {:ok, _} = Catalog.upsert_quotes(owner, kestrel_usd.id, [%{date: today, close: "46.10"}])
end

# 14f. Ready to try, refused: research notes on the source. Merging the
#      noted Orchid Bay into its twin is refused (notes never move or
#      vanish, ADR-0044); the preview offers the merge the other way.
if security_by_isin.("XS0000000066") == nil do
  noted = new_security.("Orchid Bay Pharmaceuticals plc", "XS0000000066", "EUR")
  twin = new_security.("Orchid Bay Pharmaceuticals plc", "XS0000000074", "EUR")
  buy.(demo, noted, "12", "30.00", ~D[2025-02-03])
  buy.(demo, twin, "12", "30.00", ~D[2025-02-03])

  {:ok, _} =
    Knowledge.append_note(owner, %{
      security_id: noted.id,
      author: "operator",
      kind: "evidence",
      body: "A synthetic finding for the merge refusal walkthrough.",
      source_quality: "primary",
      as_of: ~D[2026-01-15]
    })
end

# 14g. Ready to try, refused: a policy rule reads the source. Merging the
#      ruled Pinecrest into its twin is refused, naming the rule; the other
#      way passes.
if security_by_isin.("XS0000000082") == nil do
  ruled = new_security.("Pinecrest Utilities SA", "XS0000000082", "EUR")
  twin = new_security.("Pinecrest Utilities SA", "XS0000000090", "EUR")
  buy.(demo, ruled, "8", "25.00", ~D[2025-02-04])
  buy.(demo, twin, "3", "26.00", ~D[2025-05-04])

  {:ok, _} =
    PolicyRules.create_rule(owner, %{
      portfolio_id: portfolio.id,
      name: "Pinecrest Obergrenze",
      version: %{
        subject_type: "security",
        security_id: ruled.id,
        measure: "weight",
        kind: "cap",
        threshold: "12",
        severity: "hard"
      }
    })
end

# 14h. Ready to try, refused: a split one side lacks. The split copy of
#      Quarry Lane carries a 2:1 split its twin never booked, while the twin
#      holds a booking from before it (ADR-0028 §2): both directions refuse,
#      naming the split and the side lacking it.
if security_by_isin.("XS0000000108") == nil do
  split_copy = new_security.("Quarry Lane Materials AG", "XS0000000108", "EUR")
  twin = new_security.("Quarry Lane Materials AG", "XS0000000116", "EUR")
  buy.(demo, split_copy, "6", "57.30", ~D[2025-01-20])
  buy.(demo, twin, "4", "56.10", ~D[2025-02-11])

  {:ok, _} =
    Ledger.create_transaction(owner, %{
      portfolio_id: portfolio.id,
      security_id: split_copy.id,
      type: "split",
      date: ~D[2025-06-02],
      currency_code: "EUR",
      split_ratio_numerator: 2,
      split_ratio_denominator: 1
    })
end

# 14i. Ready to try, refused in step 2: a position whose buckets differ. Both
#      depots default to no bucket, but Helios in Depot Süd carries an
#      override; merging Süd into Nord would move Nord's history between views
#      (board 02, "Abgelehnt · Depot").
if depot_named.("Depot Nord") == nil do
  cash_nord = new_cash.("Broker Nord Verrechnung")
  cash_sued = new_cash.("Broker Süd Verrechnung")
  cash_booking.(cash_nord, "deposit", "2000.00", ~D[2025-01-02], %{})
  cash_booking.(cash_sued, "deposit", "2000.00", ~D[2025-01-02], %{})

  {:ok, nord} =
    Portfolios.create_securities_account(owner, %{
      portfolio_id: portfolio.id,
      cash_account_id: cash_nord.id,
      name: "Depot Nord"
    })

  {:ok, sued} =
    Portfolios.create_securities_account(owner, %{
      portfolio_id: portfolio.id,
      cash_account_id: cash_sued.id,
      name: "Depot Süd"
    })

  helios = new_security.("Helios Solar Systems SE", "XS0000000124", "EUR")
  buy.({nord, cash_nord}, helios, "15", "18.00", ~D[2025-02-12])
  buy.({sued, cash_sued}, helios, "5", "19.20", ~D[2025-03-14])
  :ok = Buckets.set_position_override(owner, sued, helios, [bucket.("Spekulativ").id])
end

# 14j. Ready to try, refused in step 2: a name that would stop resolving. Two
#      securities without an ISIN, one named "… Class B": merging it into the
#      other leaves nothing under its name, so an import naming it would
#      create it again (identity_unresolvable, ADR-0050 §9).
if find_security.("Alder Creek Timber Fund Class B") == nil do
  {:ok, alder} =
    Catalog.create_security(owner, %{
      name: "Alder Creek Timber Fund",
      currency_code: "EUR",
      asset_class: "fund"
    })

  {:ok, alder_b} =
    Catalog.create_security(owner, %{
      name: "Alder Creek Timber Fund Class B",
      currency_code: "EUR",
      asset_class: "fund"
    })

  buy.(demo, alder, "30", "11.20", ~D[2025-03-03])
  buy.(demo, alder_b, "10", "11.40", ~D[2025-04-03])
end

# 14k. Ready to try, refused in step 2: two split ratios on one day. Both
#      copies of Juniper Rail split on 2025-06-02, one 2:1 and one 3:1; the
#      remedy is to delete the split with the wrong ratio.
if security_by_isin.("XS0000000132") == nil do
  juniper = new_security.("Juniper Rail AG", "XS0000000132", "EUR")
  juniper_copy = new_security.("Juniper Rail AG", "XS0000000140", "EUR")
  buy.(demo, juniper, "9", "33.00", ~D[2025-01-21])
  buy.(demo, juniper_copy, "3", "33.40", ~D[2025-02-21])

  for {security, numerator} <- [{juniper, 2}, {juniper_copy, 3}] do
    {:ok, _} =
      Ledger.create_transaction(owner, %{
        portfolio_id: portfolio.id,
        security_id: security.id,
        type: "split",
        date: ~D[2025-06-02],
        currency_code: "EUR",
        split_ratio_numerator: numerator,
        split_ratio_denominator: 1
      })
  end
end

# 14l. Ready to try, refused in step 2: a set balance the amount column cannot
#      hold. A savings-plan buy on the old account was booked without its
#      amount (0.333333333333 shares at 3.333333), and the new account carries
#      a set balance after it: merging the old into the new is refused, naming
#      the set balance and the buy (board 14 ②).
if cash_named.("Sparplan Konto") == nil do
  plan_old = new_cash.("Sparplan Konto (alt)")
  plan_new = new_cash.("Sparplan Konto")
  cash_booking.(plan_old, "deposit", "100.00", ~D[2025-01-02], %{})

  {:ok, plan_depot} =
    Portfolios.create_securities_account(owner, %{
      portfolio_id: portfolio.id,
      cash_account_id: plan_old.id,
      name: "Sparplan Depot"
    })

  {:ok, fraction_fund} =
    Catalog.create_security(owner, %{
      name: "Birchwood Global Savings Fund",
      isin: "XS0000000157",
      currency_code: "EUR",
      asset_class: "fund"
    })

  {:ok, _} =
    Ledger.create_transaction(owner, %{
      portfolio_id: portfolio.id,
      securities_account_id: plan_depot.id,
      cash_account_id: plan_old.id,
      security_id: fraction_fund.id,
      type: "buy",
      date: ~D[2025-01-10],
      quantity: "0.333333333333",
      price: "3.333333",
      currency_code: "EUR"
    })

  {:ok, _} = Ledger.set_cash_balance(owner, plan_new, %{date: ~D[2025-02-01], amount: "100.00"})
end

# 14m. Step 1 of "Merge into…" on Kestrel Industrial Group NV: three
#      look-alikes, each disabled as a target with its reason — a benchmark,
#      a retired security, and one whose synced quotes are treated as raw
#      while Kestrel has quotes.
for {name, flags} <- [
      {"Kestrel Industrial Group NV Index", %{is_benchmark: true}},
      {"Kestrel Industrial Group NV (alt)", %{is_retired: true}},
      {"Kestrel Industrial Group NV (roh)", %{treat_quotes_as_raw: true}}
    ],
    find_security.(name) == nil do
  {:ok, _} =
    Catalog.create_security(
      owner,
      Map.merge(%{name: name, currency_code: "EUR", asset_class: "equity"}, flags)
    )
end

IO.puts("review seed done (timber position: #{timber_state})")
