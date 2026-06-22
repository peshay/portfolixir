defmodule Portfolixir.Portfolios do
  @moduledoc "Portfolio and linked account setup."

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo

  def list_portfolios do
    from(portfolio in Portfolio, order_by: [asc: portfolio.id])
    |> Repo.all()
    |> Enum.map(&load_cash_target/1)
  end

  def count_portfolios do
    Repo.aggregate(Portfolio, :count, :id)
  end

  def first_portfolio do
    from(portfolio in Portfolio, order_by: [asc: portfolio.id], limit: 1)
    |> Repo.one()
    |> load_cash_target()
  end

  def get_portfolio!(id), do: Repo.get!(Portfolio, id) |> load_cash_target()

  def get_portfolio(id) when is_integer(id), do: Repo.get(Portfolio, id) |> load_cash_target()

  @doc """
  Creates a portfolio on behalf of `actor` (FR-28). The `portfolios` row and its
  audit-journal entry commit in one transaction (ADR-0017); the table is
  guard-armed, so this is the only sanctioned create path. The virtual
  cash-target weight is persisted separately to its own (un-armed) target table,
  mirroring the prior behavior.
  """
  def create_portfolio(%Actor{} = actor, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.insert(:portfolio, Portfolio.changeset(%Portfolio{}, attrs))
    |> Journal.record(actor, resource_type: "portfolio", operation: :create, source: :portfolio)
    |> Repo.transaction()
    |> portfolio_write_result()
    |> persist_cash_target()
  end

  @doc """
  Updates a portfolio on behalf of `actor` (FR-28). The update and its audit
  journal entry (with the pre-image as `before`) commit in one transaction.
  """
  def update_portfolio(%Actor{} = actor, %Portfolio{} = portfolio, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.update(:portfolio, Portfolio.changeset(portfolio, attrs))
    |> Journal.record(actor,
      resource_type: "portfolio",
      operation: :update,
      source: :portfolio,
      before: portfolio
    )
    |> Repo.transaction()
    |> portfolio_write_result()
    |> persist_cash_target()
  end

  defp portfolio_write_result({:ok, %{portfolio: portfolio}}), do: {:ok, portfolio}

  defp portfolio_write_result({:error, :portfolio, %Ecto.Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  # Unwraps a journaled account Multi (the business write under `key`, plus the
  # journal steps) into the bare `{:ok, record}` / `{:error, changeset}` the
  # callers expect.
  defp account_write_result({:ok, changes}, key), do: {:ok, Map.fetch!(changes, key)}

  defp account_write_result({:error, key, %Ecto.Changeset{} = changeset, _changes}, key),
    do: {:error, changeset}

  @doc """
  Sets (or clears) a portfolio's cash target weight, the SOLL share of cash in
  the allocation's 100% basis (securities + counting cash, see issue #335).

  Since ADR-0020 the cash target lives on the portfolio's Gesamt cash plan
  (`Portfolixir.Portfolios.Targets`); this writes there and returns the portfolio
  with the value loaded into its virtual field, preserving the prior contract.

  `weight` is a fraction in `[0, 1]` or `nil` to stop steering a cash quote.
  Returns `{:ok, %Portfolio{}}` or `{:error, %Ecto.Changeset{}}` (a weight out
  of range).
  """
  def set_cash_target(%Portfolio{} = portfolio, weight) do
    case Targets.set_cash_target(portfolio.id, weight) do
      :ok -> {:ok, %{portfolio | cash_target_weight: weight}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # Populates the virtual cash_target_weight from the portfolio-wide Gesamt cash
  # plan, so reads keep exposing the value the column used to carry (ADR-0020).
  defp load_cash_target(nil), do: nil

  defp load_cash_target(%Portfolio{} = portfolio) do
    %{portfolio | cash_target_weight: Targets.get_cash_target(portfolio.id)}
  end

  # Write-through: after a portfolio write, persist the virtual cash target onto
  # the Gesamt cash plan when the changeset carried one (it casts and validates a
  # `[0, 1]` fraction). A nil weight clears the steered quote.
  defp persist_cash_target({:ok, %Portfolio{} = portfolio}) do
    weight = portfolio.cash_target_weight
    :ok = Targets.set_cash_target(portfolio.id, weight)
    {:ok, %{portfolio | cash_target_weight: weight}}
  end

  defp persist_cash_target(other), do: other

  def list_cash_accounts do
    Repo.all(from(account in CashAccount, order_by: [asc: account.name, asc: account.id]))
  end

  def list_cash_accounts_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(account in CashAccount,
        where: account.portfolio_id == ^portfolio_id,
        order_by: [asc: account.name, asc: account.id]
      )
    )
  end

  def count_cash_accounts do
    Repo.aggregate(CashAccount, :count, :id)
  end

  def create_cash_account(%Actor{} = actor, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.insert(:cash_account, CashAccount.changeset(%CashAccount{}, attrs))
    |> Journal.record(actor,
      resource_type: "cash_account",
      operation: :create,
      source: :cash_account
    )
    |> Repo.transaction()
    |> account_write_result(:cash_account)
  end

  def get_cash_account(id) when is_integer(id), do: Repo.get(CashAccount, id)

  def update_cash_account(%Actor{} = actor, %CashAccount{} = cash_account, attrs)
      when is_map(attrs) do
    Multi.new()
    |> Multi.update(:cash_account, CashAccount.changeset(cash_account, attrs))
    |> Journal.record(actor,
      resource_type: "cash_account",
      operation: :update,
      source: :cash_account,
      before: cash_account
    )
    |> Repo.transaction()
    |> account_write_result(:cash_account)
  end

  @doc """
  Deletes a cash account on behalf of `actor`. All account FKs are
  `on_delete: :restrict`, so an account still referenced by a transaction or a
  securities account cannot be removed; this returns `{:error, :referenced}`
  instead of raising. The deletion is journaled with the full `before` snapshot.
  """
  def delete_cash_account(%Actor{} = actor, %CashAccount{} = cash_account) do
    if cash_account_referenced?(cash_account.id) do
      {:error, :referenced}
    else
      Multi.new()
      |> Multi.delete(:cash_account, cash_account)
      |> Journal.record(actor,
        resource_type: "cash_account",
        operation: :delete,
        source: :cash_account,
        before: cash_account
      )
      |> Repo.transaction()
      |> account_write_result(:cash_account)
    end
  end

  defp cash_account_referenced?(id) do
    Repo.exists?(
      from(t in Transaction,
        where: t.cash_account_id == ^id or t.counter_cash_account_id == ^id
      )
    ) or Repo.exists?(from(s in SecuritiesAccount, where: s.cash_account_id == ^id))
  end

  def list_securities_accounts do
    Repo.all(
      from(account in SecuritiesAccount,
        order_by: [asc: account.name, asc: account.id],
        preload: [:cash_account]
      )
    )
  end

  def list_securities_accounts_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(account in SecuritiesAccount,
        where: account.portfolio_id == ^portfolio_id,
        order_by: [asc: account.name, asc: account.id],
        preload: [:cash_account]
      )
    )
  end

  def count_securities_accounts do
    Repo.aggregate(SecuritiesAccount, :count, :id)
  end

  def create_securities_account(%Actor{} = actor, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.insert(:securities_account, SecuritiesAccount.changeset(%SecuritiesAccount{}, attrs))
    |> Journal.record(actor,
      resource_type: "securities_account",
      operation: :create,
      source: :securities_account
    )
    |> Repo.transaction()
    |> account_write_result(:securities_account)
  end

  def get_securities_account(id) when is_integer(id) do
    case Repo.get(SecuritiesAccount, id) do
      nil -> nil
      account -> Repo.preload(account, :cash_account)
    end
  end

  def update_securities_account(
        %Actor{} = actor,
        %SecuritiesAccount{} = securities_account,
        attrs
      )
      when is_map(attrs) do
    Multi.new()
    |> Multi.update(:securities_account, SecuritiesAccount.changeset(securities_account, attrs))
    |> Journal.record(actor,
      resource_type: "securities_account",
      operation: :update,
      source: :securities_account,
      before: securities_account
    )
    |> Repo.transaction()
    |> account_write_result(:securities_account)
    |> case do
      {:ok, updated} -> {:ok, Repo.preload(updated, :cash_account, force: true)}
      other -> other
    end
  end

  @doc """
  Deletes a securities account on behalf of `actor`. Its FKs are
  `on_delete: :restrict`, so an account still referenced by a transaction cannot
  be removed; this returns `{:error, :referenced}` instead of raising. The
  deletion is journaled with the full `before` snapshot.
  """
  def delete_securities_account(%Actor{} = actor, %SecuritiesAccount{} = securities_account) do
    if securities_account_referenced?(securities_account.id) do
      {:error, :referenced}
    else
      Multi.new()
      |> Multi.delete(:securities_account, securities_account)
      |> Journal.record(actor,
        resource_type: "securities_account",
        operation: :delete,
        source: :securities_account,
        before: securities_account
      )
      |> Repo.transaction()
      |> account_write_result(:securities_account)
    end
  end

  defp securities_account_referenced?(id) do
    Repo.exists?(
      from(t in Transaction,
        where: t.securities_account_id == ^id or t.counter_securities_account_id == ^id
      )
    )
  end
end
