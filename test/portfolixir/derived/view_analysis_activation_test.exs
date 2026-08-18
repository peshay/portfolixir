defmodule Portfolixir.Derived.ViewAnalysisActivationTest do
  @moduledoc """
  The `:durable` activation of `performance_view_analysis` (ADR-0039 §2 and the
  2026-08-15 amendment §4, issue #711).

  The measurement recorded in ADR-0039 is what decided it: the cross-portfolio
  view walk costs the same seconds as the per-portfolio walk that was activated
  in the first pass, and it is what the Wealth page and the dashboard card open.
  It was registered from the start and left at the `:request` default, so it
  died with every restart.

  An activation is not a configuration line — it is a claim that the value can
  be stored, read back and invalidated correctly. Each of those is a test here.
  """

  use Portfolixir.DataCase, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Derived.Value
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance

  @today ~D[2024-12-31]

  setup do
    Memo.reset()

    # No `lifetimes:` override: the layer is switched on and the LIFETIMES stay
    # the ones the application configures, because what is under test IS the
    # activation. Overriding them here would test the override.
    DerivedConfig.enable!()
    :ok
  end

  defp world! do
    unique = System.unique_integer([:positive])

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Act #{unique}",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Act Cash #{unique}",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Act Depot #{unique}"
      })

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: "Act AG #{unique}", currency_code: "EUR"})

    %{portfolio: portfolio, cash: cash, depot: depot, security: security}
  end

  defp buy!(world, date, quantity, price) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: world.security.id,
        type: "buy",
        date: date,
        quantity: Decimal.new(quantity),
        price: Decimal.new(price),
        gross_amount: Decimal.mult(Decimal.new(quantity), Decimal.new(price)),
        currency_code: "EUR"
      })

    tx
  end

  defp quote!(world, date, close) do
    {:ok, _} =
      Quotes.upsert_many(world.security.id, [%{date: date, close: close, source: "manual"}])
  end

  defp analysis, do: Performance.view_analysis(nil, base_currency: "EUR", today: @today)

  defp durable_row do
    Repo.one(
      from(v in Value,
        where: v.analytic_id == "performance_view_analysis",
        order_by: [desc: v.id],
        limit: 1
      )
    )
  end

  # User story (#711, ADR-0039 amendment §4):
  # As a local portfolio maintainer,
  # I want the cross-portfolio walk the Wealth page and the dashboard open to
  # survive a restart,
  # so that the first visit after a restart shows a number instead of paying
  # seconds for a walk that was already computed.
  #
  # Acceptance criteria:
  # - The walk is stored in the durable tier, not only in the volatile memo.
  # - A read after the memo is wiped is served FROM the stored row.
  test "the view walk is stored durably and served from the row after a restart" do
    world = world!()
    buy!(world, ~D[2024-06-01], "10", "100")
    quote!(world, ~D[2024-07-01], "120")

    assert %{daily: [_ | _]} = analysis()
    assert %Value{} = row = durable_row()

    # A restart empties the volatile memo and nothing else. The stored payload
    # is marked, so only a read served FROM the row can return the mark.
    Memo.reset()
    marked = Map.put(Value.decode(row.payload), :served_from_row, true)

    Repo.update_all(from(v in Value, where: v.id == ^row.id),
      set: [payload: Value.encode(marked)]
    )

    assert analysis().served_from_row == true
  end

  # I3 on the global basis: the view walk depends on every portfolio, so a
  # backdated booking in any of them must rewrite it behind its own date.
  test "a backdated booking invalidates the stored view walk" do
    world = world!()
    buy!(world, ~D[2024-06-01], "10", "100")
    quote!(world, ~D[2024-07-01], "120")

    materialized = analysis()
    assert materialized.first_date == ~D[2024-06-01]

    buy!(world, ~D[2024-03-15], "5", "80")

    served = analysis()
    assert served.first_date == ~D[2024-03-15]
    refute comparable(served) == comparable(materialized)

    # And what is served is the whole walk, not a patched prefix: identical to
    # the same walk computed with the layer off.
    assert comparable(served) == comparable(DerivedConfig.with_layer_off(&analysis/0))
  end

  # ADR-0039's standing claim, checked for THIS analytic at its new lifetime:
  # a lifetime changes latency, never numbers.
  test "the durable value equals the same walk computed with the layer off" do
    world = world!()
    buy!(world, ~D[2024-02-01], "7", "90")
    quote!(world, ~D[2024-08-01], "133.3333")

    durable = analysis()
    Memo.reset()

    assert comparable(durable) == comparable(DerivedConfig.with_layer_off(&analysis/0))
  end

  # `stale` and the computed-at stamp are freshness annotations applied outside
  # the stored value (ADR-0039 C4), so they are not part of what must match.
  defp comparable(analysis) do
    analysis
    |> Map.drop([:stale, :served_from_row])
    |> Map.update!(:basis, &Map.drop(&1, [:computed_at]))
  end
end
