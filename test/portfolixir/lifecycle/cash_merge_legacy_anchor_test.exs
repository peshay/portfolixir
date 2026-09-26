defmodule Portfolixir.Lifecycle.CashMergeLegacyAnchorTest do
  # ADR-0050 §1, §3 and §7 step 4 against the one state the record did not
  # foresee (L3a, #328; risk-tier: idempotency, ADR-0036). §1 says an anchor
  # holds no import hash, and the check behind it is NOT VALID on an
  # instance where an imported row was re-typed to `balance_adjustment`
  # before this release (L1's review round): such a legacy anchor keeps its
  # hash, and every edit of it is refused by the check. A merge deletes an
  # anchor it folds, which the check allows, and retires its hash so the
  # held-or-retired set still only grows; an anchor it would have to restate
  # or move cannot be written, so the merge refuses up front with a named
  # reason and the remedy the upgrade logged, instead of failing at the
  # database.
  #
  # async: false — the test drops and re-adds a constraint on `transactions`,
  # which takes a lock every concurrent test on the ledger would wait on.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.RetiredImportHash
  alias Portfolixir.Portfolios

  @migration "priv/repo/migrations/20260925130000_create_retired_import_hashes.exs"
  @migration_module Portfolixir.Repo.Migrations.CreateRetiredImportHashes
  @constraint "transactions_import_hash_kind_check"

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Legacy World",
        base_currency_code: "EUR"
      })

    %{
      portfolio: portfolio,
      source: cash!(portfolio, "Savings (old)"),
      target: cash!(portfolio, "Savings")
    }
  end

  # User story:
  # As the operator of an instance where an agent once re-typed an imported
  # deposit into a balance anchor,
  # I want a merge that folds that anchor into the survivor's anchor of the
  # same day to go through and keep its hash retired,
  # so that the re-import of the export it came from still books nothing.
  #
  # Acceptance criteria:
  # - The folded legacy anchor is deleted, its hash retired as a
  #   collapsed_duplicate superseded by the anchor that absorbs it.
  # - The survivor's anchor holds the sum of both.
  test "a folded legacy anchor is deleted and its hash retired", ctx do
    deposit!(ctx, ctx.source, "100.00", ~D[2025-01-02])
    legacy = legacy_anchor!(ctx, ctx.source, "300.00", ~D[2025-06-30], "synthetic-legacy-fold")
    absorbing = anchor!(ctx.target, "700.00", ~D[2025-06-30])

    {:ok, preview} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
    assert Enum.all?(preview.guards, & &1.passed)

    {:ok, record, :applied} =
      Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: false
      })

    Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

    refute Repo.get(Transaction, legacy.id)

    assert Decimal.equal?(
             Repo.get!(Transaction, absorbing.id).gross_amount,
             Decimal.new("1000.00")
           )

    assert [
             %RetiredImportHash{
               import_hash: "synthetic-legacy-fold",
               reason: :collapsed_duplicate,
               superseded_by_transaction_id: superseded_by,
               merge_record_id: record_id
             }
           ] = Repo.all(RetiredImportHash)

    assert superseded_by == absorbing.id
    assert record_id == record.id
  end

  # User story:
  # As the operator whose legacy anchor would have to be restated or moved,
  # I want the merge refused with a reason that names the row and the remedy,
  # so that it never fails half-way at the database.
  #
  # Acceptance criteria:
  # - The preview and the apply answer {:refused, guards} with the
  #   legacy_hashed_anchor guard failed, naming the transaction id in its
  #   detail and, as data, the anchor's id, date and account.
  # - Nothing is written.
  test "a legacy anchor that would have to be restated or moved refuses the merge", ctx do
    deposit!(ctx, ctx.target, "100.00", ~D[2025-01-02])
    legacy = legacy_anchor!(ctx, ctx.source, "300.00", ~D[2025-06-30], "synthetic-legacy-move")

    assert {:error, {:refused, guards}} =
             Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)

    assert %{passed: false, detail: detail, anchors: anchors} =
             Enum.find(guards, &(&1.code == :legacy_hashed_anchor))

    assert detail =~ "##{legacy.id}"

    # The refusal names the row as data too, so a dialog can say which set
    # balance to change (review finding M-4).
    assert anchors == [%{id: legacy.id, date: ~D[2025-06-30], cash_account_id: ctx.source.id}]

    assert {:error, {:refused, _guards}} =
             Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
               plan_digest: "sha256:whatever",
               collapse_key_equal: false
             })

    assert Repo.get!(Transaction, legacy.id).cash_account_id == ctx.source.id
    assert Repo.all(RetiredImportHash) == []
  end

  # --- world ------------------------------------------------------------------

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  defp deposit!(ctx, account, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: account.id,
        type: "deposit",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp anchor!(account, amount, date) do
    {:ok, tx} = Ledger.set_cash_balance(agent(), account, %{date: date, amount: amount})
    tx
  end

  # The state the old writer could leave: an imported deposit, hashed, whose
  # type a later edit changed to an anchor (the absolute balance now), with
  # the check re-added NOT VALID by the migration's own step, as on an
  # upgraded instance.
  defp legacy_anchor!(ctx, account, amount, date, hash) do
    {:ok, deposit} =
      Ledger.create_transaction(
        Actor.import_session(),
        %{
          portfolio_id: ctx.portfolio.id,
          cash_account_id: account.id,
          type: "deposit",
          date: date,
          gross_amount: amount,
          currency_code: "EUR"
        },
        import_hash: hash
      )

    Repo.query!("ALTER TABLE transactions DROP CONSTRAINT #{@constraint}")

    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

      Repo.query!("UPDATE transactions SET type = 'balance_adjustment' WHERE id = $1", [
        deposit.id
      ])
    end)

    capture_log(fn -> migration().add_kind_check(Repo) end)
    Repo.get!(Transaction, deposit.id)
  end

  defp migration do
    case Code.ensure_loaded(@migration_module) do
      {:module, module} ->
        module

      {:error, _not_loaded} ->
        [{module, _bytecode}] = Code.require_file(@migration)
        module
    end
  end
end
