defmodule PortfolixirWeb.ApiV1NotesTest do
  # ADR-0044 §§4, 7 (issue #750) and §1 (issue #749): the research log over
  # the JSON API — append, the four reads, and the thesis state carried in
  # the security detail. The MCP companion wraps these 1:1
  # (mcp-server/test/tools.test.ts).
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp get_json(conn, path, status \\ 200) do
    conn |> api_conn() |> get(path) |> json_response(status)
  end

  defp post_json(conn, path, body, status) do
    conn |> api_conn() |> post(path, Jason.encode!(body)) |> json_response(status)
  end

  defp append!(security, attrs) do
    base = %{
      security_id: security.id,
      author: "agent",
      kind: "evidence",
      body: "finding",
      source_quality: "primary",
      as_of: ~D[2026-08-01]
    }

    {:ok, note} = Knowledge.append_note(Actor.owner_ui(), Map.merge(base, attrs))
    note
  end

  # User story (ADR-0044 §§2–4, §7.1; issue #750):
  # As the operating agent,
  # I want to append an entry to a security's research log and read the
  # whole log newest first over the API,
  # so that my next run starts from one call — and a refuted finding is
  # withdrawn by appending a retraction, never by editing or deleting.
  #
  # Acceptance criteria:
  # - POST /api/v1/securities/:security_id/notes creates the entry (201),
  #   journaled under the API-token actor; closed-set violations are 422s
  #   naming the field.
  # - GET /api/v1/securities/:security_id/notes lists entries newest first,
  #   each with superseded_by_ids, plus the derived thesis_state and a note
  #   stating that entries never vanish.
  # - There is no PATCH and no DELETE route for an entry.
  test "appends an entry and lists the log newest first", %{conn: conn} do
    security = WorldFixtures.create_security!(name: "Log Co.", ticker: "LOGC")

    created =
      post_json(
        conn,
        "/api/v1/securities/#{security.id}/notes",
        %{
          "note" => %{
            "kind" => "thesis",
            "body" => "Pricing power holds through 2027.",
            "conviction" => "high",
            "invalidation_condition" => "gross margin below 40% for two quarters",
            "time_stop" => "2027-06-30",
            "source_quality" => "primary",
            "source_url" => "https://example.invalid/ir/annual",
            "as_of" => "2026-08-01"
          }
        },
        201
      )

    assert %{"data" => thesis} = created
    assert thesis["kind"] == "thesis"
    assert thesis["author"] == "agent"
    assert thesis["conviction"] == "high"
    assert thesis["machine_generated"] == false
    assert thesis["as_of"] == "2026-08-01"
    assert thesis["superseded_by_ids"] == []
    assert is_binary(thesis["inserted_at"])

    assert [entry] = Journal.list_entries(resource_type: "security_note")
    assert entry.actor_type == :api_token_rw

    retraction =
      post_json(
        conn,
        "/api/v1/securities/#{security.id}/notes",
        %{
          "note" => %{
            "kind" => "retraction",
            "body" => "Guided down twice; thesis withdrawn.",
            "supersedes_id" => thesis["id"],
            "source_quality" => "primary",
            "as_of" => "2026-08-20"
          }
        },
        201
      )

    assert %{"data" => data} = get_json(conn, "/api/v1/securities/#{security.id}/notes")
    assert data["security_id"] == security.id
    assert [newest, oldest] = data["entries"]
    assert newest["id"] == retraction["data"]["id"]
    assert oldest["id"] == thesis["id"]
    assert oldest["superseded_by_ids"] == [newest["id"]]
    assert oldest["superseded"] == true
    assert newest["superseded"] == false

    assert data["thesis_state"]["status"] == "retracted"
    assert data["thesis_state"]["derived_from_entry_id"] == thesis["id"]
    assert data["thesis_state"]["retracted_by_entry_id"] == newest["id"]
    assert data["log_note"] =~ "never"

    # No update, no delete (ADR-0044 §3): the routes do not exist.
    for {verb, path} <- [
          {:patch, "/api/v1/securities/#{security.id}/notes/#{thesis["id"]}"},
          {:delete, "/api/v1/securities/#{security.id}/notes/#{thesis["id"]}"},
          {:delete, "/api/v1/notes/#{thesis["id"]}"}
        ] do
      assert api_conn(conn)
             |> Phoenix.ConnTest.dispatch(@endpoint, verb, path)
             |> response(404)
    end
  end

  test "rejects closed-set violations and a machine-generated entry without a source", %{
    conn: conn
  } do
    security = WorldFixtures.create_security!(name: "Strict Co.", ticker: "STRC")

    %{"errors" => errors} =
      post_json(
        conn,
        "/api/v1/securities/#{security.id}/notes",
        %{
          "note" => %{
            "kind" => "hunch",
            "body" => "x",
            "source_quality" => "vibes",
            "as_of" => "2026-08-01",
            "author" => "local_model",
            "machine_generated" => true
          }
        },
        422
      )

    assert errors["kind"] == ["is invalid"]
    assert errors["source_quality"] == ["is invalid"]
    assert errors["source_url"] == ["is required for a machine-generated entry"]

    assert %{"errors" => %{"detail" => "not found"}} =
             post_json(conn, "/api/v1/securities/999999/notes", %{"note" => %{}}, 404)
  end

  # User story (ADR-0044 §1; issue #749):
  # As the operating agent reading a security,
  # I want the derived thesis state in the security detail,
  # so that I get the current thesis without reducing the log myself — and
  # it names the entry it derives from.
  #
  # Acceptance criteria:
  # - GET /api/v1/securities/:id carries thesis_state (status none when the
  #   log is empty; the thesis fields and derived_from_entry_id otherwise).
  # - Listings carry thesis_state as null (not computed per row).
  test "the security detail carries the derived thesis state", %{conn: conn} do
    security = WorldFixtures.create_security!(name: "State Co.", ticker: "STAT")

    %{"data" => empty} = get_json(conn, "/api/v1/securities/#{security.id}")
    assert empty["thesis_state"]["status"] == "none"
    assert empty["thesis_state"]["basis"] =~ "research log"

    thesis =
      append!(security, %{
        kind: "thesis",
        body: "compounder",
        conviction: "medium",
        time_stop: ~D[2027-01-01]
      })

    %{"data" => detail} = get_json(conn, "/api/v1/securities/#{security.id}")
    assert detail["thesis_state"]["status"] == "intact"
    assert detail["thesis_state"]["thesis"] == "compounder"
    assert detail["thesis_state"]["conviction"] == "medium"
    assert detail["thesis_state"]["time_stop"] == "2027-01-01"
    assert detail["thesis_state"]["derived_from_entry_id"] == thesis.id
    assert detail["thesis_state"]["last_reviewed_by"] == "agent"

    %{"data" => [row]} = get_json(conn, "/api/v1/securities?projection=full&query=State")
    assert Map.has_key?(row, "thesis_state")
    assert row["thesis_state"] == nil
  end

  # User story (ADR-0044 §7.2–7.4; issue #750):
  # As the operating agent running review hygiene,
  # I want the positions with no entry for N days, the entries that still
  # need corroboration, and the blocks expiring within N days,
  # so that the weekly run asks three questions instead of re-reading the log.
  #
  # Acceptance criteria:
  # - GET /api/v1/notes/unreviewed?days=N lists held securities with no entry
  #   in the window (nulls for never-reviewed); an invalid days is a 422.
  # - GET /api/v1/notes/uncorroborated lists non-primary, unsuperseded entries.
  # - GET /api/v1/notes/expiring?days=N lists blocks ending in the window.
  test "the three hygiene reads answer with their parameters echoed", %{conn: conn} do
    world = WorldFixtures.base_world()
    stale = WorldFixtures.create_security!(name: "Stale Co.", ticker: "STAL")
    fresh = WorldFixtures.create_security!(name: "Fresh Co.", ticker: "FRSH")
    WorldFixtures.buy!(world, stale, quantity: "1", price: "10")
    WorldFixtures.buy!(world, fresh, quantity: "1", price: "10")

    today = Portfolixir.Clock.today()
    append!(stale, %{as_of: Date.add(today, -200)})
    append!(fresh, %{as_of: Date.add(today, -3), source_quality: "awareness"})
    block = append!(fresh, %{kind: "decision", body: "no adds", valid_until: Date.add(today, 4)})

    %{"data" => unreviewed} = get_json(conn, "/api/v1/notes/unreviewed?days=90")
    assert unreviewed["days"] == 90
    assert [row] = unreviewed["positions"]
    assert row["security_id"] == stale.id
    assert row["security_name"] == "Stale Co."
    assert row["days_since_last_entry"] == 200
    assert unreviewed["basis"] =~ "Held securities"

    assert %{"errors" => %{"days" => ["is invalid"]}} =
             get_json(conn, "/api/v1/notes/unreviewed?days=-3", 422)

    %{"data" => uncorroborated} = get_json(conn, "/api/v1/notes/uncorroborated")
    assert [entry] = uncorroborated["entries"]
    assert entry["security_id"] == fresh.id
    assert entry["source_quality"] == "awareness"
    assert uncorroborated["include_superseded"] == false

    %{"data" => expiring} = get_json(conn, "/api/v1/notes/expiring?days=7")
    assert expiring["days"] == 7
    assert [expiring_entry] = expiring["entries"]
    assert expiring_entry["id"] == block.id
    assert expiring_entry["days_until_expiry"] == 4

    %{"data" => none_expiring} = get_json(conn, "/api/v1/notes/expiring?days=2")
    assert none_expiring["entries"] == []
  end

  # Review round: parameter edge cases answer 422 or the default, never a 500;
  # unknown securities are a 404 on both the list and the append.
  test "parameter edge cases degrade to defaults or 422s", %{conn: conn} do
    assert %{"errors" => %{"detail" => "not found"}} =
             get_json(conn, "/api/v1/securities/999999/notes", 404)

    security = WorldFixtures.create_security!(name: "Edge Co.", ticker: "EDGE")

    # A non-object note body is a 422 naming the required fields, not a crash.
    %{"errors" => errors} =
      post_json(conn, "/api/v1/securities/#{security.id}/notes", %{"note" => "garbage"}, 422)

    assert "can't be blank" in errors["body"]

    # Blank days means the default; garbage and negative are 422.
    assert get_json(conn, "/api/v1/notes/unreviewed?days=")["data"]["days"] == 90
    assert get_json(conn, "/api/v1/notes/unreviewed")["data"]["days"] == 90

    assert %{"errors" => %{"days" => _}} =
             get_json(conn, "/api/v1/notes/unreviewed?days=abc", 422)

    assert %{"errors" => %{"days" => _}} =
             get_json(conn, "/api/v1/notes/expiring?days[]=1", 422)

    assert get_json(conn, "/api/v1/notes/expiring?days=")["data"]["days"] == 30

    # security_id: blank is unscoped, garbage and zero are 422, a filter narrows.
    assert get_json(conn, "/api/v1/notes/uncorroborated?security_id=")["data"]["security_id"] ==
             nil

    assert %{"errors" => %{"security_id" => _}} =
             get_json(conn, "/api/v1/notes/uncorroborated?security_id=abc", 422)

    assert %{"errors" => %{"security_id" => _}} =
             get_json(conn, "/api/v1/notes/expiring?security_id=0", 422)

    append!(security, %{source_quality: "unverified"})
    other = WorldFixtures.create_security!(name: "Other Co.", ticker: "OTHR")
    append!(other, %{source_quality: "unverified"})

    scoped = get_json(conn, "/api/v1/notes/uncorroborated?security_id=#{security.id}")["data"]
    assert scoped["security_id"] == security.id
    assert Enum.map(scoped["entries"], & &1["security_id"]) == [security.id]

    # include_superseded: blank is false, garbage is 422, "true" widens.
    assert get_json(conn, "/api/v1/notes/uncorroborated?include_superseded=")["data"][
             "include_superseded"
           ] == false

    assert %{"errors" => %{"include_superseded" => _}} =
             get_json(conn, "/api/v1/notes/uncorroborated?include_superseded=maybe", 422)

    assert get_json(conn, "/api/v1/notes/uncorroborated?include_superseded=true")["data"][
             "include_superseded"
           ] == true
  end
end
