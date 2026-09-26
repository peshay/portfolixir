defmodule Portfolixir.Lifecycle.SecurityMergeLegacySplitTest do
  # ADR-0050 §1, §3 and §9 against the one legacy state the record did not
  # foresee for splits (the L3–L5 review round, finding F3; risk-tier:
  # idempotency, ADR-0036). §1 says a split holds no import hash, and the
  # check behind it is NOT VALID on an instance where an imported row was
  # re-typed to `split` before this release: such a legacy split keeps its
  # hash, and every edit of it is refused by the check. The cash merge
  # already handles the anchor half (cash_merge_legacy_anchor_test.exs); the
  # security merge now does the same for a split: one it collapses is
  # deleted, which the check allows, with its hash retired so the
  # held-or-retired set still only grows (O1); one it would have to move is
  # refused up front with a named reason and the remedy the upgrade logged,
  # instead of failing at the database after the operator confirmed.
  #
  # async: false — the test drops and re-adds a constraint on `transactions`,
  # which takes a lock every concurrent test on the ledger would wait on.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.RetiredImportHash
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.Api.V1.MergeJSON

  @migration "priv/repo/migrations/20260925130000_create_retired_import_hashes.exs"
  @migration_module Portfolixir.Repo.Migrations.CreateRetiredImportHashes
  @constraint "transactions_import_hash_kind_check"

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Legacy Split World",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Broker cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot 1"
      })

    # One name for both, so the stored identity of either resolves to the
    # survivor (§9's precondition) and the test is about the split alone.
    %{
      portfolio: portfolio,
      cash: cash,
      depot: depot,
      target: security!("Synthetic Split Fund"),
      source: security!("Synthetic Split Fund")
    }
  end

  # User story:
  # As the operator of an instance where an imported booking of a duplicate
  # security was once re-typed into a split,
  # I want the merge to refuse up front when it would have to move that
  # split, naming it and the remedy,
  # so that it never fails at the database after I confirmed it.
  #
  # Acceptance criteria:
  # - The preview and the apply answer {:refused, guards} with
  #   legacy_hashed_split failed, naming the row in its detail and, as
  #   data, its id and date.
  # - Nothing is written.
  test "a legacy split the merge would have to move refuses it by name", ctx do
    buy!(ctx, ctx.source, "10", ~D[2025-01-10])
    legacy = legacy_split!(ctx, ctx.source, ~D[2025-03-01], "synthetic-legacy-split-move")
    buy!(ctx, ctx.target, "4", ~D[2025-04-01])

    assert {:error, {:refused, guards}} =
             Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)

    assert %{passed: false, detail: detail, splits: splits} =
             Enum.find(guards, &(&1.code == :legacy_hashed_split))

    assert detail =~ "##{legacy.id}"
    assert splits == [%{id: legacy.id, date: ~D[2025-03-01]}]

    # On the wire, errors.splits names it beside errors.guards.
    assert MergeJSON.guard_facts(Enum.find(guards, &(&1.code == :legacy_hashed_split))) == %{
             splits: [%{id: legacy.id, date: "2025-03-01"}]
           }

    assert {:error, {:refused, _guards}} =
             Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
               plan_digest: "sha256:whatever",
               collapse_key_equal: false
             })

    assert Repo.get!(Transaction, legacy.id).security_id == ctx.source.id
    assert Repo.all(RetiredImportHash) == []
  end

  # User story:
  # As the operator of such an instance whose survivor carries the same
  # split,
  # I want the merge that collapses the legacy split into the survivor's to
  # go through and keep its hash retired,
  # so that a re-import of the export it came from still books nothing.
  #
  # Acceptance criteria:
  # - The legacy split is deleted, its hash retired as a collapsed_duplicate
  #   superseded by the survivor's split of that day.
  # - The survivor holds both positions scaled once.
  test "a collapsed legacy split is deleted and its hash retired", ctx do
    buy!(ctx, ctx.target, "4", ~D[2025-01-05])
    buy!(ctx, ctx.source, "10", ~D[2025-01-10])

    {:ok, [twin]} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: ctx.target.id,
        date: ~D[2025-03-01],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    legacy = legacy_split!(ctx, ctx.source, ~D[2025-03-01], "synthetic-legacy-split-fold")

    {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
    assert Enum.all?(preview.guards, & &1.passed)

    {:ok, record, :applied} =
      Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: false
      })

    Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

    refute Repo.get(Transaction, legacy.id)
    assert Repo.get(Transaction, twin.id)

    assert [
             %RetiredImportHash{
               import_hash: "synthetic-legacy-split-fold",
               reason: :collapsed_duplicate,
               former_transaction_id: former_id,
               superseded_by_transaction_id: superseded_by,
               merge_record_id: record_id
             }
           ] = Repo.all(RetiredImportHash)

    assert former_id == legacy.id
    assert superseded_by == twin.id
    assert record_id == record.id

    assert Ledger.positions_for_portfolio(ctx.portfolio.id)
           |> Map.get({ctx.depot.id, ctx.target.id})
           |> Decimal.equal?(Decimal.new("28"))
  end

  # --- world ------------------------------------------------------------------

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "etf"
      })

    security
  end

  defp buy!(ctx, security, quantity, date) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: ctx.portfolio.id,
        type: "buy",
        date: date,
        security_id: security.id,
        securities_account_id: ctx.depot.id,
        cash_account_id: ctx.cash.id,
        quantity: quantity,
        price: "10.00",
        currency_code: "EUR"
      })

    tx
  end

  # The state the old writer could leave: an imported dividend, hashed,
  # whose type a later edit changed to a 2:1 split, with the check re-added
  # NOT VALID by the migration's own step, as on an upgraded instance.
  defp legacy_split!(ctx, security, date, hash) do
    {:ok, dividend} =
      Ledger.create_transaction(
        Actor.import_session(),
        %{
          portfolio_id: ctx.portfolio.id,
          type: "dividend",
          date: date,
          security_id: security.id,
          securities_account_id: ctx.depot.id,
          cash_account_id: ctx.cash.id,
          gross_amount: "1.00",
          currency_code: "EUR"
        },
        import_hash: hash
      )

    Repo.query!("ALTER TABLE transactions DROP CONSTRAINT #{@constraint}")

    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

      Repo.query!(
        """
        UPDATE transactions
        SET type = 'split', split_ratio_numerator = 2, split_ratio_denominator = 1,
            quantity = NULL, price = NULL, gross_amount = NULL, security_amount = NULL,
            settlement_amount = NULL, settlement_fx_rate = NULL, cash_account_id = NULL,
            counter_cash_account_id = NULL, securities_account_id = NULL,
            counter_securities_account_id = NULL
        WHERE id = $1
        """,
        [dividend.id]
      )
    end)

    capture_log(fn -> migration().add_kind_check(Repo) end)
    Repo.get!(Transaction, dividend.id)
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
