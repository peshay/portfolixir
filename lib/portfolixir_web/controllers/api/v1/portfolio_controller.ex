defmodule PortfolixirWeb.Api.V1.PortfolioController do
  @moduledoc """
  Portfolio compatibility endpoints (ADR-0024 modification 1). The write
  endpoints keep working in phase 1 but are **deprecated** — they respond with
  a `Deprecation: true` header and are documented "compatibility only — use
  buckets/views for grouping". After two releases without external portfolio
  writes a follow-up story merges the records into buckets+views (the ADR's
  sunset criterion). Every record written here stays visible in the
  Accounts & depots admin list, so no writable resource is invisible.
  """

  use PortfolixirWeb, :controller

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Portfolio
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Portfolios.list_portfolios(), &JSON.portfolio/1)})
  end

  def create(conn, params) do
    attrs = Map.get(params, "portfolio", %{})
    conn = put_deprecation(conn)

    case Portfolios.create_portfolio(conn.assigns.actor, attrs) do
      {:ok, portfolio} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.portfolio(portfolio)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: JSON.errors(changeset)})
    end
  end

  # Patches a portfolio's master data. The `cash_target_weight` is the SOLL cash
  # share of the allocation's 100% basis (securities + counting cash, issue
  # #335): a fraction in `[0, 1]`, or `null` to stop steering a cash quote.
  def update(conn, %{"portfolio_id" => portfolio_id} = params) do
    conn = put_deprecation(conn)

    with {:ok, pid} <- parse_id(portfolio_id),
         %Portfolio{} = portfolio <- Portfolios.get_portfolio(pid) do
      attrs = Map.get(params, "portfolio", %{})

      case Portfolios.update_portfolio(conn.assigns.actor, portfolio, attrs) do
        {:ok, updated} ->
          json(conn, %{data: JSON.portfolio(updated)})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: JSON.errors(changeset)})
      end
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  # The RFC-style deprecation signal on the portfolio write endpoints
  # (ADR-0024 modification 1): the calls keep working, the header tells
  # automation to move to buckets/views for grouping.
  defp put_deprecation(conn) do
    put_resp_header(conn, "deprecation", "true")
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
