defmodule PortfolixirWeb.ApiV1NewsLabelsTest do
  # ADR-0056 §7 and §14 item 6 (Sprint 28, N1; plan D-1 criterion 2): the
  # label write over the API, attacked first. A label is written by a
  # script driven by an outside model, so this file reads every request as a
  # labeller that wants to write more than a label: a field outside §7, a
  # value of the wrong type or size, a story, security or note that is not
  # there, a character nobody can see. Each case answers 422 naming the
  # field and writes nothing. Synthetic names and hosts only, no socket.
  use PortfolixirWeb.ConnCase

  import Portfolixir.NewsFixtures, only: [security!: 0, security!: 1, story!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.News.Label
  alias Portfolixir.Repo

  @labeller_token String.duplicate("l", 40)
  @agent_token String.duplicate("a", 40)

  setup %{conn: conn} do
    previous = Application.get_env(:portfolixir, :api_tokens)

    Application.put_env(:portfolixir, :api_tokens, [
      {"labeller", @labeller_token},
      {"mcp", @agent_token}
    ])

    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    security = security!()

    %{conn: conn, security: security, story: story!(security)}
  end

  defp as(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  defp put_body(conn, body, token \\ @labeller_token),
    do: conn |> as(token) |> put("/api/v1/news/labels", Jason.encode!(body))

  defp put_label(conn, label, token \\ @labeller_token),
    do: put_body(conn, %{label: label}, token)

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

  defp thesis!(security, condition) do
    {:ok, note} =
      Knowledge.append_note(Actor.owner_ui(), %{
        security_id: security.id,
        author: :operator,
        kind: :thesis,
        body: "Synthetic thesis",
        source_quality: :primary,
        as_of: Date.utc_today(),
        invalidation_condition: condition
      })

    note
  end

  # User story (ADR-0056 §7, §14 item 6):
  # As the operator whose labeller is a script an outside model drives,
  # I want PUT /api/v1/news/labels to store exactly one label and answer it
  # compactly, and the journal to name the token that wrote it,
  # so that I can tell which labeller said what, and a second run of the
  # same labeller corrects its label instead of piling up copies.
  #
  # Acceptance criteria:
  # - A new label answers 201 with its fields, confidence as a string,
  #   machine_generated true and its times; null fields are left out.
  # - The same (cluster, model, prompt version) answers 200 and replaces
  #   the label in place; an equal put answers 200 and journals nothing.
  # - Each entry names the token that wrote it: the labeller's token, or
  #   the agent's when the agent's token writes.
  describe "PUT /api/v1/news/labels" do
    test "stores a label, replaces it in place, and journals the token", %{
      conn: conn,
      story: story
    } do
      created = conn |> put_label(label(story)) |> json_response(201) |> Map.fetch!("data")

      assert %{
               "cluster_id" => cluster_id,
               "model" => "synthetic-model-1",
               "prompt_version" => "v1",
               "event_type" => "earnings",
               "materiality" => 2,
               "tone" => 1,
               "confidence" => "0.85",
               "machine_generated" => true
             } = created

      assert cluster_id == story.id
      assert {:ok, _at, 0} = DateTime.from_iso8601(created["created_at"])

      for absent <- ~w(thesis_note_id clause_idx suggested_security_id),
          do: refute(Map.has_key?(created, absent), absent)

      replaced =
        conn
        |> put_label(label(story, %{"tone" => -1, "confidence" => "0.5"}))
        |> json_response(200)
        |> Map.fetch!("data")

      assert replaced["id"] == created["id"]
      assert {replaced["tone"], replaced["confidence"]} == {-1, "0.5"}

      assert conn
             |> put_label(label(story, %{"tone" => -1, "confidence" => "0.50"}))
             |> json_response(200)

      assert [update, create] = entries()
      assert {create.operation, update.operation} == {:create, :update}

      for entry <- [create, update] do
        assert {entry.actor_type, entry.actor_label} == {:api_token_rw, "labeller"}
        assert entry.resource_id == to_string(created["id"])
      end

      conn
      |> put_label(label(story, %{"model" => "synthetic-model-2"}), @agent_token)
      |> json_response(201)

      assert [by_agent | _] = entries()
      assert by_agent.actor_label == "mcp"
      assert Repo.aggregate(Label, :count) == 2
    end
  end

  # User story (ADR-0056 §7, plan D-1 criterion 2: a label can change
  # nothing but a label):
  # As the operator,
  # I want a label put that names any field outside §7 refused whole,
  # naming each such field, inside or beside the label,
  # so that a labeller cannot move a story to a security, rate a source,
  # promote an item, write a note or set a time through its one write.
  #
  # Acceptance criteria:
  # - security_id, tier, status, notes, events, feeds, assignment,
  #   created_at, updated_at and id inside label: 422 naming each, nothing
  #   stored or journaled.
  # - The same keys beside label in the body, or as query parameters:
  #   422 naming them.
  # - label that is not an object (a string, a number, a list, null): 422
  #   naming label.
  describe "the closed schema (attack cases)" do
    test "a field outside §7 is refused, naming it, inside or beside the label", %{
      conn: conn,
      story: story,
      security: security
    } do
      outside =
        ~w(security_id tier status notes events feeds assignment created_at updated_at id)

      for key <- outside do
        errors = conn |> put_label(label(story, %{key => security.id})) |> refused!()
        assert Map.keys(errors) == [key], key
        assert hd(errors[key]) =~ "is unknown", key
      end

      errors =
        conn
        |> put_label(label(story, Map.new(outside, &{&1, "x"})))
        |> refused!()

      assert Enum.sort(Map.keys(errors)) == Enum.sort(outside)

      errors = conn |> put_body(%{label: label(story), security_id: security.id}) |> refused!()
      assert Map.keys(errors) == ["security_id"]

      errors =
        conn
        |> as(@labeller_token)
        |> put("/api/v1/news/labels?tier=primary", Jason.encode!(%{label: label(story)}))
        |> refused!()

      assert Map.keys(errors) == ["tier"]

      for not_an_object <- ["earnings", 42, [label(story)], nil] do
        errors = conn |> put_body(%{label: not_an_object}) |> refused!()
        assert Map.has_key?(errors, "label"), inspect(not_an_object)
      end

      errors = conn |> put_body(%{}) |> refused!()
      assert Map.has_key?(errors, "label")
    end

    # User story (the security lens: a nested object, a wrong type):
    # As the operator,
    # I want every field of a label held to its one JSON type,
    # so that a nested object, a list or a number where text belongs never
    # reaches the cast, and an integer is never read from a string.
    #
    # Acceptance criteria:
    # - A nested object or a list in any field: 422 naming the field.
    # - An integer field given a string, a float or a boolean; a text field
    #   given a number or a boolean; machine_generated given a string: 422
    #   naming the field.
    test "a nested object or a wrong type in any field is refused, naming it", %{
      conn: conn,
      story: story
    } do
      cases =
        for key <- Label.fields(),
            bad <- [%{"nested" => %{"security_id" => 1}}, [1, 2]],
            do: {key, bad}

      cases =
        cases ++
          [
            {"cluster_id", to_string(story.id)},
            {"cluster_id", story.id + 0.0},
            {"materiality", "2"},
            {"materiality", 2.5},
            {"materiality", true},
            {"tone", "+1"},
            {"thesis_note_id", "1"},
            {"clause_idx", 1.0},
            {"suggested_security_id", "7"},
            {"model", 1},
            {"prompt_version", 1.5},
            {"event_type", true},
            {"machine_generated", "true"},
            {"machine_generated", 1}
          ]

      for {key, bad} <- cases do
        errors = conn |> put_label(label(story, %{key => bad})) |> refused!()
        assert Map.keys(errors) == [key], "#{key}: #{inspect(bad)} → #{inspect(errors)}"
      end
    end

    # User story (ADR-0003: decimals are strings in the API):
    # As the operator,
    # I want a confidence sent as a JSON number refused as every decimal the
    # API takes is, and a confidence string held to a plain decimal from 0
    # to 1,
    # so that a binary float never becomes a stored confidence.
    #
    # Acceptance criteria:
    # - 0.85 and 1 as JSON numbers: 422, confidence ["must be a decimal
    #   string"].
    # - "1.0001", "-0.1", "0.12345", "1e-1", " 0.5", "0,5", "NaN", "",
    #   "Infinity": 422 naming confidence. "0", "1" and "0.1234" are stored.
    test "confidence is a decimal string from 0 to 1, never a JSON number", %{
      conn: conn,
      story: story
    } do
      for number <- [0.85, 1, 0] do
        assert %{"confidence" => ["must be a decimal string"]} =
                 conn |> put_label(label(story, %{"confidence" => number})) |> refused!()
      end

      for bad <- ["1.0001", "-0.1", "0.12345", "1e-1", " 0.5", "0,5", "NaN", "", "Infinity"] do
        errors = conn |> put_label(label(story, %{"confidence" => bad})) |> refused!()
        assert Map.keys(errors) == ["confidence"], inspect(bad)
      end

      for {good, model} <- [{"0", "m0"}, {"1", "m1"}, {"0.1234", "m2"}] do
        assert conn
               |> put_label(label(story, %{"confidence" => good, "model" => model}))
               |> json_response(201)
      end
    end

    # User story (ADR-0056 §7's ranges and closed sets):
    # As the operator,
    # I want materiality, tone, the event type and machine_generated held to
    # what §7 names,
    # so that a label is always one of the shapes the digest and the screen
    # can read.
    #
    # Acceptance criteria:
    # - materiality 4 or -1, tone 2 or -2, an event type outside the nine
    #   (including a case variant and an atom-like string): 422 naming the
    #   field.
    # - machine_generated false: 422 naming it; true is accepted.
    test "values outside §7's ranges and sets are refused, naming the field", %{
      conn: conn,
      story: story
    } do
      for {key, bad} <- [
            {"materiality", 4},
            {"materiality", -1},
            {"tone", 2},
            {"tone", -2},
            {"event_type", "rumour"},
            {"event_type", "EARNINGS"},
            {"event_type", "Elixir.Portfolixir.Repo"},
            {"event_type", ""},
            {"machine_generated", false}
          ] do
        errors = conn |> put_label(label(story, %{key => bad})) |> refused!()
        assert Map.keys(errors) == [key], "#{key}: #{inspect(bad)}"
      end

      assert conn
             |> put_label(label(story, %{"machine_generated" => true}))
             |> json_response(201)
    end

    # User story (the security lens: sizes and invisible characters,
    # ADR-0054 §4):
    # As the operator,
    # I want an over-long or hidden model name or prompt version refused,
    # naming any invisible character by its code point,
    # so that a label's identity is always text I can read and compare.
    #
    # Acceptance criteria:
    # - model of 65 characters, prompt_version of 100,000: 422 naming each.
    # - A zero-width space, a right-to-left override, a tag character and a
    #   soft hyphen in model or prompt_version: 422 naming the field and the
    #   code point.
    # - A space, a line break or an empty string: 422 naming the field.
    test "an over-long or invisible identifier is refused, naming the code point", %{
      conn: conn,
      story: story
    } do
      for {key, bad} <- [
            {"model", String.duplicate("m", 65)},
            {"prompt_version", String.duplicate("v", 100_000)},
            {"model", "two words"},
            {"prompt_version", "v1\n"},
            {"model", ""}
          ] do
        errors = conn |> put_label(label(story, %{key => bad})) |> refused!()
        assert Map.keys(errors) == [key], key
      end

      for {key, hidden, point} <- [
            {"model", "model\u200B", "U+200B"},
            {"prompt_version", "v1\u202E", "U+202E"},
            {"model", "model" <> <<0xE0041::utf8>>, "U+E0041"},
            {"prompt_version", "v\u00AD1", "U+00AD"}
          ] do
        errors = conn |> put_label(label(story, %{key => hidden})) |> refused!()
        assert [message] = errors[key], key
        assert message =~ point, "#{key}: #{message}"
      end
    end

    # User story (the security lens: a story, a security or a note that is
    # not there, or not the story's):
    # As the operator,
    # I want a label refused when it names a story, a security or a thesis
    # that does not exist, a thesis of another security, or a clause the
    # thesis does not have,
    # so that a label never points at something it cannot be about.
    #
    # Acceptance criteria:
    # - cluster_id naming no story: 422 naming cluster_id; one past the
    #   bigint range: 422 naming it before any read.
    # - suggested_security_id naming no security: 422 naming it.
    # - thesis_note_id naming no note, another security's thesis or a note
    #   that is not a thesis: 422 naming it.
    # - clause_idx without a thesis note or past its clauses: 422 naming it.
    test "a story, security, note or clause that is not there is refused", %{
      conn: conn,
      story: story,
      security: security
    } do
      other = security!("Harbourline Freight AG")
      note = thesis!(security, "Margin falls below 20 %; the CEO leaves")
      other_note = thesis!(other, "Order book shrinks")

      for {key, value} <- [
            {"cluster_id", story.id + 1_000_000},
            {"cluster_id", 9_223_372_036_854_775_808},
            {"suggested_security_id", other.id + 1_000_000},
            {"thesis_note_id", note.id + 1_000_000},
            {"thesis_note_id", other_note.id},
            {"clause_idx", 1}
          ] do
        errors = conn |> put_label(label(story, %{key => value})) |> refused!()
        assert Map.keys(errors) == [key], "#{key}: #{value}"
      end

      errors =
        conn
        |> put_label(label(story, %{"thesis_note_id" => note.id, "clause_idx" => 3}))
        |> refused!()

      assert Map.keys(errors) == ["clause_idx"]

      assert conn
             |> put_label(
               label(story, %{
                 "thesis_note_id" => note.id,
                 "clause_idx" => 2,
                 "suggested_security_id" => other.id
               })
             )
             |> json_response(201)
    end

    # User story (plan D-1 criterion 2: a label can change nothing but a
    # label):
    # As the operator,
    # I want a label put, accepted or refused, to leave every other record
    # as it was,
    # so that the labeller's token reaching the API changes the labels and
    # the journal and nothing else.
    #
    # Acceptance criteria:
    # - After a refused put naming security_id, tier and status and an
    #   accepted put naming a suggested security and a thesis, the story,
    #   its items, the securities and the research log read exactly as
    #   before; only news_labels and the journal grew.
    test "a put changes nothing but a label", %{conn: conn, story: story, security: security} do
      other = security!("Harbourline Freight AG")
      note = thesis!(security, "Margin falls")

      snapshot = fn ->
        for table <- ~w(news_clusters news_items securities security_notes news_sources
                        news_feeds),
            into: %{} do
          {table, Repo.query!("SELECT * FROM #{table} ORDER BY id").rows}
        end
      end

      before = snapshot.()

      conn
      |> put_label(
        label(story, %{"security_id" => other.id, "tier" => "primary", "status" => "promoted"})
      )
      |> json_response(422)

      conn
      |> put_label(
        label(story, %{
          "suggested_security_id" => other.id,
          "thesis_note_id" => note.id,
          "clause_idx" => 1,
          "materiality" => 3
        })
      )
      |> json_response(201)

      assert snapshot.() == before
      assert Repo.aggregate(Label, :count) == 1
      assert [_one] = entries()
    end

    # User story (AGENTS.md: no atom from external input):
    # As the operator,
    # I want a flood of unknown keys and unknown event types to make no atom,
    # so that a labeller cannot fill the VM's atom table through the one
    # write it has.
    #
    # Acceptance criteria:
    # - 500 puts, each with a distinct unknown key and a distinct unknown
    #   event type, leave the VM's atom count unchanged.
    test "unknown keys and event types make no atom", %{conn: conn, story: story} do
      warm = label(story, %{"zz_warm" => 1, "event_type" => "zz_warm"})
      conn |> put_label(warm) |> json_response(422)
      before = :erlang.system_info(:atom_count)

      for n <- 1..500 do
        key = "zz_unknown_key_#{n}_#{System.unique_integer([:positive])}"
        type = "zz_event_#{n}_#{System.unique_integer([:positive])}"
        conn |> put_label(label(story, %{key => 1, "event_type" => type})) |> json_response(422)
      end

      assert :erlang.system_info(:atom_count) == before
    end
  end
end
