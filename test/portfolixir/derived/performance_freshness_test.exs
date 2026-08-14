defmodule Portfolixir.Derived.PerformanceFreshnessTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Derived
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance

  # User story (ADR-0039 C4, FR-1 binding property 3):
  # As a local portfolio maintainer and as the agent reading over API/MCP,
  # I want every served performance summary to carry `as_of` and an explicit
  # `stale` flag, plus the metric's computation basis,
  # so that a materialized figure is never silent about its freshness and
  # never ambiguous about what was computed.
  #
  # Acceptance criteria:
  # - Every summary — fresh, superseded, and empty — carries `as_of` (the
  #   analysis's compute instant) and `stale` (boolean, structural, never
  #   only a warning triangle).
  # - A summary chained from a superseded analysis is marked `stale: true`.
  # - The summary states the computation basis: input series, window,
  #   reference, and the treatment of gaps (AGENTS.md analytics rule).

  setup do
    Memo.reset()

    Application.put_env(:portfolixir, Derived,
      enabled?: true,
      lifetimes: [performance_analysis: :durable]
    )

    on_exit(fn -> Application.put_env(:portfolixir, Derived, enabled?: false) end)
    :ok
  end

  defp world! do
    unique = System.unique_integer([:positive])

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Fresh #{unique}",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Fresh Cash #{unique}",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Fresh Depot #{unique}"
      })

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Fresh AG #{unique}",
        currency_code: "EUR"
      })

    %{portfolio: portfolio, cash: cash, depot: depot, security: security}
  end

  defp buy!(world, date) do
    {:ok, _tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: world.security.id,
        type: "buy",
        date: date,
        quantity: Decimal.new("10"),
        price: Decimal.new("100"),
        gross_amount: Decimal.new("1000"),
        currency_code: "EUR"
      })
  end

  test "a fresh summary carries as_of, stale: false and its computation basis" do
    world = world!()
    buy!(world, ~D[2024-01-10])

    analysis = Performance.analysis(world.portfolio.id, today: ~D[2024-06-30])
    {:ok, summary} = Performance.summarise(analysis, "max")

    assert summary.stale == false
    assert %DateTime{} = summary.as_of
    assert summary.as_of == analysis.basis.computed_at

    assert %{input_series: input, window: window, reference: nil, gaps: gaps} =
             summary.computation_basis

    assert is_binary(input)
    assert is_binary(gaps)
    assert window == %{start_date: summary.start_date, end_date: summary.end_date}
  end

  test "an empty summary still carries as_of, stale and the computation basis" do
    world = world!()

    {:ok, summary} = Performance.for_portfolio(world.portfolio.id, today: ~D[2024-06-30])

    assert summary.stale == false
    assert %DateTime{} = summary.as_of
    assert %{window: %{start_date: nil}} = summary.computation_basis
  end

  test "a summary chained from a superseded analysis is marked stale" do
    world = world!()
    buy!(world, ~D[2024-01-10])

    fresh = Performance.analysis(world.portfolio.id, today: ~D[2024-06-30])
    assert fresh.stale == false

    # A new booking supersedes the materialized walk; the not-yet-replaced
    # value is the §6 stale render source and must say so structurally.
    buy!(world, ~D[2024-04-02])

    superseded = Performance.previous_analysis(world.portfolio.id, today: ~D[2024-06-30])
    assert superseded.stale == true

    {:ok, summary} = Performance.summarise(superseded, "max")
    assert summary.stale == true
    assert summary.as_of == superseded.basis.computed_at
  end

  test "the view walk's summaries carry the same freshness fields" do
    world = world!()
    buy!(world, ~D[2024-01-10])

    {:ok, summary} = Performance.for_view(nil, today: ~D[2024-06-30])

    assert summary.stale == false
    assert %DateTime{} = summary.as_of
    assert %{gaps: gaps} = summary.computation_basis
    assert is_binary(gaps)
  end
end
