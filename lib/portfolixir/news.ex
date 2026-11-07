defmodule Portfolixir.News do
  @moduledoc """
  The news layer (ADR-0056): registered feeds fetched, their items matched
  to a security or a category by rule, deduplicated into stories, rated by
  a hand-kept source tier, and served compactly. No model runs here, and
  nothing stored is an article: excerpts are capped at 600 characters and
  items are kept 90 days (§12).

  The tables and their rules are `Portfolixir.News.Feed`,
  `Portfolixir.News.Source`, `Portfolixir.News.Item`,
  `Portfolixir.News.Cluster` and `Portfolixir.News.FeedDay` (where each
  rolling count of §6 is read from). Later stories of the sprint fill this
  context: the fetcher, the matcher, the clustering, retention and health,
  the reads and the writes.

  ## What a security merge does with news rows (ADR-0050 §9, §14)

  `reassign_security/3` moves every news row of a merge's source onto its
  target, inside the merge's transaction, before the source is deleted:

    * the source's feeds are re-bound to the target, one journaled update
      each (`resource_type: "news_feed"`; feeds are master data, B7);
    * its stories and items move without a journal entry (B7: a staging
      area written by a system job); a story carries its items' security
      with it (the items' composite key follows it);
    * an ambiguous item that listed the source lists the target instead;
      one that listed both now has one candidate, so it is `assigned` to
      the target, out of any story — exactly one hit assigns (§2).

  Stories of the source and the target that are one event stay two stories
  until the clustering runs over the target's items again.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Item
  alias Portfolixir.Repo

  @type moved :: %{
          feeds: [pos_integer()],
          stories: non_neg_integer(),
          items: non_neg_integer(),
          candidates: non_neg_integer()
        }

  @doc """
  Moves every news row of security `source_id` onto `target_id`, for a
  security merge holding both rows' locks. See the moduledoc.
  """
  @spec reassign_security(Actor.t(), pos_integer(), pos_integer()) ::
          {:ok, moved()}
          | {:error, :raced | {:write_refused, String.t(), integer(), Ecto.Changeset.t()}}
  def reassign_security(%Actor{} = actor, source_id, target_id)
      when is_integer(source_id) and is_integer(target_id) and source_id != target_id do
    feeds = Repo.all(from(f in Feed, where: f.security_id == ^source_id, order_by: f.id))

    with :ok <- reassign_feeds(actor, feeds, target_id) do
      # Counted first: a story's items follow it through their composite key,
      # so the items' own update below reaches only those outside a story.
      items = Repo.aggregate(from(i in Item, where: i.security_id == ^source_id), :count)

      {stories, _} =
        Repo.update_all(from(c in Cluster, where: c.security_id == ^source_id),
          set: [security_id: target_id, updated_at: now()]
        )

      Repo.update_all(from(i in Item, where: i.security_id == ^source_id),
        set: [security_id: target_id, updated_at: now()]
      )

      candidates = collapse_candidates(source_id, target_id)

      {:ok,
       %{feeds: Enum.map(feeds, & &1.id), stories: stories, items: items, candidates: candidates}}
    end
  end

  defp reassign_feeds(actor, feeds, target_id) do
    Enum.reduce_while(feeds, :ok, fn feed, :ok ->
      Multi.new()
      |> Multi.update(:feed, fn changes ->
        changes |> Journal.locked_row() |> Ecto.Changeset.change(security_id: target_id)
      end)
      |> Journal.record(actor,
        resource_type: "news_feed",
        operation: :update,
        source: :feed,
        before: feed
      )
      |> Repo.transaction()
      |> case do
        {:ok, _changes} ->
          {:cont, :ok}

        {:error, :feed, changeset, _changes} ->
          {:halt, {:error, {:write_refused, "news_feed", feed.id, changeset}}}

        {:error, _step, _reason, _changes} ->
          {:halt, {:error, :raced}}
      end
    end)
  end

  # §2: exactly one hit assigns. An item that listed both securities now has
  # one; any other lists the target where it listed the source.
  defp collapse_candidates(source_id, target_id) do
    {collapsed, _} =
      Repo.update_all(
        from(i in Item,
          where:
            i.assignment == :ambiguous and ^source_id in i.candidates and
              ^target_id in i.candidates and fragment("cardinality(?) = 2", i.candidates)
        ),
        set: [assignment: :assigned, security_id: target_id, candidates: [], updated_at: now()]
      )

    {listed, _} =
      Repo.update_all(
        from(i in Item,
          where: ^source_id in i.candidates,
          update: [
            set: [
              candidates:
                fragment(
                  "ARRAY(SELECT DISTINCT c FROM unnest(array_replace(?, ?, ?)) AS c ORDER BY c)",
                  i.candidates,
                  ^source_id,
                  ^target_id
                ),
              updated_at: ^now()
            ]
          ]
        ),
        []
      )

    collapsed + listed
  end

  defp now, do: DateTime.utc_now()
end
