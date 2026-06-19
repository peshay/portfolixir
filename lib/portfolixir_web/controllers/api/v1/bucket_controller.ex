defmodule PortfolixirWeb.Api.V1.BucketController do
  @moduledoc """
  JSON API for buckets (ADR-0018): the overlapping tags applied to holdings.

  Writes are actor-first and routed through `Portfolixir.Buckets`, which journals
  every bucket-definition change (ADR-0017). The controller never touches the
  Repo.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Buckets
  alias Portfolixir.Buckets.Bucket
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, _params) do
    json(conn, %{data: Enum.map(Buckets.list_buckets(), &JSON.bucket/1)})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, bid} <- parse_id(id),
         %Bucket{} = bucket <- Buckets.get_bucket(bid) do
      json(conn, %{data: JSON.bucket(bucket)})
    else
      _ -> not_found(conn)
    end
  end

  def create(conn, params) do
    attrs = Map.get(params, "bucket", %{})

    case Buckets.create_bucket(conn.assigns.actor, attrs) do
      {:ok, bucket} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.bucket(bucket)})

      {:error, changeset} ->
        unprocessable(conn, JSON.errors(changeset))
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "bucket", %{})

    with {:ok, bid} <- parse_id(id),
         %Bucket{} = bucket <- Buckets.get_bucket(bid),
         {:ok, updated} <- Buckets.update_bucket(conn.assigns.actor, bucket, attrs) do
      json(conn, %{data: JSON.bucket(updated)})
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
      {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, bid} <- parse_id(id),
         %Bucket{} = bucket <- Buckets.get_bucket(bid) do
      case Buckets.delete_bucket(conn.assigns.actor, bucket) do
        {:ok, _} -> send_resp(conn, :no_content, "")
        {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
      end
    else
      nil -> not_found(conn)
      :error -> not_found(conn)
    end
  end

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
