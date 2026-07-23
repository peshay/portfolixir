defmodule PortfolixirWeb.Api.V1.HoldingsReconcileController do
  @moduledoc """
  `POST /api/v1/holdings/reconcile` — the FR-35 read-only reconcile
  (ADR-0029 §6).

  The external position list arrives **only** in the request body (paste/file
  content parsed client-side into rows); there is no network acquisition, and
  nothing from the request is persisted or logged (the `rows` parameter is
  filtered from Phoenix logs, see `config/config.exs`). Quantities must be
  canonical dot-decimal strings — locale parsing is the client's job, so any
  other format is a 422 naming the offending row. An optional `portfolio_id`
  or `view` bounds the compare; the default is the whole instance.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Reconcile
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ViewParam

  @quantity_format ~r/^-?\d+(\.\d+)?$/

  def create(conn, params) do
    with {:ok, rows} <- parse_rows(Map.get(params, "rows")),
         {:ok, scope} <- scope_opts(params) do
      json(conn, %{data: JSON.reconcile(Reconcile.run(rows, scope))})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "not found"}})

      {:error, errors} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})
    end
  end

  # -- Rows -------------------------------------------------------------------

  defp parse_rows(rows) when is_list(rows) and rows != [] do
    rows
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {row, number}, {:ok, parsed} ->
      case parse_row(row, number) do
        {:ok, parsed_row} -> {:cont, {:ok, [parsed_row | parsed]}}
        {:error, message} -> {:halt, {:error, %{rows: [message]}}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp parse_rows(_rows) do
    {:error, %{rows: ["rows must be a non-empty list of {identifier, quantity} objects"]}}
  end

  defp parse_row(row, number) when is_map(row) do
    with {:ok, identifier} <- identifier(row, number),
         {:ok, quantity} <- quantity(row, number),
         {:ok, currency} <- currency(row, number),
         {:ok, security_id} <- security_id(row, number) do
      {:ok,
       %{identifier: identifier, quantity: quantity, currency: currency, security_id: security_id}}
    end
  end

  defp parse_row(_row, number) do
    {:error, "row #{number}: must be a {identifier, quantity} object"}
  end

  defp identifier(row, number) do
    case Map.get(row, "identifier") do
      identifier when is_binary(identifier) ->
        if String.trim(identifier) == "" do
          {:error, "row #{number}: identifier must be a non-empty string"}
        else
          {:ok, identifier}
        end

      _other ->
        {:error, "row #{number}: identifier must be a non-empty string"}
    end
  end

  # Canonical dot-decimal only (ADR-0029 §6): digits, optional leading minus,
  # at most one dot. Locale formats (comma decimals, thousands separators,
  # exponents) are the client's parsing job — never silently reinterpreted.
  defp quantity(row, number) do
    with value when is_binary(value) <- Map.get(row, "quantity"),
         true <- Regex.match?(@quantity_format, value),
         {decimal, ""} <- Decimal.parse(value) do
      {:ok, decimal}
    else
      _invalid ->
        {:error,
         "row #{number}: quantity must be a canonical dot-decimal string " <>
           ~s|(e.g. "1234.5" — digits, optional leading "-", one "."); | <>
           "locale parsing is the client's job"}
    end
  end

  defp currency(row, number) do
    case Map.get(row, "currency") do
      nil -> {:ok, nil}
      currency when is_binary(currency) -> {:ok, currency}
      _other -> {:error, "row #{number}: currency must be a string"}
    end
  end

  defp security_id(row, number) do
    case Map.get(row, "security_id") do
      nil -> {:ok, nil}
      id when is_integer(id) and id > 0 -> {:ok, id}
      _other -> {:error, "row #{number}: security_id must be a positive integer"}
    end
  end

  # -- Scope ------------------------------------------------------------------

  defp scope_opts(params) do
    case {Map.get(params, "portfolio_id"), Map.get(params, "view")} do
      {nil, nil} -> {:ok, []}
      {portfolio_id, nil} -> portfolio_scope(portfolio_id)
      {nil, _view} -> view_scope(params)
      {_both, _given} -> {:error, %{scope: ["pass either portfolio_id or view, not both"]}}
    end
  end

  defp portfolio_scope(portfolio_id) do
    with {:ok, id} <- parse_id(portfolio_id),
         portfolio when not is_nil(portfolio) <- Portfolios.get_portfolio(id) do
      {:ok, [portfolio_id: id]}
    else
      :error -> {:error, %{portfolio_id: ["is invalid"]}}
      nil -> {:error, :not_found}
    end
  end

  defp view_scope(params) do
    case ViewParam.resolve(params) do
      {:ok, nil} -> {:ok, []}
      {:ok, view} -> {:ok, [view: view.id]}
      {:error, :view} -> {:error, %{view: ["is invalid"]}}
      :view_not_found -> {:error, :not_found}
    end
  end

  defp parse_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _invalid -> :error
    end
  end

  defp parse_id(_value), do: :error
end
