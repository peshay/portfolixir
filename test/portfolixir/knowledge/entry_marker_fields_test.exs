defmodule Portfolixir.Knowledge.EntryMarkerFieldsTest do
  # ADR-0044's amendment of 2026-11-06 (Sprint 28, N5): an entry may carry a
  # `headline`, an `event_type` and a `tone`, each set once at write, on an
  # `evidence` or `event_result` entry only. Risk tier: an agent write path
  # on the append-only log.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  defp security! do
    WorldFixtures.create_security!(name: "Marker Fields AG", ticker: "MKF", asset_class: "equity")
  end

  defp attrs(security, extra) do
    Map.merge(
      %{
        "security_id" => security.id,
        "author" => "agent",
        "kind" => "evidence",
        "body" => "A synthetic finding.",
        "source_quality" => "primary",
        "as_of" => "2026-11-01"
      },
      extra
    )
  end

  defp append(attrs), do: Knowledge.append_note(Actor.api_token_rw("agent"), attrs)

  # User story (ADR-0044, amendment of 2026-11-06):
  # As the operator who wants a kept news item drawn on the security's chart
  # with a short headline, coloured by how it reads for the security,
  # I want an evidence or event_result entry to carry a headline, an event
  # type and a tone, stated once by its writer,
  # so that the chart has something short to show and nothing about an entry
  # changes after it was written.
  #
  # Acceptance criteria:
  # - An evidence entry and an event_result entry store all three and answer
  #   them back; an entry without them reads them as absent.
  # - On any other kind, each of the three is refused naming the field.
  # - A headline over 80 characters, with a line break or an invisible
  #   character is refused naming headline (ADR-0054 §4); an event type
  #   outside the eight (noise included) and a tone outside -1, 0, 1 are
  #   refused naming their field, and no atom is made from input.
  # - The database refuses each rule too, and refuses an update of a stored
  #   entry's headline (the log is append-only).
  describe "headline, event_type and tone" do
    test "an evidence and an event_result entry store all three; others read them as absent" do
      security = security!()

      assert {:ok, evidence} =
               append(
                 attrs(security, %{
                   "headline" => "Quarterly margin above guidance",
                   "event_type" => "earnings",
                   "tone" => 1
                 })
               )

      assert evidence.headline == "Quarterly margin above guidance"
      assert evidence.event_type == :earnings
      assert evidence.tone == 1

      assert {:ok, result} =
               append(
                 attrs(security, %{
                   "kind" => "event_result",
                   "headline" => "Merger closed",
                   "event_type" => "m_and_a",
                   "tone" => -1
                 })
               )

      assert {result.event_type, result.tone} == {:m_and_a, -1}

      assert {:ok, plain} = append(attrs(security, %{}))
      assert {plain.headline, plain.event_type, plain.tone} == {nil, nil, nil}
    end

    test "on any other kind each of the three is refused naming the field" do
      security = security!()

      for kind <- ~w(thesis risk decision invalidation_check),
          {field, value} <- [{"headline", "A headline"}, {"event_type", "legal"}, {"tone", 0}] do
        assert {:error, changeset} = append(attrs(security, %{"kind" => kind, field => value}))

        assert Keyword.has_key?(changeset.errors, String.to_existing_atom(field)),
               "#{kind} took #{field}"
      end
    end

    test "a headline over 80 characters, multi-line or with an invisible character is refused" do
      security = security!()

      for headline <- [
            String.duplicate("x", 81),
            "two\nlines",
            "zero" <> <<0x200B::utf8>> <> "width"
          ] do
        assert {:error, changeset} = append(attrs(security, %{"headline" => headline}))
        assert Keyword.has_key?(changeset.errors, :headline), inspect(headline)
      end

      assert {:ok, note} = append(attrs(security, %{"headline" => String.duplicate("x", 80)}))
      assert String.length(note.headline) == 80
    end

    test "an event type outside the eight and a tone outside -1, 0, 1 are refused" do
      security = security!()

      for value <- ["noise", "not_an_event_type_atom_n5"] do
        assert {:error, changeset} = append(attrs(security, %{"event_type" => value}))
        assert Keyword.has_key?(changeset.errors, :event_type)
      end

      for tone <- [2, -2, "up"] do
        assert {:error, changeset} = append(attrs(security, %{"tone" => tone}))
        assert Keyword.has_key?(changeset.errors, :tone), inspect(tone)
      end

      assert SecurityNote.event_types() ==
               ~w(earnings guidance capital_measure legal m_and_a product regulatory macro)
    end

    test "the database refuses each rule, and an update of a stored headline" do
      security = security!()

      insert = fn kind, column, value ->
        Repo.transaction(fn ->
          Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system:test', true)")

          Repo.query!(
            "INSERT INTO security_notes (security_id, author, kind, body, source_quality, " <>
              "as_of, inserted_at, #{column}) VALUES ($1, 'agent', $2, 'b', 'primary', " <>
              "'2026-11-01', now(), $3)",
            [security.id, kind, value]
          )
        end)
      end

      for {kind, column, value, check} <- [
            {"thesis", "headline", "A headline", "security_notes_marker_kind_check"},
            {"evidence", "headline", String.duplicate("x", 81),
             "security_notes_headline_length_check"},
            {"evidence", "event_type", "noise", "security_notes_event_type_check"},
            {"evidence", "tone", 2, "security_notes_tone_check"}
          ] do
        assert_raise Postgrex.Error, ~r/#{check}/, fn -> insert.(kind, column, value) end
      end

      {:ok, note} = append(attrs(security, %{"headline" => "Stated once"}))

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.query!("UPDATE security_notes SET headline = 'Changed' WHERE id = $1", [note.id])
      end
    end
  end
end
