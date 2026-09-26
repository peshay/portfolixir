defmodule PortfolixirWeb.ApiV1FutureDatesTest do
  # E25 S6 (#891), F44 and G09 over the API (and MCP, which wraps it): a
  # research-log entry's as_of after the instance's calendar day, and an
  # event's checked_at later than tomorrow, answer 422 and store nothing.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Clock
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.WorldFixtures

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn, security: WorldFixtures.create_security!(name: "Estuary Rail", ticker: "ESR")}
  end

  defp iso(days), do: Clock.today() |> Date.add(days) |> Date.to_iso8601()

  # User story:
  # As the operator's agent appending to the research log,
  # I want an entry dated after today refused with the field named,
  # so that a slip of the year never becomes a permanent entry.
  #
  # Acceptance criteria:
  # - POST .../notes with as_of tomorrow answers 422 on as_of and stores
  #   nothing; as_of today answers 201.
  test "a research-log entry dated after today answers 422", %{conn: conn, security: security} do
    note = %{
      "kind" => "evidence",
      "body" => "Guidance reiterated at the investor day.",
      "source_quality" => "primary"
    }

    path = "/api/v1/securities/#{security.id}/notes"

    body =
      conn
      |> post(path, %{"note" => Map.put(note, "as_of", iso(1))})
      |> json_response(422)

    assert body["errors"]["as_of"] == ["must not be in the future"]
    assert Knowledge.list_notes(security.id) == []

    assert conn |> post(path, %{"note" => Map.put(note, "as_of", iso(0))}) |> json_response(201)
  end

  # User story:
  # As the operator's agent keeping the event calendar,
  # I want a checked_at later than tomorrow refused on create and update,
  # so that an event cannot be hidden from the stale-calendar read.
  #
  # Acceptance criteria:
  # - POST .../events and PATCH /api/v1/security_events/:id with checked_at
  #   two days ahead answer 422 on checked_at and write nothing; today and
  #   tomorrow are accepted.
  test "an event's checked_at past tomorrow answers 422 on create and update",
       %{conn: conn, security: security} do
    event = %{
      "kind" => "earnings",
      "date" => iso(30),
      "timing" => "estimated",
      "source_quality" => "awareness"
    }

    path = "/api/v1/securities/#{security.id}/events"

    body =
      conn
      |> post(path, %{"event" => Map.put(event, "checked_at", iso(2))})
      |> json_response(422)

    assert body["errors"]["checked_at"] == ["must not be later than tomorrow"]
    assert Events.list_for_security(security.id) == []

    created =
      conn
      |> post(path, %{"event" => Map.put(event, "checked_at", iso(0))})
      |> json_response(201)

    id = created["data"]["id"]

    assert conn
           |> patch("/api/v1/security_events/#{id}", %{"event" => %{"checked_at" => iso(2)}})
           |> json_response(422)

    assert Events.get_event(id).checked_at == Clock.today()

    assert conn
           |> patch("/api/v1/security_events/#{id}", %{"event" => %{"checked_at" => iso(1)}})
           |> json_response(200)
  end
end
