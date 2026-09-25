defmodule Portfolixir.Derived.BeforeImageRadiusTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Ledger

  defp portfolio_version(portfolio),
    do: DataVersion.current(DataVersion.portfolio_basis(portfolio.id))

  defp security_version(security),
    do: DataVersion.current(DataVersion.security_basis(security.id))

  # User story (#851, ADR-0039 §2–§5, risk-tier attention):
  # As the operator editing a booking,
  # I want the edit to invalidate what the booking USED to affect as well as
  # what it affects now,
  # so that a walk or a metric memoised for the old portfolio or the old
  # security is never served stale after the booking moved away from it.
  #
  # Acceptance criteria:
  # - Moving a transaction from security A to security B bumps A's security
  #   basis, not only B's.
  # - Moving a transaction from portfolio P to portfolio Q bumps P's
  #   portfolio basis, not only Q's.
  # - The radius is the union of both images; an unresolvable image still
  #   widens (the widening invariant is unchanged).
  test "an edit that moves a transaction bumps the bases of its before-image too" do
    world = base_world(name: "Before")
    other = base_world(name: "After")
    a = create_security!(name: "Security A", ticker: "SA")
    b = create_security!(name: "Security B", ticker: "SB")

    tx = buy!(world, a, quantity: "1", price: "10")

    a_before = security_version(a)
    {:ok, moved} = Ledger.update_transaction(Actor.owner_ui(), tx, %{security_id: b.id})

    assert security_version(a) > a_before,
           "the old security's basis must bump when a booking leaves it"

    p_before = portfolio_version(world.portfolio)

    {:ok, _} =
      Ledger.update_transaction(Actor.owner_ui(), moved, %{
        portfolio_id: other.portfolio.id,
        securities_account_id: other.depot.id,
        cash_account_id: other.cash.id
      })

    assert portfolio_version(world.portfolio) > p_before,
           "the old portfolio's basis must bump when a booking leaves it"
  end

  # User story (E25 S6 review round, M3):
  # As the operator whose agent resends a definition it already stored,
  # I want a write that changes nothing to leave the derived values alone,
  # so that a no-op never makes every portfolio's figures recompute.
  #
  # Acceptance criteria:
  # - An update that changes nothing writes no journal entry and bumps no
  #   basis: resending a view's sets leaves the global basis and each
  #   portfolio's basis where they were; resending a booking's own values
  #   leaves its portfolio's and its security's bases.
  # - A real change still bumps them.
  test "an update that changes nothing bumps no basis" do
    world = base_world(name: "Unchanged")
    security = create_security!(name: "Security U", ticker: "SU")
    tx = buy!(world, security, quantity: "1", price: "10")

    {:ok, bucket} =
      Portfolixir.Buckets.create_bucket(Actor.owner_ui(), %{
        name: "Resent #{System.unique_integer([:positive])}"
      })

    {:ok, view} =
      Portfolixir.Buckets.create_view(Actor.owner_ui(), %{
        name: "Resent view #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Portfolixir.Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    global = fn -> DataVersion.current(DataVersion.global_basis()) end

    versions = fn ->
      {global.(), portfolio_version(world.portfolio), security_version(security)}
    end

    before = versions.()
    :ok = Portfolixir.Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    {:ok, _} = Ledger.update_transaction(Actor.owner_ui(), tx, %{notes: tx.notes})
    assert versions.() == before

    {:ok, _} = Ledger.update_transaction(Actor.owner_ui(), tx, %{notes: "changed"})
    assert portfolio_version(world.portfolio) > elem(before, 1)
  end
end
