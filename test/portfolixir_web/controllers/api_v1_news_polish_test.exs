defmodule PortfolixirWeb.ApiV1NewsPolishTest do
  # The news lines of "Polish: API and MCP" (#1356; Sprint 30 plan, A2):
  # names that agree in their first 19 characters read apart wherever a
  # news answer cuts them, `news.get`'s `note_ids` capped with a flag, and
  # `news.health` showing a feed's backoff. Items are stored through the
  # ingest; synthetic names and hosts only, no socket.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Portfolixir.NewsFixtures, only: [feed!: 1, story!: 2]
  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Item
  alias Portfolixir.Repo

  @agent_token String.duplicate("a", 40)

  setup %{conn: conn} do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{"mcp", @agent_token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> @agent_token)

    %{conn: conn}
  end

  defp held!(world, attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{currency_code: "EUR", asset_class: "equity"}, attrs)
      )

    buy!(world, security, quantity: "1", price: "10")
    security
  end

  defp read(conn, path, query \\ []),
    do:
      conn |> get(path <> "?" <> URI.encode_query(query)) |> json_response(200) |> Map.get("data")

  # User story (#1356; ADR-0056 §9):
  # As the operator's agent reading what is new,
  # I want two securities whose names agree in their first 19 characters
  # to read apart wherever a news answer cuts their names,
  # so that I do not take one's story for the other's.
  #
  # Acceptance criteria:
  # - A cut name carries, after a middle dot, the security's ticker, or its
  #   WKN where it has no ticker: in the digest's rows, in `news.get`'s
  #   `security` and in `news.unlabeled`'s universe.
  # - A name that fits its 20 characters is answered as it is.
  test "cut names read apart by their ticker, else their WKN", %{conn: conn} do
    world = base_world(name: "Names", cash_name: "Cash", depot_name: "Depot")
    fund = held!(world, %{name: "Alder Creek Timber Fund", ticker_symbol: "ACTF"})
    class_b = held!(world, %{name: "Alder Creek Timber Fund Class B", wkn: "A1B2C3"})
    short = held!(world, %{name: "Birchwood AG", ticker_symbol: "BIRW"})

    stories = Map.new([fund, class_b, short], &{&1.id, story!(&1, []).id})

    expected = %{
      fund.id => "Alder Creek Timber … · ACTF",
      class_b.id => "Alder Creek Timber … · A1B2C3",
      short.id => "Birchwood AG"
    }

    digest = read(conn, "/api/v1/news/digest")
    assert Map.new(digest["rows"], &{&1["id"], &1["name"]}) == expected

    for {id, cluster_id} <- stories do
      assert read(conn, "/api/v1/news/stories/#{cluster_id}")["security"]["name"] == expected[id]
    end

    universe = read(conn, "/api/v1/news/unlabeled", prompt_version: "v1")["universe"]
    assert Map.new(universe, &{&1["id"], &1["name"]}) == expected
  end

  # User story (#1356; ADR-0056 §9's 400 tokens):
  # As the operator's agent reading one story,
  # I want its note_ids capped, with a flag when the cap left notes out,
  # so that a story promoted to many notes still fits its budget.
  #
  # Acceptance criteria:
  # - A story or item with more than three notes answers the newest three,
  #   ascending, and `note_ids_truncated: true` (three keep the widest
  #   story within its 400 tokens).
  # - One with three or fewer answers them all and no flag.
  test "news.get caps note_ids at three and says so", %{conn: conn} do
    world = base_world(name: "Notes", cash_name: "Cash", depot_name: "Depot")
    security = held!(world, %{name: "Cedar Lane AG", ticker_symbol: "CDRL"})
    many = story!(security, [])
    few = story!(security, [])

    promote!(many, Enum.to_list(1001..1008))
    promote!(few, [2001, 2002])

    story = read(conn, "/api/v1/news/stories/#{many.id}")
    assert story["note_ids"] == [1006, 1007, 1008]
    assert story["note_ids_truncated"] == true

    item_id = Repo.one!(from(i in Item, where: i.cluster_id == ^many.id, select: i.id))
    item = read(conn, "/api/v1/news/items/#{item_id}")
    assert item["note_ids"] == [1006, 1007, 1008]
    assert item["note_ids_truncated"] == true

    story = read(conn, "/api/v1/news/stories/#{few.id}")
    assert story["note_ids"] == [2001, 2002]
    refute Map.has_key?(story, "note_ids_truncated")
  end

  defp promote!(cluster, note_ids) do
    Repo.update_all(from(i in Item, where: i.cluster_id == ^cluster.id),
      set: [status: :promoted, note_ids: note_ids]
    )
  end

  # User story (#1356; ADR-0056 §5, §6):
  # As the operator's agent checking the collector,
  # I want the health read to show a feed's backoff,
  # so that I can tell a feed waiting out a 429 or 5xx from one that failed
  # once.
  #
  # Acceptance criteria:
  # - Each feed answers `failures` (the consecutive 429 and 5xx answers);
  #   one in backoff adds `retry_at`, to the second in UTC.
  test "news.health shows failures and retry_at", %{conn: conn} do
    backing_off = feed!(%{class: "aggregator", url: "https://wire.example.com/a.xml"})
    healthy = feed!(%{class: "aggregator", url: "https://wire.example.com/b.xml"})
    retry_at = ~U[2026-11-20 08:30:00.000000Z]

    Repo.update_all(from(f in Feed, where: f.id == ^backing_off.id),
      set: [failures: 3, retry_at: retry_at, last_error: "http_503"]
    )

    feeds = Map.new(read(conn, "/api/v1/news/health")["feeds"], &{&1["id"], &1})

    assert %{"failures" => 3, "retry_at" => "2026-11-20T08:30:00Z", "last_error" => "http_503"} =
             feeds[backing_off.id]

    assert feeds[healthy.id]["failures"] == 0
    refute Map.has_key?(feeds[healthy.id], "retry_at")
  end
end
