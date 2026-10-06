defmodule PortfolixirWeb.Api.V1.CategoryResultController do
  @moduledoc """
  Per-category result (ADR-0041 slice one, issue #712): what each category of a
  classification tree cost, what it is worth now, and what it has made.

  Kept as its own endpoint rather than folded into the allocation read: the two
  answer different questions off different engines — allocation compares actual
  against target, this compares current value against cost — and merging them
  would couple `Allocation` to the cost side for no consumer that needs both in
  one call.

  The view scope (#901; ADR-0051 §6) comes in the performance family's two
  forms: the portfolio read narrowed with `?view=` (`index/2`), and the view
  read across every portfolio (`show/2`), each echoing the active view.
  `total/2` reads every portfolio with no view (#1091's read half,
  `CategoryResult.for_all_portfolios/2`), the roll-up the classification
  screen shows, in EUR.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CategoryResult
  alias Portfolixir.Portfolios.Portfolio
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ViewParam

  def index(conn, %{"portfolio_id" => portfolio_id} = params) do
    with {:ok, pid} <- IdParam.parse(portfolio_id),
         %Portfolio{} <- Portfolios.get_portfolio(pid),
         {:ok, view} <- ViewParam.resolve(params),
         {:ok, cid} <- classification_id(Map.get(params, "classification_id")) do
      pid
      |> CategoryResult.for_portfolio(cid, ViewParam.opts(view))
      |> respond(conn, view)
    else
      {:error, :view} -> unprocessable(conn, %{view: ["is invalid"]})
      failure -> refuse(conn, failure)
    end
  end

  def show(conn, %{"view_id" => view_id} = params) do
    with {:ok, vid} <- IdParam.parse(view_id),
         %View{} = view <- Buckets.get_view(vid),
         {:ok, cid} <- classification_id(Map.get(params, "classification_id")) do
      vid
      |> CategoryResult.for_view(cid)
      |> respond(conn, view)
    else
      failure -> refuse(conn, failure)
    end
  end

  # #1091 (the read half): every portfolio, in EUR, the roll-up the
  # classification screen shows; no view to echo.
  def total(conn, params) do
    case classification_id(Map.get(params, "classification_id")) do
      {:ok, cid} -> cid |> CategoryResult.for_all_portfolios() |> respond(conn, nil)
      failure -> refuse(conn, failure)
    end
  end

  # An unknown classification, or a view deleted between the lookup and the
  # read (TOCTOU), is a plain 404, never a 500.
  defp respond({:ok, result}, conn, view),
    do: json(conn, %{data: result |> JSON.category_result() |> ViewParam.put_active(view)})

  defp respond({:error, _not_found}, conn, _view), do: not_found(conn)

  defp refuse(conn, :missing), do: unprocessable(conn, %{classification_id: ["is required"]})
  defp refuse(conn, _not_found), do: not_found(conn)

  defp classification_id(nil), do: :missing
  defp classification_id(value), do: IdParam.parse(value)

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
end
