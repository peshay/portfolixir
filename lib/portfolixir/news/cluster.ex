defmodule Portfolixir.News.Cluster do
  @moduledoc """
  A story (ADR-0056 §4, B3): the items about one security — or one category
  — in one language that the clustering found to be one event.

  It carries what a read needs without reading its members: the
  `representative_item_id`, the `member_count`, the earliest first sight
  and the earliest (clamped) publication of its members, and the best tier
  among them (never `blocked`).

  **The survivor key** (B3): when an item links two stories, the surviving
  story is the one whose earliest member is earliest by
  `(first_seen_at, canonical_url)`, **never by id**. The story stores that
  member's two values as `earliest_first_seen_at` and `earliest_url`, so a
  merge compares two stories without reading their members.

  Exactly one of `security_id` and `category_id`; at least one member; the
  earliest publication never after the earliest first sight (B4 clamps
  each member's).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text
  alias Portfolixir.News.Shapes

  @fields ~w(security_id category_id language representative_item_id member_count
             earliest_first_seen_at earliest_published_at earliest_url best_tier)a

  @type t :: %__MODULE__{}

  schema "news_clusters" do
    belongs_to(:security, Portfolixir.Catalog.Security)
    belongs_to(:category, Portfolixir.Classifications.Category)
    field(:language, :string)
    belongs_to(:representative_item, Portfolixir.News.Item)
    field(:member_count, :integer)
    field(:earliest_first_seen_at, :utc_datetime_usec)
    field(:earliest_published_at, :utc_datetime_usec)
    field(:earliest_url, :string)
    field(:best_tier, Ecto.Enum, values: Shapes.stored_tiers())

    has_many(:items, Portfolixir.News.Item)

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Casts and checks a story."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(cluster, attrs) do
    cluster
    |> cast(attrs, @fields)
    |> validate_required([
      :language,
      :representative_item_id,
      :member_count,
      :earliest_first_seen_at,
      :earliest_published_at,
      :earliest_url,
      :best_tier
    ])
    |> validate_scope()
    |> Text.validate([:language, :earliest_url], max: Shapes.url_max())
    |> Shapes.language(:language)
    |> validate_number(:member_count, greater_than_or_equal_to: 1)
    |> Shapes.item_url(:earliest_url)
    |> validate_earliest()
    |> foreign_key_constraint(:security_id, name: :news_clusters_security_id_fkey)
    |> foreign_key_constraint(:category_id, name: :news_clusters_category_id_fkey)
    |> foreign_key_constraint(:representative_item_id,
      name: :news_clusters_representative_item_id_fkey
    )
    |> check_constraint(:security_id, name: :news_clusters_scope_check, message: "is invalid")
    |> check_constraint(:language, name: :news_clusters_language_check, message: "is invalid")
    |> check_constraint(:member_count,
      name: :news_clusters_member_count_check,
      message: "is invalid"
    )
    |> check_constraint(:best_tier, name: :news_clusters_best_tier_check, message: "is invalid")
    |> check_constraint(:earliest_published_at,
      name: :news_clusters_earliest_check,
      message: "is invalid"
    )
    |> check_constraint(:earliest_url,
      name: :news_clusters_earliest_url_check,
      message: "is invalid"
    )
  end

  defp validate_scope(changeset) do
    case {get_field(changeset, :security_id), get_field(changeset, :category_id)} do
      {nil, nil} ->
        add_error(changeset, :security_id, "a story names a security or a category")

      {security_id, category_id} when not is_nil(security_id) and not is_nil(category_id) ->
        add_error(changeset, :category_id, "a story names a security or a category, not both")

      _one ->
        changeset
    end
  end

  defp validate_earliest(changeset) do
    published = get_field(changeset, :earliest_published_at)
    seen = get_field(changeset, :earliest_first_seen_at)

    if published && seen && DateTime.compare(published, seen) == :gt,
      do:
        add_error(changeset, :earliest_published_at, "must not be after the earliest first sight"),
      else: changeset
  end
end
