defmodule PortfolixirWeb.ApiV1NewsPromotionTest do
  # ADR-0056 §8 (Sprint 28, N5) over the JSON API: POST
  # /api/v1/securities/:security_id/notes with note.cluster_id writes a
  # research note pre-filled from the story and promotes the story; POST
  # /api/v1/securities/:security_id/events with event.news_id takes the
  # item's link and source quality. Risk tier SECURITY: an agent write path
  # from foreign text. Synthetic names and hosts only.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.News.Item
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp post_json(conn, path, body, status) do
    conn |> api_conn() |> post(path, Jason.encode!(body)) |> json_response(status)
  end

  defp get_json(conn, path), do: conn |> api_conn() |> get(path) |> json_response(200)

  # User story (ADR-0056 §8):
  # As the operating agent that judged a story worth keeping,
  # I want notes.append to take its cluster_id and fill in the rest but
  # the body,
  # so that one call keeps it with the story's provenance and the story
  # shows it was kept.
  #
  # Acceptance criteria:
  # - With cluster_id and a body, 201: an evidence entry with the story's
  #   date, link, source quality, headline, and the label's event type and
  #   tone; the story's read names the note, its item reads promoted.
  # - A headline sent beside cluster_id replaces the pre-fill.
  # - source_quality beside cluster_id answers 422 naming it; a cluster_id
  #   that is not an id, or names no story, 422 naming cluster_id; nothing
  #   is written.
  test "notes.append with cluster_id writes the pre-filled entry and promotes the story",
       %{conn: conn} do
    security = NewsFixtures.security!("Promotion API AG")
    story = NewsFixtures.story!(security, title: "Promotion API AG reports a synthetic result")
    NewsFixtures.label!(story.id, event_type: "earnings", tone: 1)
    path = "/api/v1/securities/#{security.id}/notes"

    created =
      post_json(conn, path, %{"note" => %{"cluster_id" => story.id, "body" => "Kept."}}, 201)[
        "data"
      ]

    item = Repo.get!(Item, story.representative_item_id)

    assert created["kind"] == "evidence"
    assert created["body"] == "Kept."
    assert created["author"] == "agent"
    assert created["source_url"] == item.canonical_url
    assert created["source_quality"] == "primary"
    assert created["as_of"] == Date.to_iso8601(Portfolixir.Clock.local_date(item.published_at))
    assert created["headline"] == "Promotion API AG reports a synthetic result"
    assert {created["event_type"], created["tone"]} == {"earnings", 1}
    assert is_integer(created["news_label_id"])

    assert get_json(conn, "/api/v1/news/stories/#{story.id}")["data"]["note_ids"] == [
             created["id"]
           ]

    assert get_json(conn, "/api/v1/news/items/#{item.id}")["data"]["status"] == "promoted"

    again =
      post_json(
        conn,
        path,
        %{"note" => %{"cluster_id" => story.id, "body" => "Again.", "headline" => "Own"}},
        201
      )["data"]

    assert again["headline"] == "Own"

    for {note, field} <- [
          {%{"cluster_id" => story.id, "body" => "x", "source_quality" => "primary"},
           "source_quality"},
          {%{"cluster_id" => "story-1", "body" => "x"}, "cluster_id"},
          {%{"cluster_id" => 9_000_000_000, "body" => "x"}, "cluster_id"}
        ] do
      errors = post_json(conn, path, %{"note" => note}, 422)["errors"]
      assert Map.keys(errors) == [field], inspect(errors)
    end

    assert Repo.aggregate(SecurityNote, :count) == 2
  end

  # User story (ADR-0056 §8; ADR-0048):
  # As the operating agent recording a date a news item announced,
  # I want events.create to take the item's news_id as its source,
  # so that the event carries its link and source quality by rule.
  #
  # Acceptance criteria:
  # - With news_id, 201: the event's source_url is the item's link and its
  #   source_quality the item's tier's (an issuer's: primary).
  # - source_url beside news_id answers 422 naming it; another security's
  #   item, and a news_id that is not an id, 422 naming news_id.
  test "events.create with news_id takes the item's link and source quality", %{conn: conn} do
    security = NewsFixtures.security!("Event Source API AG")
    story = NewsFixtures.story!(security)
    item = Repo.get!(Item, story.representative_item_id)
    path = "/api/v1/securities/#{security.id}/events"
    event = %{"kind" => "earnings", "date" => "2026-12-01", "timing" => "exact"}

    created = post_json(conn, path, %{"event" => Map.put(event, "news_id", item.id)}, 201)["data"]
    assert {created["source_url"], created["source_quality"]} == {item.canonical_url, "primary"}

    other = NewsFixtures.security!("Other Event Source AG")
    theirs = Repo.get!(Item, NewsFixtures.story!(other).representative_item_id)

    for {body, field} <- [
          {Map.merge(event, %{"news_id" => item.id, "source_url" => "https://x.example.org"}),
           "source_url"},
          {Map.put(event, "news_id", theirs.id), "news_id"},
          {Map.put(event, "news_id", "item"), "news_id"}
        ] do
      errors = post_json(conn, path, %{"event" => body}, 422)["errors"]
      assert Map.keys(errors) == [field], inspect(errors)
    end
  end
end
