defmodule PortfolixirWeb.Api.V1.NoteController do
  @moduledoc """
  JSON API for the security research log (ADR-0044 §§4, 7; issue #750).

  Append (`create`) and the four reads the ADR names as acceptance criteria:
  a security's log newest first (`index`), held positions with no entry for N
  days (`unreviewed`), entries whose source quality is not primary
  (`uncorroborated`), and dated blocks expiring within N days (`expiring`).
  There is deliberately no update and no delete action (§3): a refuted
  finding is withdrawn by appending a `retraction` that supersedes it.
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.Ledger.HeldSecurities
  alias PortfolixirWeb.Api.V1.IdParam
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit
  alias PortfolixirWeb.Api.V1.SinceParam

  @log_note "Entries are append-only: never updated, never deleted. A refuted finding is " <>
              "withdrawn by appending a retraction that supersedes it; both stay readable " <>
              "(superseded_by_ids names what superseded an entry). thesis_state is derived " <>
              "from these entries, never stored."

  # FR-38 / #830: the log's delta note. The log is append-only, so the cut
  # compares inserted_at, and there are no deletions to leave out.
  @delta_note "Entries appended strictly after `since` (UTC), by their inserted_at. The log " <>
                "is append-only, so an entry never changes after it is written and no entry " <>
                "is ever deleted: a retraction arrives as a new entry naming what it " <>
                "supersedes, and superseded_by_ids on an older entry is only complete on a " <>
                "full read. thesis_state always derives from the whole log. Use this " <>
                "response's `as_of` as the next `since`."

  @default_unreviewed_days 90
  @default_expiring_days 30

  # #776: the bound of the four reads, sized above a realistic log (hundreds
  # of securities, a few entries each) so a routine read never sees it.
  @default_limit 1_000
  @max_limit 10_000

  def index(conn, %{"security_id" => security_id} = params) do
    with {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit),
         {:ok, since} <- SinceParam.parse(params),
         %Security{} = security <- Catalog.get_security(security_id) do
      opts = [limit: limit] ++ if(since, do: [inserted_since: since.cut], else: [])

      payload = %{
        data: %{
          security_id: security.id,
          entries:
            security.id
            |> Knowledge.list_notes(opts)
            |> Enum.map(&JSON.security_note/1),
          # The projection reads the whole log, whatever the page (or the
          # delta) shows.
          thesis_state: security.id |> Knowledge.thesis_state() |> JSON.thesis_state(),
          limit: limit,
          log_note: @log_note
        }
      }

      json(conn, SinceParam.put_envelope(payload, since, @delta_note))
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
      nil -> not_found(conn)
    end
  end

  def create(conn, %{"security_id" => security_id} = params) do
    case Catalog.get_security(security_id) do
      %Security{} = security ->
        attrs =
          params
          |> Map.get("note", %{})
          |> note_attrs(security, conn.assigns.actor)

        case Knowledge.append_note(conn.assigns.actor, attrs) do
          {:ok, note} ->
            conn
            |> put_status(:created)
            |> json(%{data: JSON.security_note(note)})

          {:error, changeset} ->
            unprocessable(conn, JSON.errors(changeset))
        end

      nil ->
        not_found(conn)
    end
  end

  # Provenance is the system's to state (#766, a precision of ADR-0044 §4):
  # the author is derived from the authenticated actor, never taken from the
  # body, and the machine-generated marker is reserved for a local-model path
  # that does not exist yet, so a body cannot claim it either way.
  # `security_id` comes from the path, never from the body.
  defp note_attrs(attrs, %Security{id: id}, %Actor{} = actor) when is_map(attrs) do
    attrs
    |> Map.drop(["author", "machine_generated", :author, :machine_generated])
    |> Map.put("author", author_for(actor))
    |> Map.put("security_id", id)
  end

  defp note_attrs(_attrs, security, actor), do: note_attrs(%{}, security, actor)

  defp author_for(%Actor{type: :owner_ui}), do: "operator"
  defp author_for(%Actor{}), do: "agent"

  def unreviewed(conn, params) do
    with {:ok, days} <- days_param(params, @default_unreviewed_days),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit) do
      today = Portfolixir.Clock.today()
      rows = Knowledge.unreviewed_positions(days: days, today: today, limit: limit)

      json(conn, %{
        data: %{
          days: days,
          as_of: JSON.date(today),
          limit: limit,
          positions: Enum.map(rows, &unreviewed_row/1),
          basis: unreviewed_basis() <> " A limit keeps the most overdue positions."
        }
      })
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
    end
  end

  defp unreviewed_row(%{security: security} = row) do
    %{
      security_id: security.id,
      security_name: security.name,
      isin: security.isin,
      ticker_symbol: security.ticker_symbol,
      last_entry_as_of: JSON.date(row.last_entry_as_of),
      days_since_last_entry: row.days_since_last_entry
    }
  end

  def uncorroborated(conn, params) do
    with {:ok, security_id} <- optional_id_param(params, "security_id"),
         {:ok, include_superseded} <- bool_param(params, "include_superseded", false),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit) do
      entries =
        Knowledge.uncorroborated_notes(
          security_id: security_id,
          include_superseded: include_superseded,
          limit: limit
        )

      json(conn, %{
        data: %{
          security_id: security_id,
          include_superseded: include_superseded,
          limit: limit,
          entries: Enum.map(entries, &JSON.security_note/1),
          basis:
            "Entries whose source_quality is not primary (" <>
              Enum.join(SecurityNote.source_qualities() -- ["primary"], ", ") <>
              "); superseded entries are skipped unless include_superseded=true. " <>
              "A limit keeps the newest entries."
        }
      })
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
    end
  end

  def expiring(conn, params) do
    with {:ok, days} <- days_param(params, @default_expiring_days),
         {:ok, security_id} <- optional_id_param(params, "security_id"),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit) do
      today = Portfolixir.Clock.today()

      entries =
        Knowledge.expiring_notes(
          days: days,
          today: today,
          security_id: security_id,
          limit: limit
        )

      json(conn, %{
        data: %{
          days: days,
          as_of: JSON.date(today),
          security_id: security_id,
          limit: limit,
          entries:
            Enum.map(entries, fn note ->
              note
              |> JSON.security_note()
              |> Map.put(:days_until_expiry, note.days_until_expiry)
            end),
          basis:
            "Entries with as_of <= valid_until <= as_of + days, soonest first; " <>
              "superseded entries (a lifted block) are skipped. A limit keeps the " <>
              "soonest-expiring entries."
        }
      })
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
    end
  end

  # The held predicate's kinds are read from the one predicate (#839), so the
  # basis cannot name a narrower rule than the one the read applied.
  defp unreviewed_basis do
    %{increases: increases, decreases: decreases} = HeldSecurities.quantity_kinds()

    "Held securities (net quantity <> 0 across all depots; " <>
      Enum.join(increases, ", ") <>
      " add, " <>
      Enum.join(decreases, ", ") <>
      " subtract, a security_transfer between own depots nets to zero) whose newest " <>
      "entry as_of is older than `days` before as_of, or that have no entry at all."
  end

  # A non-negative integer; absent or empty means the default.
  defp days_param(params, default) do
    case Map.get(params, "days") do
      nil -> {:ok, default}
      "" -> {:ok, default}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      value when is_binary(value) -> parse_non_negative(value, "days")
      _ -> {:error, "days"}
    end
  end

  defp parse_non_negative(value, field) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> {:ok, int}
      _ -> {:error, field}
    end
  end

  defp optional_id_param(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      value -> value |> IdParam.parse() |> id_result(key)
    end
  end

  defp id_result({:ok, id}, _key), do: {:ok, id}
  defp id_result(:error, key), do: {:error, key}

  defp bool_param(params, key, default) do
    case Map.get(params, key) do
      nil -> {:ok, default}
      "" -> {:ok, default}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      true -> {:ok, true}
      false -> {:ok, false}
      _ -> {:error, key}
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
