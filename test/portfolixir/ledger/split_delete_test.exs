defmodule Portfolixir.Ledger.SplitDeleteTest do
  # Sprint 18 U1 (#912; plan D-6, pick H2-A, state A4), ADR-0028 §1.
  # RISK-TIER (ADR-0036; ledger invariants): a split is one security-level
  # fact stored as one `split` row per portfolio that held the security on its
  # effective date. Deleting one row leaves the others, and with them the
  # event: the chart keeps adjusting, holdings in the other portfolios stay
  # scaled, and "Record split" refuses the corrected ratio on that day. This
  # module pins the write that deletes the event as a whole.
  #
  # The invariant: after the whole-split delete no row of that split event
  # remains in any portfolio, every portfolio's positions and holdings are
  # exactly what they were before the split was booked, the security's split
  # events no longer carry it, every removed row is journaled with its
  # before-image, and booking a corrected ratio on that day is accepted.
  #
  # The atomicity half (a failure deletes nothing) is
  # split_delete_atomicity_test.exs, which installs a trigger and runs alone.
  #
  # Every name, figure and date is synthetic.
  use Portfolixir.DataCase, async: true

  import Ecto.Query

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  defp split!(security, date, {p, q}) do
    {:ok, rows} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: date,
        ratio_numerator: p,
        ratio_denominator: q
      })

    rows
  end

  defp split_rows(security) do
    Repo.all(
      from(t in Transaction,
        where: t.type == "split" and t.security_id == ^security.id,
        order_by: t.id
      )
    )
  end

  # What the holdings read says per position, the figures a split changes or
  # must leave alone: quantity, total cost and cost per share.
  defp holdings(world) do
    world.portfolio.id
    |> Ledger.holdings_for_portfolio()
    |> Enum.map(&{&1.security_id, &1.quantity, &1.cost_basis, &1.avg_cost})
    |> Enum.sort()
  end

  defp two_portfolio_world do
    world_a = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")

    world_b =
      base_world(name: "Sparplan-Portfolio", cash_name: "Tagesgeld", depot_name: "Depot 2")

    security = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    buy!(world_a, security, quantity: "40", price: "62.50", date: ~D[2026-09-01])
    buy!(world_b, security, quantity: "12", price: "60", date: ~D[2026-09-02])
    put_quote!(security, ~D[2026-09-14], "64")

    %{a: world_a, b: world_b, security: security}
  end

  # User story (U1, #912; ADR-0028 §1):
  # As the operator (or the agent) who booked a split with the wrong ratio,
  # I want to delete the split as the one fact I booked — every portfolio's
  # row in one step, journaled,
  # so that the ledger is exactly as it was before the split and the
  # corrected ratio can be booked on the same day.
  #
  # Acceptance criteria:
  # - Deleting from any one row of the event removes every row of it, in
  #   every portfolio, and answers the removed rows.
  # - Positions and holdings (quantity, cost basis, cost per share) of every
  #   portfolio equal the figures before the split was booked.
  # - The security's split events no longer carry it, and the stored quote
  #   is read unadjusted again.
  # - Each removed row has its own `delete` journal entry with the row as
  #   its before-image.
  # - "Record split" refused the corrected ratio while the event stood and
  #   accepts it afterwards.
  test "deletes every row of a split event in one step, and the ledger is as before the split" do
    %{a: a, b: b, security: security} = two_portfolio_world()
    before_a = holdings(a)
    before_b = holdings(b)

    positions_before =
      {Ledger.positions_for_portfolio(a.portfolio.id),
       Ledger.positions_for_portfolio(b.portfolio.id)}

    booked = split!(security, ~D[2026-09-15], {2, 1})
    assert length(booked) == 2
    assert holdings(a) != before_a

    corrected = %{
      security_id: security.id,
      date: ~D[2026-09-15],
      ratio_numerator: 3,
      ratio_denominator: 1
    }

    assert {:error, {:conflicting_split_ratio, _}} =
             Splits.book_split(Actor.owner_ui(), corrected)

    # Anchored at the second portfolio's row: any row names the event.
    anchor = Enum.find(booked, &(&1.portfolio_id == b.portfolio.id))

    assert {:ok, deleted} = Splits.delete_split(Actor.owner_ui(), anchor)

    assert deleted |> Enum.map(& &1.id) |> Enum.sort() ==
             booked |> Enum.map(& &1.id) |> Enum.sort()

    assert Enum.map(deleted, & &1.portfolio.name) == ["Hauptportfolio", "Sparplan-Portfolio"]

    assert split_rows(security) == []
    assert holdings(a) == before_a
    assert holdings(b) == before_b

    assert {Ledger.positions_for_portfolio(a.portfolio.id),
            Ledger.positions_for_portfolio(b.portfolio.id)} == positions_before

    assert Quotes.split_events(security.id) == []

    assert [%{close: close, adjusted?: false}] =
             Quotes.adjusted_range(security.id, ~D[2026-09-01], ~D[2026-09-30])

    assert Decimal.equal?(close, Decimal.new("64"))

    entries = Journal.list_entries(resource_type: "transaction", operation: :delete)

    assert entries |> Enum.map(& &1.resource_id) |> Enum.sort() ==
             booked |> Enum.map(&to_string(&1.id)) |> Enum.sort()

    for entry <- entries do
      assert entry.before["type"] == "split"
      assert entry.before["split_ratio_numerator"] == 2
      assert entry.before["split_ratio_denominator"] == 1
      assert entry.before["security_id"] == security.id
    end

    assert {:ok, rebooked} = Splits.book_split(Actor.owner_ui(), corrected)
    assert length(rebooked) == 2
  end

  # User story (U1, #912; ADR-0028 §1, the group identity):
  # As the operator deleting one wrong split,
  # I want only that event's rows removed,
  # so that the security's other splits, and the same day's split of another
  # security, stay booked.
  #
  # Acceptance criteria:
  # - The event is the rows sharing (security, date, normalized ratio); a
  #   split of the same security on another day and a split of another
  #   security on the same day are untouched, with no journal entry.
  test "removes only the rows of the event it names" do
    %{a: a, security: security} = two_portfolio_world()
    other = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
    buy!(a, other, quantity: "25", price: "30", date: ~D[2026-09-01])

    [earlier] = split!(security, ~D[2026-09-05], {1, 2}) |> Enum.take(1)
    wrong = split!(security, ~D[2026-09-15], {2, 1})
    [other_row] = split!(other, ~D[2026-09-15], {2, 1})

    assert {:ok, deleted} = Splits.delete_split(Actor.owner_ui(), hd(wrong))
    assert length(deleted) == 2

    remaining = split_rows(security)
    assert Enum.all?(remaining, &(&1.date == ~D[2026-09-05]))
    assert earlier.id in Enum.map(remaining, & &1.id)
    assert [%{id: other_id}] = split_rows(other)
    assert other_id == other_row.id

    assert Journal.list_entries(resource_type: "transaction", operation: :delete)
           |> Enum.map(& &1.resource_id)
           |> Enum.sort() == wrong |> Enum.map(&to_string(&1.id)) |> Enum.sort()
  end

  # User story (U1, #912; the refusals the API and the screen state):
  # As the agent or the operator deleting a split,
  # I want a row that is gone, or a row that is no split, refused by name
  # with nothing deleted,
  # so that a stale screen or a wrong id never removes another booking.
  #
  # Acceptance criteria:
  # - A row deleted since it was read answers {:error, :not_found}.
  # - A booking of another kind answers {:error, :not_a_split} and stays.
  # - Neither writes a journal entry.
  test "refuses a row that is gone and a booking that is no split" do
    %{a: a, security: security} = two_portfolio_world()
    [row_a, row_b] = split!(security, ~D[2026-09-15], {2, 1})

    {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), row_a)
    assert {:error, :not_found} = Splits.delete_split(Actor.owner_ui(), row_a)

    buy = buy!(a, security, quantity: "1", price: "70", date: ~D[2026-09-20])
    assert {:error, :not_a_split} = Splits.delete_split(Actor.owner_ui(), buy)
    assert Ledger.get_transaction(buy.id)
    assert Ledger.get_transaction(row_b.id)

    assert [single] = Journal.list_entries(resource_type: "transaction", operation: :delete)
    assert single.resource_id == to_string(row_a.id)
  end

  # User story (U1, #912; pick H2-A, state A4):
  # As the operator about to delete a split,
  # I want to see which portfolios' rows go with it,
  # so that the confirmation can name them before anything is written.
  #
  # Acceptance criteria:
  # - Splits.event_rows/1 answers every row of the event a row belongs to,
  #   each with its portfolio, ordered by portfolio, and writes nothing.
  # - Splits.booked_on/2 answers the split rows a security carries on a day,
  #   the rows "Record split" checks a new ratio against.
  test "names the rows of an event without writing anything" do
    %{security: security} = two_portfolio_world()
    [row_a, row_b] = split!(security, ~D[2026-09-15], {2, 1})

    assert [first, second] = Splits.event_rows(row_b)
    assert {first.id, second.id} == {row_a.id, row_b.id}

    assert {first.portfolio.name, second.portfolio.name} ==
             {"Hauptportfolio", "Sparplan-Portfolio"}

    assert security.id |> Splits.booked_on(~D[2026-09-15]) |> Enum.map(& &1.id) == [
             row_a.id,
             row_b.id
           ]

    assert Splits.booked_on(security.id, ~D[2026-09-16]) == []
    assert length(split_rows(security)) == 2
  end
end
