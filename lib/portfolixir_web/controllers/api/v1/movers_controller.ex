defmodule PortfolixirWeb.Api.V1.MoversController do
  @moduledoc """
  The tops and flops over the API (FR-59, ADR-0061 §9; Sprint 30, T2), each
  answer `Portfolixir.Portfolios.Performance.Movers.read/3`'s, rendered by
  `PortfolixirWeb.Api.V1.MoversJSON`:

    * `GET /api/v1/views/:view_id/movers` — the view's two rankings, the
      view echoed as `view`;
    * `GET /api/v1/movers` — everything's, every depot and cash account of
      every portfolio, `view_id` null.

  Both take `window` (`day`, the default and the window the Overview reads,
  `week`, `month`, `quarter`, `ytd` or `1y`), `limit` (per half, default 5,
  capped at 50 and echoed, as the limit family reads it, #771) and
  `include_unanswered` (`true` lists the securities and positions without a
  figure). The read is closed: an unknown window, a malformed limit or
  `include_unanswered`, and any parameter it does not take answer 422 naming
  it. A view that does not exist, or an id that is no id, answers 404.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias Portfolixir.Portfolios.Performance.Movers
  alias PortfolixirWeb.Api.V1.ClosedBody
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.ListLimit
  alias PortfolixirWeb.Api.V1.MoversJSON
  alias PortfolixirWeb.Api.V1.ViewParam

  @params ~w(window limit include_unanswered)
  @default_window "day"

  def show(conn, %{"view_id" => view_id}) do
    with {:ok, id} <- IdParam.parse(view_id),
         %View{} = view <- Buckets.get_view(id) do
      read(conn, view)
    else
      _missing -> not_found(conn)
    end
  end

  def total(conn, _params), do: read(conn, nil)

  # `view` nil is the Everything scope, as the performance family's total.
  defp read(conn, view) do
    params = conn.query_params

    with :ok <- closed(conn),
         {:ok, window} <- window(params),
         {:ok, limit} <- limit(params),
         {:ok, include_unanswered} <- include_unanswered(params),
         {:ok, result} <-
           Movers.read(ViewParam.id(view), window,
             limit: limit,
             include_unanswered: include_unanswered
           ) do
      data = result |> MoversJSON.movers() |> ViewParam.put_active(view)
      json(conn, %{data: data})
    else
      # The view vanished between the lookup and the read (TOCTOU): a plain
      # 404, never a 500.
      {:error, :view_not_found} -> not_found(conn)
      {:error, :invalid_window} -> ClosedBody.refuse(conn, window_error())
      {:error, :invalid_limit} -> ClosedBody.refuse(conn, limit_error())
      {:error, %{} = errors} -> ClosedBody.refuse(conn, errors)
    end
  end

  defp closed(conn) do
    body = if is_map(conn.body_params), do: conn.body_params, else: %{}

    case ClosedBody.unknown(Map.merge(conn.query_params, body), @params, "this read") do
      empty when empty == %{} -> :ok
      errors -> {:error, errors}
    end
  end

  # Absent or blank, the day; a known key as it is; anything else, a list
  # included, refused before the read.
  defp window(params) do
    case Map.get(params, "window") do
      value when value in [nil, ""] ->
        {:ok, @default_window}

      value when is_binary(value) ->
        if value in Movers.windows(), do: {:ok, value}, else: {:error, window_error()}

      _other ->
        {:error, window_error()}
    end
  end

  # The limit family's contract (#771): absent or blank the default, above
  # the maximum capped (and echoed in the answer), zero or text refused.
  defp limit(params) do
    case ListLimit.parse(params, Movers.default_limit(), Movers.max_limit()) do
      {:ok, limit} -> {:ok, limit}
      {:error, :limit} -> {:error, limit_error()}
    end
  end

  defp include_unanswered(params) do
    case Map.get(params, "include_unanswered") do
      value when value in [nil, "", "false"] -> {:ok, false}
      "true" -> {:ok, true}
      _other -> {:error, %{include_unanswered: ["is invalid: true or false"]}}
    end
  end

  defp window_error,
    do: %{window: ["is invalid: #{windows_text()}"]}

  defp windows_text do
    {last, rest} = List.pop_at(Movers.windows(), -1)
    Enum.join(rest, ", ") <> " or " <> last
  end

  defp limit_error,
    do: %{limit: ["is invalid: a positive integer, at most #{Movers.max_limit()}"]}

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
