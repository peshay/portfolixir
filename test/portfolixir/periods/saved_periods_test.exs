defmodule Portfolixir.Periods.SavedPeriodsTest do
  # Sprint 32 T2 (I59; ADR-0062's amendment of 2026-11-25, point 6): the
  # operator's own periods, stored on the server — a name (1 to 40
  # characters, trimmed, no control characters), `from`, and `to` or
  # "until today"; at most 50; journaled per write under its actor; a
  # replace carries the lock_version it read. `saved:<id>` resolves to the
  # stored span wherever the vocabulary is read. Every name is synthetic.
  #
  # group: :periods -- a create takes the transaction advisory lock that
  # counts the stored periods (`Portfolixir.LockTable` row 31), and a
  # sandboxed test never commits: two modules creating at once would wait
  # on each other's lock until the test ended. Every module that creates a
  # period joins this group.
  use Portfolixir.DataCase, async: true, group: :periods

  alias Portfolixir.Actor
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Journal
  alias Portfolixir.Periods
  alias Portfolixir.Periods.SavedPeriod

  defp agent, do: Actor.api_token_rw("mcp")

  defp entries, do: Journal.list_entries(resource_type: "period", order: :asc)

  defp create!(name, from \\ "2025-03-01", to \\ nil) do
    {:ok, period} =
      Periods.create_saved(Actor.owner_ui(), %{"name" => name, "from" => from, "to" => to})

    period
  end

  defp errors(%Ecto.Changeset{} = changeset), do: Keyword.keys(changeset.errors)

  # User story:
  # As the operator, or the agent I run,
  # I want to store a period of my own under a name, open-ended or fixed,
  # so that „Seit Umschichtung“ is one choice on every device and every
  # widget, and the journal says who made it.
  #
  # Acceptance criteria:
  # - A create stores the name (trimmed), from, and to or nothing (until
  #   today), lock_version 1; one journal entry, a create under the actor.
  # - `saved:<id>` resolves to {:range, from, to}, an open one to today.
  # - The list reads in the order the periods were made.
  # - A key the create does not take is refused, and nothing is written.
  test "a create is stored, journaled under its actor and resolved by reference" do
    assert {:ok, %SavedPeriod{} = open} =
             Periods.create_saved(agent(), %{
               "name" => " Seit Umschichtung ",
               "from" => "2025-03-01"
             })

    assert open.name == "Seit Umschichtung"
    assert open.from == ~D[2025-03-01]
    assert open.to == nil
    assert open.lock_version == 1

    assert [entry] = entries()
    assert entry.operation == :create
    assert entry.actor_type == :api_token_rw
    assert entry.actor_label == "mcp"
    assert entry.resource_id == to_string(open.id)
    assert entry.after["name"] == "Seit Umschichtung"

    fixed = create!("Sommer 2026", "2026-06-01", "2026-08-31")
    assert fixed.to == ~D[2026-08-31]

    today = ~D[2026-11-25]
    assert Periods.resolve("saved:#{open.id}", today) == {:ok, {:range, ~D[2025-03-01], today}}

    assert Periods.resolve("saved:#{fixed.id}", today) ==
             {:ok, {:range, ~D[2026-06-01], ~D[2026-08-31]}}

    assert Periods.key?("saved:#{fixed.id}")
    assert Enum.map(Periods.list_saved(), & &1.id) == [open.id, fixed.id]

    assert {:error, {:unknown_fields, %{"lock_version" => [_]}}} =
             Periods.create_saved(agent(), %{
               "name" => "X",
               "from" => "2025-01-01",
               "lock_version" => 1
             })

    assert length(entries()) == 2
  end

  # User story:
  # As the operator,
  # I want a name or a span that cannot be a period refused with its reason,
  # so that nothing unreadable is stored and the menu never breaks.
  #
  # Acceptance criteria (each seen refused first):
  # - an empty name, and one of spaces only; a 41-character name (40 are
  #   taken); a control character (a line feed, a NUL, a bell);
  # - `from` after `to`; a missing or malformed `from`; a malformed `to`;
  #   a `from` after today (a period not yet begun);
  # - nothing is written and nothing journaled.
  test "an empty or 41-character name, a control character and from after to are refused" do
    for name <- ["", "   ", String.duplicate("x", 41), "Zwei\nZeilen", "Nul\u0000", "Bell\u0007"] do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Periods.create_saved(agent(), %{"name" => name, "from" => "2025-01-01"}),
             inspect(name)

      assert :name in errors(changeset), inspect(name)
    end

    assert {:ok, %SavedPeriod{name: forty}} =
             Periods.create_saved(agent(), %{
               "name" => String.duplicate("y", 40),
               "from" => "2025-01-01"
             })

    assert String.length(forty) == 40

    assert {:error, changeset} =
             Periods.create_saved(agent(), %{
               "name" => "Rückwärts",
               "from" => "2026-05-02",
               "to" => "2026-05-01"
             })

    assert :to in errors(changeset)

    for {attrs, field} <- [
          {%{"name" => "Ohne Anfang"}, :from},
          {%{"name" => "Kein Datum", "from" => "gestern"}, :from},
          {%{"name" => "Kein Ende", "from" => "2025-01-01", "to" => "morgen"}, :to},
          {%{
             "name" => "Später",
             "from" => Date.to_iso8601(Date.add(Portfolixir.Clock.today(), 1))
           }, :from}
        ] do
      assert {:error, changeset} = Periods.create_saved(agent(), attrs), inspect(attrs)
      assert field in errors(changeset), inspect(attrs)
    end

    assert [%{name: ^forty}] = Periods.list_saved()
    assert length(entries()) == 1
  end

  # User story:
  # As the operator,
  # I want at most 50 periods stored,
  # so that a runaway agent cannot fill the menu without end.
  #
  # Acceptance criteria:
  # - The 50th create is stored; the 51st is refused and writes nothing.
  test "a 51st period is refused" do
    for n <- 1..50, do: create!("Synthetic #{n}")
    assert Periods.max_saved() == 50

    assert Periods.create_saved(agent(), %{"name" => "Synthetic 51", "from" => "2025-01-01"}) ==
             {:error, :too_many_periods}

    assert length(Periods.list_saved()) == 50
    assert length(entries()) == 50
  end

  # User story:
  # As the operator changing a period my agent changes at the same time,
  # I want the change built on an older read refused with the period as
  # stored,
  # so that neither change is lost unseen.
  #
  # Acceptance criteria:
  # - A replace takes exactly name, from, to (null: until today) and the
  #   lock_version read; it raises lock_version by one and is journaled
  #   as an update with its before-image.
  # - A stale lock_version answers {:error, :stale, stored}, writing
  #   nothing; an unknown id {:error, :not_found}.
  # - `saved:<id>` follows the change.
  test "a replace carries its lock_version, a stale one is refused" do
    period = create!("Seit Umschichtung")

    assert {:ok, replaced} =
             Periods.replace_saved(agent(), period.id, %{
               "name" => "Seit Umschichtung",
               "from" => "2025-04-01",
               "to" => "2025-12-31",
               "lock_version" => 1
             })

    assert replaced.lock_version == 2
    assert replaced.from == ~D[2025-04-01]

    assert Periods.resolve("saved:#{period.id}", ~D[2026-11-25]) ==
             {:ok, {:range, ~D[2025-04-01], ~D[2025-12-31]}}

    assert [_create, update] = entries()
    assert update.operation == :update
    assert update.before["from"] == "2025-03-01"
    assert update.after["to"] == "2025-12-31"

    assert {:error, :stale, %SavedPeriod{lock_version: 2}} =
             Periods.replace_saved(Actor.owner_ui(), period.id, %{
               "name" => "Älter",
               "from" => "2025-01-01",
               "to" => nil,
               "lock_version" => 1
             })

    assert Periods.get_saved(period.id).name == "Seit Umschichtung"

    assert {:error, {:missing_fields, %{"lock_version" => _}}} =
             Periods.replace_saved(agent(), period.id, %{
               "name" => "X",
               "from" => "2025-01-01",
               "to" => nil
             })

    assert {:error, :not_found} =
             Periods.replace_saved(agent(), period.id + 1000, %{
               "name" => "X",
               "from" => "2025-01-01",
               "to" => nil,
               "lock_version" => 1
             })

    assert length(entries()) == 2
  end

  # User story:
  # As the operator,
  # I want a period I no longer need deleted, and every reference to it
  # to stop resolving,
  # so that a widget pinned to it falls back instead of reading a ghost.
  #
  # Acceptance criteria:
  # - A delete removes the row, journaled as a delete with its
  #   before-image; `saved:<id>` then answers {:error, :not_found}.
  # - A period's write moves no derived value: its blast radius is :none.
  test "a delete is journaled and the reference stops resolving" do
    period = create!("Sommer 2026", "2026-06-01", "2026-08-31")
    key = "saved:#{period.id}"
    assert {:ok, _span} = Periods.resolve(key, ~D[2026-11-25])

    assert {:ok, %SavedPeriod{}} = Periods.delete_saved(agent(), period.id)
    assert Periods.get_saved(period.id) == nil
    assert Periods.resolve(key, ~D[2026-11-25]) == {:error, :not_found}
    assert Periods.delete_saved(agent(), period.id) == {:error, :not_found}

    assert [_create, delete] = entries()
    assert delete.operation == :delete
    assert delete.before["name"] == "Sommer 2026"

    assert BlastRadius.for_write("period", period) == :none
  end

  # Attack: an id is a whole number in the bigint range, matched by form;
  # anything else is no key and reads nothing.
  test "a saved key that is no id is refused without a read" do
    for key <- ~w(saved: saved:0 saved:-1 saved:01 saved:1x saved:99999999999999999999 SAVED:1) do
      refute Periods.key?(key), key
      assert Periods.resolve(key, ~D[2026-11-25]) == {:error, :unknown_period}, key
    end

    assert Periods.resolve("saved:9223372036854775807", ~D[2026-11-25]) == {:error, :not_found}
  end
end
