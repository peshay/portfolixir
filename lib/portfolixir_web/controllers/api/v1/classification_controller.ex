defmodule PortfolixirWeb.Api.V1.ClassificationController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Classification
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Classifications.list_trees(), &JSON.classification_tree/1)})
  end

  def create(conn, params) do
    attrs = Map.get(params, "classification", %{})

    case Classifications.create_classification(conn.assigns.actor, attrs) do
      {:ok, classification} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.classification(classification)})

      {:error, changeset} ->
        unprocessable(conn, JSON.errors(changeset))
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "classification", %{})

    with {:ok, cid} <- parse_id(id),
         %Classification{} = classification <- Classifications.get_classification(cid) do
      case Classifications.update_classification(conn.assigns.actor, classification, attrs) do
        {:ok, classification} ->
          json(conn, %{data: JSON.classification(classification)})

        {:error, reason} ->
          render_error(conn, reason)
      end
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, cid} <- parse_id(id),
         %Classification{} = classification <- Classifications.get_classification(cid) do
      case Classifications.delete_classification(conn.assigns.actor, classification) do
        {:ok, _classification} -> json(conn, %{data: %{deleted: true}})
        {:error, reason} -> render_error(conn, reason)
      end
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
    end
  end

  def create_category(conn, %{"classification_id" => classification_id} = params) do
    with {:ok, id} <- parse_id(classification_id) do
      attrs = params |> Map.get("category", %{}) |> Map.put("classification_id", id)

      case Classifications.create_category(conn.assigns.actor, attrs) do
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

  def update_category(conn, %{"classification_id" => classification_id, "id" => id} = params) do
    # Only patch user-editable fields; never let a request re-home a category
    # into a different classification.
    attrs = params |> Map.get("category", %{}) |> Map.drop(["classification_id"])

    with {:ok, cid} <- parse_id(classification_id),
         {:ok, category_id} <- parse_id(id),
         %{classification_id: ^cid} = category <- Classifications.get_category(category_id) do
      case Classifications.update_category(conn.assigns.actor, category, attrs) do
        {:ok, category} -> json(conn, %{data: JSON.category(category)})
        {:error, reason} -> render_error(conn, reason)
      end
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      %{} -> not_found(conn)
    end
  end

  def delete_category(conn, %{"classification_id" => classification_id, "id" => id}) do
    with {:ok, cid} <- parse_id(classification_id),
         {:ok, category_id} <- parse_id(id),
         %{classification_id: ^cid} = category <- Classifications.get_category(category_id) do
      case Classifications.delete_category(conn.assigns.actor, category) do
        {:ok, _category} -> json(conn, %{data: %{deleted: true}})
        {:error, reason} -> render_error(conn, reason)
      end
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
      %{} -> not_found(conn)
    end
  end

  def assign(conn, %{"classification_id" => classification_id} = params) do
    with {:ok, cid} <- parse_id(classification_id),
         {:ok, security_id} <- parse_id(Map.get(params, "security_id")),
         {:ok, category_id} <- parse_id(Map.get(params, "category_id")) do
      previous = Classifications.get_assignment(security_id, cid)

      case Classifications.assign_security(conn.assigns.actor, security_id, cid, category_id) do
        {:ok, assignment} ->
          json(conn, %{data: assignment_result(assignment, previous)})

        {:error, reason} ->
          render_error(conn, reason)
      end
    else
      :error -> not_found(conn)
    end
  end

  def assign_bulk(conn, %{"classification_id" => classification_id} = params) do
    with {:ok, cid} <- parse_id(classification_id),
         {:ok, category_id} <- parse_id(Map.get(params, "category_id")),
         {:ok, security_ids} <- parse_ids(Map.get(params, "security_ids")) do
      case Classifications.assign_securities(conn.assigns.actor, security_ids, cid, category_id) do
        {:ok, count} ->
          json(conn, %{
            data: %{assigned: count, category_id: category_id, security_ids: security_ids}
          })

        {:error, reason} ->
          render_error(conn, reason)
      end
    else
      :error -> not_found(conn)
    end
  end

  # Reports whether the assignment was newly created, moved between categories,
  # or already pointed at the target category.
  defp assignment_result(assignment, previous) do
    status =
      cond do
        is_nil(previous) -> "created"
        previous.category_id == assignment.category_id -> "unchanged"
        true -> "moved"
      end

    assignment
    |> JSON.assignment()
    |> Map.put(:status, status)
    |> Map.put(:previous_category_id, previous && previous.category_id)
  end

  def unassign(conn, %{"classification_id" => classification_id, "security_id" => security_id}) do
    with {:ok, cid} <- parse_id(classification_id),
         {:ok, sid} <- parse_id(security_id) do
      {:ok, count} = Classifications.unassign_security(conn.assigns.actor, sid, cid)
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

  defp parse_ids(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case parse_id(value) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      :error -> :error
    end
  end

  defp parse_ids(_values), do: :error

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
