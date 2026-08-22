defmodule PortfolixirWeb.Api.V1.SecurityController do
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Catalog.SecurityFields
  alias PortfolixirWeb.Api.V1.FieldSelection
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.SinceParam

  @sortable_fields Map.new(SecurityFields.sortable(), fn field ->
                     {Atom.to_string(field.key), field.key}
                   end)

  # #732 (extending FR-37): the sparse fieldset resolves against the FULL
  # projection's field list and, when present, supersedes `projection=` — a
  # sparse fieldset IS a projection, chosen field by field.
  @fields_whitelist FieldSelection.whitelist(JSON.security_fields())

  def index(conn, params) do
    with {:ok, opts} <- list_opts(params),
         {:ok, data_quality} <- data_quality_param(params),
         {:ok, serializer} <- listing_serializer(params),
         {:ok, fields} <- FieldSelection.parse(params, @fields_whitelist),
         {:ok, since} <- SinceParam.parse(params) do
      serializer = fields_serializer(fields, serializer)

      securities =
        opts
        |> put_updated_since(since)
        |> list_by(data_quality)
        |> Enum.map(serializer)

      json(conn, SinceParam.put_envelope(%{data: securities}, since))
    else
      {:error, field} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{field => ["is invalid"]}})
    end
  end

  defp put_updated_since(opts, nil), do: opts
  defp put_updated_since(opts, %{cut: cut}), do: Keyword.put(opts, :updated_since, cut)

  defp fields_serializer(nil, serializer), do: serializer

  defp fields_serializer(fields, _serializer),
    do: &(&1 |> JSON.security() |> FieldSelection.take(fields))

  # The data-quality predicates (#705). Routed through `Catalog.DataQuality` so
  # the agent's set is the SAME set the dashboard counts and the securities page
  # links to — the point of the story was that there were three copies of the
  # rule and only two of them had a caller.
  defp list_by(opts, nil), do: Catalog.list_securities(opts)

  defp list_by(opts, id) do
    id
    |> DataQuality.list(opts)
    |> Enum.map(& &1.security)
  end

  # String-keyed and whitelisted: a query param never mints an atom.
  defp data_quality_param(%{"data_quality" => ""}), do: {:ok, nil}

  defp data_quality_param(%{"data_quality" => id}) do
    if DataQuality.valid?(id), do: {:ok, id}, else: {:error, "data_quality"}
  end

  defp data_quality_param(_params), do: {:ok, nil}

  # FR-33: listings default to the slim whitelist projection;
  # `projection=full` opts back into the complete serializer. Named
  # `projection` (not `view`) because `view` means "bucket-view id" on the
  # analytics endpoints. An empty value counts as absent — the same leniency
  # every other param on this route applies. Anything else is a 422 rather
  # than a silent fallback.
  defp listing_serializer(params) do
    case Map.get(params, "projection", "slim") do
      value when value in ["slim", ""] -> {:ok, &JSON.security_listing/1}
      "full" -> {:ok, &JSON.security/1}
      _other -> {:error, "projection"}
    end
  end

  def show(conn, %{"id" => id}) do
    case Catalog.get_security(id) do
      nil ->
        not_found(conn)

      security ->
        # The detail carries the recorded former-ISIN aliases (ADR-0029 §3).
        json(conn, %{data: JSON.security(Catalog.with_identifier_aliases(security))})
    end
  end

  def create(conn, params) do
    attrs = Map.get(params, "security", %{})

    case Catalog.create_security(conn.assigns.actor, attrs) do
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
         {:ok, updated} <- Catalog.update_security(conn.assigns.actor, security, attrs) do
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
        case Catalog.delete_security(conn.assigns.actor, security) do
          {:ok, _} ->
            send_resp(conn, :no_content, "")

          {:error, _changeset} ->
            conflict(conn)
        end
    end
  end

  defp list_opts(params) do
    with {:ok, sort} <- sort_param(params),
         {:ok, holding_status} <- holding_status_param(params),
         {:ok, logo_status} <- logo_status_param(params),
         {:ok, limit} <- int_param(params, "limit", :limit),
         {:ok, offset} <- int_param(params, "offset", :offset) do
      opts =
        []
        |> put_if_present(:query, params["query"])
        |> put_if_present(:sort, sort)
        |> put_if_present(:holding_status, holding_status)
        |> put_if_present(:logo_status, logo_status)
        |> put_if_present(:limit, limit)
        |> put_if_present(:offset, offset)

      {:ok, opts}
    end
  end

  defp logo_status_param(%{"logo_status" => status}) when status in ["missing", "present"] do
    {:ok, status}
  end

  defp logo_status_param(%{"logo_status" => ""}), do: {:ok, nil}
  defp logo_status_param(%{"logo_status" => _}), do: {:error, :logo_status}
  defp logo_status_param(_params), do: {:ok, nil}

  defp int_param(params, key, field) do
    case Map.get(params, key) do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int >= 0 -> {:ok, int}
          _ -> {:error, field}
        end

      _ ->
        {:error, field}
    end
  end

  defp holding_status_param(%{"holding_status" => status})
       when status in ["all", "held", "not_held"] do
    {:ok, status}
  end

  defp holding_status_param(%{"holding_status" => ""}), do: {:ok, nil}
  defp holding_status_param(%{"holding_status" => _}), do: {:error, :holding_status}
  defp holding_status_param(_params), do: {:ok, nil}

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
