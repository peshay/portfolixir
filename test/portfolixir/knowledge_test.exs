defmodule Portfolixir.KnowledgeTest do
  # ADR-0044 §§1–5 (issue #748): the security research log as an append-only
  # table, and the four reads §7 names as the acceptance criteria. Risk-tier
  # attention label (ADR-0036): an agent write path and an append-only
  # invariant — the database half of that invariant is pinned in
  # test/portfolixir/journal/append_only_test.exs (unboxed, real commits).
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.WorldFixtures

  defp owner, do: Actor.owner_ui()

  defp security!(opts \\ []) do
    WorldFixtures.create_security!(
      Keyword.merge([name: "Knowledge Co.", ticker: "KNOW", asset_class: "equity"], opts)
    )
  end

  defp append!(security, attrs) do
    base = %{
      security_id: security.id,
      author: "agent",
      kind: "evidence",
      body: "a dated finding",
      source_quality: "primary",
      as_of: ~D[2026-08-01]
    }

    {:ok, note} = Knowledge.append_note(owner(), Map.merge(base, attrs))
    note
  end

  # User story (ADR-0044 §§1–2, §5):
  # As the operating agent recording what I learned about a security,
  # I want to append a dated, sourced, typed entry to that security's research
  # log,
  # so that the next run starts from a record instead of from nothing — and
  # the write is attributed in the audit journal like every other write.
  #
  # Acceptance criteria:
  # - The entry stores kind, body, source URL, source quality, `as_of`
  #   (distinct from the write time), author and the machine_generated marker.
  # - kind, source_quality and author are closed sets: an unknown value is a
  #   changeset error, never a new atom.
  # - The write is journaled as `security_note` / create under the actor.
  describe "append_note/2" do
    test "stores a typed, dated, sourced entry and journals the write" do
      security = security!()
      actor = Actor.api_token_rw("agent-token")

      assert {:ok, %SecurityNote{} = note} =
               Knowledge.append_note(actor, %{
                 security_id: security.id,
                 author: "agent",
                 kind: "evidence",
                 body: "Q2 report: margin guidance confirmed.",
                 source_url: "https://example.invalid/ir/q2",
                 source_quality: "primary",
                 as_of: ~D[2026-07-31]
               })

      assert note.kind == :evidence
      assert note.author == :agent
      assert note.source_quality == :primary
      assert note.as_of == ~D[2026-07-31]
      assert note.machine_generated == false
      assert %NaiveDateTime{} = note.inserted_at

      assert [entry] = Journal.list_entries(resource_type: "security_note")
      assert entry.operation == :create
      assert entry.actor_type == :api_token_rw
      assert entry.actor_label == "agent-token"
      assert entry.resource_id == to_string(note.id)
      assert entry.after["kind"] == "evidence"
    end

    test "rejects values outside the closed sets without minting atoms" do
      security = security!()

      assert {:error, changeset} =
               Knowledge.append_note(owner(), %{
                 security_id: security.id,
                 author: "someone_else_entirely_zz",
                 kind: "rumour_zz",
                 body: "x",
                 source_quality: "gut_feeling_zz",
                 as_of: ~D[2026-08-01]
               })

      errors = errors_on(changeset)
      assert errors.kind == ["is invalid"]
      assert errors.source_quality == ["is invalid"]
      assert errors.author == ["is invalid"]

      # The rejected strings never became atoms.
      for value <- ~w(rumour_zz gut_feeling_zz someone_else_entirely_zz) do
        assert_raise ArgumentError, fn -> String.to_existing_atom(value) end
      end
    end

    test "source_quality and as_of are set, not guessed" do
      security = security!()

      assert {:error, changeset} =
               Knowledge.append_note(owner(), %{
                 security_id: security.id,
                 author: "agent",
                 kind: "evidence",
                 body: "undated, unrated"
               })

      errors = errors_on(changeset)
      assert "can't be blank" in errors.source_quality
      assert "can't be blank" in errors.as_of
    end

    # ADR-0044 §4: an extracted entry is a proposal carrying its source.
    test "a machine-generated entry must carry its source link" do
      security = security!()

      assert {:error, changeset} =
               Knowledge.append_note(owner(), %{
                 security_id: security.id,
                 author: "local_model",
                 machine_generated: true,
                 kind: "evidence",
                 body: "extracted from a filing",
                 source_quality: "unverified",
                 as_of: ~D[2026-08-01]
               })

      assert errors_on(changeset).source_url == ["is required for a machine-generated entry"]
    end
  end

  # User story (ADR-0044 §3 — the load-bearing clause):
  # As the operating agent who found a premise refuted on the primary source,
  # I want to withdraw the earlier finding by appending a retraction that
  # supersedes it and carries the reason,
  # so that both stay readable and the next run sees the retraction first —
  # the fourth investigation of a settled premise never happens.
  #
  # Acceptance criteria:
  # - A retraction must supersede an earlier entry of the same security.
  # - The superseded entry stays in the list, marked with what superseded it.
  # - Nothing in the context updates or deletes an entry.
  describe "supersession and retraction" do
    test "a retraction supersedes an earlier entry; both stay readable" do
      security = security!()
      finding = append!(security, %{body: "supplier dispute will hit Q3", as_of: ~D[2026-07-10]})

      retraction =
        append!(security, %{
          kind: "retraction",
          body: "Checked the 10-Q on 2026-08-02: no dispute disclosed. Withdrawn.",
          supersedes_id: finding.id,
          as_of: ~D[2026-08-02]
        })

      [newest, oldest] = Knowledge.list_notes(security.id)
      assert newest.id == retraction.id
      assert oldest.id == finding.id
      assert oldest.superseded_by_ids == [retraction.id]
      assert newest.superseded_by_ids == []
    end

    test "a retraction without a superseded entry is rejected" do
      security = security!()

      assert {:error, changeset} =
               Knowledge.append_note(owner(), %{
                 security_id: security.id,
                 author: "agent",
                 kind: "retraction",
                 body: "withdrawn",
                 source_quality: "primary",
                 as_of: ~D[2026-08-02]
               })

      assert errors_on(changeset).supersedes_id == ["a retraction must supersede an entry"]
    end

    test "an entry cannot supersede an entry of another security" do
      security = security!()
      other = security!(name: "Other Co.", ticker: "OTHR")
      foreign = append!(other, %{})

      assert {:error, changeset} =
               Knowledge.append_note(owner(), %{
                 security_id: security.id,
                 author: "agent",
                 kind: "evidence",
                 body: "replaces something it may not",
                 source_quality: "primary",
                 as_of: ~D[2026-08-02],
                 supersedes_id: foreign.id
               })

      assert errors_on(changeset).supersedes_id == [
               "must reference an entry of the same security"
             ]
    end

    test "the context exposes no update and no delete" do
      refute function_exported?(Knowledge, :update_note, 3)
      refute function_exported?(Knowledge, :delete_note, 2)
    end
  end

  # User story (ADR-0044 §7 — the four reads are the acceptance criteria):
  # As the operating agent starting a research run,
  # I want the log of one security newest first, the held positions with no
  # entry for N days, the entries that still need corroboration, and the
  # dated blocks expiring within N days,
  # so that review hygiene is a query, not a re-read of old conversations.
  #
  # Acceptance criteria:
  # - list_notes/1 orders by as_of, then write time, newest first.
  # - unreviewed_positions/1 lists held securities whose newest entry is
  #   older than N days (or absent); a security with a fresh entry is not
  #   listed; a security that is not held is not listed.
  # - uncorroborated_notes/1 lists entries whose source_quality is not
  #   primary, skipping superseded ones.
  # - expiring_notes/1 lists entries whose valid_until falls in [today,
  #   today + N days], skipping superseded ones and past blocks.
  describe "the four reads" do
    test "list_notes/1 is newest first by as_of, then write time" do
      security = security!()
      older = append!(security, %{as_of: ~D[2026-06-01]})
      newest = append!(security, %{as_of: ~D[2026-08-01]})
      middle = append!(security, %{as_of: ~D[2026-07-01]})

      assert Enum.map(Knowledge.list_notes(security.id), & &1.id) == [
               newest.id,
               middle.id,
               older.id
             ]
    end

    test "unreviewed_positions/1 names held securities without a recent entry" do
      world = WorldFixtures.base_world()
      stale = security!(name: "Stale Co.", ticker: "STAL")
      fresh = security!(name: "Fresh Co.", ticker: "FRSH")
      never = security!(name: "Never Co.", ticker: "NEVR")
      unheld = security!(name: "Unheld Co.", ticker: "UNHD")

      for s <- [stale, fresh, never], do: WorldFixtures.buy!(world, s, quantity: "1", price: "10")
      today = ~D[2026-09-03]

      append!(stale, %{as_of: Date.add(today, -120)})
      append!(fresh, %{as_of: Date.add(today, -10)})
      append!(unheld, %{as_of: Date.add(today, -400)})

      rows = Knowledge.unreviewed_positions(days: 90, today: today)

      assert Enum.map(rows, & &1.security.id) |> Enum.sort() == Enum.sort([stale.id, never.id])

      stale_row = Enum.find(rows, &(&1.security.id == stale.id))
      assert stale_row.last_entry_as_of == Date.add(today, -120)
      assert stale_row.days_since_last_entry == 120

      never_row = Enum.find(rows, &(&1.security.id == never.id))
      assert never_row.last_entry_as_of == nil
      assert never_row.days_since_last_entry == nil
    end

    test "uncorroborated_notes/1 lists non-primary entries that are not superseded" do
      security = security!()
      primary = append!(security, %{source_quality: "primary"})
      rumour = append!(security, %{source_quality: "awareness", body: "heard at a conference"})

      superseded =
        append!(security, %{
          source_quality: "unverified",
          body: "later confirmed",
          as_of: ~D[2026-07-01]
        })

      _confirmation =
        append!(security, %{
          source_quality: "primary",
          body: "confirmed on the filing",
          supersedes_id: superseded.id,
          as_of: ~D[2026-08-05]
        })

      ids = Knowledge.uncorroborated_notes() |> Enum.map(& &1.id)
      assert rumour.id in ids
      refute primary.id in ids
      refute superseded.id in ids

      assert Knowledge.uncorroborated_notes(include_superseded: true)
             |> Enum.map(& &1.id)
             |> Enum.member?(superseded.id)
    end

    test "expiring_notes/1 lists dated blocks ending within the window" do
      security = security!()
      today = ~D[2026-09-03]

      soon =
        append!(security, %{
          kind: "decision",
          body: "buying block",
          valid_until: Date.add(today, 5)
        })

      _later =
        append!(security, %{kind: "decision", body: "lockup", valid_until: Date.add(today, 40)})

      _past =
        append!(security, %{kind: "decision", body: "expired", valid_until: Date.add(today, -1)})

      lifted =
        append!(security, %{
          kind: "decision",
          body: "lifted later",
          valid_until: Date.add(today, 3)
        })

      _lift =
        append!(security, %{kind: "decision", body: "block lifted", supersedes_id: lifted.id})

      rows = Knowledge.expiring_notes(days: 7, today: today)
      assert Enum.map(rows, & &1.id) == [soon.id]
      assert hd(rows).days_until_expiry == 5
    end
  end

  # Review round: the closed-set resolution accepts atoms and strings, skips
  # blanks (validate_required speaks), and rejects everything else; the
  # thesis-only fields are refused on other kinds; get_note/1 and the
  # security_id narrowing of the corroboration read.
  describe "input shapes" do
    test "closed sets accept atoms, skip blanks, reject other types" do
      security = security!()

      assert {:ok, note} =
               Knowledge.append_note(owner(), %{
                 security_id: security.id,
                 author: :operator,
                 kind: :thesis,
                 body: "  trimmed thesis  ",
                 source_quality: :primary,
                 conviction: :low,
                 source_url: "   ",
                 as_of: ~D[2026-08-01]
               })

      assert note.author == :operator and note.kind == :thesis and note.conviction == :low
      assert note.body == "trimmed thesis"
      assert note.source_url == nil
      assert Knowledge.get_note(note.id).id == note.id

      assert {:error, changeset} =
               Knowledge.append_note(owner(), %{
                 security_id: security.id,
                 author: :nobody,
                 kind: 42,
                 body: "x",
                 source_quality: "",
                 as_of: ~D[2026-08-01]
               })

      errors = errors_on(changeset)
      assert errors.author == ["is invalid"]
      assert errors.kind == ["is invalid"]
      assert "can't be blank" in errors.source_quality

      assert SecurityNote.authors() == ~w(operator agent local_model)
      assert SecurityNote.convictions() == ~w(low medium high)
    end

    test "thesis-only fields are refused on other kinds" do
      security = security!()

      assert {:error, changeset} =
               Knowledge.append_note(owner(), %{
                 security_id: security.id,
                 author: "agent",
                 kind: "evidence",
                 body: "x",
                 source_quality: "primary",
                 as_of: ~D[2026-08-01],
                 conviction: "high",
                 time_stop: ~D[2027-01-01]
               })

      assert errors_on(changeset).conviction == ["is only recorded on a thesis entry"]
      assert errors_on(changeset).time_stop == ["is only recorded on a thesis entry"]
    end

    test "uncorroborated_notes/1 narrows to one security" do
      a = security!(name: "A Co.", ticker: "AAA")
      b = security!(name: "B Co.", ticker: "BBB")
      append!(a, %{source_quality: "awareness"})
      append!(b, %{source_quality: "awareness"})

      assert Knowledge.uncorroborated_notes(security_id: a.id) |> Enum.map(& &1.security_id) ==
               [a.id]
    end

    test "source_url must be an http(s) URL — a script or data scheme is refused" do
      security = security!()

      for bad <- ["javascript:alert(1)", "data:text/html,x", "ftp://x", "not a url"] do
        assert {:error, changeset} =
                 Knowledge.append_note(owner(), %{
                   security_id: security.id,
                   author: "agent",
                   kind: "evidence",
                   body: "x",
                   source_quality: "primary",
                   as_of: ~D[2026-08-01],
                   source_url: bad
                 })

        assert errors_on(changeset).source_url == ["must be an http(s) URL"], bad
      end

      assert {:ok, _} =
               Knowledge.append_note(owner(), %{
                 security_id: security.id,
                 author: "agent",
                 kind: "evidence",
                 body: "x",
                 source_quality: "primary",
                 as_of: ~D[2026-08-01],
                 source_url: "HTTPS://example.invalid/ir?q=1"
               })
    end
  end
end
