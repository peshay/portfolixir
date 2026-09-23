defmodule PortfolixirWeb.LiveIdRange do
  @moduledoc """
  The #840 range guarantee for the pages (#855): an id no `bigint` column can
  hold never reaches the database from a LiveView.

  The JSON API refuses such an id in its pipeline
  (`PortfolixirWeb.Api.V1.IdRangeGuard`). A LiveView reads its params twice —
  on the static render and again on the connected mount, from the client's
  URL — so a plug could only cover the first. This `on_mount` hook attaches a
  `handle_params` hook to every page of the live session instead, and runs
  before the page's own `handle_params`:

    * an id-shaped **query** parameter past the range (`id`, `*_id`, `*_ids`,
      `view`) is dropped by navigating to the same page without it;
    * an id-shaped **path** parameter past the range (`/securities/:id`,
      `/classifications/:id`) navigates to the route's index.

  On the static render the navigation is an HTTP 302, never a 500; a
  malformed or an in-range unknown id is not this hook's business and keeps
  the answer it had.
  """
  import Phoenix.LiveView, only: [attach_hook: 4, push_navigate: 2]

  alias PortfolixirWeb.Api.V1.IdParam

  @scalar_keys ~w(id view)

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :id_range, :handle_params, &guard/3)}
  end

  defp guard(params, url, socket) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "")

    path_out_of_range? =
      Enum.any?(params, fn {key, value} ->
        not Map.has_key?(query, key) and id_key?(key) and out_of_range?(value)
      end)

    out_of_range_query = for {key, value} <- query, id_key?(key), out_of_range?(value), do: key

    cond do
      path_out_of_range? ->
        {:halt, push_navigate(socket, to: parent(uri.path))}

      out_of_range_query != [] ->
        kept = Map.drop(query, out_of_range_query)
        to = if kept == %{}, do: uri.path, else: uri.path <> "?" <> URI.encode_query(kept)
        {:halt, push_navigate(socket, to: to)}

      true ->
        {:cont, socket}
    end
  end

  defp id_key?(key),
    do: key in @scalar_keys or String.ends_with?(key, "_id") or String.ends_with?(key, "_ids")

  defp out_of_range?(values) when is_list(values), do: Enum.any?(values, &out_of_range?/1)

  defp out_of_range?(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.any?(&(not IdParam.int8?(String.trim(&1))))
  end

  defp out_of_range?(_value), do: false

  # `/securities/99…9` → `/securities`: the id is the path's last segment.
  defp parent(path) do
    case path |> String.split("/", trim: true) |> Enum.drop(-1) do
      [] -> "/"
      segments -> "/" <> Enum.join(segments, "/")
    end
  end
end
