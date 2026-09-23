defmodule Portfolixir.Ledger.HeldSecuritiesTest do
  @moduledoc """
  The one "is it held?" predicate (#839, risk-tier per ADR-0036: projection
  semantics). Three surfaces used to carry their own copy — the catalog's
  `holding_status` filter, the research log's unreviewed-positions read and
  the events' `held_only` — and two of them counted only buys and sells.
  Every surface is asserted here against the same ledger, so a copy that
  drifts from the canonical projection turns this file red.
  """
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.HeldSecurities
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction

  @today ~D[2026-09-20]

  defp book!(world, security, type, quantity, extra \\ %{}) do
    {:ok, tx} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        Map.merge(
          %{
            portfolio_id: world.portfolio.id,
            securities_account_id: world.depot.id,
            security_id: security.id,
            type: type,
            date: ~D[2026-01-05],
            quantity: quantity,
            currency_code: "EUR"
          },
          extra
        )
      )

    tx
  end

  # A ledger holding one security of each shape the predicate must tell
  # apart, none of them touched by a buy or a sell.
  defp delivery_world do
    world = base_world(name: "Held World", cash_name: "HW Cash", depot_name: "HW Depot A")

    %{depot: depot_b} =
      add_depot(world.portfolio, cash_name: "HW Cash B", depot_name: "HW Depot B")

    delivered = create_security!(name: "Delivered Co", ticker: "DLV")
    moved = create_security!(name: "Moved Co", ticker: "MOV")
    emptied = create_security!(name: "Emptied Co", ticker: "EMP")
    bought = create_security!(name: "Bought Co", ticker: "BGT")
    never = create_security!(name: "Never Co", ticker: "NVR")

    # Received by an inbound delivery only — a depot transferred in.
    book!(world, delivered, "inbound_delivery", "5")

    # Received by an inbound delivery, then moved to the second depot by a
    # security transfer: still held, now in depot B.
    book!(world, moved, "inbound_delivery", "4")

    book!(world, moved, "security_transfer", "4", %{
      counter_securities_account_id: depot_b.id
    })

    # Delivered in and fully delivered out again.
    book!(world, emptied, "inbound_delivery", "5")
    book!(world, emptied, "outbound_delivery", "5")

    # The control the old copies already got right.
    buy!(world, bought)

    %{delivered: delivered, moved: moved, emptied: emptied, bought: bought, never: never}
  end

  defp ids(securities), do: securities |> Enum.map(& &1.id) |> Enum.sort()

  describe "the predicate is derived from the canonical projection" do
    test "each kind moves the security-level quantity by the sign effects/1 gives it" do
      assert Projection.security_quantity_sign("buy") == 1
      assert Projection.security_quantity_sign("inbound_delivery") == 1
      assert Projection.security_quantity_sign("sell") == -1
      assert Projection.security_quantity_sign("outbound_delivery") == -1

      # A transfer between own depots nets to zero at the security level; a
      # split scales rather than adds; the cash kinds move no shares.
      for kind <- Transaction.kinds() -- ~w(buy sell inbound_delivery outbound_delivery) do
        assert Projection.security_quantity_sign(kind) == 0, kind
      end
    end

    # The invariant the predicate exists for: "held" at the security level is
    # exactly "the positions fold leaves a non-zero total across all depots".
    test "held agrees with the positions fold on every security of the ledger" do
      %{} = world = delivery_world()

      totals =
        Transaction
        |> Repo.all()
        |> Positions.calculate()
        |> Enum.group_by(fn {{_account, security_id}, _qty} -> security_id end, &elem(&1, 1))
        |> Map.new(fn {security_id, qtys} -> {security_id, Enum.reduce(qtys, &Decimal.add/2)} end)

      from_fold =
        for {security_id, total} <- totals, not Decimal.equal?(total, 0), do: security_id

      assert Enum.sort(HeldSecurities.held_ids()) == Enum.sort(from_fold)

      assert Enum.sort(HeldSecurities.held_ids()) ==
               ids([world.delivered, world.moved, world.bought])
    end
  end

  # Acceptance criteria (closing-act finding F1, risk-tier): a split scales
  # the pre-split quantity, and bookings after it are in post-split units
  # (ADR-0028 §3), so a raw sum cannot answer for a security that split.
  # - Bought 10, split 2:1, sold 20: not held, although the raw sum is -10.
  # - Bought 10, split 2:1, sold 10: held (10 left), and agrees with the fold.
  # - A split in ANOTHER portfolio does not scale this portfolio's position.
  test "held agrees with the positions fold across a split followed by a trade" do
    world = base_world(name: "Split Held", cash_name: "SH Cash", depot_name: "SH Depot")
    sold_out = create_security!(name: "Sold Out Co", ticker: "SOC")
    half_sold = create_security!(name: "Half Sold Co", ticker: "HSC")

    split! = fn security ->
      book!(world, security, "split", nil, %{
        securities_account_id: nil,
        quantity: nil,
        date: ~D[2026-02-01],
        split_ratio_numerator: 2,
        split_ratio_denominator: 1
      })
    end

    for security <- [sold_out, half_sold] do
      buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])
      split!.(security)
    end

    Portfolixir.WorldFixtures.sell!(world, sold_out,
      quantity: "20",
      price: "50",
      date: ~D[2026-03-01]
    )

    Portfolixir.WorldFixtures.sell!(world, half_sold,
      quantity: "10",
      price: "50",
      date: ~D[2026-03-01]
    )

    totals =
      Transaction
      |> Repo.all()
      |> Positions.calculate()
      |> Enum.group_by(fn {{_account, security_id}, _qty} -> security_id end, &elem(&1, 1))
      |> Map.new(fn {security_id, qtys} -> {security_id, Enum.reduce(qtys, &Decimal.add/2)} end)

    from_fold = for {security_id, total} <- totals, not Decimal.equal?(total, 0), do: security_id

    assert Enum.sort(from_fold) == [half_sold.id]
    assert Enum.sort(HeldSecurities.held_ids()) == [half_sold.id]
    assert Repo.all(HeldSecurities.held_ids_query()) == [half_sold.id]
  end

  # User story (#839; ADR-0048 §2 for why an under-reporting filter matters):
  # As the operator whose depot was transferred in rather than bought,
  # I want every surface that asks "is it held?" to mean what the ledger
  # means by it,
  # so that a position acquired by an inbound delivery or moved by a security
  # transfer is never reported as one I do not own.
  #
  # Acceptance criteria:
  # - A security received only by an inbound delivery, or moved between own
  #   depots by a security transfer, is held on the catalog's holding_status
  #   filter, the research log's unreviewed positions and the events'
  #   held_only.
  # - A security delivered out in full is not held on any of them.
  test "every surface that asks 'is it held?' answers from the one predicate" do
    world = delivery_world()
    held = ids([world.delivered, world.moved, world.bought])
    not_held = ids([world.emptied, world.never])

    assert ids(Catalog.list_securities(holding_status: :held)) == held
    assert ids(Catalog.list_securities(holding_status: :not_held)) == not_held

    unreviewed = Knowledge.unreviewed_positions(today: @today)
    assert unreviewed |> Enum.map(& &1.security) |> ids() == held

    assert Enum.sort(Events.held_security_ids()) == held

    for security <- [world.delivered, world.moved, world.emptied, world.bought, world.never] do
      {:ok, _event} =
        Events.create_event(Actor.owner_ui(), %{
          security_id: security.id,
          kind: "earnings",
          date: ~D[2026-09-25],
          timing: "exact",
          source_quality: "primary"
        })
    end

    held_only = Events.upcoming(days: 7, today: @today, held_only: true)
    assert held_only |> Enum.map(& &1.security_id) |> Enum.sort() == held
  end
end
