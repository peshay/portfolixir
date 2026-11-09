defmodule Portfolixir.News.SourcesTest do
  # ADR-0056 §3 and B5 (Sprint 27, N5): the tier table and the tier an item
  # is stored with. Synthetic domains only, every rated one this module's
  # own (`*.sources-test.example.*`): a domain two async modules rate holds
  # the unique index under one's uncommitted row and blocks the other
  # (Sprint 28, #1424's likely flake).
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.News.Source
  alias Portfolixir.News.Sources
  alias Portfolixir.Repo

  @agent Actor.api_token_rw("synthetic-agent")
  @seeder Actor.system_job("synthetic-seed")

  describe "tier_for/2 (§3, B5)" do
    # User story (ADR-0056 §3, B5):
    # As the operator and the agent who read a story's tier,
    # I want an item's tier to come from the source table, with `primary`
    # given only by construction to an issuer's or a regulator's own feed,
    # so that no claim inside an item, and no domain an aggregator names,
    # makes its item primary.
    #
    # Acceptance criteria:
    # - An unknown domain reads `awareness`.
    # - An `issuer` or `regulatory` item is `primary` whatever its domain's
    #   row says, unless the domain is `blocked`, which drops it.
    # - An `aggregator` or `thematic` item takes its domain's tier, capped
    #   at `secondary`: a domain rated `primary` gives `secondary`.
    # - A `blocked` domain answers `blocked` for every class.
    # - A domain's row covers its subdomains unless a subdomain has a row
    #   of its own; `www.` and case do not matter.
    test "an unknown domain is awareness, and primary comes only by construction" do
      assert Sources.tier_for("unrated.example.com", :aggregator) == :awareness
      assert Sources.tier_for("unrated.example.com", :thematic) == :awareness
      assert Sources.tier_for("unrated.example.com", :issuer) == :primary
      assert Sources.tier_for("unrated.example.com", :regulatory) == :primary

      {:ok, _} = Sources.put_source(@agent, "wire.sources-test.example.com", :primary)
      {:ok, _} = Sources.put_source(@agent, "daily.sources-test.example.com", :secondary)
      {:ok, _} = Sources.put_source(@agent, "chatter.sources-test.example.com", :awareness)

      # B5: an aggregator item naming a primary domain reads secondary.
      assert Sources.tier_for("wire.sources-test.example.com", :aggregator) == :secondary
      assert Sources.tier_for("wire.sources-test.example.com", :thematic) == :secondary
      assert Sources.tier_for("daily.sources-test.example.com", :aggregator) == :secondary
      assert Sources.tier_for("chatter.sources-test.example.com", :aggregator) == :awareness
      assert Sources.tier_for("chatter.sources-test.example.com", :issuer) == :primary
      assert Sources.tier_for("daily.sources-test.example.com", :regulatory) == :primary
    end

    test "a blocked domain is blocked for every class, its subdomains with it" do
      {:ok, _} = Sources.put_source(@agent, "spam.sources-test.example.net", :blocked)

      for class <- [:issuer, :regulatory, :aggregator, :thematic] do
        assert Sources.tier_for("spam.sources-test.example.net", class) == :blocked,
               inspect(class)

        assert Sources.tier_for("deep.cdn.spam.sources-test.example.net", class) == :blocked
      end

      assert Sources.blocked?("spam.sources-test.example.net")
      assert Sources.blocked?("WWW.Spam.Sources-Test.Example.Net.")
      assert Sources.blocked?("x.spam.sources-test.example.net")
      refute Sources.blocked?("notspam.sources-test.example.net")
      refute Sources.blocked?("example.net")
      refute Sources.blocked?("unrated.example.org")
    end

    test "a subdomain's own row wins over its parent's; www and case do not matter" do
      {:ok, _} = Sources.put_source(@agent, "daily.sources-test.example.com", :secondary)
      {:ok, _} = Sources.put_source(@agent, "blog.daily.sources-test.example.com", :awareness)

      assert Sources.tier_for("www.daily.sources-test.example.com", :aggregator) == :secondary
      assert Sources.tier_for("Markets.Daily.Sources-Test.Example.COM", :aggregator) == :secondary
      assert Sources.tier_for("blog.daily.sources-test.example.com", :aggregator) == :awareness
      assert Sources.tier_for("a.blog.daily.sources-test.example.com", :aggregator) == :awareness

      assert Sources.lookup([
               "markets.daily.sources-test.example.com",
               "blog.daily.sources-test.example.com",
               "x.example"
             ]) ==
               %{
                 "markets.daily.sources-test.example.com" => :secondary,
                 "blog.daily.sources-test.example.com" => :awareness
               }
    end

    test "tier/2 is the same rule without the table" do
      assert Sources.tier(:issuer, nil) == :primary
      assert Sources.tier(:aggregator, nil) == :awareness
      assert Sources.tier(:aggregator, :primary) == :secondary
      assert Sources.tier(:thematic, :primary) == :secondary
      assert Sources.tier(:regulatory, :awareness) == :primary
      assert Sources.tier(:issuer, :blocked) == :blocked
      assert Sources.tier(:aggregator, :blocked) == :blocked
    end
  end

  describe "put_source/4 (§3, B7)" do
    # User story (ADR-0056 §3, B7; ADR-0044 §2's invariant):
    # As the operator or the agent correcting a source's tier by hand,
    # I want my correction kept when a seed later rates the same domain,
    # and every write journaled with who made it,
    # so that a seed never silently undoes a judgement, and a tier change
    # can be traced to its writer.
    #
    # Acceptance criteria:
    # - The domain is stored normalized: trimmed, lower-case, without a
    #   trailing dot or a leading `www.`.
    # - A hand write overwrites a seed's row and a hand row; a seed write
    #   overwrites a seed's row, and leaves a hand row as it is and
    #   journals nothing (`{:kept, row}`).
    # - Every write is one journal entry under its actor, `news_source`,
    #   with the before and after images; an unchanged write records none.
    # - A tier outside the four or a malformed domain is a changeset error.
    test "a hand correction is never overwritten by a later seed" do
      {:ok, seeded} =
        Sources.put_source(@seeder, "Wire.Sources-Test.Example.com", :secondary, set_by: :seed)

      assert %Source{domain: "wire.sources-test.example.com", tier: :secondary, set_by: :seed} =
               seeded

      {:ok, reseeded} =
        Sources.put_source(@seeder, "wire.sources-test.example.com", :awareness, set_by: :seed)

      assert %Source{tier: :awareness, set_by: :seed, id: id} = reseeded
      assert id == seeded.id

      {:ok, corrected} =
        Sources.put_source(@agent, "www.wire.sources-test.example.com.", :primary)

      assert %Source{id: ^id, tier: :primary, set_by: :hand} = corrected

      assert {:kept, kept} =
               Sources.put_source(@seeder, "wire.sources-test.example.com", :blocked,
                 set_by: :seed
               )

      assert %Source{id: ^id, tier: :primary, set_by: :hand} = kept
      assert Repo.get!(Source, id).tier == :primary

      {:ok, recorrected} =
        Sources.put_source(@agent, "wire.sources-test.example.com", :blocked, set_by: :hand)

      assert %Source{tier: :blocked, set_by: :hand} = recorrected

      entries = Journal.list_entries(resource_type: "news_source", order: :asc)
      assert length(entries) == 4

      assert Enum.map(entries, &{&1.actor_type, &1.actor_label, &1.operation}) == [
               {:system_job, "synthetic-seed", :upsert},
               {:system_job, "synthetic-seed", :upsert},
               {:api_token_rw, "synthetic-agent", :upsert},
               {:api_token_rw, "synthetic-agent", :upsert}
             ]

      assert Enum.all?(entries, &(&1.resource_id == to_string(id)))
      [first, second, third, fourth] = entries
      assert first.before == nil
      assert first.after["tier"] == "secondary"
      assert second.before["tier"] == "secondary" and second.after["tier"] == "awareness"
      assert third.after["set_by"] == "hand"
      assert fourth.before["tier"] == "primary" and fourth.after["tier"] == "blocked"
    end

    test "a write that changes nothing records nothing" do
      {:ok, source} = Sources.put_source(@agent, "daily.sources-test.example.com", :secondary)

      assert {:ok, ^source} =
               Sources.put_source(@agent, "daily.sources-test.example.com", :secondary)

      assert length(Journal.list_entries(resource_type: "news_source")) == 1
    end

    test "a bad tier or domain is a changeset error, and nothing is written" do
      assert {:error, changeset} =
               Sources.put_source(@agent, "daily.sources-test.example.com", :gold)

      assert %{tier: ["is invalid"]} = errors_on(changeset)

      assert {:error, changeset} = Sources.put_source(@agent, "https://x.example/a", :secondary)
      assert %{domain: [_message]} = errors_on(changeset)

      assert {:error, changeset} = Sources.put_source(@agent, "bücher.example", :secondary)
      assert %{domain: [_message]} = errors_on(changeset)

      assert Repo.aggregate(Source, :count) == 0
      assert Journal.list_entries(resource_type: "news_source") == []
    end
  end

  describe "normalize_domain/1" do
    test "trims, lower-cases, drops a trailing dot and one leading www." do
      assert Sources.normalize_domain("  WWW.Example.COM. ") == "example.com"
      assert Sources.normalize_domain("www.www.example.com") == "www.example.com"
      assert Sources.normalize_domain("www") == "www"
      assert Sources.normalize_domain("news.example.com") == "news.example.com"
      # An international name stays as received, lower-cased: the table stores
      # punycode only, so it matches no row and reads `awareness`.
      assert Sources.normalize_domain("Bücher.example") == "bücher.example"
      assert Sources.tier_for("Bücher.example", :aggregator) == :awareness
    end
  end
end
