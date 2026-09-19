defmodule PortfolixirWeb.Api.V1.SecurityEventController do
  @moduledoc """
  JSON API for security events (FR-44, ADR-0048 §5).

  The four reads the record names as its acceptance criteria — one security's
  events, what is due across the catalog, what passed unconfirmed, and what
  nobody has re-read — plus the three writes an agent needs to keep the
  calendar current.

  Two boundaries are visible in this module and are not accidents:

    * **The catalog is the default scope** (§2). `held_only=true` narrows the
      catalog-wide reads and is never the default, because a calendar that
      defaults to the holdings cannot hold a date for a security not yet
      owned — which is the failure this object exists to prevent.
    * **This is a pull surface.** The due-date read is polled; nothing is
      pushed anywhere (B3.7), nothing fetches a calendar (B3.3) and no rule
      reads these rows (FR-43, B3.6).

  Mirrored by the `portfolixir.events.*` MCP tools (API/MCP parity,
  FR-16/AR-11).
  """
  use PortfolixirWeb, :controller

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Knowledge.SecurityEvent
  alias PortfolixirWeb.Api.V1.JSON
  alias PortfolixirWeb.Api.V1.ListLimit

  @events_note "An event is a dated calendar fact that books nothing (ADR-0048): a split " <>
                 "changes a position and is a ledger event, an earnings date changes " <>
                 "nothing until a price moves. When the dividend is actually paid, book it " <>
                 "through the ledger as always and mark the event confirmed — the event is " <>
                 "never converted into a transaction. Rows are mutable: a rescheduled date " <>
                 "is a PATCH on the same row, not a second row, and the change history is " <>
                 "in the audit journal."

  @scope_note "Scope is the whole catalog, not the holdings: a security with no position " <>
                "is listed like any other, because a purchase candidate's date is exactly " <>
                "the one worth not missing. held_only=true narrows to securities with a " <>
                "non-zero ledger quantity."

  @due_note "A window or month event is due when ANY day it could fall on is inside the " <>
              "horizon — the conservative direction, because the failure being prevented " <>
              "is a missed date rather than an early warning."

  @stale_note "Events whose checked_at (the day the fact was last re-read against its " <>
                "source) is older than days, or that were never checked at all — those " <>
                "carry days_since_checked null. Distinct from the unconfirmed read: a " <>
                "confirmed future date nobody has re-read is a different risk from a past " <>
                "date nobody resolved."

  @default_limit 1_000
  @max_limit 10_000

  def index(conn, %{"security_id" => security_id} = params) do
    with {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit),
         %Security{} = security <- Catalog.get_security(security_id) do
      json(conn, %{
        data: %{
          security_id: security.id,
          events:
            security.id
            |> Events.list_for_security(limit: limit)
            |> Enum.map(&JSON.security_event/1),
          limit: limit,
          events_note: @events_note
        }
      })
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
      nil -> not_found(conn)
    end
  end

  def create(conn, %{"security_id" => security_id} = params) do
    case Catalog.get_security(security_id) do
      %Security{} = security ->
        attrs = event_attrs(Map.get(params, "event", %{}), security)

        case Events.create_event(conn.assigns.actor, attrs) do
          {:ok, event} ->
            conn |> put_status(:created) |> json(%{data: JSON.security_event(event)})

          {:error, changeset} ->
            unprocessable(conn, JSON.errors(changeset))
        end

      nil ->
        not_found(conn)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, event_id} <- parse_id(id),
         %SecurityEvent{} = event <- Events.get_event(event_id) do
      # `security_id` is not re-assignable: an event belongs to the security
      # it was recorded against, and moving one would silently rewrite two
      # calendars at once.
      attrs = params |> Map.get("event", %{}) |> drop_reserved()

      case Events.update_event(conn.assigns.actor, event, attrs) do
        {:ok, updated} -> json(conn, %{data: JSON.security_event(updated)})
        {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
      end
    else
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, event_id} <- parse_id(id),
         %SecurityEvent{} = event <- Events.get_event(event_id),
         {:ok, _deleted} <- Events.delete_event(conn.assigns.actor, event) do
      send_resp(conn, :no_content, "")
    else
      {:error, changeset} -> unprocessable(conn, JSON.errors(changeset))
      :error -> not_found(conn)
      nil -> not_found(conn)
    end
  end

  def upcoming(conn, params) do
    with {:ok, days} <- days_param(params, Events.default_upcoming_days()),
         {:ok, kind} <- kind_param(params),
         {:ok, held_only} <- boolean_param(params, "held_only"),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit) do
      today = Clock.today()

      events =
        Events.upcoming(
          days: days,
          today: today,
          kind: kind,
          held_only: held_only,
          limit: limit
        )

      json(conn, %{
        data: %{
          days: days,
          as_of: JSON.date(today),
          held_only: held_only,
          kind: kind,
          limit: limit,
          events: Enum.map(events, &JSON.security_event/1),
          scope_note: @scope_note,
          due_note: @due_note,
          events_note: @events_note
        }
      })
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
    end
  end

  def unconfirmed(conn, params) do
    with {:ok, kind} <- kind_param(params),
         {:ok, held_only} <- boolean_param(params, "held_only"),
         {:ok, security_id} <- security_id_param(params),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit) do
      today = Clock.today()

      events =
        Events.unconfirmed_past(
          today: today,
          kind: kind,
          held_only: held_only,
          security_id: security_id,
          limit: limit
        )

      json(conn, %{
        data: %{
          as_of: JSON.date(today),
          held_only: held_only,
          kind: kind,
          security_id: security_id,
          limit: limit,
          events: Enum.map(events, &JSON.security_event/1),
          scope_note: @scope_note,
          basis:
            "Events whose whole span is before as_of and whose confirmed flag is false — " <>
              "the did-it-actually-happen queue, which is what keeps the calendar from " <>
              "quietly rotting."
        }
      })
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
    end
  end

  def stale(conn, params) do
    with {:ok, days} <- days_param(params, Events.default_stale_days()),
         {:ok, kind} <- kind_param(params),
         {:ok, held_only} <- boolean_param(params, "held_only"),
         {:ok, security_id} <- security_id_param(params),
         {:ok, limit} <- ListLimit.parse(params, @default_limit, @max_limit) do
      today = Clock.today()

      events =
        Events.stale(
          days: days,
          today: today,
          kind: kind,
          held_only: held_only,
          security_id: security_id,
          limit: limit
        )

      json(conn, %{
        data: %{
          days: days,
          as_of: JSON.date(today),
          held_only: held_only,
          kind: kind,
          security_id: security_id,
          limit: limit,
          events: Enum.map(events, &JSON.security_event/1),
          scope_note: @scope_note,
          basis: @stale_note
        }
      })
    else
      {:error, field} -> unprocessable(conn, %{field => ["is invalid"]})
    end
  end

  # `security_id` comes from the path, never from the body, and
  # `machine_generated` is reserved for a local-model path that does not exist
  # (#766's precision, applied here from the first commit).
  defp event_attrs(attrs, %Security{id: id}) when is_map(attrs) do
    attrs
    |> drop_reserved()
    |> Map.put("security_id", id)
  end

  defp event_attrs(_attrs, security), do: event_attrs(%{}, security)

  defp drop_reserved(attrs) when is_map(attrs),
    do: Map.drop(attrs, ["security_id", "machine_generated", :security_id, :machine_generated])

  defp drop_reserved(_attrs), do: %{}

  defp days_param(params, default) do
    case Map.get(params, "days") do
      value when value in [nil, ""] ->
        {:ok, default}

      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {days, ""} when days >= 0 -> {:ok, days}
          _ -> {:error, :days}
        end

      _ ->
        {:error, :days}
    end
  end

  # A closed-enum string mapped to its atom without `String.to_atom/1`; an
  # unknown kind is a 422 rather than a silent full list.
  defp kind_param(params) do
    case Map.get(params, "kind") do
      value when value in [nil, ""] -> {:ok, nil}
      value when is_binary(value) -> known_kind(value)
      _ -> {:error, :kind}
    end
  end

  defp known_kind(value) do
    if value in SecurityEvent.kinds(),
      do: {:ok, value},
      else: {:error, :kind}
  end

  defp boolean_param(params, key) do
    case Map.get(params, key) do
      value when value in [nil, ""] -> {:ok, false}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      true -> {:ok, true}
      false -> {:ok, false}
      _ -> {:error, String.to_existing_atom(key)}
    end
  end

  defp security_id_param(params) do
    case Map.get(params, "security_id") do
      value when value in [nil, ""] ->
        {:ok, nil}

      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {id, ""} -> {:ok, id}
          _ -> {:error, :security_id}
        end

      _ ->
        {:error, :security_id}
    end
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}
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
