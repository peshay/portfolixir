defmodule Portfolixir.News.Dossier do
  @moduledoc """
  The news block of `securities.dossier` (ADR-0056 §9's extension; Sprint
  28, N6): what the agent needs to decide whether to read a security's news
  first, in about 50 tokens.

    * `count_7d` — the security's stories that had a member enter their
      scope within the 7 days before `now`: `news.list`'s `since` rule
      (`scope_at`, C3), so `news.list?security_id=…&since=<7 days back>`
      lists exactly them;
    * `primary_7d` — those whose best tier is `primary` (an issuer's or a
      regulator's item);
    * `max_materiality` — the highest materiality of their active labels of
      the newest prompt version (`Portfolixir.News.Labels`; the reads'
      default), `nil` with no label: a label sorts, so the block says how
      material the week was, never which story to skip;
    * `newest_primary` — the security's newest primary story **at any
      age**, in `news.list`'s order: its `id`, its representative's title
      cut at 50 characters as the companion spells them (the digest's cut,
      `Portfolixir.News.Reads.clip_spelled/2`) and its publication `at`;
      `nil` when it has none. *Why at any age:* when the week has no
      primary story the block still says when the issuer last spoke, where
      a 7-day bound would only repeat `primary_7d`.
  """
  import Ecto.Query

  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
  alias Portfolixir.News.Labels
  alias Portfolixir.News.Reads
  alias Portfolixir.Repo

  @days 7
  @title_max 50
  @rank_sql "CASE ? WHEN 'primary' THEN 0 WHEN 'secondary' THEN 1 ELSE 2 END"

  @type t :: %{
          count_7d: non_neg_integer(),
          primary_7d: non_neg_integer(),
          max_materiality: 0..3 | nil,
          newest_primary: %{id: pos_integer(), title: String.t(), at: DateTime.t()} | nil
        }

  @doc "The news block of the security `security_id` at the server's clock `now`."
  @spec block(pos_integer(), DateTime.t()) :: t()
  def block(security_id, %DateTime{} = now) when is_integer(security_id) do
    since = DateTime.add(now, -@days, :day)
    seen = seen(security_id)

    %{count: count, primary: primary, materiality: materiality} =
      from(c in Cluster,
        join: s in subquery(seen),
        on: s.cluster_id == c.id,
        left_join: l in subquery(Labels.active(Labels.newest_prompt_version())),
        on: l.cluster_id == c.id,
        where: c.security_id == ^security_id and s.seen > ^since,
        select: %{
          count: count(c.id),
          primary: filter(count(c.id), c.best_tier == :primary),
          materiality: max(l.materiality)
        }
      )
      |> Repo.one()

    %{
      count_7d: count,
      primary_7d: primary,
      max_materiality: materiality,
      newest_primary: newest_primary(security_id, seen)
    }
  end

  # Each story's newest entry into its scope, read from the security's items
  # (a story's items carry its security), as news.list reads it.
  defp seen(security_id) do
    from(i in Item,
      where: i.security_id == ^security_id and not is_nil(i.cluster_id),
      group_by: i.cluster_id,
      select: %{cluster_id: i.cluster_id, seen: max(i.scope_at)}
    )
  end

  defp newest_primary(security_id, seen) do
    from(c in Cluster,
      join: s in subquery(seen),
      on: s.cluster_id == c.id,
      join: r in Item,
      on: r.id == c.representative_item_id,
      where: c.security_id == ^security_id and c.best_tier == :primary,
      order_by: [
        desc: s.seen,
        asc: fragment(@rank_sql, c.best_tier),
        desc: r.published_at,
        asc: fragment("md5(?)", r.canonical_url),
        desc: c.id
      ],
      limit: 1,
      select: %{id: c.id, title: r.title, at: r.published_at}
    )
    |> Repo.one()
    |> case do
      nil -> nil
      story -> %{story | title: Reads.clip_spelled(story.title, @title_max)}
    end
  end
end
