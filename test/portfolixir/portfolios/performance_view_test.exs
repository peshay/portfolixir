defmodule Portfolixir.Portfolios.PerformanceViewTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.WorldFixtures

  # User story (#577):
  # As a local portfolio maintainer with more than one internal portfolio,
  # I want the TTWROR/IRR of a view to cover exactly the accounts the view's
  # header total covers — across all portfolios, each account counted once,
  # so that the performance figures never silently cover only the first
  # portfolio next to an all-accounts total.
  #
  # Acceptance criteria:
  # - The view walk covers the deduplicated account scope the view resolves to
  #   (`Buckets.load_global_scope/1`), including the nil "Everything" view.
  # - The daily series is Decimal-exact: two portfolios in one view chain as
  #   one combined series (value, flow and return base summed per day).
  # - A view that collapses to a single portfolio produces the same daily
  #   series as that portfolio's own scoped walk.
  # - Money crossing the view boundary is an external flow (ADR-0019); money
  #   moving between two in-scope portfolios is not.

  # Two portfolios, each tagged with its own scope bucket:
  # A: 1000 in, 10 @ 100 bought, quoted 100 -> 120 (+20% on 1000).
  # B: 1000 in, 10 @ 100 bought, quoted 100 -> 110 (+10% on 1000).
  defp two_portfolio_world do
    a = base_world(name: "Alpha", cash_name: "Cash A", depot_name: "Depot A")
    b = base_world(name: "Beta", cash_name: "Cash B", depot_name: "Depot B")

    sec_a = create_security!(name: "Fund A", ticker: "FNA", asset_class: "etf")
    sec_b = create_security!(name: "Fund B", ticker: "FNB", asset_class: "etf")

    deposit!(a, "1000", ~D[2026-01-01])
    WorldFixtures.buy!(a, sec_a, quantity: "10", price: "100", date: ~D[2026-01-01])
    WorldFixtures.put_quotes!(sec_a, [{~D[2026-01-01], "100"}, {~D[2026-01-10], "120"}])

    deposit!(b, "1000", ~D[2026-01-01])
    WorldFixtures.buy!(b, sec_b, quantity: "10", price: "100", date: ~D[2026-01-01])
    WorldFixtures.put_quotes!(sec_b, [{~D[2026-01-01], "100"}, {~D[2026-01-10], "110"}])

    {:ok, bucket_a} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Scope A"})
    {:ok, bucket_b} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Scope B"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), a.depot, [bucket_a.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), a.cash, [bucket_a.id])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), b.depot, [bucket_b.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), b.cash, [bucket_b.id])

    %{a: a, b: b, sec_a: sec_a, sec_b: sec_b, bucket_a: bucket_a, bucket_b: bucket_b}
  end

  defp view_including!(bucket_ids, name) do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: name, include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, bucket_ids, [])
    view
  end

  defp rounded(decimal, places), do: Decimal.round(decimal, places)

  test "a view spanning two portfolios chains one combined series" do
    %{a: a, b: b, bucket_a: bucket_a, bucket_b: bucket_b} = two_portfolio_world()
    view = view_including!([bucket_a.id, bucket_b.id], "Both")

    {:ok, result} = Performance.for_view(view.id, today: ~D[2026-01-10])

    # 2000 in on day one, 2300 out at the end: one combined +15%.
    assert rounded(result.ttwror, 6) |> Decimal.equal?(Decimal.new("0.15"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("2000"))
    assert Decimal.equal?(result.end_value, Decimal.new("2300"))
    assert result.view_id == view.id

    # Decimal-exact per day: the combined value is the sum of the two
    # portfolios' own walks, every single day.
    series_a = Performance.analysis(a.portfolio.id, today: ~D[2026-01-10]).daily
    series_b = Performance.analysis(b.portfolio.id, today: ~D[2026-01-10]).daily
    combined = Performance.view_analysis(view.id, today: ~D[2026-01-10]).daily

    assert length(combined) == 10

    for {{point, pa}, pb} <- Enum.zip(Enum.zip(combined, series_a), series_b) do
      assert point.date == pa.date
      assert Decimal.equal?(point.value, Decimal.add(pa.value, pb.value))
      assert Decimal.equal?(point.flow, Decimal.add(pa.flow, pb.flow))
    end
  end

  test "the nil Everything view covers all portfolios" do
    two_portfolio_world()

    {:ok, result} = Performance.for_view(nil, today: ~D[2026-01-10])

    assert rounded(result.ttwror, 6) |> Decimal.equal?(Decimal.new("0.15"))
    assert Decimal.equal?(result.end_value, Decimal.new("2300"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("2000"))
    assert result.view_id == nil
  end

  test "a view collapsing to one portfolio equals that portfolio's own walk" do
    %{a: a, bucket_a: bucket_a} = two_portfolio_world()
    view = view_including!([bucket_a.id], "Only A")

    scoped = Performance.analysis(a.portfolio.id, view: view.id, today: ~D[2026-01-10])
    global = Performance.view_analysis(view.id, today: ~D[2026-01-10])

    assert global.first_date == scoped.first_date
    assert length(global.daily) == length(scoped.daily)

    for {gp, sp} <- Enum.zip(global.daily, scoped.daily) do
      assert gp.date == sp.date
      assert Decimal.equal?(gp.value, sp.value)
      assert Decimal.equal?(gp.flow, sp.flow)
      assert Decimal.equal?(gp.basis, sp.basis)
    end

    {:ok, from_view} = Performance.summarise(global, "max")
    {:ok, from_portfolio} = Performance.summarise(scoped, "max")

    assert Decimal.equal?(from_view.ttwror, from_portfolio.ttwror)
    assert Decimal.equal?(from_view.end_value, from_portfolio.end_value)
    assert Decimal.equal?(from_view.net_external_flows, from_portfolio.net_external_flows)
  end

  # ADR-0019 at the portfolio boundary: a removal in one in-scope portfolio and
  # the matching deposit into another in-scope portfolio net to zero flow — the
  # money never left the view.
  test "money moved between two in-scope portfolios is not an external flow" do
    %{a: a, b: b, bucket_a: bucket_a, bucket_b: bucket_b} = two_portfolio_world()
    view = view_including!([bucket_a.id, bucket_b.id], "Both scopes")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: a.portfolio.id,
        cash_account_id: a.cash.id,
        type: "removal",
        date: ~D[2026-01-05],
        gross_amount: "300",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: b.portfolio.id,
        cash_account_id: b.cash.id,
        type: "deposit",
        date: ~D[2026-01-05],
        gross_amount: "300",
        currency_code: "EUR"
      })

    {:ok, result} = Performance.for_view(view.id, today: ~D[2026-01-10])

    # The move nets to zero on its day; only the two initial deposits remain.
    day5 = Enum.find(result.series, &(&1.date == ~D[2026-01-05]))
    assert Decimal.equal?(day5.flow, Decimal.new("0"))
    assert Decimal.equal?(result.net_external_flows, Decimal.new("2000"))
    assert rounded(result.ttwror, 6) |> Decimal.equal?(Decimal.new("0.15"))
  end

  # ADR-0019: the same removal is an external outflow when its counterpart
  # lands outside the view.
  test "money crossing the view boundary is an external flow" do
    %{a: a, b: b, bucket_a: bucket_a} = two_portfolio_world()
    view = view_including!([bucket_a.id], "Only A crossing")

    # Fund the later removal so A's cash never goes negative.
    deposit!(a, "300", ~D[2026-01-02])

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: a.portfolio.id,
        cash_account_id: a.cash.id,
        type: "removal",
        date: ~D[2026-01-05],
        gross_amount: "300",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: b.portfolio.id,
        cash_account_id: b.cash.id,
        type: "deposit",
        date: ~D[2026-01-05],
        gross_amount: "300",
        currency_code: "EUR"
      })

    {:ok, result} = Performance.for_view(view.id, today: ~D[2026-01-10])

    day5 = Enum.find(result.series, &(&1.date == ~D[2026-01-05]))
    assert Decimal.equal?(day5.flow, Decimal.new("-300"))
    # A: 1000 + 300 in, 300 out; the neutralised return stays +20% on the fund.
    assert Decimal.equal?(result.net_external_flows, Decimal.new("1000"))
    assert rounded(result.ttwror, 6) |> Decimal.equal?(Decimal.new("0.2"))
  end

  test "for_view equals view_analysis plus summarise for every period" do
    %{bucket_a: bucket_a, bucket_b: bucket_b} = two_portfolio_world()
    view = view_including!([bucket_a.id, bucket_b.id], "Parity")

    analysis = Performance.view_analysis(view.id, today: ~D[2026-01-10])

    for period <- Performance.periods() do
      {:ok, from_analysis} = Performance.summarise(analysis, period)
      {:ok, direct} = Performance.for_view(view.id, period: period, today: ~D[2026-01-10])
      assert from_analysis == direct
    end

    assert {:error, :invalid_period} = Performance.for_view(view.id, period: "2w")
  end

  test "a vanished view degrades to an error, never a crash" do
    %{bucket_a: bucket_a} = two_portfolio_world()
    view = view_including!([bucket_a.id], "Vanishing")
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), view)

    assert {:error, :view_not_found} = Performance.view_analysis(view.id, today: ~D[2026-01-10])
    assert {:error, :view_not_found} = Performance.for_view(view.id, today: ~D[2026-01-10])
  end
end
