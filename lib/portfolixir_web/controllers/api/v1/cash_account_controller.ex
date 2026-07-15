defmodule PortfolixirWeb.Api.V1.CashAccountController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    balances = Ledger.cash_balances()

    data =
      Portfolios.list_cash_accounts()
      |> Enum.map(fn account ->
        balance = Map.get(balances, account.id, Decimal.new("0"))

        account
        |> JSON.cash_account()
        |> Map.put(:balance, JSON.decimal(balance))
      end)

    json(conn, %{data: data})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, cid} <- parse_id(id),
         %CashAccount{} = account <- Portfolios.get_cash_account(cid) do
      json(conn, %{data: JSON.cash_account(account)})
    else
      _ -> not_found(conn)
    end
  end

  def create(conn, params) do
    # ADR-0024: no portfolio decision required — a missing portfolio_id
    # resolves to the deterministic internal default; an explicit id keeps
    # winning for compatibility clients.
    attrs =
      params
      |> Map.get("cash_account", %{})
      |> default_portfolio_binding(conn.assigns.actor)

    case Portfolios.create_cash_account(conn.assigns.actor, attrs) do
      {:ok, account} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.cash_account(account)})

      {:error, changeset} ->
        unprocessable(conn, JSON.errors(changeset))
    end
  end

  def update(conn, %{"id" => id} = params) do
    # Never let an update move an account into a different portfolio.
    attrs = params |> Map.get("cash_account", %{}) |> Map.drop(["portfolio_id"])

    with {:ok, cid} <- parse_id(id),
         %CashAccount{} = account <- Portfolios.get_cash_account(cid),
         {:ok, updated} <- Portfolios.update_cash_account(conn.assigns.actor, account, attrs) do
      json(conn, %{data: JSON.cash_account(updated)})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, cid} <- parse_id(id),
         %CashAccount{} = account <- Portfolios.get_cash_account(cid) do
      case Portfolios.delete_cash_account(conn.assigns.actor, account) do
        {:ok, _} -> send_resp(conn, :no_content, "")
        {:error, :referenced} -> conflict(conn)
        {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
      end
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
    end
  end

  @doc """
  Records an absolute cash-balance snapshot for one account (ADR-0009): the
  current balance as of `date`, without mirroring every booking. Body:
  `{"date": "2026-06-01", "amount": "4250.00"}` (`notes` optional).
  """
  def set_balance(conn, %{"id" => id} = params) do
    attrs = Map.take(params, ["date", "amount", "notes"])

    with {:ok, cid} <- parse_id(id),
         %CashAccount{} = account <- Portfolios.get_cash_account(cid),
         {:ok, transaction} <- Ledger.set_cash_balance(conn.assigns.actor, account, attrs) do
      conn
      |> put_status(:created)
      |> json(%{data: JSON.transaction(transaction)})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp default_portfolio_binding(attrs, actor) when is_map(attrs) do
    case Map.get(attrs, "portfolio_id") do
      value when value in [nil, ""] ->
        Map.put(attrs, "portfolio_id", Portfolios.default_portfolio(actor).id)

      _explicit ->
        attrs
    end
  end

  defp default_portfolio_binding(attrs, _actor), do: attrs

  defp unprocessable(conn, errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end

  defp conflict(conn) do
    conn
    |> put_status(:conflict)
    |> json(%{errors: %{detail: "cash account is referenced by existing records"}})
  end
end
