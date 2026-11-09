defmodule PortfolixirWeb.ApiV1EntryMarkersTest do
  # ADR-0044's amendment of 2026-11-06 (Sprint 28, N5) over the JSON API:
  # POST /api/v1/securities/:security_id/notes takes headline, event_type and
  # tone on an evidence or event_result entry, and every entry read answers
  # them (absent ones as null).
  use PortfolixirWeb.ConnCase

  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp post_json(conn, path, body, status) do
    conn |> api_conn() |> post(path, Jason.encode!(body)) |> json_response(status)
  end

  # User story (ADR-0044, amendment of 2026-11-06):
  # As the operating agent keeping a finding worth drawing on the chart,
  # I want to state its headline, event type and tone with the entry,
  # so that the operator sees it at its date without opening the log.
  #
  # Acceptance criteria:
  # - An evidence entry with the three answers 201 and carries them; the
  #   log read answers them, and an entry without them reads them as null.
  # - On a thesis, each answers 422 naming the field; an event type outside
  #   the eight answers 422 naming event_type; news_label_id in the body is
  #   not taken (it is the server's provenance).
  test "an evidence entry takes headline, event_type and tone; a thesis refuses them",
       %{conn: conn} do
    security = WorldFixtures.create_security!(name: "Markers API AG", ticker: "MKAPI")
    path = "/api/v1/securities/#{security.id}/notes"

    note = %{
      "kind" => "evidence",
      "body" => "Synthetic finding.",
      "source_quality" => "primary",
      "as_of" => "2026-11-02"
    }

    created =
      post_json(
        conn,
        path,
        %{
          "note" =>
            Map.merge(note, %{
              "headline" => "Guidance raised",
              "event_type" => "guidance",
              "tone" => 1,
              "news_label_id" => 7
            })
        },
        201
      )["data"]

    assert created["headline"] == "Guidance raised"
    assert created["event_type"] == "guidance"
    assert created["tone"] == 1
    assert created["news_label_id"] == nil

    plain = post_json(conn, path, %{"note" => note}, 201)["data"]
    assert {plain["headline"], plain["event_type"], plain["tone"]} == {nil, nil, nil}
    assert Map.has_key?(plain, "headline")

    entries = conn |> api_conn() |> get(path) |> json_response(200)
    assert [_, _] = entries["data"]["entries"]
    assert Enum.any?(entries["data"]["entries"], &(&1["headline"] == "Guidance raised"))

    thesis = Map.put(note, "kind", "thesis")

    for {field, value} <- [{"headline", "A headline"}, {"event_type", "legal"}, {"tone", 0}] do
      errors = post_json(conn, path, %{"note" => Map.put(thesis, field, value)}, 422)["errors"]
      assert Map.has_key?(errors, field), field
    end

    errors =
      post_json(conn, path, %{"note" => Map.put(note, "event_type", "noise")}, 422)["errors"]

    assert Map.has_key?(errors, "event_type")
  end
end
