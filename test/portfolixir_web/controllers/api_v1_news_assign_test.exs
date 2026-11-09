defmodule PortfolixirWeb.ApiV1NewsAssignTest do
  # ADR-0056 §7, §9 (Sprint 28, N4): news.assign over the API, closed and
  # journaled, and the remainder's rows beside a label's suggestion.
  # Synthetic names and hosts only, no socket.
  use PortfolixirWeb.ConnCase

  import Portfolixir.NewsFixtures, only: [feed!: 1]
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo

  @agent_token String.duplicate("a", 40)

  setup %{conn: conn} do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{"mcp", @agent_token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer " <> @agent_token)

    %{conn: conn}
  end

  defp watched!(name, token) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  defp aggregator_item!(title) do
    n = System.unique_integer([:positive])
    feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-#{n}"})
    link = "https://search.example.com/r?u=#{n}"
    item = struct!(Parsed, %{title: title, link: link, source_domain: "wire.example.com"})
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], DateTime.utc_now())
    Repo.get_by!(Item, canonical_url: link)
  end

  defp put_assignment(conn, id, body),
    do: put(conn, "/api/v1/news/items/#{id}/assignment", Jason.encode!(body))

  defp errors(conn), do: json_response(conn, 422)["errors"]

  # User story (ADR-0056 §9):
  # As the operator's agent working the queue of items no security, or
  # several, claim,
  # I want to assign one by hand, or give it back to the matcher, through
  # the API,
  # so that it reads in the right security's stories, journaled under my
  # token.
  #
  # Acceptance criteria:
  # - PUT /api/v1/news/items/:id/assignment with {"assignment":
  #   {"security_id": id}} assigns the item and answers it: id, story_id,
  #   assignment, security_id; with null the matcher's answer now, an
  #   ambiguous item with its candidates.
  # - The write is journaled under the token's name.
  # - Closed: a key beside or inside assignment, a missing security_id, a
  #   security_id of the wrong type, an issuer item and a security that does
  #   not exist answer 422 naming the field; an unknown item answers 404.
  test "assigns an item by hand and gives it back to the matcher", %{conn: conn} do
    northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
    harbourline = watched!("Harbourline Shipping AG", "Harbourline")
    item = aggregator_item!("Northwind Harbour and Harbourline agree on a joint venture")
    assert %Item{assignment: :ambiguous} = Repo.get!(Item, item.id)

    assigned =
      json_response(
        put_assignment(conn, item.id, %{assignment: %{security_id: northwind.id}}),
        200
      )

    assert %{
             "id" => id,
             "assignment" => "assigned",
             "security_id" => security_id,
             "story_id" => _
           } =
             assigned["data"]

    assert {id, security_id} == {item.id, northwind.id}

    back =
      json_response(put_assignment(conn, item.id, %{assignment: %{security_id: nil}}), 200)[
        "data"
      ]

    assert back["assignment"] == "ambiguous"
    assert back["candidates"] == Enum.sort([northwind.id, harbourline.id])
    refute Map.has_key?(back, "story_id")

    assert [undone, first] = Journal.list_entries(resource_type: "news_item", limit: 10)
    assert {first.actor_label, undone.actor_label} == {"mcp", "mcp"}

    for {body, key} <- [
          {%{assignment: %{security_id: northwind.id, tier: "primary"}}, "tier"},
          {%{assignment: %{security_id: northwind.id}, status: "promoted"}, "status"},
          {%{assignment: %{}}, "security_id"},
          {%{assignment: %{security_id: "1"}}, "security_id"},
          {%{assignment: %{security_id: 1.5}}, "security_id"},
          {%{assignment: %{security_id: 2_000_000_000}}, "security_id"},
          {%{}, "assignment"},
          {%{assignment: "northwind"}, "assignment"}
        ] do
      assert Map.has_key?(errors(put_assignment(conn, item.id, body)), key), inspect(body)
    end

    issuer_feed = feed!(%{class: "issuer", security_id: northwind.id})
    release = struct!(Parsed, %{title: "Northwind release", link: "https://ir.example.com/r"})
    {:ok, %{stored: 1}} = Ingest.ingest(issuer_feed, [release], DateTime.utc_now())
    issuer_item = Repo.get_by!(Item, canonical_url: "https://ir.example.com/r")

    assert %{"news_id" => [_]} =
             errors(
               put_assignment(conn, issuer_item.id, %{assignment: %{security_id: harbourline.id}})
             )

    assert json_response(
             put_assignment(conn, 2_000_000_000, %{assignment: %{security_id: northwind.id}}),
             404
           )

    assert json_response(
             put_assignment(conn, "x", %{assignment: %{security_id: northwind.id}}),
             404
           )

    assert length(Journal.list_entries(resource_type: "news_item", limit: 10)) == 2
  end

  # User story (ADR-0056 §7; Sprint 28 N1's known gap):
  # As the operator's agent reading the queue,
  # I want no suggestion shown that no label made for the item,
  # so that a remainder row never carries another story's proposal.
  #
  # Acceptance criteria:
  # - An unassigned or ambiguous item is in no story, so no label reaches
  #   it: its row in news.list(assignment=…) carries no
  #   suggested_security_id (the open question is recorded in ADR-0056).
  test "a remainder row carries no suggestion", %{conn: conn} do
    watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
    watched!("Harbourline Shipping AG", "Harbourline")
    item = aggregator_item!("Northwind Harbour and Harbourline agree on a joint venture")

    rows =
      conn
      |> get("/api/v1/news/stories?assignment=ambiguous")
      |> json_response(200)
      |> get_in(["data", "rows"])

    assert [row] = Enum.filter(rows, &(&1["id"] == item.id))
    refute Map.has_key?(row, "suggested_security_id")
    assert Repo.get!(Item, item.id).cluster_id == nil
  end
end
