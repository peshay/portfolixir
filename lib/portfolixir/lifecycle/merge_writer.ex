defmodule Portfolixir.Lifecycle.MergeWriter do
  @moduledoc """
  The writes a lifecycle merge makes, row by row (ADR-0050 §7, §13).

  Every function runs inside the merge's one database transaction (each
  opens its own, which joins the caller's) and journals **one entry per
  row** it moves, restates or deletes, with the row as stored under its lock
  as the before-image (ADR-0017; E25 S6, F49). There is no `update_all` and
  no cascade: a moved row bumps the union of its before- and after-radius
  through `Portfolixir.Journal.record/3` (#851), and a delete removes the one
  row it names.

  A refusal answers `{:error, reason}` and leaves the rest to the caller,
  which rolls the whole merge back — inside the merge's transaction a failed
  write has already doomed it.

  Shared by the merge kinds: the cash merge today (`Portfolixir.Lifecycle.CashMerge`),
  the depot and the security merge behind it.
  """

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount

  @type refusal :: {:write_refused, String.t(), integer(), Changeset.t()} | :raced

  @doc """
  Re-points `row` and, on a balance anchor, restates its amount, through
  `Transaction.reassign_changeset/2`: `attrs` names the foreign-key columns
  that change (and `gross_amount` for an anchor). Journaled as one
  `transaction` update.
  """
  @spec reassign_transaction(Actor.t(), %Transaction{}, map()) ::
          {:ok, %Transaction{}} | {:error, refusal()}
  def reassign_transaction(%Actor{} = actor, %Transaction{} = row, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.update(:transaction, fn changes ->
      changes |> Journal.locked_row() |> Transaction.reassign_changeset(attrs)
    end)
    |> Journal.record(actor,
      resource_type: "transaction",
      operation: :update,
      source: :transaction,
      before: row
    )
    |> run(:transaction, "transaction", row.id)
  end

  @doc """
  Deletes `row` — an internal transfer (§5), a collapsed duplicate (§8) or a
  folded anchor (§7 step 4) — through the ledger's journaled delete: one
  `transaction` delete with the full before-image.
  """
  @spec delete_transaction(Actor.t(), %Transaction{}) ::
          {:ok, %Transaction{}} | {:error, refusal()}
  def delete_transaction(%Actor{} = actor, %Transaction{} = row) do
    case Ledger.delete_transaction(actor, row) do
      {:ok, deleted} ->
        {:ok, deleted}

      {:error, :not_found} ->
        {:error, :raced}

      {:error, %Changeset{} = changeset} ->
        {:error, {:write_refused, "transaction", row.id, changeset}}
    end
  end

  @doc """
  Retires the content hash `row` carried, under the merge record `record_id`
  (§3, obligation O1): `reason` `:internal_transfer`, or
  `:collapsed_duplicate` with the row that supersedes it. A row without a
  hash (booked by hand) has nothing to retire.
  """
  @spec retire_hash(Actor.t(), %Transaction{}, pos_integer(), atom(), integer() | nil) ::
          :ok | {:error, refusal()}
  def retire_hash(_actor, %Transaction{import_hash: nil}, _record_id, _reason, _superseded_by),
    do: :ok

  def retire_hash(%Actor{} = actor, %Transaction{} = row, record_id, reason, superseded_by) do
    case Lifecycle.retire_import_hash(actor, %{
           import_hash: row.import_hash,
           former_transaction_id: row.id,
           merge_record_id: record_id,
           reason: reason,
           superseded_by_transaction_id: superseded_by
         }) do
      {:ok, _retired} -> :ok
      {:error, changeset} -> {:error, {:write_refused, "retired_import_hash", row.id, changeset}}
    end
  end

  @doc """
  Re-points a depot linked to a merged-away cash account onto the survivor
  (§7 step 5), through `SecuritiesAccount.reassign_changeset/2`: one
  `securities_account` update.
  """
  @spec reassign_depot(Actor.t(), %SecuritiesAccount{}, integer()) ::
          {:ok, %SecuritiesAccount{}} | {:error, refusal()}
  def reassign_depot(%Actor{} = actor, %SecuritiesAccount{} = depot, cash_account_id)
      when is_integer(cash_account_id) do
    Multi.new()
    |> Multi.update(:securities_account, fn changes ->
      changes
      |> Journal.locked_row()
      |> SecuritiesAccount.reassign_changeset(%{cash_account_id: cash_account_id})
    end)
    |> Journal.record(actor,
      resource_type: "securities_account",
      operation: :update,
      source: :securities_account,
      before: depot
    )
    |> run(:securities_account, "securities_account", depot.id)
  end

  @doc """
  Appends `names` to `account`'s former names (§4, §7 step 7): the source's
  names, as `Portfolixir.Lifecycle.AccountNames.merge_names/2` answered them
  under the account-identity lock the merge took first, after the source is
  gone. One update of the account; no names, no write.
  """
  @spec append_former_names(Actor.t(), %CashAccount{} | %SecuritiesAccount{}, [String.t()]) ::
          {:ok, %CashAccount{} | %SecuritiesAccount{}} | {:error, refusal()}
  def append_former_names(_actor, account, []), do: {:ok, account}

  def append_former_names(%Actor{} = actor, %schema{} = account, names) when is_list(names) do
    resource_type = if schema == CashAccount, do: "cash_account", else: "securities_account"

    Multi.new()
    |> Multi.update(:account, fn changes ->
      stored = Journal.locked_row(changes)

      case stored do
        %CashAccount{} ->
          CashAccount.former_names_changeset(stored, stored.former_names ++ names)

        %SecuritiesAccount{} ->
          SecuritiesAccount.former_names_changeset(stored, stored.former_names ++ names)
      end
    end)
    |> Journal.record(actor,
      resource_type: resource_type,
      operation: :update,
      source: :account,
      before: account
    )
    |> run(:account, resource_type, account.id)
  end

  defp run(multi, step, resource_type, id) do
    case Portfolixir.Repo.transaction(multi) do
      {:ok, changes} ->
        {:ok, Map.fetch!(changes, step)}

      {:error, ^step, %Changeset{} = changeset, _changes} ->
        {:error, {:write_refused, resource_type, id, changeset}}

      {:error, {:journal_lock, _}, :not_found, _changes} ->
        {:error, :raced}
    end
  end
end
