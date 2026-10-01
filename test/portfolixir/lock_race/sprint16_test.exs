defmodule Portfolixir.LockRace.Sprint16Test do
  # Sprint 16's three lock-order cycles (Sprint 16 retrospective, "lock-order
  # cycles"), raced on two real connections by the lock-order harness
  # (Sprint 17, Lane G-2, #996): the importer against a rename (#884), the
  # ISIN writers (S6-R3, F49), and a security delete against a position
  # override (#417, #919, #954). Each case pauses the first writer inside the
  # conflict (after its first lock; the importer after its first booking,
  # which holds the account), lets the second run into it, and asserts that
  # neither deadlocks and that the two outcomes agree with each other.
  #
  # Each case was mutation-verified: with the Sprint 16 fix taken out, the
  # race fails with the 40P01 the release would have answered as a 500 (the
  # evidence is in the commit that adds them).
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits, and need no other test's load on the cores.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.LockRace
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  # The test process writes its fixtures and reads the outcome on the
  # scratch database too; the process ends with the test.
  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp owner, do: Actor.owner_ui()

  # User story:
  # As the operator renaming a cash account while an import books onto it,
  # I want the import and the rename to take their locks in one order,
  # so that one waits for the other and neither is aborted by a deadlock.
  #
  # Acceptance criteria:
  # - With the import held right after its first booking onto the account
  #   and the rename run into it, neither writer deadlocks.
  # - The import books both rows (one onto the account, one onto an account
  #   it creates), the rename lands, and the renamed account remembers its
  #   former name.
  test "an import and a rename of the account it books onto do not deadlock", %{db: db} do
    world = WorldFixtures.base_world(name: "Lock Order Import", cash_name: "Giro")

    preview =
      parse!([
        deposit("Giro", "100.00", "2025-01-02"),
        deposit("Fresh Savings", "50.00", "2025-01-03")
      ])

    {imported, renamed} =
      LockRace.race!(
        db,
        {fn -> Imports.apply(preview, %{portfolio_id: world.portfolio.id}) end,
         LockRace.query?(~s(INSERT INTO "transactions"))},
        fn -> Portfolios.update_cash_account(owner(), world.cash, %{name: "Giro Renamed"}) end
      )

    assert {:ok, %Result{created_transactions: 2}} = imported
    assert {:ok, %{name: "Giro Renamed"}} = renamed

    accounts =
      world.portfolio.id
      |> Portfolios.list_cash_accounts_for_portfolio()
      |> Enum.map(&{&1.name, &1.former_names})
      |> Enum.sort()

    assert accounts == [{"Fresh Savings", []}, {"Giro Renamed", ["Giro"]}]
  end

  # User story:
  # As the operator correcting a security's ISIN while an ISIN change of the
  # same security is recorded,
  # I want every ISIN writer to take the ISIN write lock before the
  # security's row,
  # so that the two queue and neither is aborted by a deadlock.
  #
  # Acceptance criteria:
  # - With the edit held right after its first lock and the ISIN change run
  #   into it, neither writer deadlocks.
  # - Both land in order: the edit's ISIN becomes the alias the change
  #   records, and the security carries the change's ISIN.
  test "an ISIN edit and an ISIN change of one security do not deadlock", %{db: db} do
    security =
      WorldFixtures.create_security!(name: "Lock Order AG", ticker: "LOAG", isin: "DE00000000A3")

    {edited, changed} =
      LockRace.race!(
        db,
        {fn -> Catalog.update_security(owner(), security, %{isin: "DE00000000B1"}) end,
         &LockRace.lock?/1},
        fn -> Catalog.record_isin_change(owner(), security, "DE00000000A3") end
      )

    assert {:ok, %{isin: "DE00000000B1"}} = edited
    assert {:ok, %{security: %{isin: "DE00000000A3"}, alias: alias_row}} = changed
    assert alias_row.former_isin == "DE00000000B1"
    assert Catalog.get_security(security.id).isin == "DE00000000A3"
  end

  # User story:
  # As the operator deleting a security while a position override for it is
  # cleared on one of my depots,
  # I want the delete and the override writer to take the depot before the
  # security,
  # so that one waits for the other and neither is aborted by a deadlock.
  #
  # Acceptance criteria:
  # - With the delete held right after its first lock and the clear run into
  #   it, neither writer deadlocks.
  # - The delete removes the security and its override; the clear, which
  #   finds the security gone, answers not found and writes nothing.
  test "a security delete and a clear of its position override do not deadlock", %{db: db} do
    world = WorldFixtures.base_world(name: "Lock Order Delete", depot_name: "Override Depot")
    security = WorldFixtures.create_security!(name: "Lock Order Delete AG", ticker: "LODA")
    :ok = Buckets.set_position_override(owner(), world.depot, security, [])

    {deleted, cleared} =
      LockRace.race!(
        db,
        {fn -> Catalog.delete_security(owner(), security) end, &LockRace.lock?/1},
        fn -> Buckets.clear_position_override(owner(), world.depot, security) end
      )

    assert {:ok, _deleted} = deleted
    assert {:error, :not_found} = cleared
    assert Catalog.get_security(security.id) == nil
    assert Buckets.position_override(world.depot.id, security.id) == :inherit
  end

  # -- a synthetic Portfolio Performance export --------------------------------

  defp deposit(account, amount, date) do
    %{
      "type" => "DEPOSIT",
      "account" => account,
      "date" => date,
      "currency" => "EUR",
      "amount" => Jason.Fragment.new(amount)
    }
  end

  defp parse!(rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "synthetic.json")
    preview
  end
end
