defmodule Portfolixir.News.N34AttackTest do
  # Sprint 28 plan D-8 (carry-forwards 1 and 5): the security and order
  # lens's attack on the digest's consumer cursor (N3) and news.assign (N4),
  # beyond the author's tests. Context level: the cursor's signature against
  # every edit of its two parts, a consumer recreated under its name, the
  # names, and the assignment's edges. Synthetic names and hosts only, no
  # socket.
  use Portfolixir.DataCase, async: true

  import Portfolixir.NewsFixtures, only: [feed!: 1, label!: 2]
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.News.DigestCursor
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Label
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo

  @key :crypto.strong_rand_bytes(32)
  @agent Actor.api_token_rw("synthetic-agent")
  @title "Northwind Harbour reports third quarter results"

  defp now, do: DateTime.utc_now()

  defp consumer!(name) do
    {:ok, consumer} = DigestCursor.consumer(name, nil, now(), @key)
    consumer
  end

  defp position(name), do: Repo.get_by!(DigestConsumer, name: name).position

  defp watched!(name, token) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  defp aggregator_item!(title, at \\ DateTime.utc_now()) do
    n = System.unique_integer([:positive])
    feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-#{n}"})
    link = "https://search.example.com/r?u=#{n}"
    item = struct!(Parsed, %{title: title, link: link, source_domain: "wire.example.com"})
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], at)
    Repo.get_by!(Item, canonical_url: link)
  end

  defp reload(item), do: Repo.get!(Item, item.id)

  defp days_ago(days), do: DateTime.add(now(), -days * 86_400, :second)

  defp entries, do: Journal.list_entries(resource_type: "news_item", order: :asc)

  describe "the cursor's signature (N3, security lens)" do
    # User story (ADR-0056 §9; plan D-8 carry-forward 1):
    # As the operator whose agents read the digest under their own names,
    # I want a cursor to confirm only the position the server signed for
    # that one consumer row,
    # so that no client skips stories by editing, forging or borrowing a
    # cursor, and a consumer removed and named again starts clean.
    #
    # Acceptance criteria:
    # - Every edit of the seconds (leading zero or plus, negative, huge,
    #   non-numeric, an extra separator) and of the tag (whitespace, a
    #   lookalike, padding, case) is refused, and the position stays.
    # - A cursor confirmed twice moves the position once.
    # - A consumer deleted and created again under the same name refuses
    #   the cursors issued to the old row.
    test "every edit of a cursor is refused and moves nothing" do
      consumer = consumer!("attack-run")
      start = position("attack-run")
      at = DateTime.add(now(), -60, :second)
      cursor = DigestCursor.issue(consumer, at, @key)
      [seconds, tag] = String.split(cursor, "~")
      unix = String.to_integer(seconds)

      forgeries = [
        "0" <> seconds <> "~" <> tag,
        "+" <> seconds <> "~" <> tag,
        "-" <> seconds <> "~" <> tag,
        Integer.to_string(unix + 86_400 * 365 * 100) <> "~" <> tag,
        String.duplicate("9", 40) <> "~" <> tag,
        seconds <> ".0~" <> tag,
        "0x" <> Integer.to_string(unix, 16) <> "~" <> tag,
        seconds <> "~" <> tag <> "~" <> tag,
        seconds <> "~~" <> tag,
        "~" <> seconds <> "~" <> tag,
        seconds <> "~" <> tag <> " ",
        seconds <> "~ " <> tag,
        " " <> seconds <> "~" <> tag,
        seconds <> "~" <> tag <> "==",
        seconds <> "~" <> String.upcase(tag),
        seconds <> "~" <> String.replace(tag, "A", "\u0410"),
        seconds <> "~" <> tag <> "\u200B",
        seconds <> "~" <> binary_part(tag, 0, byte_size(tag) - 1),
        seconds <> "~",
        "~" <> tag,
        "",
        "~"
      ]

      for forged <- Enum.reject(forgeries, &(&1 == cursor)) do
        assert DigestCursor.consumer("attack-run", forged, now(), @key) == {:error, :not_issued},
               inspect(forged)
      end

      assert position("attack-run") == start

      # The genuine cursor, confirmed twice, moves the position once.
      assert {:ok, first} = DigestCursor.consumer("attack-run", cursor, now(), @key)
      assert {:ok, second} = DigestCursor.consumer("attack-run", cursor, now(), @key)
      assert first.position == second.position
      assert DateTime.to_unix(first.position) == unix
    end

    test "a cursor signed with another key, or for another consumer, is refused" do
      morning = consumer!("morning-run")
      _evening = consumer!("evening-run")
      at = DateTime.add(now(), -60, :second)

      other_key = :crypto.strong_rand_bytes(32)

      assert DigestCursor.consumer(
               "morning-run",
               DigestCursor.issue(morning, at, other_key),
               now(),
               @key
             ) ==
               {:error, :not_issued}

      assert DigestCursor.consumer(
               "evening-run",
               DigestCursor.issue(morning, at, @key),
               now(),
               @key
             ) ==
               {:error, :not_issued}
    end

    test "a consumer deleted and created again under its name refuses the old row's cursors" do
      old = consumer!("recreated-run")
      cursor = DigestCursor.issue(old, DateTime.add(now(), -60, :second), @key)

      Repo.delete!(old)
      new = consumer!("recreated-run")
      assert new.id != old.id

      assert DigestCursor.consumer("recreated-run", cursor, now(), @key) == {:error, :not_issued}
    end

    test "a cursor cannot name a position ahead of the one the server signed" do
      consumer = consumer!("ahead-run")
      signed = DigestCursor.issue(consumer, DateTime.add(now(), -60, :second), @key)
      [_seconds, tag] = String.split(signed, "~")
      ahead = Integer.to_string(DateTime.to_unix(now()) + 3600)

      assert DigestCursor.consumer("ahead-run", ahead <> "~" <> tag, now(), @key) ==
               {:error, :not_issued}

      assert DateTime.compare(position("ahead-run"), now()) == :lt
    end
  end

  describe "consumer names (N3)" do
    # User story (ADR-0056 §9):
    # As the operator reading the consumers my agents created,
    # I want a name to be one plain identifier, with no lookalike or
    # invisible character making two consumers look like one,
    # so that a position is never confirmed under a name that reads like
    # another.
    #
    # Acceptance criteria:
    # - Names that differ only in case are two consumers (the database
    #   compares bytes), each with its own cursor.
    # - A Cyrillic lookalike, a full-width letter, a trailing newline, and
    #   a name of 65 characters are no consumer's name; 64 is.
    test "case variants are two consumers; lookalikes and invisible characters are no name" do
      upper = consumer!("Agent")
      lower = consumer!("agent")
      assert upper.id != lower.id

      cursor = DigestCursor.issue(upper, DateTime.add(now(), -60, :second), @key)
      assert DigestCursor.consumer("agent", cursor, now(), @key) == {:error, :not_issued}

      for name <- [
            "\u0430gent",
            "\uFF41gent",
            "agent\n",
            "agent\u200B",
            "agent\u00A0",
            String.duplicate("a", 65)
          ] do
        refute DigestCursor.name?(name), inspect(name)
      end

      assert DigestCursor.name?(String.duplicate("a", 64))
    end
  end

  describe "news.assign's edges (N4)" do
    # User story (ADR-0056 §9; plan D-8 carry-forward 5):
    # As the operator whose agent works the remainder,
    # I want news.assign to write and journal only what changes, never to
    # move a story's label onto another event, and never to land an item
    # behind a consumer's confirmed position,
    # so that the journal records decisions, labels stay with their event,
    # and the digest's cursor stays at least once.
    #
    # Acceptance criteria:
    # - null on an item the matcher still leaves unassigned writes and
    #   journals nothing, and keeps its `scope_at`.
    # - An item leaving a labelled story leaves the label on the story the
    #   remaining member holds; the story it joins keeps its own.
    # - An old item assigned after a consumer confirmed a position enters
    #   its new scope after that position.
    # - Assigning to a retired security is refused or the item reads in a
    #   security no digest of the universe misses (here: characterised).
    test "null on a never-assigned item writes and journals nothing" do
      _northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
      item = aggregator_item!("A harbour somewhere reports results")
      assert %Item{assignment: :unassigned} = before = reload(item)

      assert {:ok, after_null} = News.assign_item(@agent, item.id, nil)
      assert after_null.assignment == :unassigned
      assert after_null.scope_at == before.scope_at
      assert after_null.updated_at == before.updated_at
      assert entries() == []
    end

    test "a labelled story keeps its label when one member leaves; the target keeps its own" do
      northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
      harbourline = watched!("Harbourline Shipping AG", "Harbourline")

      stays = aggregator_item!(@title)
      leaves = aggregator_item!(@title)
      source_story = reload(stays).cluster_id
      assert reload(leaves).cluster_id == source_story
      source_label = label!(source_story, materiality: 3)

      target_item = aggregator_item!("Harbourline reports third quarter results")
      target_story = reload(target_item).cluster_id
      target_label = label!(target_story, materiality: 1, model: "synthetic-model-2")

      assert {:ok, _moved} = News.assign_item(@agent, leaves.id, harbourline.id)

      assert reload(stays).cluster_id == source_story
      assert reload(stays).security_id == northwind.id
      assert Repo.get!(Label, source_label.id).cluster_id == source_story
      assert Repo.get!(Label, target_label.id).cluster_id == target_story
      assert Repo.get!(Cluster, source_story).security_id == northwind.id
    end

    test "an old item assigned after a consumer's confirmation enters its scope after it" do
      _northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
      harbourline = watched!("Harbourline Shipping AG", "Harbourline")
      item = aggregator_item!(@title, DateTime.add(now(), -3 * 3600, :second))

      consumer = consumer!("order-run")
      cursor = DigestCursor.issue(consumer, News.Reads.as_of(), @key)
      {:ok, confirmed} = DigestCursor.consumer("order-run", cursor, now(), @key)
      assert DateTime.compare(reload(item).scope_at, confirmed.position) == :lt

      {:ok, moved} = News.assign_item(@agent, item.id, harbourline.id)
      assert DateTime.compare(moved.scope_at, confirmed.position) == :gt
    end

    # User story (ADR-0056 C3, §9; closing act, AT8):
    # As the operator whose agent gives an ambiguous item back to the
    # matcher after a third security started naming it,
    # I want the item to enter the new candidate's remainder now,
    # so that a view holding that security reads it as new.
    #
    # Acceptance criteria:
    # - null on an item ambiguous between two securities, which a third
    #   now also names (first seen 8 days ago, outside the re-match's
    #   window), keeps it ambiguous with three candidates and stamps
    #   scope_at with the time of the write.
    test "null on an ambiguous item whose candidates change stamps scope_at anew" do
      _a = watched!("Northwind Harbour Logistics AG", "Northwind")
      _b = watched!("Harbourline Shipping AG", "Harbourline")
      item = aggregator_item!("Northwind and Harbourline at Quayside", days_ago(8))
      assert %Item{assignment: :ambiguous, candidates: [_, _]} = before = reload(item)

      _c = watched!("Quayside Terminals AG", "Quayside")
      assert reload(item).candidates == before.candidates

      assert {:ok, moved} = News.assign_item(@agent, item.id, nil)
      assert %Item{assignment: :ambiguous, candidates: [_, _, _]} = moved
      assert DateTime.diff(moved.scope_at, now(), :second) in -60..0
    end

    test "an item assigned to a retired security (characterised: accepted, out of the universe)" do
      _northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
      retired = create_security!(name: "Retired Harbour AG", ticker: nil, asset_class: "equity")
      {:ok, retired} = Catalog.update_security(Actor.owner_ui(), retired, %{is_retired: true})
      assert retired.is_retired
      item = aggregator_item!(@title)

      assert {:ok, moved} = News.assign_item(@agent, item.id, retired.id)
      assert moved.security_id == retired.id
      refute retired.id in Enum.map(News.Universe.members(), & &1.id)
    end
  end
end
