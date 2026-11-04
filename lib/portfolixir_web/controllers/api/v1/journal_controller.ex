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

  `since=` (Sprint 24 J2, decision D-4) makes the read the family's paged
  delta (K17), as `SinceParam` describes it: the entries strictly after the
  cut, oldest first, with `has_more` and a top-level `as_of` that is the
  next `since` (a cursor `<instant>~<id>` at the page's last entry when the
  page is full). It is the only way to reach entries past the newest 1000.
  `meta.as_of` stays the read's instant; without `since` the read is as it
  was, newest first.

  This is mirrored by the `portfolixir.journal.list` MCP tool (API/MCP parity,
  FR-16/AR-11).
  """
  use PortfolixirWeb, :controller

  alias PortfolixirWeb.Api.V1.JournalQuery
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.SinceParam

  # J2: the journal's delta note. The journal is append-only, so the cut
  # compares inserted_at and nothing is updated or deleted after the cut.
  @delta_note "Entries written strictly after `since` (UTC), by their inserted_at, oldest " <>
                "first. The journal is append-only: an entry never changes after it is " <>
                "written and none is ever deleted. meta.as_of is the read's instant, " <>
                "not the cursor. " <> SinceParam.page_rule()

  def index(conn, params) do
    case JournalQuery.parse(params) do
      {:ok, opts} ->
        since = opts[:since]
        order = if since, do: :asc, else: :desc
        # #1254: one row past the limit tells a cut answer from the whole;
        # K17: under since, that page is oldest first after the cursor.
        {entries, truncated} = JournalQuery.list(opts, order)

        payload = %{
          data: Enum.map(entries, &JSON.journal_entry/1),
          limit: Keyword.fetch!(opts, :limit),
          truncated: truncated,
          meta: meta(opts, entries, order)
        }

        page = %{has_more: truncated, last: last_stamp(entries)}
        json(conn, SinceParam.put_page_envelope(payload, since, @delta_note, page))

      {:error, field} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{field => ["is invalid"]}})
    end
  end

  defp meta(opts, entries, order) do
    %{
      as_of: DateTime.to_iso8601(DateTime.utc_now()),
      order: "inserted_at:#{order},id:#{order}",
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
      since: opts[:since] && opts[:since].raw,
      limit: opts[:limit]
    }
  end

  # The page's last entry, for its cursor; the stamp to the microsecond.
  defp last_stamp([]), do: nil

  defp last_stamp(entries) do
    last = List.last(entries)
    {DateTime.to_naive(last.inserted_at), last.id}
  end
end
