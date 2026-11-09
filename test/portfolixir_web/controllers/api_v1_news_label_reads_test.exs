defmodule PortfolixirWeb.ApiV1NewsLabelReadsTest do
  # ADR-0056 §7, §9, §14 items 7 and 8 (Sprint 28, N2; plan D-1 criterion
  # 3): the labels in the agent's reads. A label sorts aggregator and
  # thematic stories and never hides an issuer's or a regulator's; the
  # active label is the newest per prompt version; tone is never a filter
  # or a sort key; with no label every read answers. Items are stored
  # through the ingest at times relative to now, labels through the one
  # write; synthetic names and hosts only, no socket.
  use PortfolixirWeb.ConnCase

  import Portfolixir.NewsFixtures, only: [category!: 0, feed!: 1, label!: 2, story!: 2]
  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
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
      |> put_req_header("authorization", "Bearer " <> @agent_token)

    %{conn: conn, now: DateTime.utc_now() |> DateTime.truncate(:second)}
  end

  defp hours_ago(now, hours), do: DateTime.add(now, -round(hours * 3600), :second)

  defp read(conn, path, query \\ []),
    do:
      conn
      |> get(path <> "?" <> URI.encode_query(query))
      |> json_response(200)
      |> Map.fetch!("data")

  defp held!(world, name, alias_token) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")
    buy!(world, security, quantity: "1", price: "10")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_aliases: [%{token: alias_token, context: [], case: "insensitive"}]
      })

    security
  end

  # One aggregator item naming `token`, stored at `at`: its story's id.
  defp aggregator_story!(title, link, at) do
    {:ok, %{stored: 1}} =
      Ingest.ingest(
        feed!(%{class: "aggregator"}),
        [%Parsed{title: title, link: link, source_domain: "wire.example.com"}],
        at
      )

    Repo.get_by!(Item, canonical_url: link).cluster_id
  end

  defp thematic_story!(category, title, link, at) do
    {:ok, %{stored: 1}} =
      Ingest.ingest(
        feed!(%{class: "thematic", category_id: category.id}),
        [%Parsed{title: title, link: link}],
        at
      )

    Repo.get_by!(Item, canonical_url: link).cluster_id
  end

  # Three securities and a category, each with one new story of one class:
  # Northwind an issuer's release, Southwind and Eastwind an aggregator's
  # report, the category a thematic story.
  defp world!(now) do
    world = base_world(name: "Labels", cash_name: "Cash", depot_name: "Depot")
    north = held!(world, "Northwind Harbour Logistics AG", "Northwind")
    south = held!(world, "Southwind Shipping SE", "Southwind")
    east = held!(world, "Eastwind Ferries plc", "Eastwind")
    category = category!()

    issuer = story!(north, title: "Northwind annual report", at: hours_ago(now, 5)).id

    report =
      aggregator_story!("Southwind freight slips", "https://agg.example.com/s", hours_ago(now, 4))

    other =
      aggregator_story!("Eastwind adds a ferry", "https://agg.example.com/e", hours_ago(now, 3))

    theme =
      thematic_story!(
        category,
        "Water tariffs rise",
        "https://theme.example.com/w",
        hours_ago(now, 2)
      )

    %{
      north: north,
      south: south,
      east: east,
      category: category,
      issuer: issuer,
      report: report,
      other: other,
      theme: theme
    }
  end

  defp row_ids(rows), do: Enum.map(rows, & &1["id"])

  # User story (ADR-0056 §7, §14 item 7; plan D-1 criterion 3):
  # As the operator whose agent reads the digest a model's labels sort,
  # I want a label to order and filter only the stories that may be noise —
  # an aggregator's and a thematic feed's — and never to hide what an issuer
  # or a regulator published, whatever materiality a model gave it,
  # so that a mislabelled release still reaches me.
  #
  # Acceptance criteria:
  # - An issuer story labelled materiality 0 appears in the digest at the
  #   default (min_materiality 2); an aggregator story labelled 1 does not,
  #   and is counted in hidden; an aggregator story labelled 2 and a
  #   thematic story labelled 3 do, the thematic one under categories,
  #   without include_unlabeled.
  # - A row names its highest materiality and its stories' event types; the
  #   rows come by highest materiality first, so a label orders them.
  # - min_materiality=0 shows the story labelled 1; min_materiality=3 hides
  #   the one labelled 2 but never the issuer's.
  # - include_unlabeled=true adds an unlabeled aggregator story, never one
  #   labelled below min_materiality.
  # - The digest names the prompt_version its labels are read under, and
  #   unlabeled counts the new stories without a label of it.
  describe "the digest (§14 item 7)" do
    test "a label sorts aggregator and thematic stories and never hides an issuer's",
         %{conn: conn, now: now} do
      w = world!(now)

      label!(w.issuer, materiality: 0, event_type: "noise")
      label!(w.report, materiality: 1, event_type: "macro")
      label!(w.theme, materiality: 3, event_type: "regulatory")

      data = read(conn, "/api/v1/news/digest")

      assert row_ids(data["rows"]) == [w.north.id]
      assert [%{"materiality" => 0, "event_types" => ["noise"]}] = data["rows"]
      assert [%{"id" => category_id, "materiality" => 3}] = data["categories"]
      assert category_id == w.category.id
      # Southwind's story labelled 1 and Eastwind's unlabeled one.
      assert data["hidden"] == 2
      assert data["unlabeled"] == 1
      assert data["prompt_version"] == "v1"

      label!(w.other, materiality: 2, event_type: "product")
      data = read(conn, "/api/v1/news/digest")

      # Eastwind's story labelled 2 now shows, before Northwind's labelled 0.
      assert row_ids(data["rows"]) == [w.east.id, w.north.id]
      assert data["hidden"] == 1 and data["unlabeled"] == 0

      every = read(conn, "/api/v1/news/digest", min_materiality: 0)
      assert row_ids(every["rows"]) == [w.east.id, w.south.id, w.north.id]
      assert every["hidden"] == 0

      high = read(conn, "/api/v1/news/digest", min_materiality: 3)
      assert row_ids(high["rows"]) == [w.north.id]
      assert high["hidden"] == 2
    end

    test "include_unlabeled adds unlabeled stories, never one labelled below the threshold",
         %{conn: conn, now: now} do
      w = world!(now)
      label!(w.report, materiality: 1, event_type: "macro")

      data = read(conn, "/api/v1/news/digest", include_unlabeled: true)

      # Eastwind's story has no label; Southwind's is labelled 1 < 2.
      assert row_ids(data["rows"]) == [w.north.id, w.east.id]
      refute Map.has_key?(hd(data["rows"]), "materiality")
      assert [%{"id" => _theme_category}] = data["categories"]
      assert data["hidden"] == 1
      assert data["unlabeled"] == 3
    end
  end

  # User story (ADR-0056 §7: "the active label of a cluster is the newest
  # one per prompt_version"):
  # As the operator whose labeller may change its prompt or its model,
  # I want each read to use one prompt version's labels — the newest
  # version unless I name one — and of it each story's newest label,
  # so that materialities from two prompts are never compared in one answer.
  #
  # Acceptance criteria:
  # - Two models label one story under v1: the newer label is the active one.
  # - A label under v2 makes v2 the default: the digest, the list and get
  #   read v2 and name it; a story without a v2 label is unlabeled there.
  # - prompt_version=v1 reads v1's labels; a prompt_version that is not an
  #   identifier answers 422 naming it.
  describe "the active label" do
    test "the newest label of the newest prompt version, unless one is named",
         %{conn: conn, now: now} do
      w = world!(now)

      label!(w.report, model: "model-a", materiality: 1, event_type: "macro")
      label!(w.report, model: "model-b", materiality: 3, event_type: "legal")

      list = read(conn, "/api/v1/news/stories", security_id: w.south.id)
      assert [%{"materiality" => 3, "event_type" => "legal"}] = list["rows"]
      assert list["prompt_version"] == "v1"

      label!(w.other, prompt_version: "v2", materiality: 2, event_type: "product")

      digest = read(conn, "/api/v1/news/digest")
      assert digest["prompt_version"] == "v2"
      assert row_ids(digest["rows"]) == [w.east.id, w.north.id]

      v2_list = read(conn, "/api/v1/news/stories", security_id: w.south.id)
      assert [row] = v2_list["rows"]
      refute Map.has_key?(row, "materiality")
      assert v2_list["prompt_version"] == "v2"

      v1 = read(conn, "/api/v1/news/digest", prompt_version: "v1")
      assert v1["prompt_version"] == "v1"
      assert row_ids(v1["rows"]) == [w.south.id, w.north.id]

      story = read(conn, "/api/v1/news/stories/#{w.report}", prompt_version: "v1")
      assert story["label"]["materiality"] == 3

      errors =
        conn
        |> get("/api/v1/news/digest?prompt_version=" <> URI.encode_www_form("v 1"))
        |> json_response(422)
        |> Map.fetch!("errors")

      assert Map.has_key?(errors, "prompt_version")
    end
  end

  # User story (ADR-0056 §9, NFR-10):
  # As the operator's agent,
  # I want a story's rows to carry its materiality and event type, and the
  # one-story read its whole label marked as machine-generated,
  # so that I see what a model said and that a model said it.
  #
  # Acceptance criteria:
  # - news.list's story rows carry materiality and event_type when labelled;
  #   min_materiality leaves out aggregator and thematic stories below it,
  #   never an issuer's; on a story's items or the remainder it answers 422
  #   naming it (a label is a story's).
  # - news.get of a story answers label {event_type, materiality, tone,
  #   confidence (a string), thesis_note_id, clause_idx, machine_generated
  #   true}; of an item, no label.
  describe "news.list and news.get" do
    test "rows carry the label, get its whole proposal", %{conn: conn, now: now} do
      w = world!(now)
      story!(w.south, title: "Southwind quarterly release", at: hours_ago(now, 1))
      label!(w.report, materiality: 1, event_type: "macro", tone: -1, confidence: "0.4")

      rows = read(conn, "/api/v1/news/stories", security_id: w.south.id)["rows"]

      assert [%{"event_type" => nil}, %{"materiality" => 1, "event_type" => "macro"}] =
               Enum.map(rows, &Map.put_new(&1, "event_type", nil))

      filtered = read(conn, "/api/v1/news/stories", security_id: w.south.id, min_materiality: 2)
      assert [%{"title" => "Southwind quarterly release"}] = filtered["rows"]

      for query <- [[cluster_id: w.report], [assignment: "unassigned"]] do
        errors =
          conn
          |> get("/api/v1/news/stories?" <> URI.encode_query(query ++ [min_materiality: 1]))
          |> json_response(422)
          |> Map.fetch!("errors")

        assert Map.has_key?(errors, "min_materiality"), inspect(query)
      end

      story = read(conn, "/api/v1/news/stories/#{w.report}")

      assert story["label"] == %{
               "event_type" => "macro",
               "materiality" => 1,
               "tone" => -1,
               "confidence" => "0.4",
               "machine_generated" => true
             }

      item = Repo.get_by!(Item, cluster_id: w.report)
      refute Map.has_key?(read(conn, "/api/v1/news/items/#{item.id}"), "label")
    end
  end

  # User story (ADR-0056 §7: "tone is never a filter or a sort key"):
  # As the operator,
  # I want every news read to refuse tone as a filter or a sort,
  # so that a model's reading of a story's mood never decides what my
  # agent sees or in which order.
  #
  # Acceptance criteria:
  # - tone, min_tone, tone_min, sort=tone and order=tone, passed to the
  #   list, a story, an item, the digest, the health and the labeller's
  #   read, each answer 422 naming the parameter.
  test "tone is refused as a filter or a sort by every news read", %{conn: conn, now: now} do
    w = world!(now)
    label!(w.report, tone: 1)
    item = Repo.get_by!(Item, cluster_id: w.report)

    paths = [
      {"/api/v1/news/stories", [security_id: w.south.id]},
      {"/api/v1/news/stories/#{w.report}", []},
      {"/api/v1/news/items/#{item.id}", []},
      {"/api/v1/news/digest", []},
      {"/api/v1/news/health", []},
      {"/api/v1/news/unlabeled", [prompt_version: "v2"]}
    ]

    for {path, base} <- paths,
        {key, value} <- [tone: 1, min_tone: 0, tone_min: 0, sort: "tone", order: "tone"] do
      errors =
        conn
        |> get(path <> "?" <> URI.encode_query(base ++ [{key, value}]))
        |> json_response(422)
        |> Map.fetch!("errors")

      assert Map.has_key?(errors, Atom.to_string(key)), "#{path} #{key}: #{inspect(errors)}"
    end
  end

  # User story (ADR-0056 §7 "Fail-open", §14 item 8; plan D-1 criterion 3):
  # As the operator whose labeller may never have run,
  # I want every read to answer as it did before labels existed,
  # so that nothing waits for the labeller.
  #
  # Acceptance criteria:
  # - With no label at all, the digest, the list, a story and an item
  #   answer 200; the digest shows the issuer's story and counts the
  #   aggregator and thematic ones as hidden, as before labels; no row
  #   carries a materiality, no story a label, no answer a prompt_version.
  # - Only unlabeled grows: a new story adds one to it, and nothing else in
  #   the digest's counts moves but its own row.
  test "fail-open: with no label every read answers and only unlabeled grows",
       %{conn: conn, now: now} do
    w = world!(now)

    before = read(conn, "/api/v1/news/digest")
    assert row_ids(before["rows"]) == [w.north.id]
    assert before["hidden"] == 3 and before["unlabeled"] == 4
    refute Map.has_key?(before, "prompt_version")
    refute Map.has_key?(hd(before["rows"]), "materiality")

    story!(w.north, title: "Northwind names a new chief", at: hours_ago(now, 1))
    later = read(conn, "/api/v1/news/digest")
    assert later["unlabeled"] == 5

    assert Map.drop(later, ~w(rows unlabeled as_of since)) ==
             Map.drop(before, ~w(rows unlabeled as_of since))

    list = read(conn, "/api/v1/news/stories", security_id: w.south.id)
    assert [row] = list["rows"]
    refute Map.has_key?(row, "materiality") or Map.has_key?(list, "prompt_version")

    refute Map.has_key?(read(conn, "/api/v1/news/stories/#{w.report}"), "label")
    item = Repo.get_by!(Item, cluster_id: w.report)
    assert read(conn, "/api/v1/news/items/#{item.id}")["id"] == item.id
  end
end
