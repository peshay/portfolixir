defmodule PortfolixirWeb.Api.V1.ViewParam do
  @moduledoc """
  Shared parsing for the optional `view` scope query param on the analytics
  endpoints (ADR-0018, FR-13).

  A request may carry `?view=<view_id>` to scope an analytics result to the
  holdings matching that view. This helper resolves the param to the view the
  analytics context should run under, returning `{:ok, nil}` for the unscoped
  default (so output stays byte-identical to today), `{:ok, %View{}}` for an
  existing view, `{:error, :view}` for a malformed id, and `:view_not_found`
  when no such view exists. Resolving the view first means the context never
  receives an id whose `view_filter/1` would raise.
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias PortfolixirWeb.Api.V1.JSON

  @type result :: {:ok, View.t() | nil} | {:error, :view} | :view_not_found

  @doc "Resolves the `view` param from a request's params map."
  @spec resolve(map()) :: result()
  def resolve(params) do
    case Map.get(params, "view") do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      raw -> resolve_id(raw)
    end
  end

  @doc "The keyword options to forward to an analytics context call."
  @spec opts(View.t() | nil) :: keyword()
  def opts(nil), do: []
  def opts(%View{id: id}), do: [view: id]

  @doc "Merges the active-view echo into a serialized analytics response map."
  @spec put_active(map(), View.t() | nil) :: map()
  def put_active(data, nil), do: data
  def put_active(data, %View{} = view), do: Map.put(data, :view, JSON.active_view(view))

  defp resolve_id(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {vid, ""} -> lookup(vid)
      _ -> {:error, :view}
    end
  end

  defp resolve_id(_raw), do: {:error, :view}

  defp lookup(vid) do
    case Buckets.get_view(vid) do
      %View{} = view -> {:ok, view}
      nil -> :view_not_found
    end
  end
end
