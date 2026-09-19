defmodule PortfolixirWeb.Api.V1.SecurityEventControllerTest do
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge.Events

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp event!(security, attrs) do
    {:ok, event} =
      Events.create_event(
        Actor.owner_ui(),
        Enum.into(attrs, %{
          security_id: security.id,
          kind: "earnings",
          date: ~D[2026-11-04],
          timing: "exact",
          source_quality: "primary"
        })
      )

    event
  end

  # User story (FR-44, ADR-0048 §5.1, §6):
  # As the operator's agent,
  # I want to record and read one security's calendar over the JSON API,
  # so that a date I must not miss is kept where the instance keeps it and
  # not in a local file I rebuild from the holdings.
  #
  # Acceptance criteria:
  # - A POST records the event and answers 201 with its fields.
  # - The GET lists that security's events, soonest first, with the closed
  #   sets echoed as strings.
  test "records and lists one security's events", %{conn: conn} do
    security = create_security!(name: "Cal Co", ticker: "CAL")

    %{"data" => created} =
      conn
      |> post("/api/v1/securities/#{security.id}/events", %{
        "event" => %{
          "kind" => "earnings",
          "date" => "2026-11-04",
          "timing" => "exact",
          "source_url" => "https://example.invalid/ir",
          "source_quality" => "primary",
          "checked_at" => "2026-09-19",
          "note" => "Q3 report"
        }
      })
      |> json_response(201)

    assert created["kind"] == "earnings"
    assert created["timing"] == "exact"
    assert created["date"] == "2026-11-04"
    assert created["confirmed"] == false
    assert created["security_id"] == security.id

    %{"data" => data} =
      conn |> get("/api/v1/securities/#{security.id}/events") |> json_response(200)

    assert data["security_id"] == security.id
    assert [row] = data["events"]
    assert row["id"] == created["id"]
    assert data["events_note"] =~ "books nothing"
  end

  # Acceptance criteria (ADR-0048 §4):
  # - A rescheduled date is a PATCH on the same row, and a duplicate is
  #   removed with a DELETE; both are journaled by the context.
  test "reschedules and removes an event", %{conn: conn} do
    security = create_security!(name: "Move Co", ticker: "MOV")
    event = event!(security, [])

    %{"data" => moved} =
      conn
      |> patch("/api/v1/security_events/#{event.id}", %{
        "event" => %{"date" => "2026-11-11", "confirmed" => true}
      })
      |> json_response(200)

    assert moved["id"] == event.id
    assert moved["date"] == "2026-11-11"
    assert moved["confirmed"] == true

    assert conn |> delete("/api/v1/security_events/#{event.id}") |> response(204)
    assert Events.count_events() == 0
  end

  # User story (ADR-0048 §2, §5.2 — the read the agent is missing):
  # As the operator's agent planning a purchase,
  # I want the dates due in the next N days across the whole catalog,
  # so that a candidate I do not own yet cannot have an invisible date.
  #
  # Acceptance criteria:
  # - The default scope is the whole catalog; `held_only=true` narrows it and
  #   is never the default.
  # - The payload states the scope it applied, so the answer is
  #   self-describing (FR-13).
  test "upcoming covers the catalog by default and states its scope", %{conn: conn} do
    world = base_world(name: "Cat World", cash_name: "CW Cash", depot_name: "CW Depot")
    held = create_security!(name: "Owned Co", ticker: "OWN")
    candidate = create_security!(name: "Wanted Co", ticker: "WNT")
    buy!(world, held, quantity: "1", price: "100", date: ~D[2026-01-05])

    today = Portfolixir.Clock.today()
    event!(held, date: Date.add(today, 3))
    event!(candidate, date: Date.add(today, 4))

    %{"data" => data} =
      conn |> get("/api/v1/events/upcoming", %{"days" => "30"}) |> json_response(200)

    assert data["days"] == 30
    assert data["held_only"] == false
    assert data["scope_note"] =~ "whole catalog"
    assert length(data["events"]) == 2

    %{"data" => narrowed} =
      conn
      |> get("/api/v1/events/upcoming", %{"days" => "30", "held_only" => "true"})
      |> json_response(200)

    assert narrowed["held_only"] == true
    assert Enum.map(narrowed["events"], & &1["security_id"]) == [held.id]
  end

  # Acceptance criteria (ADR-0048 §5.3, §5.4):
  # - The "did it happen?" queue and the "nobody re-read this" queue are two
  #   separate reads, each echoing what it applied.
  test "answers the unconfirmed-past and the stale reads", %{conn: conn} do
    security = create_security!(name: "Queue Co", ticker: "QUE")
    today = Portfolixir.Clock.today()

    past = event!(security, date: Date.add(today, -5))
    event!(security, date: Date.add(today, -6), confirmed: true)

    %{"data" => unconfirmed} = conn |> get("/api/v1/events/unconfirmed") |> json_response(200)
    assert Enum.map(unconfirmed["events"], & &1["id"]) == [past.id]

    %{"data" => stale} =
      conn |> get("/api/v1/events/stale", %{"days" => "30"}) |> json_response(200)

    assert stale["days"] == 30
    # Never checked counts as stale, with a null age rather than a number.
    assert Enum.any?(stale["events"], &(&1["days_since_checked"] == nil))
  end

  # Acceptance criteria (ADR-0048 §6, AGENTS.md hard rules):
  # - An unknown closed-set value is a 422 naming the field, never a silent
  #   fallback and never a new atom.
  # - A malformed days or kind filter is a 422; an unknown security is a 404.
  test "refuses malformed input", %{conn: conn} do
    security = create_security!(name: "Bad Co", ticker: "BAD")

    assert %{"errors" => %{"kind" => [_ | _]}} =
             conn
             |> post("/api/v1/securities/#{security.id}/events", %{
               "event" => %{
                 "kind" => "rumour",
                 "date" => "2026-11-04",
                 "timing" => "exact",
                 "source_quality" => "primary"
               }
             })
             |> json_response(422)

    assert %{"errors" => %{"days" => [_ | _]}} =
             conn |> get("/api/v1/events/upcoming", %{"days" => "soon"}) |> json_response(422)

    assert %{"errors" => %{"kind" => [_ | _]}} =
             conn |> get("/api/v1/events/upcoming", %{"kind" => "rumour"}) |> json_response(422)

    assert %{"errors" => _} =
             conn |> get("/api/v1/securities/999999/events") |> json_response(404)

    assert %{"errors" => _} =
             conn |> delete("/api/v1/security_events/999999") |> json_response(404)
  end

  # Acceptance criteria (AR-11):
  # - Every event surface is behind the local bearer token.
  test "requires the bearer token", %{conn: conn} do
    conn = delete_req_header(conn, "authorization")

    for path <- ["/api/v1/events/upcoming", "/api/v1/events/unconfirmed", "/api/v1/events/stale"] do
      conn |> get(path) |> json_response(401)
    end
  end
end
