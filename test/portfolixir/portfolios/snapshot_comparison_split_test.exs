defmodule Portfolixir.Portfolios.SnapshotComparisonSplitTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots

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

  defp book_split!(security, date, {p, q}) do
    {:ok, txs} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: date,
        ratio_numerator: p,
        ratio_denominator: q
      })

    txs
  end

  defp comparison_for(world, source) do
    security =
      create_security!(name: "SC #{source}", ticker: String.upcase(String.slice(source, 0, 3)))

    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{
        name: "Before split (#{source})",
        as_of: ~D[2026-02-15]
      })

    case source do
      "manual" ->
        # Raw as-traded closes: pre-split 110, post-split 12.1.
        insert_quote!(security, ~D[2026-02-14], "110", "manual")
        insert_quote!(security, ~D[2026-03-05], "12.1", "manual")

      "coingecko" ->
        # The provider's back-adjusted mirror of the same reality.
        insert_quote!(security, ~D[2026-02-14], "11", "coingecko")
        insert_quote!(security, ~D[2026-03-05], "12.1", "coingecko")
    end

    book_split!(security, ~D[2026-03-01], {10, 1})

    {:ok, comparison} =
      SnapshotComparison.for_snapshot(snapshot.id, world.portfolio.id, today: ~D[2026-03-10])

    comparison
  end

  # User story (ADR-0028 §2/§5 SnapshotComparison on both bases, issue #590):
  # As a maintainer comparing a frozen snapshot against reality across a
  # split,
  # I want the frozen buy-and-hold side to scale its quantities at the
  # effective date and price each day in that day's own basis — on the raw
  # AND the provider-adjusted storage basis,
  # so that the counterfactual shows the true price return instead of a
  # split-sized cliff (the engine does not dispatch through
  # Projection.effects/1, so nothing fails loudly here without this test).
  describe "frozen side across a 10:1 split (both bases)" do
    for source <- ["manual", "coingecko"] do
      test "on the #{source} basis the frozen series is continuous and returns +10 %" do
        world =
          base_world(
            name: "SCW #{unquote(source)}",
            cash_name: "SCW Cash #{unquote(source)}",
            depot_name: "SCW Depot #{unquote(source)}"
          )

        comparison = comparison_for(world, unquote(source))

        # As-of: 10 shares x 110 as traded = 1100.
        assert Decimal.equal?(comparison.as_of_value, Decimal.new("1100"))
        # Today: 100 post-split shares x 12.1 = 1210 -> +10 % price return.
        assert Decimal.equal?(comparison.current_value, Decimal.new("1210"))
        assert Decimal.equal?(comparison.snapshot_return, Decimal.new("0.1"))

        by_date = Map.new(comparison.series, &{&1.date, &1.snapshot_value})

        # No cliff around the effective date: the day before and the day of
        # the split value identically (quantity x10, carried price /10).
        assert Decimal.equal?(by_date[~D[2026-02-28]], Decimal.new("1100"))
        assert Decimal.equal?(by_date[~D[2026-03-01]], Decimal.new("1100"))
        assert Decimal.equal?(by_date[~D[2026-03-05]], Decimal.new("1210"))
      end
    end
  end
end
