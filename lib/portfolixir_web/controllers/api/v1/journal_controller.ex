defmodule PortfolixirWeb.Api.V1.JournalController do
  @moduledoc """
  Read surface for the append-only audit journal (FR-28, ADR-0017).

  Lists journal entries newest-first with optional filters. The response is
  self-describing (FR-13): it echoes the `as_of` instant, the filters actually
  applied, and the ordering, alongside the `data`. By default only real
  (non-scenario) writes are returned; `include_scenarios=true` adds persisted
  what-if entries.

  `limit=` goes through `PortfolixirWeb.Api.V1.ListLimit.parse/3`, the one
  parser of the bounded-list family (#771, #776, #811): absent or blank is the
  default, an oversized value is capped at the maximum and echoed in
  `meta.filters.limit`, and zero, a negative or a non-number is a `422` naming
  the field.

  This is mirrored by the `portfolixir.journal.list` MCP tool (API/MCP parity,
  FR-16/AR-11).
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Journal.Entry
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit
  alias PortfolixirWeb.Api.V1.TextParam

  # #811: the bound is the family's, spelled the family's way. This read
  # carried its own copy of the parser until Sprint 13 — identical in
  # behaviour and therefore exactly the kind of duplicate that drifts.
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
    with {:ok, resource_type} <- text_param(params, "resource_type"),
         {:ok, resource_id} <- text_param(params, "resource_id"),
         {:ok, actor_type} <- enum_param(params, "actor_type", Actor.types()),
         {:ok, operation} <- enum_param(params, "operation", Entry.operations()),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit) do
      opts =
        [limit: limit, include_scenarios: params["include_scenarios"] == "true"]
        |> put_if_present(:resource_type, resource_type)
        |> put_if_present(:resource_id, resource_id)
        |> put_if_present(:actor_type, actor_type)
        |> put_if_present(:operation, operation)

      {:ok, opts}
    end
  end

  # The text rule every writer meets (TextParam, G24 review round).
  defp text_param(params, key) do
    case TextParam.parse(params, key) do
      {:ok, text} -> {:ok, text}
      :error -> {:error, String.to_existing_atom(key)}
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

  defp put_if_present(opts, _key, value) when value in [nil, ""], do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)
end
