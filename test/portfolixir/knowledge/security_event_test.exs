defmodule Portfolixir.Knowledge.SecurityEventTest do
  # ADR-0048 §6 and the "Hard Rules" atom clause: the three closed sets are
  # cast by hand so that an unknown value is a plain `"is invalid"` and never
  # a new atom. That guarantee lives in the changeset, so it is pinned here
  # rather than through the controller, where a JSON body can only ever carry
  # strings and the atom and non-string paths are unreachable.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Knowledge.SecurityEvent

  @today ~D[2026-09-19]

  defp valid_attrs(security, attrs) do
    Enum.into(attrs, %{
      security_id: security.id,
      kind: "earnings",
      date: @today,
      timing: "exact",
      source_quality: "primary"
    })
  end

  defp create(security, attrs) do
    Events.create_event(Actor.owner_ui(), valid_attrs(security, attrs))
  end

  setup do
    %{security: create_security!(name: "Closed Set Co", ticker: "CSC")}
  end

  # User story (ADR-0048 §6, FR-44):
  # As the agent writing an event over the JSON API or MCP,
  # I want a value outside a closed set rejected with a field error I can read,
  # so that a typo in `kind` is a 422 naming the field rather than a new atom
  # in a table that is never garbage-collected.
  #
  # Acceptance criteria:
  # - An unknown string in any of the three closed sets is `"is invalid"`.
  # - The unknown string does not become an atom.
  # - A value that is neither a string nor an atom is `"is invalid"` too —
  #   not an `Ecto.Enum` type tuple the API error renderer cannot interpolate.
  # - An atom already in the set is accepted, so an internal caller may pass
  #   one; an atom outside it is `"is invalid"`.
  test "rejects an unknown closed-set string without creating an atom", %{security: security} do
    for field <- [:kind, :timing, :source_quality] do
      # Unique per run, so it cannot already be in the atom table for an
      # unrelated reason: if the cast created one, the second lookup below
      # would find it.
      value = "not_a_#{field}_#{System.unique_integer([:positive])}"

      assert_raise ArgumentError, fn -> String.to_existing_atom(value) end

      assert {:error, changeset} = create(security, %{field => value})
      assert errors_on(changeset)[field] == ["is invalid"]

      assert_raise ArgumentError, fn -> String.to_existing_atom(value) end
    end
  end

  # The same rejection with the values an operator actually mistypes — the
  # near-misses are what the message has to be readable for.
  test "rejects a plausible near-miss in each closed set", %{security: security} do
    for {field, value} <- [kind: "earnings_call", timing: "roughly", source_quality: "hearsay"] do
      assert {:error, changeset} = create(security, %{field => value})
      assert errors_on(changeset)[field] == ["is invalid"]
    end
  end

  test "rejects a closed-set value that is neither string nor atom", %{security: security} do
    assert {:error, changeset} = create(security, %{kind: 7})
    assert errors_on(changeset)[:kind] == ["is invalid"]
  end

  test "accepts a closed-set atom from an internal caller", %{security: security} do
    assert {:ok, event} =
             create(security, %{
               kind: :ex_dividend,
               timing: :estimated,
               source_quality: :awareness
             })

    assert event.kind == :ex_dividend
    assert event.timing == :estimated
    assert event.source_quality == :awareness
  end

  test "rejects a closed-set atom outside the set", %{security: security} do
    assert {:error, changeset} = create(security, %{kind: :earnings_call})
    assert errors_on(changeset)[:kind] == ["is invalid"]
  end

  # A blank closed-set value is a *missing* value, not a wrong one: the error
  # an operator reads should say the field is empty, because "is invalid"
  # sends them looking for a typo in something they never typed.
  test "reports a blank closed-set value as missing, not invalid", %{security: security} do
    for blank <- [nil, ""] do
      assert {:error, changeset} = create(security, %{kind: blank})
      assert errors_on(changeset)[:kind] == ["can't be blank"]
    end
  end

  # On an update the same skip means "leave it alone" — a required closed set
  # cannot be cleared, and a partial PATCH that omits it must not fail.
  test "leaves a closed set untouched when an update passes it blank", %{security: security} do
    {:ok, event} = create(security, %{kind: "index_review"})

    assert {:ok, updated} =
             Events.update_event(Actor.owner_ui(), event, %{"kind" => "", "confirmed" => true})

    assert updated.kind == :index_review
    assert updated.confirmed == true
  end

  # User story (ADR-0048 §6):
  # As the operator correcting an event in a form,
  # I want a field I blanked out to be stored as empty rather than as spaces,
  # so that "no source link yet" and "a link made of whitespace" are the same
  # row, and the http(s) check does not fire on something I did not type.
  #
  # Acceptance criteria:
  # - A whitespace-only `source_url` or `note` is stored as `nil`.
  # - A surrounding-whitespace value is stored trimmed.
  # - Clearing a stored value with an explicit `nil` clears it.
  # - A whitespace-only value on an *update* clears the stored one, rather
  #   than being skipped as if the field had been omitted.
  test "normalises blank text to nil and trims what is left", %{security: security} do
    assert {:ok, event} = create(security, %{source_url: "   ", note: "  Q3 call  "})
    assert event.source_url == nil
    assert event.note == "Q3 call"
  end

  test "clears a stored source url with an explicit nil", %{security: security} do
    {:ok, event} = create(security, %{source_url: "https://example.invalid/ir"})

    assert {:ok, cleared} = Events.update_event(Actor.owner_ui(), event, %{source_url: nil})
    assert cleared.source_url == nil
  end

  test "clears a stored note when an update blanks it out", %{security: security} do
    {:ok, event} = create(security, %{note: "Q3 call"})

    assert {:ok, cleared} = Events.update_event(Actor.owner_ui(), event, %{"note" => "   "})
    assert cleared.note == nil
  end

  # The three accessors are what the API contract and the MCP tool schemas
  # enumerate; a set that grew in the schema and not in its accessor would
  # ship a tool schema that rejects a value the database accepts.
  test "exposes each closed set as the strings the API and MCP schemas carry" do
    assert "earnings" in SecurityEvent.kinds()
    assert "guidance_update" in SecurityEvent.kinds()
    assert SecurityEvent.timings() == ~w(exact estimated window month)
    assert SecurityEvent.source_qualities() == ~w(primary secondary_multi awareness unverified)

    for set <- [SecurityEvent.kinds(), SecurityEvent.timings(), SecurityEvent.source_qualities()],
        value <- set do
      assert is_binary(value)
    end
  end

  # Acceptance criteria (closing-act finding): the column counts codepoints,
  # so a URL of 255 graphemes built from combining marks is refused by the
  # changeset rather than by the database.
  test "a source_url over 255 codepoints is refused even under 255 graphemes", %{
    security: security
  } do
    combining = "https://x.invalid/" <> String.duplicate("e\u0301", 237)
    assert String.length(combining) == 255

    assert {:error, changeset} = create(security, %{source_url: combining})
    assert %{source_url: [_ | _]} = errors_on(changeset)
  end
end
