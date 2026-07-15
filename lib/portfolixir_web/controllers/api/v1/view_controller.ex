defmodule PortfolixirWeb.Api.V1.ViewController do
  @moduledoc """
  JSON API for views (ADR-0018): named global filters over buckets, expressed as
  `{include | "all", exclude}` sets where exclude always wins.

  View-definition writes are actor-first (for the uniform write signature) but,
  per ADR-0018 §5, are deliberately not journaled. The controller routes every
  write through `Portfolixir.Buckets` and never touches the Repo.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    data =
      Buckets.list_views()
      |> Enum.map(fn view -> JSON.view(view, filter_for(view)) end)

    json(conn, %{data: data})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, vid} <- parse_id(id),
         %View{} = view <- Buckets.get_view(vid) do
      json(conn, %{data: JSON.view(view, filter_for(view))})
    else
      _ -> not_found(conn)
    end
  end

  def create(conn, params) do
    attrs = Map.get(params, "view", %{})

    case Buckets.create_view(conn.assigns.actor, attrs) do
      {:ok, view} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.view(view, filter_for(view))})

      {:error, changeset} ->
        unprocessable(conn, JSON.errors(changeset))
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "view", %{})

    with {:ok, vid} <- parse_id(id),
         %View{} = view <- Buckets.get_view(vid),
         {:ok, updated} <- Buckets.update_view(conn.assigns.actor, view, attrs) do
      json(conn, %{data: JSON.view(updated, filter_for(updated))})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, vid} <- parse_id(id),
         %View{} = view <- Buckets.get_view(vid),
         {:ok, _} <- Buckets.delete_view(conn.assigns.actor, view) do
      send_resp(conn, :no_content, "")
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  @doc """
  Replaces a view's include/exclude bucket sets. Body: `{"include": [..],
  "exclude": [..]}` (both optional, default `[]`). Returns the view with its
  resolved filter.
  """
  def set_buckets(conn, %{"id" => id} = params) do
    with {:ok, vid} <- parse_id(id),
         %View{} = view <- Buckets.get_view(vid),
         {:ok, include} <- id_list(params, "include", :include),
         {:ok, exclude} <- id_list(params, "exclude", :exclude),
         :ok <- Buckets.set_view_buckets(conn.assigns.actor, view, include, exclude) do
      json(conn, %{data: JSON.view(view, filter_for(view))})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, field} when is_atom(field) -> unprocessable(conn, %{field => ["is invalid"]})
      {:error, _reason} -> unprocessable(conn, %{detail: ["could not set view buckets"]})
    end
  end

  # The just-handled view's resolved filter. A concurrent delete between the
  # write and this read (fix round TOCTOU) serializes as an empty filter
  # instead of raising a 500 — the record itself was verified moments before.
  defp filter_for(%View{id: id}) do
    case Buckets.view_filter(id) do
      {:ok, filter} -> filter
      {:error, :view_not_found} -> %{include: [], exclude: []}
    end
  end

  # Parses a list of bucket ids from `params[key]`. Absent -> []. Any non-integer
  # entry returns `{:error, key_atom}` so a malformed body is a 422, not a crash.
  defp id_list(params, key, field) do
    case Map.get(params, key) do
      nil -> {:ok, []}
      list when is_list(list) -> parse_ids(list, field)
      _ -> {:error, field}
    end
  end

  defp parse_ids(list, field) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case parse_id(value) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        :error -> {:halt, {:error, field}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  defp parse_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_value), do: :error

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
