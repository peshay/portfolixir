defmodule PortfolixirWeb.Api.V1.SecurityEventControllerTest do
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Knowledge.Events
  alias PortfolixirWeb.Api.V1.SecurityEventController

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

  # User story (ADR-0048 §1 and §4; found by the correctness hunter in the
  # Sprint 13 closing act):
  # As the operator's agent cleaning up a candidate I no longer watch,
  # I want deleting a security that carries events to be refused the way
  # deleting one with quotes, bookings or research entries already is,
  # so that a normal sequence — record a reporting date, then drop the
  # candidate — answers 409 instead of crashing.
  #
  # Acceptance criteria:
  # - The delete answers 409 with the family's message, and the security and
  #   its events survive.
  # - Removing the events makes the same delete succeed with 204.
  test "deleting a security that carries events is a conflict, not a crash", %{conn: conn} do
    security = create_security!(name: "Calendar Co", ticker: "CAL")
    event = event!(security, %{})

    assert conn
           |> delete("/api/v1/securities/#{security.id}")
           |> json_response(409) ==
             %{"errors" => %{"detail" => "security is referenced by existing records"}}

    assert Catalog.get_security(security.id)
    assert Events.get_event(event.id)

    {:ok, _} = Events.delete_event(Actor.owner_ui(), event)

    assert conn |> delete("/api/v1/securities/#{security.id}") |> response(204) == ""
    refute Catalog.get_security(security.id)
  end

  # User story (#811's bounded-list contract, applied to `days`; found by the
  # edge-case hunter in the Sprint 13 closing act):
  # As the agent calling the calendar reads,
  # I want an absurd horizon capped and echoed the way an absurd limit is,
  # so that a number nobody meant is an answer rather than a 500 or a
  # request that never returns.
  #
  # Acceptance criteria:
  # - `days` above the maximum is capped, echoed, and answers 200.
  # - The same holds for the staleness read, whose cutoff runs backwards and
  #   used to leave the range a date column can store.
  test "an oversized days is capped and echoed, never a crash", %{conn: conn} do
    max = SecurityEventController.max_days()

    %{"data" => upcoming} =
      conn
      |> get("/api/v1/events/upcoming", %{"days" => "99999999999999999999"})
      |> json_response(200)

    assert upcoming["days"] == max

    %{"data" => stale} =
      conn |> get("/api/v1/events/stale", %{"days" => "100000000"}) |> json_response(200)

    assert stale["days"] == max
    assert stale["events"] == []
  end

  # User story (ADR-0048 §6; found by the edge-case hunter):
  # As the agent recording a source link that carries tracking parameters,
  # I want a link the column cannot hold to be refused with a field error,
  # so that a long URL is a 422 I can act on rather than a 500 I cannot.
  #
  # Acceptance criteria:
  # - A `source_url` longer than the column answers 422 naming the field.
  # - A link at the limit is stored.
  test "a source_url longer than the column is a 422, not a 500", %{conn: conn} do
    security = create_security!(name: "Long Link Co", ticker: "LLC")

    too_long = "https://example.invalid/?q=" <> String.duplicate("a", 300)

    assert %{"errors" => %{"source_url" => [_ | _]}} =
             conn
             |> post("/api/v1/securities/#{security.id}/events", %{
               "event" => %{
                 "kind" => "earnings",
                 "date" => "2026-11-04",
                 "timing" => "exact",
                 "source_quality" => "primary",
                 "source_url" => too_long
               }
             })
             |> json_response(422)

    at_limit = "https://example.invalid/?q=" <> String.duplicate("a", 255 - 27)
    assert String.length(at_limit) == 255

    assert %{"data" => %{"source_url" => ^at_limit}} =
             conn
             |> post("/api/v1/securities/#{security.id}/events", %{
               "event" => %{
                 "kind" => "earnings",
                 "date" => "2026-11-04",
                 "timing" => "exact",
                 "source_quality" => "primary",
                 "source_url" => at_limit
               }
             })
             |> json_response(201)
  end

  # User story (ADR-0048 §4; found by the edge-case hunter):
  # As the operator editing an event the agent deleted a moment earlier,
  # I want the write to answer "it is gone",
  # so that the two-writer model ADR-0048 §4 exists for does not answer 500.
  #
  # Acceptance criteria:
  # - Updating or deleting an event that has since vanished answers 404.
  test "a write to an event that has vanished answers 404", %{conn: conn} do
    security = create_security!(name: "Race Co", ticker: "RCE")
    event = event!(security, %{})

    {:ok, _} = Events.delete_event(Actor.owner_ui(), event)

    assert {:error, :stale} = Events.update_event(Actor.owner_ui(), event, %{note: "late"})
    assert {:error, :stale} = Events.delete_event(Actor.owner_ui(), event)

    assert %{"errors" => _} =
             conn
             |> patch("/api/v1/security_events/#{event.id}", %{"event" => %{"confirmed" => true}})
             |> json_response(404)
  end

  # User story (the patch-coverage listing of the pre-promotion CI run, which
  # D-5 requires read BEFORE promotion):
  # As the agent calling the event surface with a malformed request,
  # I want every malformed shape to answer a 4xx naming what is wrong,
  # so that a parameter sent as a list, or a body sent as a string, is a
  # error I can correct rather than a 500 I cannot.
  #
  # Acceptance criteria:
  # - A closed-set or boolean parameter sent as a list is a 422 naming it.
  # - An `event` body that is not an object is a 422, not a crash.
  # - A non-numeric `security_id` filter is a 422.
  # - Deleting an event that has since vanished is a 404 at the route, not
  #   only at the context.
  test "every malformed shape answers a 4xx naming the field", %{conn: conn} do
    security = create_security!(name: "Malformed Co", ticker: "MFC")

    assert %{"errors" => %{"held_only" => [_ | _]}} =
             conn |> get("/api/v1/events/upcoming?held_only[]=yes") |> json_response(422)

    assert %{"errors" => %{"kind" => [_ | _]}} =
             conn |> get("/api/v1/events/stale?kind[]=earnings") |> json_response(422)

    assert %{"errors" => %{"security_id" => [_ | _]}} =
             conn
             |> get("/api/v1/events/unconfirmed", %{"security_id" => "abc"})
             |> json_response(422)

    # An `event` that is not an object: the required fields are simply
    # absent, which is a changeset error rather than a crash.
    assert %{"errors" => errors} =
             conn
             |> post("/api/v1/securities/#{security.id}/events", %{"event" => "nonsense"})
             |> json_response(422)

    assert Map.has_key?(errors, "kind")

    event = event!(security, %{})
    {:ok, _} = Events.delete_event(Actor.owner_ui(), event)

    assert %{"errors" => _} =
             conn |> delete("/api/v1/security_events/#{event.id}") |> json_response(404)
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
