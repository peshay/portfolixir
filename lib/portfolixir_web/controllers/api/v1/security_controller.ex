defmodule PortfolixirWeb.Api.V1.SecurityController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.SecurityFields
  alias PortfolixirWeb.Api.V1.JSON

  @sortable_fields Map.new(SecurityFields.sortable(), fn field ->
                     {Atom.to_string(field.key), field.key}
                   end)

  def index(conn, params) do
    case list_opts(params) do
      {:ok, opts} ->
        securities =
          opts
          |> Catalog.list_securities()
          |> Enum.map(&JSON.security/1)

        json(conn, %{data: securities})

      {:error, field} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{field => ["is invalid"]}})
    end
  end

  def show(conn, %{"id" => id}) do
    case Catalog.get_security(id) do
      nil -> not_found(conn)
      security -> json(conn, %{data: JSON.security(security)})
    end
  end

  def create(conn, params) do
    attrs = Map.get(params, "security", %{})

    case Catalog.create_security(attrs) do
      {:ok, security} ->
        conn
        |> put_status(:created)
        |> json(%{data: JSON.security(security)})

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "security", %{})

    with security when not is_nil(security) <- Catalog.get_security(id),
         {:ok, updated} <- Catalog.update_security(security, attrs) do
      json(conn, %{data: JSON.security(updated)})
    else
      nil -> not_found(conn)
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Catalog.get_security(id) do
      nil ->
        not_found(conn)

      security ->
        case Catalog.delete_security(security) do
          {:ok, _} ->
            send_resp(conn, :no_content, "")

          {:error, _changeset} ->
            conflict(conn)
        end
    end
  end

  defp list_opts(params) do
    with {:ok, sort} <- sort_param(params) do
      opts =
        []
        |> put_if_present(:query, params["query"])
        |> put_if_present(:sort, sort)

      {:ok, opts}
    end
  end

  defp sort_param(%{"sort" => sort} = params) when is_binary(sort) do
    direction = Map.get(params, "direction", "asc")

    with {:ok, key} <- Map.fetch(@sortable_fields, sort),
         {:ok, dir} <- direction(direction) do
      {:ok, {key, dir}}
    else
      :error -> {:error, :sort}
    end
  end

  defp sort_param(_params), do: {:ok, nil}

  defp direction("asc"), do: {:ok, :asc}
  defp direction("desc"), do: {:ok, :desc}
  defp direction(_), do: :error

  defp put_if_present(opts, _key, nil), do: opts
  defp put_if_present(opts, _key, ""), do: opts
  defp put_if_present(opts, _key, []), do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end

  defp validation_error(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: JSON.errors(changeset)})
  end

  defp conflict(conn) do
    conn
    |> put_status(:conflict)
    |> json(%{errors: %{detail: "security is referenced by existing records"}})
  end
end
