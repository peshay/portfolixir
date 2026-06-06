defmodule PortfolixirWeb.Api.V1.ClassificationController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Classifications
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Classifications.list_trees(), &JSON.classification_tree/1)})
  end

  def create(conn, params) do
    attrs = Map.get(params, "classification", %{})

    case Classifications.create_classification(attrs) do
      {:ok, classification} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.classification(classification)})

      {:error, changeset} ->
        unprocessable(conn, JSON.errors(changeset))
    end
  end

  def create_category(conn, %{"classification_id" => classification_id} = params) do
    with {:ok, id} <- parse_id(classification_id) do
      attrs = params |> Map.get("category", %{}) |> Map.put("classification_id", id)

      case Classifications.create_category(attrs) do
        {:ok, category} ->
          conn
          |> put_status(:created)
          |> json(%{data: JSON.category(category)})

        {:error, reason} ->
          render_error(conn, reason)
      end
    else
      :error -> not_found(conn)
    end
  end

  def assign(conn, %{"classification_id" => classification_id} = params) do
    with {:ok, cid} <- parse_id(classification_id),
         {:ok, security_id} <- parse_id(Map.get(params, "security_id")),
         {:ok, category_id} <- parse_id(Map.get(params, "category_id")) do
      case Classifications.assign_security(security_id, cid, category_id) do
        {:ok, assignment} ->
          json(conn, %{data: JSON.assignment(assignment)})

        {:error, reason} ->
          render_error(conn, reason)
      end
    else
      :error -> not_found(conn)
    end
  end

  def unassign(conn, %{"classification_id" => classification_id, "security_id" => security_id}) do
    with {:ok, cid} <- parse_id(classification_id),
         {:ok, sid} <- parse_id(security_id) do
      {:ok, count} = Classifications.unassign_security(sid, cid)
      json(conn, %{data: %{unassigned: count}})
    else
      :error -> not_found(conn)
    end
  end

  defp render_error(conn, %Ecto.Changeset{} = changeset),
    do: unprocessable(conn, JSON.errors(changeset))

  defp render_error(conn, :not_found), do: not_found(conn)
  defp render_error(conn, :category_not_found), do: not_found(conn)

  defp render_error(conn, :builtin_locked),
    do: unprocessable(conn, %{detail: "classification is built-in and cannot be edited"})

  defp render_error(conn, :category_mismatch),
    do: unprocessable(conn, %{detail: "category does not belong to the classification"})

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
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
