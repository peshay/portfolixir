defmodule PortfolixirWeb.Api.V1.JournalController do
  @moduledoc """
  Read surface for the append-only audit journal (FR-28, ADR-0017).

  Lists journal entries newest-first with optional filters. The response is
  self-describing (FR-13): it echoes the `as_of` instant, the filters actually
  applied, and the ordering, alongside the `data`. By default only real
  (non-scenario) writes are returned; `include_scenarios=true` adds persisted
  what-if entries.

  This is mirrored by the `portfolixir.journal.list` MCP tool (API/MCP parity,
  FR-16/AR-11).
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Journal.Entry
  alias PortfolixirWeb.Api.V1.JSON

  @default_limit 100
  @max_limit 1000

  def index(conn, params) do
    case list_opts(params) do
      {:ok, opts} ->
        entries = Journal.list_entries(opts)

        json(conn, %{
          data: Enum.map(entries, &JSON.journal_entry/1),
          meta: meta(opts, entries)
        })

      {:error, field} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{field => ["is invalid"]}})
    end
  end

  defp meta(opts, entries) do
    %{
      as_of: DateTime.to_iso8601(DateTime.utc_now()),
      order: "inserted_at:desc,id:desc",
      count: length(entries),
      filters: filters_echo(opts)
    }
  end

  defp filters_echo(opts) do
    %{
      resource_type: opts[:resource_type],
      resource_id: opts[:resource_id],
      actor_type: opts[:actor_type] && Atom.to_string(opts[:actor_type]),
      operation: opts[:operation] && Atom.to_string(opts[:operation]),
      include_scenarios: opts[:include_scenarios] == true,
      limit: opts[:limit]
    }
  end

  defp list_opts(params) do
    with {:ok, actor_type} <- enum_param(params, "actor_type", Actor.types()),
         {:ok, operation} <- enum_param(params, "operation", Entry.operations()),
         {:ok, limit} <- limit_param(params) do
      opts =
        [limit: limit, include_scenarios: params["include_scenarios"] == "true"]
        |> put_if_present(:resource_type, params["resource_type"])
        |> put_if_present(:resource_id, params["resource_id"])
        |> put_if_present(:actor_type, actor_type)
        |> put_if_present(:operation, operation)

      {:ok, opts}
    end
  end

  # Accepts a closed-enum string and maps it to its atom without
  # `String.to_atom` (no atom-table growth from untrusted input).
  defp enum_param(params, key, allowed) do
    case Map.get(params, key) do
      value when value in [nil, ""] ->
        {:ok, nil}

      value ->
        case Enum.find(allowed, fn atom -> Atom.to_string(atom) == value end) do
          nil -> {:error, String.to_existing_atom(key)}
          atom -> {:ok, atom}
        end
    end
  end

  defp limit_param(params) do
    case Map.get(params, "limit") do
      value when value in [nil, ""] ->
        {:ok, @default_limit}

      value when is_integer(value) and value > 0 ->
        {:ok, min(value, @max_limit)}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 -> {:ok, min(int, @max_limit)}
          _ -> {:error, :limit}
        end

      _ ->
        {:error, :limit}
    end
  end

  defp put_if_present(opts, _key, value) when value in [nil, ""], do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)
end
