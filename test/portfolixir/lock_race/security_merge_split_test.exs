defmodule Portfolixir.LockRace.SecurityMergeSplitTest do
  # A security merge against a split of its target (security review
  # 2026-10-12, H60), raced on two real connections by the lock-order harness
  # (#996). The merge locks both securities FOR UPDATE, after the depots
  # (ADR-0050 §10), and then their bookings; the split booking and the
  # whole-split delete take the security's split-event lock and then read
  # the event's portfolios. Both now hold the security's row in key-share
  # mode right after the split-event lock, before that read, so a merge in
  # flight holds the split back until it has committed, and a split in
  # flight holds the merge back until the merge can read what it booked.
  # The split flow locks no depot, so the merge's order is kept.
  #
  # The table of every writer's lock order is `Portfolixir.LockTable`.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits, and need no other test's load on the cores.
  #
  # Every name, figure and date is synthetic.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @moduletag :lock_race

  @bought_on ~D[2026-08-03]
  @split_on ~D[2026-09-15]

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp owner, do: Actor.owner_ui()
  defp agent, do: Actor.api_token_rw("synthetic-agent")

  # A portfolio with its own cash account and depot holding 10 units of
  # `security`, bought before the split day.
  defp holder!(name, security) do
    world =
      WorldFixtures.base_world(name: name, cash_name: "#{name} Cash", depot_name: "#{name} Depot")

    WorldFixtures.deposit!(world, "1000", @bought_on)
    WorldFixtures.buy!(world, security, quantity: "10", price: "50", date: @bought_on)
    world
  end

  # Two securities of one name, so the merge's resolvability guard passes:
  # the target held by portfolio A, the source by portfolio B. The merge
  # moves B's bookings onto the target.
  defp world(name) do
    target = WorldFixtures.create_security!(name: "#{name} AG", ticker: nil)
    source = WorldFixtures.create_security!(name: "#{name} AG", ticker: nil)
    a = holder!("#{name} A", target)
    b = holder!("#{name} B", source)
    %{target: target, source: source, a: a, b: b}
  end

  defp split_attrs(security),
    do: %{security_id: security.id, date: @split_on, ratio_numerator: 2, ratio_denominator: 1}

  # The operator's approved preview, read before the race.
  defp approved(w) do
    {:ok, preview} = Lifecycle.preview_security_merge(w.source.id, w.target.id)
    preview.plan_digest
  end

  defp merge(w, digest) do
    Lifecycle.merge_security(agent(), w.source.id, w.target.id, %{
      plan_digest: digest,
      collapse_key_equal: false
    })
  end

  defp split_portfolios(security) do
    Repo.all(
      from(t in Transaction,
        where: t.type == "split" and t.security_id == ^security.id and t.date == ^@split_on,
        select: t.portfolio_id,
        order_by: t.portfolio_id
      )
    )
  end

  # The ledger's own fold of a holder's position in `security` in its depot.
  defp quantity(holder, security) do
    holder.portfolio.id
    |> Ledger.positions_for_portfolio()
    |> Map.get({holder.depot.id, security.id})
  end

  defp source_exists?(w), do: Repo.get(Security, w.source.id) != nil

  # The merge's lock on the two securities, and on their bookings.
  defp securities_lock?(%{source: "securities", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp securities_lock?(_metadata), do: false

  defp bookings_lock?(%{source: "transactions", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp bookings_lock?(_metadata), do: false

  # User story (security review 2026-10-12, H60; ADR-0050 §9, §10; ADR-0036,
  # risk-tier):
  # As the operator merging a security into another while a split of the
  # surviving security is booked,
  # I want the split and the merge to take turns,
  # so that the split scales every portfolio that holds the security once the
  # merge has moved its bookings, or the merge is refused because of the
  # split, and never a position the split left unscaled.
  #
  # Acceptance criteria:
  # - With the merge held after its lock on the securities, the split waits
  #   for it; the merge applies, and the split then books a row for both
  #   portfolios, each of which holds 20 units of the target.
  # - With the split held after its first row, the merge waits for it and is
  #   refused (the two securities' split events differ); the source keeps
  #   portfolio B's 10 units, and the split stands in portfolio A alone.
  # - Neither writer deadlocks.
  test "a split of the target waits for the merge and scales every merged-in portfolio",
       %{db: db} do
    w = world("Merge Before Split")
    digest = approved(w)

    {merged, booked} =
      LockRace.race!(db, {fn -> merge(w, digest) end, &securities_lock?/1}, fn ->
        Splits.book_split(owner(), split_attrs(w.target))
      end)

    assert {:ok, _record, :applied} = merged
    assert {:ok, [_a, _b]} = booked
    assert split_portfolios(w.target) == Enum.sort([w.a.portfolio.id, w.b.portfolio.id])
    assert quantity(w.a, w.target) == Decimal.new("20.000000")
    assert quantity(w.b, w.target) == Decimal.new("20.000000")
    refute source_exists?(w)
  end

  test "a merge waits for a split of its target and is refused", %{db: db} do
    w = world("Split Before Merge")
    digest = approved(w)

    {booked, merged} =
      LockRace.race!(
        db,
        {fn -> Splits.book_split(owner(), split_attrs(w.target)) end,
         LockRace.query?(~s(INSERT INTO "transactions"))},
        fn -> merge(w, digest) end
      )

    assert {:ok, [_a]} = booked
    assert {:error, {:refused, guards}} = merged
    assert Enum.any?(guards, &(&1.code == :split_event_mismatch and &1.passed == false))
    assert source_exists?(w)
    assert split_portfolios(w.target) == [w.a.portfolio.id]
    assert quantity(w.a, w.target) == Decimal.new("20.000000")
    assert quantity(w.b, w.source) == Decimal.new("10.000000000000")
  end

  # User story (security review 2026-10-12, H60; ADR-0028 §1; ADR-0036,
  # risk-tier):
  # As the operator deleting a split event of a security while the security
  # carrying the same event is merged into it,
  # I want the delete and the merge to take turns,
  # so that a delete that answers success leaves no row of the event in any
  # portfolio.
  #
  # Acceptance criteria:
  # - With the merge held after its lock on the bookings, the delete waits
  #   for it; the merge moves portfolio B's split row onto the target, and
  #   the delete then removes both rows: no portfolio keeps the split, and
  #   both hold 10 units of the target.
  # - With the delete held after its lock on the event's rows, the merge
  #   waits for it and is refused (the two securities' split events now
  #   differ); the source keeps its split, the target has none.
  # - Neither writer deadlocks.
  test "a whole-split delete waits for the merge and removes the row it moved", %{db: db} do
    w = world("Merge Before Delete")
    {:ok, [row_a]} = Splits.book_split(owner(), split_attrs(w.target))
    {:ok, [_row_b]} = Splits.book_split(owner(), split_attrs(w.source))
    digest = approved(w)

    {merged, deleted} =
      LockRace.race!(db, {fn -> merge(w, digest) end, &bookings_lock?/1}, fn ->
        Splits.delete_split(owner(), row_a)
      end)

    assert {:ok, _record, :applied} = merged
    assert {:ok, [_a, _b]} = deleted
    assert split_portfolios(w.target) == []
    assert quantity(w.a, w.target) == Decimal.new("10.000000000000")
    assert quantity(w.b, w.target) == Decimal.new("10.000000000000")
    refute source_exists?(w)
  end

  test "a merge waits for a whole-split delete of its target and is refused", %{db: db} do
    w = world("Delete Before Merge")
    {:ok, [row_a]} = Splits.book_split(owner(), split_attrs(w.target))
    {:ok, [_row_b]} = Splits.book_split(owner(), split_attrs(w.source))
    digest = approved(w)

    {deleted, merged} =
      LockRace.race!(
        db,
        {fn -> Splits.delete_split(owner(), row_a) end, &bookings_lock?/1},
        fn -> merge(w, digest) end
      )

    assert {:ok, [_a]} = deleted
    assert {:error, {:refused, guards}} = merged
    assert Enum.any?(guards, &(&1.code == :split_event_mismatch and &1.passed == false))
    assert source_exists?(w)
    assert split_portfolios(w.target) == []
    assert split_portfolios(w.source) == [w.b.portfolio.id]
    assert quantity(w.a, w.target) == Decimal.new("10.000000000000")
    assert quantity(w.b, w.source) == Decimal.new("20.000000")
  end

  # The two sequential orders the races must each end like.
  test "a split booked after the merge fans out to every merged-in portfolio" do
    w = world("Sequential Merge First")
    assert {:ok, _record, :applied} = merge(w, approved(w))
    assert {:ok, [_a, _b]} = Splits.book_split(owner(), split_attrs(w.target))
    assert split_portfolios(w.target) == Enum.sort([w.a.portfolio.id, w.b.portfolio.id])
    assert quantity(w.a, w.target) == Decimal.new("20.000000")
    assert quantity(w.b, w.target) == Decimal.new("20.000000")
  end

  test "a merge previewed after a split of the target is refused" do
    w = world("Sequential Split First")
    assert {:ok, [_row]} = Splits.book_split(owner(), split_attrs(w.target))

    assert {:error, {:refused, guards}} =
             Lifecycle.preview_security_merge(w.source.id, w.target.id)

    assert Enum.any?(guards, &(&1.code == :split_event_mismatch and &1.passed == false))
  end
end
