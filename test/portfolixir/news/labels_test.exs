defmodule Portfolixir.News.LabelsTest do
  # ADR-0056 §7, §12 and §14 item 6 (Sprint 28, N1): the labels an outside
  # model writes — the table's rules, each refused by the context with a
  # field error and by the database when a row bypasses the context; the one
  # write, closed, idempotent per (cluster, model, prompt version) and
  # journaled under the token that wrote it; and labels that outlive their
  # story. Synthetic names and hosts only, no socket.
  use Portfolixir.DataCase, async: true

  import Ecto.Query, only: [from: 2]
  import Portfolixir.NewsFixtures, only: [category!: 0, feed!: 1, security!: 0, security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Label
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Retention
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo

  @labeller Actor.api_token_rw("labeller")

  defp story!(security \\ security!()), do: NewsFixtures.story!(security)

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

  defp entries, do: Journal.list_entries(resource_type: "news_label", limit: 50)

  defp actor! do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-schema-test', true)")
  end

  defp raw_insert(row) do
    columns = Map.keys(row)
    placeholders = Enum.map_join(1..length(columns), ", ", &"$#{&1}")
    sql = "INSERT INTO news_labels (#{Enum.join(columns, ", ")}) VALUES (#{placeholders})"
    actor!()

    case Repo.query(sql, Enum.map(columns, &Map.fetch!(row, &1)), mode: :savepoint) do
      {:ok, _result} ->
        :inserted

      {:error, %Postgrex.Error{postgres: %{constraint: constraint}}} when constraint != nil ->
        constraint

      {:error, %Postgrex.Error{postgres: %{code: code}}} ->
        code
    end
  end

  describe "the table (§7)" do
    # User story (ADR-0056 §7):
    # As the operator who lets an outside model label stories,
    # I want every rule of a label's own fields held by the database too,
    # so that a writer that skips the context still cannot store a label
    # outside §7's schema.
    #
    # Acceptance criteria:
    # - The event type is one of the nine; materiality 0 to 3; tone -1, 0
    #   or +1; confidence a decimal from 0 to 1 with at most four places;
    #   machine_generated true; model and prompt version identifiers of at
    #   most 64 characters; a clause only with a thesis note, from 1.
    # - One label per (cluster, model, prompt version); a thesis note that
    #   does not exist is refused by its foreign key.
    # - A write without a journal actor is refused by the guard.
    # - A row inside every rule is stored, its confidence a numeric, never a
    #   float.
    test "every rule of the row is refused by the database" do
      story = story!()
      now = NaiveDateTime.utc_now()

      row = %{
        cluster_id: story.id,
        model: "m",
        prompt_version: "v1",
        event_type: "earnings",
        materiality: 1,
        tone: 0,
        confidence: Decimal.new("0.5"),
        machine_generated: true,
        created_at: now,
        updated_at: now
      }

      assert raw_insert(%{row | event_type: "rumour"}) == "news_labels_event_type_check"
      assert raw_insert(%{row | materiality: 4}) == "news_labels_materiality_check"
      assert raw_insert(%{row | materiality: -1}) == "news_labels_materiality_check"
      assert raw_insert(%{row | tone: 2}) == "news_labels_tone_check"
      assert raw_insert(%{row | tone: -2}) == "news_labels_tone_check"

      assert raw_insert(%{row | confidence: Decimal.new("1.0001")}) ==
               "news_labels_confidence_check"

      assert raw_insert(%{row | confidence: Decimal.new("-0.1")}) ==
               "news_labels_confidence_check"

      assert raw_insert(%{row | confidence: Decimal.new("0.12345")}) ==
               "news_labels_confidence_check"

      assert raw_insert(%{row | machine_generated: false}) ==
               "news_labels_machine_generated_check"

      assert raw_insert(%{row | model: "two words"}) == "news_labels_model_check"

      assert raw_insert(%{row | model: String.duplicate("m", 65)}) ==
               :string_data_right_truncation

      assert raw_insert(%{row | model: "m\u200B"}) == "news_labels_model_check"
      assert raw_insert(%{row | prompt_version: ""}) == "news_labels_prompt_version_check"
      assert raw_insert(Map.put(row, :clause_idx, 1)) == "news_labels_clause_check"

      note = thesis!(security!("Clause Holder AG"), "Margin falls")

      assert raw_insert(Map.merge(row, %{thesis_note_id: note.id, clause_idx: 0})) ==
               "news_labels_clause_check"

      assert raw_insert(Map.put(row, :thesis_note_id, note.id + 1_000_000)) ==
               "news_labels_thesis_note_id_fkey"

      assert raw_insert(%{row | updated_at: NaiveDateTime.add(now, -1)}) ==
               "news_labels_updated_at_check"

      assert raw_insert(row) == :inserted
      assert raw_insert(%{row | event_type: "noise"}) == "news_labels_cluster_model_version_index"

      Repo.query!("SELECT set_config('portfolixir.journal_actor', '', true)")

      assert {:error, %Postgrex.Error{postgres: %{code: :restrict_violation}}} =
               Repo.query(
                 "UPDATE news_labels SET tone = 1 WHERE cluster_id = $1",
                 [story.id],
                 mode: :savepoint
               )

      %{rows: [[type]]} =
        Repo.query!(
          "SELECT data_type FROM information_schema.columns " <>
            "WHERE table_name = 'news_labels' AND column_name = 'confidence'"
        )

      assert type == "numeric"
    end
  end

  describe "put_label/2 (§7, §14 item 6)" do
    # User story (ADR-0056 §7, §14 item 6):
    # As the operator,
    # I want every label stored with the model and prompt version that made
    # it, marked machine-generated, and journaled under the token that wrote
    # it,
    # so that I can always tell which labeller said what about a story.
    #
    # Acceptance criteria:
    # - A put stores the label's fields, machine_generated true and
    #   created_at, and answers :created; the journal entry is a
    #   `news_label` create under the writer's actor and label, its after
    #   image the label with confidence as a string.
    # - The same (cluster, model, prompt version) again replaces the label
    #   in place (:updated): one row, a journaled update whose before image
    #   is the old label; an optional field not sent is cleared.
    # - The same put a third time changes nothing (:unchanged) and records
    #   no entry.
    # - Another model or prompt version is a label of its own.
    test "stores, replaces in place and journals under the writer's token" do
      security = security!()
      story = story!(security)
      suggested = security!("Harbourline Freight AG")

      assert {:ok, :created, label} =
               News.put_label(
                 @labeller,
                 label(story, %{"suggested_security_id" => suggested.id})
               )

      assert %Label{
               cluster_id: cluster_id,
               model: "synthetic-model-1",
               prompt_version: "v1",
               event_type: :earnings,
               materiality: 2,
               tone: 1,
               machine_generated: true,
               suggested_security_id: suggested_id
             } = label

      assert {cluster_id, suggested_id} == {story.id, suggested.id}
      assert Decimal.equal?(label.confidence, Decimal.new("0.85"))
      assert %DateTime{} = label.created_at

      assert [create] = entries()

      assert {create.operation, create.actor_type, create.actor_label} ==
               {:create, :api_token_rw, "labeller"}

      assert create.resource_id == to_string(label.id)
      assert create.after["confidence"] == "0.85"
      assert create.after["machine_generated"] == true

      assert {:ok, :updated, replaced} =
               News.put_label(
                 @labeller,
                 label(story, %{"event_type" => "guidance", "tone" => -1, "confidence" => "0.6"})
               )

      assert replaced.id == label.id
      assert {replaced.event_type, replaced.tone} == {:guidance, -1}
      assert replaced.suggested_security_id == nil
      assert Repo.aggregate(Label, :count) == 1

      assert [update, ^create] = entries()
      assert update.operation == :update
      assert update.actor_label == "labeller"
      assert update.before["event_type"] == "earnings"
      assert update.before["suggested_security_id"] == suggested.id
      assert update.after["event_type"] == "guidance"

      assert {:ok, :unchanged, same} =
               News.put_label(
                 @labeller,
                 label(story, %{"event_type" => "guidance", "tone" => -1, "confidence" => "0.60"})
               )

      assert same.id == label.id
      assert length(entries()) == 2

      assert {:ok, :created, other_model} =
               News.put_label(@labeller, label(story, %{"model" => "synthetic-model-2"}))

      assert {:ok, :created, other_version} =
               News.put_label(@labeller, label(story, %{"prompt_version" => "v2"}))

      assert length(Enum.uniq([label.id, other_model.id, other_version.id])) == 3
    end

    # User story (ADR-0056 §7: the schema is the hard limit on what a label
    # can change):
    # As the operator whose labeller is a script driven by a model,
    # I want the label write itself to refuse any key outside §7's fields
    # and any value of the wrong type, by name,
    # so that no caller of the context, the API's or another, can write a
    # security, a tier, a status, a note or a time through a label.
    #
    # Acceptance criteria:
    # - A key outside §7's fields (security_id, tier, status, notes,
    #   created_at, id) is refused naming it, nothing written or journaled.
    # - A value of the wrong JSON type is refused naming its field: an
    #   integer field given a string, a float or an object; a text field a
    #   number or a list; confidence a number ("must be a decimal string").
    # - machine_generated false is refused; true or absent is the same label.
    test "refuses every key outside the schema and every wrong type, by name" do
      story = story!()

      for key <- ~w(security_id tier status notes created_at updated_at id label) do
        assert {:error, %{^key => [message]}} =
                 News.put_label(@labeller, label(story, %{key => 1}))

        assert message =~ "is unknown"
      end

      for {key, value} <- [
            {"cluster_id", "#{story.id}"},
            {"materiality", "2"},
            {"materiality", 2.0},
            {"tone", %{"value" => 1}},
            {"clause_idx", [1]},
            {"model", 7},
            {"prompt_version", ["v1"]},
            {"event_type", %{"code" => "earnings"}},
            {"machine_generated", "true"},
            {"suggested_security_id", "12"}
          ] do
        assert {:error, %{^key => [_message]}} =
                 News.put_label(@labeller, label(story, %{key => value})),
               "#{key}: #{inspect(value)}"
      end

      assert {:error, %{"confidence" => ["must be a decimal string"]}} =
               News.put_label(@labeller, label(story, %{"confidence" => 0.85}))

      assert {:error, %Ecto.Changeset{} = changeset} =
               News.put_label(@labeller, label(story, %{"machine_generated" => false}))

      assert %{machine_generated: [_always]} = errors_on(changeset)

      assert Repo.aggregate(Label, :count) == 0
      assert entries() == []

      assert {:ok, :created, _label} =
               News.put_label(@labeller, label(story, %{"machine_generated" => true}))
    end

    # User story (ADR-0056 §7; ADR-0054 §4):
    # As the operator reading a label,
    # I want its values held to §7's ranges and its identifiers to visible,
    # bounded text,
    # so that a label is always one of the shapes the record names and a
    # model name cannot hide a character I cannot see.
    #
    # Acceptance criteria:
    # - materiality 4 or -1, tone 2, an event type outside the nine, a
    #   confidence above 1, below 0, with five places or not a plain decimal
    #   are refused naming the field.
    # - A model or prompt version with an invisible character is refused
    #   naming the character; one of 65 characters, with a space, or empty
    #   is refused naming the field.
    # - The required fields are named when missing.
    test "refuses values outside §7's ranges and identifiers that hide text" do
      story = story!()

      for {key, value} <- [
            {"materiality", 4},
            {"materiality", -1},
            {"tone", 2},
            {"tone", -2},
            {"event_type", "rumour"},
            {"event_type", "Earnings"},
            {"confidence", "1.0001"},
            {"confidence", "-0.1"},
            {"confidence", "0.12345"},
            {"confidence", "1e-1"},
            {"confidence", " 0.5"},
            {"confidence", "NaN"},
            {"model", String.duplicate("m", 65)},
            {"model", "two words"},
            {"model", ""},
            {"prompt_version", "v1\n"}
          ] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 News.put_label(@labeller, label(story, %{key => value})),
               "#{key}: #{inspect(value)}"

        assert Map.has_key?(errors_on(changeset), String.to_existing_atom(key)),
               "#{key}: #{inspect(value)} → #{inspect(errors_on(changeset))}"
      end

      for {key, hidden} <- [{"model", "model\u200B"}, {"prompt_version", "v1\u202E"}] do
        assert {:error, changeset} = News.put_label(@labeller, label(story, %{key => hidden}))
        [message | _] = errors_on(changeset)[String.to_existing_atom(key)]
        assert message =~ "invisible characters"
        assert message =~ "U+"
      end

      assert {:error, changeset} =
               News.put_label(@labeller, Map.drop(label(story), ["event_type", "confidence"]))

      assert %{event_type: ["can't be blank"], confidence: ["can't be blank"]} =
               errors_on(changeset)

      assert Repo.aggregate(Label, :count) == 0
    end

    # User story (ADR-0056 §7: a label is about one story and names only
    # records that exist):
    # As the operator,
    # I want a label refused when its story, its suggested security or its
    # thesis note does not exist, or when the note is not a thesis of the
    # story's own security, or the clause is not one of that thesis's,
    # so that a label never points at something it cannot be about.
    #
    # Acceptance criteria:
    # - A cluster_id that names no story: refused naming cluster_id.
    # - A suggested_security_id that names no security: refused naming it.
    # - A thesis_note_id that names no note, another security's thesis, or a
    #   note of the story's security that is not a thesis: refused naming
    #   thesis_note_id; a category's story names no thesis.
    # - A clause_idx without a thesis note, or past the thesis's clauses
    #   (line breaks and semicolons split them): refused naming clause_idx;
    #   the last clause is accepted.
    test "refuses a story, a security, a note or a clause that is not there" do
      security = security!()
      story = story!(security)
      other = security!("Harbourline Freight AG")
      note = thesis!(security, "Margin falls below 20 %;\nThe CEO leaves; ")
      other_note = thesis!(other, "Order book shrinks")

      {:ok, evidence} =
        Knowledge.append_note(Actor.owner_ui(), %{
          security_id: security.id,
          author: :operator,
          kind: :evidence,
          body: "Synthetic evidence",
          source_quality: :primary,
          as_of: Date.utc_today()
        })

      missing = story.id + 1_000_000

      assert {:error, %{cluster_id: [_]}} =
               errors_of(News.put_label(@labeller, label(story, %{"cluster_id" => missing})))

      assert {:error, %{suggested_security_id: [_]}} =
               errors_of(
                 News.put_label(
                   @labeller,
                   label(story, %{"suggested_security_id" => other.id + 1_000_000})
                 )
               )

      for note_id <- [note.id + 1_000_000, other_note.id, evidence.id] do
        assert {:error, %{thesis_note_id: [_]}} =
                 errors_of(
                   News.put_label(@labeller, label(story, %{"thesis_note_id" => note_id}))
                 ),
               "thesis_note_id #{note_id}"
      end

      assert {:error, %{clause_idx: [_]}} =
               errors_of(News.put_label(@labeller, label(story, %{"clause_idx" => 1})))

      assert {:error, %{clause_idx: [_]}} =
               errors_of(
                 News.put_label(
                   @labeller,
                   label(story, %{"thesis_note_id" => note.id, "clause_idx" => 3})
                 )
               )

      category_story = category_story!()

      assert {:error, %{thesis_note_id: [_]}} =
               errors_of(
                 News.put_label(
                   @labeller,
                   label(category_story, %{"thesis_note_id" => note.id})
                 )
               )

      assert Repo.aggregate(Label, :count) == 0
      assert entries() == []

      assert {:ok, :created, label} =
               News.put_label(
                 @labeller,
                 label(story, %{
                   "thesis_note_id" => note.id,
                   "clause_idx" => 2,
                   "materiality" => 3
                 })
               )

      assert {label.thesis_note_id, label.clause_idx} == {note.id, 2}
      assert {:ok, :created, _} = News.put_label(@labeller, label(category_story))
    end
  end

  describe "a label outlives its story (§12)" do
    # User story (ADR-0056 §12: labels are kept without limit, they are the
    # labeller's record):
    # As the operator,
    # I want retention to empty the staging area without touching labels,
    # so that a story that ages out does not take its labeller's record
    # with it, and a labelled story never blocks retention.
    #
    # Acceptance criteria:
    # - A labelled story whose item expires is deleted by retention; the
    #   label stays, naming the story's id.
    test "retention deletes the story and keeps its label" do
      security = security!()
      feed = feed!(%{class: "issuer", security_id: security.id})
      at = DateTime.utc_now()

      {:ok, %{stored: 1}} =
        Ingest.ingest(
          feed,
          [%Parsed{title: "Northwind Harbour release", link: "https://ir.example.com/r"}],
          at
        )

      [story] = Repo.all(Cluster)
      assert {:ok, :created, label} = News.put_label(@labeller, label(story))

      assert {:ok, %{stories_deleted: 1}} = Retention.run(DateTime.add(at, 91 * 86_400))
      assert Repo.get(Cluster, story.id) == nil
      assert %Label{cluster_id: cluster_id} = Repo.get!(Label, label.id)
      assert cluster_id == story.id
    end
  end

  # User story (ADR-0032 §3.3's allowlist):
  # As the operator whose labeller writes many labels a day,
  # I want a label write to invalidate no derived figure,
  # so that labelling news never makes every chart recompute.
  #
  # Acceptance criteria:
  # - A news_label write resolves to no portfolio and no security.
  test "a label write moves no derived figure" do
    assert BlastRadius.for_write("news_label", %Label{}) == []
    assert BlastRadius.securities_for_write("news_label", %Label{}) == []
  end

  defp category_story! do
    category = category!()
    feed = feed!(%{class: "thematic", category_id: category.id})

    {:ok, %{stored: 1}} =
      Ingest.ingest(
        feed,
        [%Parsed{title: "Water utilities face new rules", link: "https://wire.example.com/w"}],
        DateTime.utc_now()
      )

    Repo.one!(from(c in Cluster, where: c.category_id == ^category.id))
  end

  defp errors_of({:error, %Ecto.Changeset{} = changeset}), do: {:error, errors_on(changeset)}
  defp errors_of(other), do: other
end
