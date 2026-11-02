defmodule PortfolixirWeb.Api.V1.JournalController do
  @moduledoc """
  Read surface for the append-only audit journal (FR-28, ADR-0017).

  Lists journal entries newest-first with optional filters. The response is
  self-describing (FR-13): it echoes the `as_of` instant, the filters actually
  applied, and the ordering, alongside the `data`. By default only real
  (non-scenario) writes are returned; `include_scenarios=true` adds persisted
  what-if entries.

  The parameters are read by `PortfolixirWeb.Api.V1.JournalQuery`, which the
  Audit journal page reads them with too (Sprint 23 V3), so both answer the
  same rows. `limit=` goes through `PortfolixirWeb.Api.V1.ListLimit.parse/3`,
  the one parser of the bounded-list family (#771, #776, #811): absent or blank is the
  default, an oversized value is capped at the maximum and echoed in
  `meta.filters.limit` and beside `data` with `truncated` (#1254), and zero, a negative or a non-number is a `422` naming
  the field.

  This is mirrored by the `portfolixir.journal.list` MCP tool (API/MCP parity,
  FR-16/AR-11).
  """
  use PortfolixirWeb, :controller

  alias PortfolixirWeb.Api.V1.JournalQuery
  alias PortfolixirWeb.Api.V1.JSON

  def index(conn, params) do
    case JournalQuery.parse(params) do
      {:ok, opts} ->
        # #1254: one row past the limit tells a cut answer from the whole.
        {entries, truncated} = JournalQuery.list(opts)

        json(conn, %{
          data: Enum.map(entries, &JSON.journal_entry/1),
          limit: Keyword.fetch!(opts, :limit),
          truncated: truncated,
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
end
