defmodule Portfolixir.News.Retier do
  @moduledoc """
  A rating re-rates the stored items it covers (ADR-0056 E1, amendment of
  2026-11-12; Sprint 29, N1, #1444). Called by
  `Portfolixir.News.Sources.put_source/4` inside its transaction, after the
  row is written and before the journal entry, so the row, the items and
  the entry commit together or not at all.

  **When.** Only a write that changes the row's stored tier: an insert (an
  unrated domain read as `awareness`, so its items carry the tier §3 gave
  an unknown domain), or an update to another tier. A write that changes
  only `set_by`, or nothing, re-rates nothing, and a seed write onto a hand
  row never gets here (§3: `{:kept, row}`).

  **Which items** (E1 rule 1): every stored item whose domain is the row's
  domain or a subdomain of it, and that no longer row decides
  (`Portfolixir.News.Sources.decider/1`, §3's longest suffix): a more
  specific row elsewhere keeps its items.

  **Their new tier** (rule 2): `Sources.tier(class, rated)`, exactly as the
  ingest computes it (B5's caps: an `aggregator` or `thematic` item at most
  `secondary`, an `issuer` or `regulatory` item `primary` unless blocked).
  An item whose tier that leaves as it is is not counted.

  **Promoted items keep their tier** (rule 5): an item `promoted` or naming
  a note is the provenance of an entry the log never rewrites. It is
  counted, when the rating would have changed it, as kept.

  **A newly blocked domain's items are removed** (rule 3): those on a
  security or a category through `Portfolixir.News.Stories.remove/5`, as
  retention removes them (§12), the others deleted; no tombstone is left,
  so a later fetch that lists one again drops it as `dropped_blocked`.

  **Each touched story is chosen again** (rule 4): the scopes and languages
  of the re-rated items are reclustered in full
  (`Portfolixir.News.Stories.recluster/4`), so each story's representative,
  best tier and C1 anchoring follow the new tiers, and each story keeps its
  id by C2's survivor key.

  **The counts** (rule 6) go to the write's journal entry:
  `items_rerated`, `items_removed` and `items_kept_promoted`.

  Items and stories are a staging area, not journaled (B7); the count is
  what the journal keeps of this.
  """
  import Ecto.Query

  alias Portfolixir.News.Item
  alias Portfolixir.News.Source
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo

  @type counts :: %{
          items_rerated: non_neg_integer(),
          items_removed: non_neg_integer(),
          items_kept_promoted: non_neg_integer()
        }

  @zero %{items_rerated: 0, items_removed: 0, items_kept_promoted: 0}

  @doc "The counts of a write that re-rated nothing."
  @spec zero() :: counts()
  def zero, do: @zero

  @doc """
  Re-rates the items the written row `source` now decides, its prior row
  being `prior` (`nil` for an insert), at the server's clock `now`; see the
  moduledoc. Runs inside the caller's transaction. `{:ok, counts}`, or
  `{:error, changeset}` when a story could not be written.
  """
  @spec run(Source.t() | nil, Source.t(), DateTime.t()) ::
          {:ok, counts()} | {:error, Ecto.Changeset.t()}
  def run(%Source{tier: tier}, %Source{tier: tier}, _now), do: {:ok, @zero}

  def run(_prior, %Source{} = source, %DateTime{} = now) do
    {promoted, unpromoted} =
      source
      |> changed_items()
      |> Enum.split_with(&promoted?/1)

    rerate(unpromoted, source.tier, now, %{@zero | items_kept_promoted: length(promoted)})
  end

  # The items the row decides whose tier the rating changes, each with its
  # new tier. The query reads the domain and its subdomains; the decider
  # keeps those no longer row decides.
  defp changed_items(%Source{domain: domain, tier: rated}) do
    items =
      Repo.all(
        from(i in Item,
          where: i.domain == ^domain or like(i.domain, ^("%." <> domain)),
          select: %{
            id: i.id,
            class: i.class,
            domain: i.domain,
            tier: i.tier,
            status: i.status,
            note_ids: i.note_ids,
            assignment: i.assignment,
            security_id: i.security_id,
            category_id: i.category_id,
            language: i.language
          }
        )
      )

    deciders = items |> Enum.map(& &1.domain) |> Enum.uniq() |> Sources.decider()

    for item <- items,
        Map.get(deciders, item.domain) == domain,
        new = Sources.tier(item.class, rated),
        new != item.tier,
        do: Map.put(item, :new, new)
  end

  defp promoted?(%{status: status, note_ids: note_ids}), do: status == :promoted or note_ids != []

  defp rerate(items, _rated, now, counts) do
    {blocked, rerated} = Enum.split_with(items, &(&1.new == :blocked))

    rerated
    |> Enum.group_by(& &1.new, & &1.id)
    |> Enum.each(fn {tier, ids} ->
      Repo.update_all(from(i in Item, where: i.id in ^ids),
        set: [tier: tier, updated_at: DateTime.utc_now()]
      )
    end)

    with {:ok, removed} <- remove(blocked, now),
         :ok <- recluster(scopes(rerated), now) do
      {:ok, %{counts | items_rerated: length(rerated), items_removed: removed}}
    end
  end

  # E1 rule 3: a newly blocked domain's unpromoted items are removed, as the
  # ingest would not have stored them (§3). Those on a security or a
  # category leave their stories through `Stories.remove/5`, as retention's
  # do (§12): one scope and language at a time, under its lock, a story left
  # without a member deleted, one that lost a member recounted and
  # represented by the best member left, one the item held together split.
  # An unassigned or ambiguous item sits in no story and is deleted. The
  # delete reads each item again: one promoted meanwhile no longer matches
  # and stays. No tombstone: a later fetch that lists the item again drops
  # it as blocked.
  defp remove([], _now), do: {:ok, 0}

  defp remove(items, now) do
    {assigned, open} = Enum.split_with(items, &(&1.assignment == :assigned))

    {open_removed, _} = Repo.delete_all(doomed(Enum.map(open, & &1.id)))

    assigned
    |> Enum.group_by(&{Stories.scope(&1), &1.language}, & &1.id)
    |> Enum.sort()
    |> Enum.reduce_while({:ok, open_removed}, fn {{scope, language}, ids}, {:ok, removed} ->
      case Stories.remove(scope, language, doomed(ids), now) do
        {:ok, %{items: count}} -> {:cont, {:ok, removed + count}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  # The items of `ids` that are still neither promoted nor linked to a note.
  defp doomed(ids) do
    from(i in Item,
      where: i.id in ^ids and i.status != :promoted and fragment("cardinality(?) = 0", i.note_ids)
    )
  end

  # The scopes and languages of the assigned items among `items`, sorted.
  defp scopes(items) do
    items
    |> Enum.filter(&(&1.assignment == :assigned))
    |> Enum.map(&{Stories.scope(&1), &1.language})
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp recluster(scopes, now) do
    Enum.reduce_while(scopes, :ok, fn {scope, language}, :ok ->
      case Stories.recluster(scope, language, now, full: true) do
        {:ok, _summary} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
