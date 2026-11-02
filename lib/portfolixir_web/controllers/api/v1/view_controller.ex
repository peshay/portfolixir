defmodule PortfolixirWeb.Api.V1.ViewController do
  @moduledoc """
  JSON API for views (ADR-0018): named global filters over buckets, expressed as
  `{include | "all", exclude}` sets where exclude always wins.

  View-definition writes are actor-first and journaled with the view's whole
  definition before and after (ADR-0018 §5 as amended in Sprint 16; E25 S6,
  F45). The controller routes every write through `Portfolixir.Buckets` and
  never touches the Repo.
  """
  use PortfolixirWeb, :controller

  plug(PortfolixirWeb.Api.V1.BodyObject, "view" when action in [:create, :update])

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.View
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.PolicyConflict

  def index(conn, _params) do
    data =
      Buckets.list_views()
      |> Enum.map(fn view -> JSON.view(view, filter_for(view)) end)

    json(conn, %{data: data})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, vid} <- IdParam.parse(id),
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

  # The view's fields at the top level of a PATCH body, outside the `view`
  # object, were dropped and the PATCH answered 200 with the view as it was
  # (#1315): they are refused, naming the field, so the agent learns the
  # shape instead of believing the view changed. The bucket sets, the PUT
  # /buckets body sent to this route by mistake, are refused the same way,
  # pointing to the route that sets them (closing act).
  @unwrapped ["must be sent inside the view object"]
  @to_buckets ["is set with PUT /api/v1/views/:id/buckets"]
  @view_fields [
    {"name", @unwrapped},
    {"include_all", @unwrapped},
    {"include", @to_buckets},
    {"exclude", @to_buckets}
  ]

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "view", %{})

    with :ok <- wrapped_fields(conn.body_params),
         {:ok, vid} <- IdParam.parse(id),
         %View{} = view <- Buckets.get_view(vid),
         {:ok, updated} <- Buckets.update_view(conn.assigns.actor, view, attrs) do
      json(conn, %{data: JSON.view(updated, filter_for(updated))})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, :not_found} -> not_found(conn)
      {:error, {:unwrapped, fields}} -> unprocessable(conn, fields)
      {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  defp wrapped_fields(%{} = body) when not is_struct(body) do
    case for(
           {field, message} <- @view_fields,
           Map.has_key?(body, field),
           into: %{},
           do: {field, message}
         ) do
      fields when map_size(fields) == 0 -> :ok
      fields -> {:error, {:unwrapped, fields}}
    end
  end

  defp wrapped_fields(_body), do: :ok

  def delete(conn, %{"id" => id}) do
    with {:ok, vid} <- IdParam.parse(id),
         %View{} = view <- Buckets.get_view(vid),
         {:ok, _} <- Buckets.delete_view(conn.assigns.actor, view) do
      send_resp(conn, :no_content, "")
    else
      {:error, {:policy_rules, rules}} -> PolicyConflict.render(conn, rules, "view")
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, :not_found} -> not_found(conn)
      {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  @doc """
  Replaces a view's include/exclude bucket sets. Body: `{"include": [..],
  "exclude": [..], "include_all": bool}` (the sets optional, default `[]`;
  `include_all` optional, left as it is when absent). The flag is saved with
  both sets in one journaled write, as the bucket picker saves it (#1315):
  without it a view created with "all" included could not be narrowed here.
  Returns the view with its resolved filter.
  """
  def set_buckets(conn, %{"id" => id} = params) do
    with {:ok, vid} <- IdParam.parse(id),
         %View{} = view <- Buckets.get_view(vid),
         {:ok, include} <- id_list(params, "include", :include),
         {:ok, exclude} <- id_list(params, "exclude", :exclude),
         {:ok, opts} <- include_all_opts(params),
         :ok <- Buckets.set_view_buckets(conn.assigns.actor, view, include, exclude, opts) do
      written = Buckets.get_view(vid) || view
      json(conn, %{data: JSON.view(written, filter_for(written))})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, :not_found} -> not_found(conn)
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

  # Absent or null leaves the flag as it is, as an absent set is empty;
  # anything but a boolean is a 422 on include_all.
  defp include_all_opts(params) do
    case Map.get(params, "include_all") do
      nil -> {:ok, []}
      flag when is_boolean(flag) -> {:ok, [include_all: flag]}
      _other -> {:error, :include_all}
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
      case IdParam.parse(value) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        :error -> {:halt, {:error, field}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

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
