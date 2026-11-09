defmodule Portfolixir.News.Promotion do
  @moduledoc """
  From story to knowledge (ADR-0056 §8, A2; ADR-0044's amendment of
  2026-11-06; Sprint 28, N5): **the one place a story becomes a research
  note**, and the source an event takes from an item. Nothing in the news
  layer writes a note, an event or a prediction by itself (NFR-10): a note
  is written here only inside a caller's `notes.append`, and an event only
  by the caller's `events.create`.

  ## `notes.append` with a `cluster_id` (`append_note/3`)

  The server fills in what the story knows, the agent writes the body:

    * `kind` — `evidence`; the caller may send `event_result` instead, the
      other kind that carries a headline, and any other kind is refused
      naming `kind` (a story is a finding or an outcome, not a thesis);
    * `as_of` — the story's publication day: its representative's
      publication (clamped, B4), as `news.get` answers it, on the
      instance's calendar (`Portfolixir.Clock.local_date/1`);
    * `source_url` — the best-tier member's link: the representative's (the
      earliest of the best tier, C2), else, when it is longer than an
      entry's 255 characters, the first member's that fits in `news.get`'s
      member order (tier, publication, link);
    * `source_quality` — §3's one rule over every member: a `primary`
      member gives `primary`; two or more distinct `secondary` domains
      `secondary_multi`; one `secondary` domain `unverified`; else
      `awareness`;
    * `headline` — the representative's title, cut at 80 characters on a
      word boundary as the companion spells them
      (`Portfolixir.News.Reads.clip_spelled_words/2`); a title that holds an
      invisible character is refused by the entry's text rule (ADR-0054
      §4) naming `headline`, and the caller sends its own;
    * `event_type` and `tone` — the story's **active label** of the newest
      prompt version (`Portfolixir.News.Labels.newest_prompt_version/0`,
      the version the agent's reads default to); a `noise` label gives no
      event type (an entry is what was judged worth keeping). The entry
      **copies** them and keeps the label's id as provenance
      (`news_label_id`) when it took either: a later put of the same
      (cluster, model, prompt version) rewrites that label in place (the
      journal keeps every version), so the id says where the proposal came
      from, and the entry's own fields say what was confirmed.

  **The pre-fill is a proposal** (the amendment: "the writer may change any
  of them before the write"): `kind`, `headline`, `event_type` and `tone`
  sent beside `cluster_id` replace it, and a `null` leaves the field out;
  the write is the confirmation NFR-10 asks for. **`as_of`, `source_url`
  and `source_quality` are the story's**, and one sent beside `cluster_id`
  is refused naming it: they state the source's provenance by rule, so a
  write cannot claim a better source than the story has; an agent that
  holds one writes an entry from that source, without `cluster_id`.

  **The story becomes `promoted` and links the note:** every member is
  `promoted` and names the note in `note_ids`, so the story's sources stay
  past retention (§12) — the members are what its source quality was
  derived from. **A second promotion appends another note**, and the story
  links both: the log is append-only, and a story can carry a finding and
  later its outcome; refusing it would leave a judged entry unwritten.

  The write runs in one transaction under the story's scope lock
  (`Portfolixir.News.Stories.lock/2`, the clustering's), with its members
  locked: no re-cluster or retention run moves a member between the read
  and the link. The story must be one of the note's own security; another
  security's, a category's and an id naming none are refused naming
  `cluster_id`.

  ## `events.create` with a `news_id` (`event_source/2`)

  An item of the event's own security gives the event's `source_url` (its
  link) and `source_quality` by §3's rule over that one item (`primary`,
  `secondary` as `unverified`, `awareness`). The item is not promoted: an
  event is a mutable calendar fact (ADR-0048 §4), and what lasts from news
  is a research note (A2).
  """
  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
  alias Portfolixir.News.Labels
  alias Portfolixir.News.Reads
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo

  @story_fields ~w(as_of source_url source_quality)
  @kinds ~w(evidence event_result)
  @source_url_max 255
  @tier_rank %{primary: 3, secondary: 2, awareness: 1}

  @type errors :: %{String.t() => [String.t()]}

  @doc """
  Appends the research note `attrs` (string keys; `security_id`, `author`
  and the caller's fields) written from the story `cluster_id`, journaled
  under `actor`; see the moduledoc. `{:ok, note}`, `{:error, errors}` for a
  refusal of the story or of a field beside it, or `{:error, changeset}`.
  """
  @spec append_note(Actor.t(), map(), pos_integer()) ::
          {:ok, SecurityNote.t()} | {:error, errors() | Ecto.Changeset.t()}
  def append_note(%Actor{} = actor, attrs, cluster_id)
      when is_map(attrs) and is_integer(cluster_id) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    with :ok <- refuse_story_fields(attrs),
         :ok <- check_kind(attrs) do
      Repo.transaction(fn -> promote(actor, attrs, cluster_id) end)
    end
  end

  defp promote(actor, attrs, cluster_id) do
    with {:ok, story} <- own_story(cluster_id, attrs["security_id"]),
         :ok <- Stories.lock({:security, story.security_id}, story.language),
         {:ok, story} <- own_story(cluster_id, attrs["security_id"]),
         members = lock_members(story),
         {:ok, source_url} <- source_url(story, members),
         {prefill, label} = prefill(story, members, source_url),
         {:ok, note} <- write(actor, Map.merge(prefill, attrs), label, attrs) do
      link(members, note)
      note
    else
      {:error, refused} -> Repo.rollback(refused)
    end
  end

  defp refuse_story_fields(attrs) do
    case Enum.filter(@story_fields, &Map.has_key?(attrs, &1)) do
      [] ->
        :ok

      fields ->
        {:error,
         Map.new(fields, &{&1, ["is the story's beside cluster_id (ADR-0056 §8): leave it out"]})}
    end
  end

  defp check_kind(attrs) do
    case Map.fetch(attrs, "kind") do
      :error ->
        :ok

      {:ok, kind} ->
        if to_string(kind) in @kinds,
          do: :ok,
          else: {:error, %{"kind" => ["a story becomes an evidence or event_result entry"]}}
    end
  end

  defp own_story(cluster_id, security_id) do
    case Repo.get(Cluster, cluster_id) do
      %Cluster{security_id: ^security_id} = story when is_integer(security_id) ->
        {:ok, story}

      %Cluster{security_id: nil} ->
        {:error, %{"cluster_id" => ["is a category's story: a note belongs to a security"]}}

      %Cluster{} ->
        {:error, %{"cluster_id" => ["is a story of another security"]}}

      nil ->
        {:error, %{"cluster_id" => ["names no story"]}}
    end
  end

  defp lock_members(story) do
    Repo.all(
      from(i in Item, where: i.cluster_id == ^story.id, order_by: i.id, lock: "FOR UPDATE")
    )
  end

  # The representative first, then news.get's member order: the best tier,
  # the earliest publication, the smallest link.
  defp source_url(story, members) do
    members
    |> Enum.sort_by(
      &{&1.id != story.representative_item_id, -@tier_rank[&1.tier],
       DateTime.to_unix(&1.published_at, :microsecond), &1.canonical_url}
    )
    |> Enum.find(&(String.length(&1.canonical_url) <= @source_url_max))
    |> case do
      %Item{canonical_url: url} ->
        {:ok, url}

      nil ->
        {:error,
         %{"cluster_id" => ["no member's link fits an entry's source_url of 255 characters"]}}
    end
  end

  defp prefill(story, members, source_url) do
    representative = Enum.find(members, &(&1.id == story.representative_item_id))
    label = Labels.active_label(story.id, Labels.newest_prompt_version())

    prefill = %{
      "kind" => "evidence",
      "as_of" => Clock.local_date(representative.published_at),
      "source_url" => source_url,
      "source_quality" => Atom.to_string(source_quality(members)),
      "headline" => Reads.clip_spelled_words(representative.title, SecurityNote.headline_max())
    }

    case label do
      nil -> {prefill, nil}
      label -> {Map.merge(prefill, label_fields(label)), label}
    end
  end

  defp label_fields(label) do
    event_type = Atom.to_string(label.event_type)

    if event_type in SecurityNote.event_types(),
      do: %{"event_type" => event_type, "tone" => label.tone},
      else: %{"tone" => label.tone}
  end

  # §3: a primary member gives primary; two or more distinct secondary
  # domains secondary_multi; one unverified; else awareness.
  defp source_quality(members) do
    secondary_domains =
      for %Item{tier: :secondary, domain: domain} <- members, uniq: true, do: domain

    cond do
      Enum.any?(members, &(&1.tier == :primary)) -> :primary
      length(secondary_domains) >= 2 -> :secondary_multi
      secondary_domains != [] -> :unverified
      true -> :awareness
    end
  end

  # The label's id stays when the entry took its event type or its tone
  # from it, the caller having sent neither in its place.
  defp write(actor, merged, label, attrs) do
    taken? =
      label != nil and
        ((Map.has_key?(merged, "event_type") and not Map.has_key?(attrs, "event_type")) or
           not Map.has_key?(attrs, "tone"))

    Knowledge.append_note(actor, merged, news_label_id: if(taken?, do: label.id))
  end

  defp link(members, note) do
    ids = Enum.map(members, & &1.id)

    Repo.update_all(from(i in Item, where: i.id in ^ids),
      set: [status: :promoted, updated_at: DateTime.utc_now()],
      push: [note_ids: note.id]
    )
  end

  @doc """
  The source an event takes from the item `news_id` of the security
  `security_id` (`events.create` with a `news_id`): `{:ok, %{"source_url"
  => link, "source_quality" => quality}}`, or `{:error, errors}` naming
  `news_id` for an item that does not exist, is not assigned to that
  security, or whose link is longer than an event's 255 characters.
  """
  @spec event_source(pos_integer(), pos_integer()) ::
          {:ok, %{String.t() => term()}} | {:error, errors()}
  def event_source(security_id, news_id) when is_integer(security_id) and is_integer(news_id) do
    case Repo.get(Item, news_id) do
      %Item{security_id: ^security_id, canonical_url: url, tier: tier} ->
        if String.length(url) <= @source_url_max,
          do: {:ok, %{"source_url" => url, "source_quality" => item_quality(tier)}},
          else:
            {:error,
             %{"news_id" => ["its link is longer than an event's source_url of 255 characters"]}}

      %Item{} ->
        {:error, %{"news_id" => ["is not an item of this security"]}}

      nil ->
        {:error, %{"news_id" => ["names no item"]}}
    end
  end

  defp item_quality(:primary), do: :primary
  defp item_quality(:secondary), do: :unverified
  defp item_quality(:awareness), do: :awareness
end
