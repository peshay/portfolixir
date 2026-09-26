defmodule Portfolixir.Lifecycle.ImportHashKindCheckTest do
  # ADR-0050 §1, §3 (L1, #417; review round #884; risk-tier: import
  # idempotency, ADR-0036). The migration that creates `retired_import_hashes`
  # also adds `transactions_import_hash_kind_check`: no balance anchor and no
  # split carries an import hash. Neither kind is ever imported, but before
  # this release `PATCH /api/v1/transactions/:id` could re-type an imported,
  # hashed row to `balance_adjustment` and keep its hash. A validated CHECK
  # would then stop the upgrade on that instance.
  #
  # The migrator cannot be driven under the SQL sandbox, so, like
  # target_plans_migration_test.exs, this test rebuilds the state before the
  # migration inside the sandbox transaction (the constraint dropped, a legacy
  # row seeded the way the old writer made it) and runs the migration's own
  # step on it. Everything rolls back at the end of the test.
  #
  # async: false — the test drops and re-adds a constraint on `transactions`,
  # which takes a lock every concurrent test on the ledger would wait on.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureLog

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.WorldFixtures

  @migration "priv/repo/migrations/20260925130000_create_retired_import_hashes.exs"
  @migration_module Portfolixir.Repo.Migrations.CreateRetiredImportHashes
  @constraint "transactions_import_hash_kind_check"

  setup do
    world = WorldFixtures.base_world(name: "Kind Check World")
    Repo.query!("ALTER TABLE transactions DROP CONSTRAINT #{@constraint}")
    %{world: world}
  end

  # User story:
  # As the operator whose agent once re-typed an imported deposit into a
  # balance anchor over the API,
  # I want the upgrade to finish and to tell me which row is affected,
  # so that my instance still boots, the row keeps the content hash that
  # stops a re-import from booking it twice, and no new row reaches that
  # state.
  #
  # Acceptance criteria:
  # - With such a row, the check is added NOT VALID: the upgrade does not
  #   fail, and the row keeps its type and its hash.
  # - Each such row is logged with its id, its kind and the remedy.
  # - A new anchor with a hash is still refused by the database.
  test "a re-typed hashed row does not stop the upgrade, and is named", %{world: world} do
    legacy = retyped_anchor!(world, "synthetic-legacy-hash")
    legacy_id = legacy.id

    log =
      capture_log(fn ->
        assert [%{id: ^legacy_id, type: "balance_adjustment"}] = run_kind_check!()
      end)

    assert validated?() == false
    assert log =~ "transaction ##{legacy.id}"
    assert log =~ "balance_adjustment"

    stored = Repo.get!(Transaction, legacy.id)
    assert stored.type == "balance_adjustment"
    assert stored.import_hash == "synthetic-legacy-hash"

    assert {:error, changeset} =
             Ledger.create_transaction(
               Actor.import_session(),
               anchor_attrs(world, ~D[2026-02-02]),
               import_hash: "synthetic-new-anchor"
             )

    assert %{import_hash: ["is never set on a balance anchor or a split"]} =
             errors_on(changeset)
  end

  test "without such a row the check is added and validated", %{world: world} do
    {:ok, _deposit} =
      Ledger.create_transaction(Actor.import_session(), deposit_attrs(world),
        import_hash: "synthetic-deposit"
      )

    log = capture_log(fn -> assert run_kind_check!() == [] end)

    assert validated?() == true
    refute log =~ "import hash"
  end

  # --- helpers ---------------------------------------------------------------

  # The migration's own step, on the sandbox connection.
  defp run_kind_check!, do: migration().add_kind_check(Repo)

  defp migration do
    case Code.ensure_loaded(@migration_module) do
      {:module, module} ->
        module

      {:error, _not_loaded} ->
        [{module, _bytecode}] = Code.require_file(@migration)
        module
    end
  end

  defp validated? do
    %{rows: [[validated]]} =
      Repo.query!("SELECT convalidated FROM pg_constraint WHERE conname = $1", [@constraint])

    validated
  end

  # The state the old writer could leave: an imported deposit, hashed, whose
  # type a later edit changed to an anchor. Seeded through the journal as the
  # old public update made it.
  defp retyped_anchor!(world, hash) do
    {:ok, deposit} =
      Ledger.create_transaction(Actor.import_session(), deposit_attrs(world), import_hash: hash)

    {:ok, %{transaction: anchor}} =
      Multi.new()
      |> Multi.update(:transaction, Ecto.Changeset.change(deposit, type: "balance_adjustment"))
      |> Journal.record(Actor.api_token_rw("synthetic-agent"),
        resource_type: "transaction",
        operation: :update,
        source: :transaction,
        before: deposit
      )
      |> Repo.transaction()

    anchor
  end

  defp deposit_attrs(world) do
    %{
      type: "deposit",
      portfolio_id: world.portfolio.id,
      cash_account_id: world.cash.id,
      currency_code: "EUR",
      date: ~D[2026-02-01],
      gross_amount: Decimal.new("250")
    }
  end

  defp anchor_attrs(world, date) do
    %{
      type: "balance_adjustment",
      portfolio_id: world.portfolio.id,
      cash_account_id: world.cash.id,
      currency_code: "EUR",
      date: date,
      gross_amount: Decimal.new("100")
    }
  end
end
