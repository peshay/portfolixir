defmodule PortfolixirWeb.ApiV1NewsLabelsAttackTest do
  # Sprint 28, plan D-8 carry-forward 1: N1's label write and the
  # labeller's read, attacked by an agent other than the story's author
  # with callers and fields the registration did not name. The author's own
  # attack list is api_v1_news_labels_test.exs and labels_test.exs; this
  # file holds only cases they do not name.
  #
  # Three tests here failed on the story's head and pinned defects the
  # lens found (the query's label dropped, a thesis the read never offered,
  # a name cut by graphemes); the fixes (N1 attack, AT1 to AT3) turned them
  # green. The others pin holes that were closed but not tested.
  # Synthetic names and hosts only, no socket.
  use PortfolixirWeb.ConnCase

  import Portfolixir.NewsFixtures, only: [category!: 0, feed!: 1, security!: 1, story!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Label
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo

  @token String.duplicate("k", 40)

  setup %{conn: conn} do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{"labeller", @token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> @token)

    security = security!("Northwind Attack Holdings AG")
    %{conn: conn, security: security, story: story!(security)}
  end

  defp json(conn), do: put_req_header(conn, "content-type", "application/json")

  defp put_raw(conn, path \\ "/api/v1/news/labels", body),
    do: conn |> json() |> put(path, body)

  defp put_label(conn, label), do: put_raw(conn, Jason.encode!(%{label: label}))

  defp label(story, attrs \\ %{}) do
    Map.merge(
      %{
        "cluster_id" => story.id,
        "model" => "synthetic-model-1",
        "prompt_version" => "v1",
        "event_type" => "earnings",
        "materiality" => 2,
        "tone" => 1,
        "confidence" => "0.85"
      },
      attrs
    )
  end

  defp entries, do: Journal.list_entries(resource_type: "news_label", limit: 50)

  defp refused!(conn) do
    %{"errors" => errors} = json_response(conn, 422)
    assert Repo.aggregate(Label, :count) == 0, "a refused put stored a label"
    assert entries() == [], "a refused put journaled"
    errors
  end

  defp thesis!(security, condition, opts \\ []) do
    {:ok, note} =
      Knowledge.append_note(
        Actor.owner_ui(),
        Map.merge(
          %{
            security_id: security.id,
            author: :operator,
            kind: :thesis,
            body: "Synthetic thesis",
            source_quality: :primary,
            as_of: Date.utc_today(),
            invalidation_condition: condition
          },
          Map.new(opts)
        )
      )

    note
  end

  # A JSON object text with `pairs` in order, so a key may appear twice.
  defp object(pairs),
    do: "{" <> Enum.map_join(pairs, ",", fn {k, v} -> Jason.encode!(k) <> ":" <> v end) <> "}"

  # --- the closed schema: a label in the query --------------------------------

  # User story (ADR-0056 §7, ClosedBody: "a key the write does not take is
  # refused with 422 naming it, never dropped in silence"):
  # As the operator,
  # I want a label field sent in the query string beside a JSON body refused
  # naming it, as a field beside the label is,
  # so that a labeller's request that names security_id or tier anywhere
  # is never answered 201 as if the write had taken it.
  #
  # Acceptance criteria:
  # - PUT /api/v1/news/labels?label[security_id]=…, ?label[tier]=primary or
  #   ?label=x with a valid JSON label: 422 naming label (or the field),
  #   nothing stored or journaled.
  test "a label field in the query beside a JSON body is refused, not dropped", %{
    conn: conn,
    story: story,
    security: security
  } do
    body = Jason.encode!(%{label: label(story)})

    for query <- ["label[security_id]=#{security.id}", "label[tier]=primary", "label=x"] do
      answer = put_raw(conn, "/api/v1/news/labels?" <> query, body)

      assert answer.status == 422,
             "?#{query} beside a valid body answered #{answer.status}: " <>
               "the query's label was dropped in silence"

      assert refused!(answer)
             |> Map.keys()
             |> Enum.any?(&(&1 in ["label", "security_id", "tier"]))
    end
  end

  # --- the closed schema: encodings and spellings (closed, pinned) ------------

  # User story (the security lens: another body encoding):
  # As the operator,
  # I want a label sent form-encoded, through the method override, or as a
  # top-level JSON array refused whole,
  # so that no parser but JSON's can carry a label, and no parser's own key
  # (`_method`, `_json`) passes for one.
  #
  # Acceptance criteria:
  # - A form-encoded PUT of every label field: 422 naming the integer fields
  #   (a form carries only strings).
  # - A form-encoded POST with _method=PUT: 422 naming _method.
  # - A JSON array body: 422 naming _json.
  test "a form, a method override and a top-level array carry no label", %{
    conn: conn,
    story: story
  } do
    form = label(story) |> Enum.map(fn {k, v} -> {"label[#{k}]", to_string(v)} end)

    errors =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put("/api/v1/news/labels", URI.encode_query(form))
      |> refused!()

    assert Enum.sort(Map.keys(errors)) == ~w(cluster_id materiality tone)

    errors =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/api/v1/news/labels", URI.encode_query([{"_method", "PUT"} | form]))
      |> refused!()

    assert Map.has_key?(errors, "_method")

    errors = conn |> put_raw(Jason.encode!([%{label: label(story)}])) |> refused!()
    assert Map.has_key?(errors, "_json")
  end

  # User story (the security lens: keys that look like §7's):
  # As the operator,
  # I want a key that differs from a field of §7 only by case, a lookalike
  # letter, a fullwidth form, an invisible character or a JavaScript
  # prototype name refused naming it,
  # so that no spelling of a field the screen shows as the same word passes
  # the closed schema.
  #
  # Acceptance criteria:
  # - Cluster_id, CLUSTER_ID, materiality with a Cyrillic a (U+0430), tone
  #   with a fullwidth t (U+FF54), tone + U+200B, tone + U+0301, __proto__
  #   and constructor
  #   inside label: 422 naming the key as sent.
  test "a key spelled like a field but not one is refused as sent", %{conn: conn, story: story} do
    for key <- [
          "Cluster_id",
          "CLUSTER_ID",
          "m\u0430teriality",
          "\uFF54one",
          "tone\u200B",
          "tone\u0301",
          "__proto__",
          "constructor"
        ] do
      errors = conn |> put_label(label(story, %{key => 1})) |> refused!()
      assert Map.keys(errors) == [key], inspect(key)
    end
  end

  # User story (the security lens: JSON's own ambiguities):
  # As the operator,
  # I want a duplicated key read one way only — the value the shape check
  # and the ranges saw is the value stored and answered, never a mix — and
  # numbers that only look like integers refused,
  # so that a body two parsers would read differently cannot store a value
  # the checks did not see.
  #
  # Acceptance criteria:
  # - materiality given twice, in either order of an in-range and an
  #   out-of-range value: refused naming materiality, or stored in range
  #   with the stored row, the answer and the journal's after image equal.
  #   (Jason keeps the first of two equal keys; the companion's JSON.parse
  #   the last, and it re-encodes what it validated, so no duplicate
  #   reaches the API through it.)
  # - materiality 1.0, 1e0 and 2E0: 422 naming it; -0 is the integer 0.
  # - a second label key whose value is not an object: never stored as one.
  test "a duplicated key is read once, and a float that equals an integer is refused", %{
    conn: conn,
    story: story
  } do
    base =
      label(story)
      |> Map.delete("materiality")
      |> Enum.map(fn {k, v} -> {k, Jason.encode!(v)} end)

    for {{first, second}, model} <- [{{"3", "4"}, "dup-a"}, {{"4", "3"}, "dup-b"}] do
      body =
        object([
          {"label",
           object(
             List.keystore(base, "model", 0, {"model", Jason.encode!(model)}) ++
               [{"materiality", first}, {"materiality", second}]
           )}
        ])

      answer = put_raw(conn, body)

      case answer.status do
        422 ->
          assert Map.keys(json_response(answer, 422)["errors"]) == ["materiality"]

        201 ->
          data = json_response(answer, 201)["data"]
          row = Repo.get!(Label, data["id"])
          assert data["materiality"] in 0..3 and row.materiality == data["materiality"]
          [entry | _] = entries()
          assert entry.resource_id == to_string(row.id)
      end
    end

    for number <- ["1.0", "1e0", "2E0"] do
      body = object([{"label", object(base ++ [{"materiality", number}])}])
      answer = put_raw(conn, body)
      assert Map.keys(json_response(answer, 422)["errors"]) == ["materiality"], number
    end

    answer =
      put_raw(
        conn,
        object([{"label", object(base ++ [{"materiality", "1"}])}, {"label", ~s("x")}])
      )

    assert answer.status in [201, 422]

    if answer.status == 201,
      do: assert(json_response(answer, 201)["data"]["materiality"] == 1)

    zero = put_raw(conn, object([{"label", object(base ++ [{"materiality", "-0"}])}]))
    assert zero.status in [200, 201]
    assert Jason.decode!(zero.resp_body)["data"]["materiality"] == 0
  end

  # User story (ADR-0003; the security lens: decimal strings a parser
  # might be lenient about):
  # As the operator,
  # I want a confidence string held to plain ASCII digits with one point,
  # so that a sign, an exponent, a hex form, a trailing line break, a
  # fullwidth or Arabic-Indic digit or a bare point never becomes a stored
  # confidence.
  #
  # Acceptance criteria:
  # - "+0.5", "0.5\n", "0.5 ", "\t0.5", ".5", "5.", "1.", "0x1", "0b1",
  #   "U+FF11", "U+FF10.U+FF15", "U+0660.U+0665", "0.5e0", "1_0", "0.9999U+200B", a 33-byte
  #   string of zeros: 422 naming confidence.
  # - "00.5" and "0.50000" are the decimal 0.5 (the value counts, not the
  #   spelling).
  test "confidence takes ASCII digits only, read as its value", %{conn: conn, story: story} do
    for bad <- [
          "+0.5",
          "0.5\n",
          "0.5 ",
          "\t0.5",
          ".5",
          "5.",
          "1.",
          "0x1",
          "0b1",
          "\uFF11",
          "\uFF10.\uFF15",
          "\u0660.\u0665",
          "0.5e0",
          "1_0",
          "0.9999\u200B",
          String.duplicate("0", 33)
        ] do
      errors = conn |> put_label(label(story, %{"confidence" => bad})) |> refused!()
      assert Map.keys(errors) == ["confidence"], inspect(bad)
    end

    for {spelled, model} <- [{"00.5", "m-a"}, {"0.50000", "m-b"}] do
      stored =
        conn
        |> put_label(label(story, %{"confidence" => spelled, "model" => model}))
        |> json_response(201)

      assert stored["data"]["confidence"] == "0.5", spelled
    end
  end

  # --- other routes: no other write reaches a label ---------------------------

  # User story (ADR-0056 §7: "security_id, tier, status, notes, events and
  # feeds cannot be written through it" — and the reverse):
  # As the operator,
  # I want the news layer's other writes to refuse a label carried beside
  # their own object, and the labeller's read to refuse a write's fields,
  # so that no route but PUT /news/labels stores a label, and no method
  # but PUT reaches it.
  #
  # Acceptance criteria:
  # - PUT /news/feeds and PUT /news/sources with a label beside their
  #   object: 422 naming label; no label stored.
  # - POST, PATCH and DELETE on /news/labels: no label stored.
  # - GET /news/unlabeled with label[...] in the query: 422 naming label.
  test "no other route or method writes a label", %{conn: conn, story: story} do
    lbl = label(story)

    for {path, body} <- [
          {"/api/v1/news/feeds",
           %{feed: %{url: "https://newsroom.example.com/a.xml", class: "aggregator"}, label: lbl}},
          {"/api/v1/news/sources",
           %{source: %{domain: "wire.example.com", tier: "primary"}, label: lbl}}
        ] do
      answer = put_raw(conn, path, Jason.encode!(body))
      assert answer.status == 422, path
      assert Map.has_key?(json_response(answer, 422)["errors"], "label"), path
    end

    for method <- [:post, :patch, :delete] do
      try do
        conn
        |> json()
        |> dispatch(@endpoint, method, "/api/v1/news/labels", Jason.encode!(%{label: lbl}))
      rescue
        Phoenix.Router.NoRouteError -> :no_route
      end
    end

    assert Repo.aggregate(Label, :count) == 0

    answer = get(conn, "/api/v1/news/unlabeled?prompt_version=v1&label[cluster_id]=#{story.id}")
    assert Map.keys(json_response(answer, 422)["errors"]) == ["label"]
  end

  # --- the thesis a label may name --------------------------------------------

  # User story (ADR-0056 §7: news.unlabeled offers "the active thesis's
  # invalidation_condition split into numbered clauses, with the note id";
  # materiality 3 "touches an invalidation condition"):
  # As the operator,
  # I want a label's thesis_note_id held to the thesis news.unlabeled
  # offers — the security's current, intact thesis — and its clause_idx
  # to that thesis's clauses,
  # so that a label never says a story touches clause 3 of a condition that
  # a newer thesis replaced or a retraction withdrew.
  #
  # Acceptance criteria:
  # - With thesis A (three clauses) superseded by thesis B (one clause),
  #   news.unlabeled offers B; a label naming A's clause 3 is refused
  #   naming thesis_note_id.
  # - With the current thesis retracted, news.unlabeled offers none; a
  #   label naming it is refused naming thesis_note_id.
  test "a label names only the thesis the labeller's read offers", %{
    conn: conn,
    security: security,
    story: story
  } do
    old = thesis!(security, "Margin falls; the CEO leaves; the order book shrinks")
    new = thesis!(security, "Cash runs out", supersedes_id: old.id)

    offered = get(conn, "/api/v1/news/unlabeled?prompt_version=v1") |> json_response(200)
    assert [%{"note_id" => note_id}] = offered["data"]["theses"]
    assert note_id == new.id

    superseded =
      conn
      |> put_label(
        label(story, %{"thesis_note_id" => old.id, "clause_idx" => 3, "materiality" => 3})
      )
      |> Map.fetch!(:status)

    other = security!("Harbourline Attack Freight AG")
    other_story = story!(other)
    current = thesis!(other, "Order book shrinks")

    {:ok, _retraction} =
      Knowledge.append_note(Actor.owner_ui(), %{
        security_id: other.id,
        author: :operator,
        kind: :retraction,
        body: "Withdrawn",
        source_quality: :primary,
        as_of: Date.utc_today(),
        supersedes_id: current.id
      })

    retracted =
      conn
      |> put_label(label(other_story, %{"thesis_note_id" => current.id, "clause_idx" => 1}))
      |> Map.fetch!(:status)

    assert {superseded, retracted} == {422, 422},
           "stored: a superseded thesis's clause 3 (#{superseded}) and a retracted thesis's " <>
             "clause 1 (#{retracted}); news.unlabeled offered only note #{new.id} and none"
  end

  # --- the labeller's read: the universe's width -------------------------------

  # User story (ADR-0056 §9: "short names of at most 20 characters"; the
  # amendment of 2026-11-08, C5: widths counted as the companion spells
  # them):
  # As the operator whose labeller pays for every token it reads,
  # I want every name news.unlabeled answers — the universe's and the
  # categories' — cut at 20 characters as the companion counts them (code
  # points, an invisible one by its [U+XXXX] spelling), as titles and
  # clauses already are,
  # so that a name built of combining marks or joined emoji, typed,
  # imported or taken from a search provider, cannot make one universe
  # entry cost ten times its share of the budget.
  #
  # Acceptance criteria:
  # - A security named "A" and 254 combining acute accents (255 code
  #   points, one grapheme) and a category named "W" and 254 combining
  #   marks: each answered with a name of at most 20 code points.
  test "the universe's and the categories' names are cut by spelled width", %{conn: conn} do
    hostile = "A" <> String.duplicate("\u0301", 254)
    wide = security!(hostile)
    _story = story!(wide)

    category = category!()

    {:ok, category} =
      Portfolixir.Classifications.update_category(Actor.owner_ui(), category, %{
        name: "W" <> String.duplicate("\u0302", 254)
      })

    {:ok, %{stored: 1}} =
      Ingest.ingest(
        feed!(%{class: "thematic", category_id: category.id}),
        [%Parsed{title: "Water theme", link: "https://theme.example.com/w-1"}],
        DateTime.utc_now()
      )

    data =
      get(conn, "/api/v1/news/unlabeled?prompt_version=v1")
      |> json_response(200)
      |> Map.fetch!("data")

    names =
      Enum.map(data["universe"], &{"security #{&1["id"]}", &1["name"]}) ++
        Enum.map(data["categories"] || [], &{"category #{&1["id"]}", &1["name"]})

    assert Enum.any?(names, fn {_who, name} -> String.starts_with?(name, "A\u0301") end)

    wide_names =
      for {who, name} <- names,
          width = name |> String.codepoints() |> length(),
          width > 20,
          do: "#{who}: #{width} code points"

    assert wide_names == [], "names wider than 20 in news.unlabeled: #{inspect(wide_names)}"
  end
end
