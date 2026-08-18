defmodule Mix.Tasks.Portfolixir.Derived.Measure do
  @shortdoc "Times the figures the operator waits on, so activation stays a measurement"

  @moduledoc """
  Seeds a synthetic ledger and times every figure a human surface waits on,
  so [ADR-0039](../../../docs/decisions/0039-durable-derived-values.md) §2's
  "activation is a configuration decision informed by measurement" has a
  measurement to be informed by (amendment §4, issue #711).

  It exists as a committed command rather than a one-off script because the
  first activation decision was taken from an ad-hoc timing run and the second
  one — this one — would otherwise have had nothing to compare against. An
  analytic that turns out cheap enough not to need a lifetime is a **finding**
  and is printed as such, not omitted.

  ## Running it

  It WRITES synthetic transactions, so point it at a throwaway database, the
  same convention `priv/demo` uses:

      DATABASE_NAME=portfolixir_bench mix ecto.create
      DATABASE_NAME=portfolixir_bench mix ecto.migrate
      DATABASE_NAME=portfolixir_bench mix portfolixir.derived.measure

  It refuses to run in `:prod`. Options, with the defaults that reproduce the
  ADR's Context row (50 securities / 1,001 bookings / weekly quotes / ~10 years):

      --securities 50     securities in the catalog
      --bookings 1000     buy/sell bookings spread over the window
      --years 10          how far back the first booking sits
      --skip-seed         measure whatever is already in the database

  ## What the numbers mean

  Each candidate is timed **with the derived layer off**, twice. That is
  deliberately the same shape as the ADR's Context table: the first call is
  what a cold surface pays, and the second call answers the question that
  decides activation — does anything survive, or does every mount pay again?
  A candidate whose second call costs the same as its first, and whose cost is
  material, is what `:durable` is for.

  The numbers are wall-clock milliseconds on whatever box runs the command.
  They establish an order of magnitude, never a budget — the caveat ADR-0039's
  Context already carries.
  """

  use Mix.Task

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications
  alias Portfolixir.Derived
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.CategoryResult
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Risk
  alias Portfolixir.Portfolios.Valuation

  @requirements ["app.start"]

  @switches [securities: :integer, bookings: :integer, years: :integer, skip_seed: :boolean]

  @impl Mix.Task
  def run(args) do
    if Mix.env() == :prod do
      Mix.raise("portfolixir.derived.measure writes synthetic data and never runs in :prod")
    end

    {opts, _rest, _invalid} = OptionParser.parse(args, strict: @switches)

    # Ecto's per-query debug logging is on in :dev and costs more than some of
    # the analytics being timed, so leaving it on would measure the logger.
    # Silenced for the run and restored after it, never for the environment.
    previous_level = Logger.level()
    Logger.configure(level: :warning)

    try do
      unless opts[:skip_seed], do: seed(opts)
      run_measurement()
    after
      Logger.configure(level: previous_level)
    end
  end

  defp run_measurement do
    case world() do
      nil ->
        Mix.shell().error("No portfolio in this database — run without --skip-seed to seed one.")

      world ->
        report(measure(world))
    end
  end

  # -- measurement -------------------------------------------------------------

  defp measure(world) do
    # Measured with the layer OFF: what is timed is the raw computation a
    # surface waits on today, not the memo's hit rate.
    previous = Application.get_env(:portfolixir, Derived, [])
    Application.put_env(:portfolixir, Derived, Keyword.put(previous, :enabled?, false))

    try do
      Enum.map(candidates(world), fn {label, fun} ->
        %{label: label, first_ms: time(fun), second_ms: time(fun)}
      end)
    after
      Application.put_env(:portfolixir, Derived, previous)
    end
  end

  defp candidates(world) do
    %{portfolio: portfolio, classification_id: classification_id} = world
    base = portfolio.base_currency_code

    [
      {"Performance.analysis/2 (reference, activated)",
       fn -> Performance.analysis(portfolio.id) end},
      {"Performance.view_analysis/2",
       fn -> Performance.view_analysis(nil, base_currency: base) end},
      {"Valuation.for_view/2 (dashboard + header total)",
       fn -> Valuation.for_view(nil, base_currency: base) end},
      {"Valuation.for_portfolio/2", fn -> Valuation.for_portfolio(portfolio.id) end},
      {"Valuation.holdings_by_security/1 (classifications)",
       fn -> Valuation.holdings_by_security() end},
      {"Ledger.holdings_for_portfolio/2", fn -> Ledger.holdings_for_portfolio(portfolio.id) end},
      {"Ledger.negative_holdings_report/0", fn -> Ledger.negative_holdings_report() end},
      {"Income.for_portfolio/2", fn -> Income.for_portfolio(portfolio.id) end},
      {"Risk.for_portfolio/2", fn -> Risk.for_portfolio(portfolio.id) end},
      {"Quotes.attach_metrics/1 (securities table)",
       fn -> Quotes.attach_metrics(Catalog.list_securities()) end}
    ] ++ classification_candidates(portfolio, classification_id)
  end

  defp classification_candidates(_portfolio, nil), do: []

  defp classification_candidates(portfolio, classification_id) do
    [
      {"Allocation.for_portfolio/3 (allocation + drift)",
       fn -> Allocation.for_portfolio(portfolio.id, classification_id) end},
      {"CategoryResult.for_all_portfolios/2",
       fn -> CategoryResult.for_all_portfolios(classification_id) end}
    ]
  end

  defp time(fun) do
    {microseconds, _result} = :timer.tc(fun)
    Float.round(microseconds / 1000, 1)
  end

  defp report(rows) do
    width = rows |> Enum.map(&String.length(&1.label)) |> Enum.max()

    Mix.shell().info("")
    Mix.shell().info(header(width))
    Mix.shell().info(String.duplicate("-", width + 34))

    Enum.each(rows, fn row ->
      Mix.shell().info(
        String.pad_trailing(row.label, width) <>
          "  " <>
          String.pad_leading(to_string(row.first_ms), 10) <>
          "  " <>
          String.pad_leading(to_string(row.second_ms), 10) <>
          "  " <> verdict(row)
      )
    end)

    Mix.shell().info("")
  end

  defp header(width) do
    String.pad_trailing("Analytic", width) <>
      "  " <>
      String.pad_leading("1st (ms)", 10) <> "  " <> String.pad_leading("2nd (ms)", 10) <> "  Read"
  end

  # The threshold is a reading aid, not the decision: 100 ms is roughly where a
  # surface stops feeling instant, so anything under it is called out as a
  # finding rather than left looking like an omission.
  defp verdict(%{second_ms: second_ms}) when second_ms < 100, do: "cheap"
  defp verdict(_row), do: "candidate"

  # -- seeding -----------------------------------------------------------------

  defp world do
    case Portfolios.list_portfolios() do
      [] ->
        nil

      [portfolio | _] ->
        classification_id =
          case Classifications.list_classifications() do
            [] -> nil
            [classification | _] -> classification.id
          end

        %{portfolio: portfolio, classification_id: classification_id}
    end
  end

  defp seed(opts) do
    securities = Keyword.get(opts, :securities, 50)
    bookings = Keyword.get(opts, :bookings, 1000)
    years = Keyword.get(opts, :years, 10)

    Mix.shell().info(
      "Seeding #{securities} securities, #{bookings} bookings over #{years} years..."
    )

    # Deterministic: the same command twice produces the same ledger, so two
    # runs are comparable.
    :rand.seed(:exsss, {711, 711, 711})

    owner = Actor.owner_ui()
    {portfolio, cash, depot} = seed_accounts(owner)
    catalog = seed_catalog(owner, securities, years)

    {:ok, _} =
      Ledger.create_transaction(owner, %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: Date.add(Date.utc_today(), -365 * years - 1),
        gross_amount: Decimal.new(10_000_000),
        currency_code: "EUR"
      })

    seed_bookings(owner, portfolio, cash, depot, catalog, bookings, years)
    seed_classification(owner, catalog)
    Mix.shell().info("Seeded.")
  end

  defp seed_accounts(owner) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(owner, %{name: "Measurement", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(owner, %{
        portfolio_id: portfolio.id,
        name: "Measurement Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(owner, %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Measurement Depot"
      })

    {portfolio, cash, depot}
  end

  defp seed_catalog(owner, count, years) do
    today = Date.utc_today()

    Enum.map(1..count, fn n ->
      {:ok, security} =
        Catalog.create_security(owner, %{
          name: "Measurement Security #{n}",
          ticker_symbol: "MSR#{n}",
          currency_code: "EUR"
        })

      seed_quotes(security, today, years)
      security
    end)
  end

  # Weekly closes, a seeded random walk anchored at 100 — the same shape as the
  # demo quote seed, and the same weekly resolution the ADR's Context table
  # used.
  defp seed_quotes(security, today, years) do
    weeks = div(365 * years, 7)

    {rows, _price} =
      Enum.map_reduce(weeks..0//-1, 100.0, fn back, price ->
        next = max(price * (1.0 + (:rand.uniform() - 0.48) * 0.06), 1.0)

        {%{
           date: Date.add(today, -7 * back),
           close: Decimal.from_float(Float.round(next, 4)),
           source: "manual"
         }, next}
      end)

    {:ok, _count} = Quotes.upsert_many(security.id, rows)
  end

  defp seed_bookings(owner, portfolio, cash, depot, catalog, count, years) do
    today = Date.utc_today()
    span = 365 * years
    held = :counters.new(length(catalog), [])

    Enum.each(1..count, fn n ->
      index = rem(n - 1, length(catalog))
      security = Enum.at(catalog, index)
      date = Date.add(today, -span + div(span * n, count + 1))
      sell? = :counters.get(held, index + 1) > 0 and rem(n, 4) == 0
      quantity = if sell?, do: 1, else: 2

      {:ok, _} =
        Ledger.create_transaction(owner, %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: if(sell?, do: "sell", else: "buy"),
          date: date,
          quantity: Decimal.new(quantity),
          price: Decimal.new("100"),
          gross_amount: Decimal.new(quantity * 100),
          currency_code: "EUR"
        })

      :counters.add(held, index + 1, if(sell?, do: -quantity, else: quantity))
    end)
  end

  # One classification with a handful of categories, so the allocation and
  # per-category candidates have a tree to roll up.
  defp seed_classification(owner, catalog) do
    {:ok, classification} = Classifications.create_classification(owner, %{name: "Measurement"})

    categories =
      Enum.map(1..5, fn n ->
        {:ok, category} =
          Classifications.create_category(owner, %{
            classification_id: classification.id,
            name: "Category #{n}"
          })

        category
      end)

    catalog
    |> Enum.with_index()
    |> Enum.each(fn {security, index} ->
      category = Enum.at(categories, rem(index, length(categories)))

      {:ok, _} =
        Classifications.assign_security(owner, security.id, classification.id, category.id)
    end)
  end
end
