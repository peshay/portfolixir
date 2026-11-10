defmodule Portfolixir.News.NLensTest do
  # Sprint 28 plan D-8, Lane N's closing act (the correctness, edge-case and
  # security lenses on N4, N5 and the entry's headline): a story becomes
  # knowledge only by a confirmed write, and what it links stays its own
  # security's (ADR-0056 §8, §12; ADR-0044's amendment of 2026-11-06).
  # Cases tagged `:n_lens_red` show a defect the lenses found and fail until
  # it is fixed. Synthetic names and hosts only, no socket.
  use Portfolixir.DataCase

  import Portfolixir.NewsFixtures, only: [feed!: 1, security!: 1, story!: 2]
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.News
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Reads
  alias Portfolixir.Repo

  @agent Actor.api_token_rw("synthetic-agent")

  defp watched!(name, token) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  defp aggregator_item!(title) do
    n = System.unique_integer([:positive])
    feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-lens-#{n}"})

    parsed = %Parsed{
      title: title,
      link: "https://search.example.com/r?u=lens-#{n}",
      source_domain: "wire.example.com"
    }

    {:ok, %{stored: 1}} = Ingest.ingest(feed, [parsed], DateTime.utc_now())
    Repo.get_by!(Item, canonical_url: parsed.link)
  end

  defp story_rows(security) do
    {:ok, page} =
      Reads.list({:security, security.id},
        since: nil,
        tier_min: nil,
        limit: 20,
        cursor: nil,
        as_of: Reads.as_of(),
        min_materiality: 0,
        prompt_version: nil
      )

    page.rows
  end

  # User story (ADR-0056 §8: the story becomes promoted and links the note;
  # §12: a promoted item is kept as the note's source):
  # As the operator's agent reading a security's stories,
  # I want a story to name only research notes of its own security,
  # so that „kept“ never claims another security's entry and the kept
  # story keeps the source its note was written from.
  #
  # Acceptance criteria:
  # - An aggregator story of Northwind promoted to a Northwind note, whose
  #   item is then assigned to Harbourline by hand: no Harbourline story
  #   names the Northwind note, and a Northwind story still names it.
  @tag :n_lens_red
  test "an item kept in a security's research log does not carry the note to another security" do
    northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
    harbourline = watched!("Harbourline Shipping AG", "Harbourline")
    item = aggregator_item!("Northwind Harbour wins a synthetic terminal contract")
    assert %Item{security_id: security_id, cluster_id: story_id} = Repo.get!(Item, item.id)
    assert security_id == northwind.id

    {:ok, note} =
      News.append_note_from_story(
        @agent,
        %{"security_id" => northwind.id, "author" => "agent", "body" => "Kept."},
        story_id
      )

    _assigned = News.assign_item(@agent, item.id, harbourline.id)

    refute Enum.any?(story_rows(harbourline), &(note.id in &1.note_ids))
    assert Enum.any?(story_rows(northwind), &(note.id in &1.note_ids))
  end

  # User story (ADR-0056 §8; the API answers a refusal as 422 naming the
  # field, never a server error):
  # As an agent sending a malformed kind beside a cluster_id,
  # I want the refusal to name `kind`,
  # so that I can correct the call.
  #
  # Acceptance criteria:
  # - A kind that is a JSON object answers `{:error, %{"kind" => _}}`.
  @tag :n_lens_red
  test "a kind that is not a string is refused naming kind, not raised" do
    security = security!("Object Kind Synthetic AG")
    story = story!(security, title: "Object Kind Synthetic AG reports")

    assert {:error, %{"kind" => [_ | _]}} =
             News.append_note_from_story(
               @agent,
               %{
                 "security_id" => security.id,
                 "author" => "agent",
                 "body" => "Kept.",
                 "kind" => %{"evidence" => true}
               },
               story.id
             )
  end

  # User story (ADR-0044's amendment: a headline is plain text on one
  # line; the chart draws it in a pin's title and tooltip):
  # As the operator reading a pin,
  # I want a headline to be one line,
  # so that a stored headline never breaks where I cannot see why.
  #
  # Acceptance criteria:
  # - A headline carrying Unicode's line separator (U+2028) or paragraph
  #   separator (U+2029) is refused naming `headline`.
  @tag :n_lens_red
  test "a headline with a Unicode line or paragraph separator is refused" do
    for separator <- [0x2028, 0x2029] do
      changeset =
        SecurityNote.changeset(
          %SecurityNote{},
          %{
            "security_id" => 1,
            "author" => "agent",
            "kind" => "evidence",
            "body" => "Kept.",
            "source_quality" => "primary",
            "as_of" => "2026-11-02",
            "headline" => "Synthetic first line" <> <<separator::utf8>> <> "second line"
          },
          ~D[2026-11-10]
        )

      assert Keyword.has_key?(changeset.errors, :headline)
    end
  end
end
