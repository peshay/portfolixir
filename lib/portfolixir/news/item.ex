defmodule Portfolixir.News.Item do
  @moduledoc """
  One fetched news item (ADR-0056 §4), written by the fetcher, a system job
  (B7: items are a staging area that retention empties, not journaled).

  **Times** (B4): `first_seen_at` is the server's clock when the item was
  first stored; `published_at_claimed` is the publication time as the feed
  stated it, kept as stated; `published_at` is that claim **clamped to
  `first_seen_at`** — `changeset/2` derives it and never casts it, and the
  database refuses any other value — so a future date cannot make an item
  the newest. Without a claim it is `first_seen_at`.

  **Binding by class** (§2): an `issuer` or `regulatory` item is `assigned`
  to its feed's security, a `thematic` item to its feed's category; an
  `aggregator` item is `assigned` to the one security the matcher found,
  `unassigned` (no security), or `ambiguous` with at least two
  `candidates` (security ids, stored sorted and without repeats, and only on
  an ambiguous item). An item sits in a story (`cluster_id`) only once
  assigned, and only in a story of its own security (or category) and
  language.

  **Class**: its feed's class, held by a composite key onto the feed; an
  item a feed's delete detached (`feed_id` NULL) keeps it.

  **Tier**: the source's tier at ingest; never `blocked` (a blocked domain's
  items are dropped, §3) and, for an `aggregator` item, never `primary`
  (B5).

  **Text** (§4, §9, plan D-6): a title of 1 to 160 characters and an
  excerpt of at most 600, counted as characters, without control
  characters; invisible characters are kept as received.

  **Dedupe keys**: `content_hash` and `title_norm_hash` are SHA-256 digests
  in lower-case hex; `title_words` are the normalized title's words for the
  Jaccard similarity (at most 160). A feed lists an item once:
  `(feed_id, canonical_url)` is unique, so a re-fetch stores nothing new.

  `status` is `new`, `promoted` or `muted`; a promoted item names the notes
  it was promoted to (`note_ids`, §8).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text
  alias Portfolixir.News.Shapes

  @title_max 160
  @excerpt_max 600
  @words_max 160

  @fields ~w(feed_id class security_id category_id cluster_id published_at_claimed
             first_seen_at title canonical_url domain tier language excerpt content_hash
             title_norm_hash title_words assignment candidates status note_ids)a

  @type t :: %__MODULE__{}

  schema "news_items" do
    belongs_to(:feed, Portfolixir.News.Feed)
    field(:class, Ecto.Enum, values: Shapes.classes())
    belongs_to(:security, Portfolixir.Catalog.Security)
    belongs_to(:category, Portfolixir.Classifications.Category)
    belongs_to(:cluster, Portfolixir.News.Cluster)
    field(:published_at, :utc_datetime_usec)
    field(:published_at_claimed, :utc_datetime_usec)
    field(:first_seen_at, :utc_datetime_usec)
    field(:title, :string)
    field(:canonical_url, :string)
    field(:domain, :string)
    field(:tier, Ecto.Enum, values: Shapes.stored_tiers())
    field(:language, :string)
    field(:excerpt, :string)
    field(:content_hash, :string)
    field(:title_norm_hash, :string)
    field(:title_words, {:array, :string}, default: [])
    field(:assignment, Ecto.Enum, values: [:assigned, :unassigned, :ambiguous])
    field(:candidates, {:array, :integer}, default: [])
    field(:status, Ecto.Enum, values: [:new, :promoted, :muted], default: :new)
    field(:note_ids, {:array, :integer}, default: [])

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The longest title an item stores, in characters (§4)."
  @spec title_max() :: pos_integer()
  def title_max, do: @title_max

  @doc "The longest excerpt an item stores, in characters (§4)."
  @spec excerpt_max() :: pos_integer()
  def excerpt_max, do: @excerpt_max

  @doc """
  Casts and checks an item; derives `published_at` from the claim and
  `first_seen_at` (B4).
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(item, attrs) do
    item
    |> cast(attrs, @fields)
    |> validate_required([
      :class,
      :first_seen_at,
      :title,
      :canonical_url,
      :domain,
      :tier,
      :language,
      :content_hash,
      :title_norm_hash,
      :assignment,
      :status
    ])
    |> clamp_published_at()
    |> Shapes.feed_text(:title, max: @title_max)
    |> validate_not_blank(:title)
    |> Shapes.feed_text(:excerpt, max: @excerpt_max, multiline: true)
    |> Text.validate([:canonical_url, :domain, :language, :content_hash, :title_norm_hash],
      max: Shapes.url_max()
    )
    |> Shapes.item_url(:canonical_url)
    |> Shapes.domain(:domain)
    |> Shapes.language(:language)
    |> Shapes.hex64(:content_hash)
    |> Shapes.hex64(:title_norm_hash)
    |> validate_length(:title_words, max: @words_max)
    |> update_change(:candidates, &(&1 |> Enum.uniq() |> Enum.sort()))
    |> validate_binding()
    |> validate_candidates()
    |> validate_tier()
    |> validate_cluster()
    |> validate_notes()
    |> unique_constraint(:canonical_url, name: :news_items_feed_id_canonical_url_index)
    |> foreign_key_constraint(:feed_id, name: :news_items_feed_id_fkey)
    |> foreign_key_constraint(:class,
      name: :news_items_feed_class_fkey,
      message: "is not its feed's class"
    )
    |> foreign_key_constraint(:security_id, name: :news_items_security_id_fkey)
    |> foreign_key_constraint(:category_id, name: :news_items_category_id_fkey)
    |> foreign_key_constraint(:cluster_id, name: :news_items_cluster_id_fkey)
    |> foreign_key_constraint(:cluster_id,
      name: :news_items_cluster_security_fkey,
      message: "is a story of another security or language"
    )
    |> foreign_key_constraint(:cluster_id,
      name: :news_items_cluster_category_fkey,
      message: "is a story of another category or language"
    )
    |> check_constraints()
  end

  @checks [
    class: :news_items_class_check,
    assignment: :news_items_assignment_check,
    status: :news_items_status_check,
    tier: :news_items_tier_check,
    security_id: :news_items_binding_check,
    candidates: :news_items_candidates_check,
    published_at: :news_items_published_at_check,
    title: :news_items_title_check,
    excerpt: :news_items_excerpt_check,
    canonical_url: :news_items_canonical_url_check,
    domain: :news_items_domain_check,
    language: :news_items_language_check,
    content_hash: :news_items_content_hash_check,
    title_norm_hash: :news_items_title_norm_hash_check,
    title_words: :news_items_title_words_check,
    note_ids: :news_items_note_ids_check,
    cluster_id: :news_items_cluster_check
  ]

  defp check_constraints(changeset) do
    Enum.reduce(@checks, changeset, fn {field, name}, acc ->
      check_constraint(acc, field, name: name, message: "is invalid")
    end)
  end

  # B4: the claim, clamped to the server's first sight; never cast.
  defp clamp_published_at(changeset) do
    first_seen_at = get_field(changeset, :first_seen_at)
    claimed = get_field(changeset, :published_at_claimed)

    published_at =
      cond do
        is_nil(first_seen_at) -> nil
        is_nil(claimed) -> first_seen_at
        DateTime.compare(claimed, first_seen_at) == :gt -> first_seen_at
        true -> claimed
      end

    put_change(changeset, :published_at, published_at)
  end

  defp validate_not_blank(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if String.trim(value) == "", do: [{field, "can't be blank"}], else: []
    end)
  end

  # §2: the class decides the binding; an aggregator's assignment decides
  # whether it names a security.
  defp validate_binding(changeset) do
    security_id = get_field(changeset, :security_id)
    category_id = get_field(changeset, :category_id)
    assignment = get_field(changeset, :assignment)

    case get_field(changeset, :class) do
      class when class in [:issuer, :regulatory, :thematic] ->
        {required, refused} =
          if class == :thematic,
            do: {{:category_id, category_id}, {:security_id, security_id}},
            else: {{:security_id, security_id}, {:category_id, category_id}}

        changeset
        |> add_if(assignment not in [:assigned, nil], :assignment, "an #{class} item is assigned")
        |> add_if(is_nil(elem(required, 1)), elem(required, 0), "an #{class} item names it")
        |> add_if(not is_nil(elem(refused, 1)), elem(refused, 0), "an #{class} item names none")

      :aggregator ->
        changeset
        |> add_if(not is_nil(category_id), :category_id, "an aggregator item names no category")
        |> add_if(
          assignment == :assigned and is_nil(security_id),
          :security_id,
          "an assigned aggregator item names its security"
        )
        |> add_if(
          assignment in [:unassigned, :ambiguous] and not is_nil(security_id),
          :security_id,
          "only an assigned item names a security"
        )

      nil ->
        changeset
    end
  end

  defp validate_candidates(changeset) do
    candidates = get_field(changeset, :candidates) || []

    case get_field(changeset, :assignment) do
      :ambiguous ->
        add_if(
          changeset,
          length(candidates) < 2,
          :candidates,
          "an ambiguous item lists at least two candidates"
        )

      _other ->
        add_if(
          changeset,
          candidates != [],
          :candidates,
          "only an ambiguous item lists candidates"
        )
    end
  end

  # B5: an aggregator's item is at most secondary.
  defp validate_tier(changeset) do
    add_if(
      changeset,
      get_field(changeset, :class) == :aggregator and get_field(changeset, :tier) == :primary,
      :tier,
      "an aggregator item is at most secondary"
    )
  end

  defp validate_cluster(changeset) do
    add_if(
      changeset,
      not is_nil(get_field(changeset, :cluster_id)) and
        get_field(changeset, :assignment) != :assigned,
      :cluster_id,
      "only an assigned item belongs to a story"
    )
  end

  defp validate_notes(changeset) do
    add_if(
      changeset,
      get_field(changeset, :status) == :promoted and (get_field(changeset, :note_ids) || []) == [],
      :note_ids,
      "a promoted item names the notes it was promoted to"
    )
  end

  defp add_if(changeset, true, field, message), do: add_error(changeset, field, message)
  defp add_if(changeset, false, _field, _message), do: changeset
end
