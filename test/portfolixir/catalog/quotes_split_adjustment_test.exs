defmodule Portfolixir.Catalog.QuotesSplitAdjustmentTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits

  defp world_with_split(opts \\ []) do
    world = base_world(name: "Adj World", cash_name: "Adj Cash", depot_name: "Adj Depot")
    security = create_security!(name: "Adj Co", ticker: "ADJ", asset_class: "equity")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])

    if Keyword.get(opts, :split?, true) do
      {:ok, _txs} =
        Splits.book_split(Actor.owner_ui(), %{
          security_id: security.id,
          date: Keyword.get(opts, :date, ~D[2026-02-01]),
          ratio_numerator: Keyword.get(opts, :numerator, 10),
          ratio_denominator: Keyword.get(opts, :denominator, 1)
        })
    end

    {world, security}
  end

  defp insert_quote!(security, date, close, source) do
    {:ok, _} =
      %SecurityQuote{}
      |> SecurityQuote.changeset(%{
        security_id: security.id,
        date: date,
        close: Decimal.new(close),
        source: source
      })
      |> Repo.insert()
  end

  defp closes(rows),
    do: Enum.map(rows, &(&1.close |> Decimal.normalize() |> Decimal.to_string(:normal)))

  defp stored_closes(rows),
    do: Enum.map(rows, &(&1.stored_close |> Decimal.normalize() |> Decimal.to_string(:normal)))

  # User story (ADR-0028 §2/§5, issue #590):
  # As a local portfolio maintainer,
  # I want the security-level split events derived from the booked ledger
  # rows — deduplicated across the per-portfolio fan-out,
  # so that every quote read shares one canonical event list.
  #
  # Acceptance criteria:
  # - `split_events/1` returns one event per (date, normalized ratio) even
  #   when the booking fanned out to several portfolios.
  # - Events come back ascending by effective date.
  test "split_events/1 deduplicates the per-portfolio fan-out into security-level events" do
    world_a = base_world(name: "Fan A", cash_name: "FA Cash", depot_name: "FA Depot")
    world_b = base_world(name: "Fan B", cash_name: "FB Cash", depot_name: "FB Depot")
    security = create_security!(name: "Fan Co", ticker: "FNC")
    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    buy!(world_b, security, quantity: "4", price: "100", date: ~D[2026-01-05])

    {:ok, txs} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-02-01],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    assert length(txs) == 2

    {:ok, _} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-03-01],
        ratio_numerator: 1,
        ratio_denominator: 3
      })

    assert Quotes.split_events(security.id) == [
             %{date: ~D[2026-02-01], ratio: {2, 1}},
             %{date: ~D[2026-03-01], ratio: {1, 3}}
           ]

    assert Quotes.split_events_by_security([security.id]) == %{
             security.id => [
               %{date: ~D[2026-02-01], ratio: {2, 1}},
               %{date: ~D[2026-03-01], ratio: {1, 3}}
             ]
           }
  end

  # User story (ADR-0028 §2/§5 quote-basis matrix, issue #590):
  # As a local portfolio maintainer viewing a security's price history after
  # booking a split,
  # I want the displayed series continuous on every storage basis — raw-only,
  # provider-adjusted, and mixed (manual rows outside AND inside the
  # provider's range) — with stored values untouched and reachable,
  # so that the chart never shows a phantom crash and never double-adjusts.
  describe "adjusted_range/3 (quote-basis matrix, chart continuity)" do
    test "raw-only series: pre-split manual closes divide, stored values stay reachable" do
      {_world, security} = world_with_split()
      insert_quote!(security, ~D[2026-01-06], "100", "manual")
      insert_quote!(security, ~D[2026-01-31], "110", "manual")
      insert_quote!(security, ~D[2026-02-01], "11", "manual")
      insert_quote!(security, ~D[2026-02-05], "12", "manual")

      rows = Quotes.adjusted_range(security.id, ~D[2026-01-01], ~D[2026-12-31])

      assert closes(rows) == ["10", "11", "11", "12"]
      assert stored_closes(rows) == ~w(100 110 11 12)
      assert Enum.map(rows, & &1.adjusted?) == [true, true, false, false]
      assert Enum.map(rows, & &1.basis) == [:raw, :raw, :raw, :raw]

      # NFR-2: the stored rows themselves are untouched.
      stored = Quotes.range(security.id, ~D[2026-01-01], ~D[2026-12-31])

      assert Enum.map(stored, &(&1.close |> Decimal.normalize() |> Decimal.to_string(:normal))) ==
               ~w(100 110 11 12)
    end

    test "provider-adjusted series: no additional factor" do
      {_world, security} = world_with_split()
      insert_quote!(security, ~D[2026-01-31], "11", "coingecko")
      insert_quote!(security, ~D[2026-02-05], "12", "coingecko")

      rows = Quotes.adjusted_range(security.id, ~D[2026-01-01], ~D[2026-12-31])

      assert closes(rows) == ["11", "12"]
      assert Enum.map(rows, & &1.adjusted?) == [false, false]
      assert Enum.map(rows, & &1.basis) == [:provider_mirror, :provider_mirror]
    end

    test "mixed series: manual rows outside AND inside the provider range adjust per row" do
      {_world, security} = world_with_split()
      # Manual row outside (before) the provider's range: raw pre-split.
      insert_quote!(security, ~D[2026-01-06], "100", "manual")
      # Provider range 2026-01-20..2026-02-05, already back-adjusted.
      insert_quote!(security, ~D[2026-01-20], "10.5", "coingecko")
      # Manual row INSIDE the provider range (survives the sync per the §2
      # precondition, #588): raw pre-split.
      insert_quote!(security, ~D[2026-01-25], "105", "manual")
      insert_quote!(security, ~D[2026-01-31], "11", "coingecko")
      insert_quote!(security, ~D[2026-02-05], "12", "coingecko")

      rows = Quotes.adjusted_range(security.id, ~D[2026-01-01], ~D[2026-12-31])

      assert closes(rows) == ["10", "10.5", "10.5", "11", "12"]
      assert Enum.map(rows, & &1.adjusted?) == [true, false, true, false, false]
    end

    test "sequential splits compound; a reverse split multiplies up" do
      {_world, security} = world_with_split(numerator: 10, denominator: 1)

      {:ok, _} =
        Splits.book_split(Actor.owner_ui(), %{
          security_id: security.id,
          date: ~D[2026-03-01],
          ratio_numerator: 1,
          ratio_denominator: 3
        })

      insert_quote!(security, ~D[2026-01-31], "100", "manual")
      insert_quote!(security, ~D[2026-02-10], "10", "manual")
      insert_quote!(security, ~D[2026-03-05], "30", "manual")

      rows = Quotes.adjusted_range(security.id, ~D[2026-01-01], ~D[2026-12-31])

      # 100 / (10/1 * 1/3 = 10/3) = 30; 10 / (1/3) = 30; 30 stays.
      assert closes(rows) == ["30", "30", "30"]
    end

    test "the treat_quotes_as_raw override forces the raw basis for synced rows" do
      {_world, security} = world_with_split()

      {:ok, security} =
        Catalog.update_security(Actor.owner_ui(), security, %{treat_quotes_as_raw: true})

      # A provider that never back-adjusted: stored closes still pre-split.
      insert_quote!(security, ~D[2026-01-31], "110", "coingecko")
      insert_quote!(security, ~D[2026-02-05], "12", "coingecko")

      rows = Quotes.adjusted_range(security.id, ~D[2026-01-01], ~D[2026-12-31])

      assert closes(rows) == ["11", "12"]
      assert Enum.map(rows, & &1.basis) == [:raw, :raw]
    end
  end

  # User story (ADR-0028 §2, issue #590):
  # As every read model pricing a current position,
  # I want the latest close served in the current basis,
  # so that a stale raw quote from before the effective date never values a
  # post-split quantity at the unsplit price.
  describe "adjusted_latest/1 and adjusted_latest_by_security_ids/1" do
    test "a stale pre-split manual latest close divides by the later ratio" do
      {_world, security} = world_with_split()
      insert_quote!(security, ~D[2026-01-31], "110", "manual")

      assert %{close: close, stored_close: stored, basis: :raw, adjusted?: true} =
               Quotes.adjusted_latest(security.id)

      assert Decimal.equal?(close, Decimal.new("11"))
      assert Decimal.equal?(stored, Decimal.new("110"))

      by_ids = Quotes.adjusted_latest_by_security_ids([security.id])
      assert Decimal.equal?(by_ids[security.id].close, Decimal.new("11"))
    end

    test "returns nil / empty map without quotes" do
      {_world, security} = world_with_split()
      assert Quotes.adjusted_latest(security.id) == nil
      assert Quotes.adjusted_latest_by_security_ids([security.id]) == %{}
    end
  end

  # User story (ADR-0028 §2, issue #590 — attach_metrics tiles):
  # As a user of the securities list and detail metrics,
  # I want day-change/1M/1Y computed on basis-adjusted closes,
  # so that a raw series spanning the effective date shows the real price
  # move instead of a phantom -90% day.
  describe "attach_metrics/1 (day-change / 1M / 1Y tiles)" do
    test "ratios span the effective date without a phantom jump on the raw basis" do
      {_world, security} = world_with_split(date: Date.add(Date.utc_today(), -5))
      today = Date.utc_today()
      insert_quote!(security, Date.add(today, -40), "100", "manual")
      insert_quote!(security, Date.add(today, -6), "110", "manual")
      insert_quote!(security, today, "11", "manual")

      assert [%{metrics: metrics}] = Quotes.attach_metrics([security])

      # Latest close is post-split and stays 11; the previous close (raw 110,
      # pre-split) adjusts to 11 -> day change 0.
      assert Decimal.equal?(metrics.latest_price, Decimal.new("11"))
      assert Decimal.equal?(metrics.day_change_abs, Decimal.new("0"))
      assert Decimal.equal?(metrics.day_change_pct, Decimal.new("0"))
      # 1M baseline raw 100 adjusts to 10 -> +10 %.
      assert Decimal.equal?(metrics.performance_1m, Decimal.new("0.1"))
    end
  end

  # User story (ADR-0028 §5 delete-the-event, issue #590):
  # As a maintainer who booked a wrong split,
  # I want deleting the whole per-portfolio row group to restore every chart
  # and figure exactly,
  # so that the PP failure mode (wrong ratio, no way back) cannot occur.
  # User story (E17 closing-act review, finding 6):
  # As an API consumer requesting a security's quote history,
  # I want the adjusted view computed from the SAME stored rows the response
  # pairs it with,
  # so that a concurrent upsert between two reads can never misalign the
  # stored/adjusted zip.
  #
  # Acceptance criteria:
  # - `adjust_rows/2` is a pure function of the rows passed in: it returns
  #   one adjusted view per input row, in order, regardless of what is
  #   stored meanwhile.
  # - Its output matches `adjusted_range/3` for the same rows.
  test "adjust_rows/2 adjusts exactly the rows given, immune to concurrent inserts" do
    {_world, security} = world_with_split()
    insert_quote!(security, ~D[2026-01-10], "110", "manual")
    insert_quote!(security, ~D[2026-02-02], "11", "manual")

    stored = Quotes.range(security.id, ~D[2026-01-01], ~D[2026-12-31])
    security = Catalog.get_security(security.id)
    adjusted = Quotes.adjust_rows(stored, security)

    assert length(adjusted) == length(stored)
    assert Enum.map(adjusted, & &1.date) == Enum.map(stored, & &1.date)
    assert closes(adjusted) == ["11", "11"]
    assert stored_closes(adjusted) == ["110", "11"]

    # Same result as the range-loading read path for the same rows.
    assert adjusted == Quotes.adjusted_range(security.id, ~D[2026-01-01], ~D[2026-12-31])

    # A row stored AFTER the fetch does not leak into the adjusted view —
    # the function only sees the list it was handed.
    insert_quote!(security, ~D[2026-01-15], "105", "manual")
    assert Quotes.adjust_rows(stored, security) == adjusted
  end

  test "deleting the fanned-out split group restores the displayed series exactly" do
    world_a = base_world(name: "Del A", cash_name: "DA Cash", depot_name: "DA Depot")
    world_b = base_world(name: "Del B", cash_name: "DB Cash", depot_name: "DB Depot")
    security = create_security!(name: "Del Co", ticker: "DEL")
    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    buy!(world_b, security, quantity: "4", price: "100", date: ~D[2026-01-05])
    insert_quote!(security, ~D[2026-01-31], "110", "manual")

    {:ok, split_rows} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-02-01],
        ratio_numerator: 10,
        ratio_denominator: 1
      })

    assert [%{close: adjusted}] =
             Quotes.adjusted_range(security.id, ~D[2026-01-01], ~D[2026-12-31])

    assert Decimal.equal?(adjusted, Decimal.new("11"))

    for row <- split_rows do
      {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), row)
    end

    assert Quotes.split_events(security.id) == []

    assert [%{close: restored, adjusted?: false}] =
             Quotes.adjusted_range(security.id, ~D[2026-01-01], ~D[2026-12-31])

    assert Decimal.equal?(restored, Decimal.new("110"))
  end
end
