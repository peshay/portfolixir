defmodule Portfolixir.News.Feed do
  @moduledoc """
  A registered news feed (ADR-0056 §2, §4, §5).

  **The class decides the binding** (§2): `issuer` and `regulatory` feeds
  name a `security_id` and no category, a `thematic` feed a `category_id`
  of a classification and no security, an `aggregator` feed neither — its
  items find their security through the alias matcher, or none.

  **What the operator or the agent states** (`changeset/2`): the class, the
  URL (https, no userinfo, at most 2,048 characters, unique among feeds:
  B2's resolution check is the registering writer's), the binding, whether
  it is enabled, the interval (1 to 1,440 minutes; without one, the class's
  default of §5: `regulatory` 10, `issuer` 15, `aggregator` 60, `thematic`
  180) and the language (one per feed, §4).

  **What the fetcher states** (`health_changeset/2`): `last_fetch_at`,
  `last_ok_at` (never after `last_fetch_at`), `last_error` (at most 500
  characters) and the backoff state of §5 — `failures`, the consecutive
  failures, and `retry_at`, the earliest next try, set only after a failure.

  The rolling counts of §6 and A3 are not columns of this table; see
  `Portfolixir.News.FeedDay` for where each is read from.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Input.Text
  alias Portfolixir.News.Shapes

  @default_intervals %{regulatory: 10, issuer: 15, aggregator: 60, thematic: 180}
  @interval_max 1440
  @last_error_max 500

  @type t :: %__MODULE__{}

  schema "news_feeds" do
    field(:class, Ecto.Enum, values: Shapes.classes())
    field(:url, :string)
    belongs_to(:security, Security)
    belongs_to(:category, Category)
    field(:enabled, :boolean, default: true)
    field(:interval_minutes, :integer)
    field(:language, :string)
    field(:last_ok_at, :utc_datetime_usec)
    field(:last_fetch_at, :utc_datetime_usec)
    field(:last_error, :string)
    field(:failures, :integer, default: 0)
    field(:retry_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The default interval in minutes of each class (§5)."
  @spec default_intervals() :: %{atom() => pos_integer()}
  def default_intervals, do: @default_intervals

  @doc "Casts and checks what a feed's registration states."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(feed, attrs) do
    feed
    |> cast(attrs, [
      :class,
      :url,
      :security_id,
      :category_id,
      :enabled,
      :interval_minutes,
      :language
    ])
    |> default_interval()
    |> validate_required([:class, :url, :enabled, :interval_minutes, :language])
    |> validate_binding()
    |> Text.validate([:url, :language], max: Shapes.url_max())
    |> Shapes.feed_url(:url)
    |> validate_number(:interval_minutes,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: @interval_max
    )
    |> Shapes.language(:language)
    |> unique_constraint(:url, name: :news_feeds_url_index)
    |> foreign_key_constraint(:security_id, name: :news_feeds_security_id_fkey)
    |> foreign_key_constraint(:category_id, name: :news_feeds_category_id_fkey)
    |> check_constraint(:class, name: :news_feeds_class_check, message: "is invalid")
    |> check_constraint(:security_id, name: :news_feeds_binding_check, message: "is invalid")
    |> check_constraint(:url, name: :news_feeds_url_check, message: "is invalid")
    |> check_constraint(:interval_minutes,
      name: :news_feeds_interval_minutes_check,
      message: "is invalid"
    )
    |> check_constraint(:language, name: :news_feeds_language_check, message: "is invalid")
  end

  @doc "Casts and checks the fetcher's record of a fetch: its times, its error, its backoff."
  @spec health_changeset(t(), map()) :: Ecto.Changeset.t()
  def health_changeset(feed, attrs) do
    feed
    |> cast(attrs, [:last_ok_at, :last_fetch_at, :last_error, :failures, :retry_at])
    |> validate_required([:failures])
    |> validate_number(:failures, greater_than_or_equal_to: 0)
    |> Text.validate(:last_error, max: @last_error_max)
    |> validate_last_ok()
    |> validate_retry()
    |> check_constraint(:failures, name: :news_feeds_failures_check, message: "is invalid")
    |> check_constraint(:retry_at, name: :news_feeds_retry_at_check, message: "is invalid")
    |> check_constraint(:last_ok_at, name: :news_feeds_last_ok_at_check, message: "is invalid")
    |> check_constraint(:last_error, name: :news_feeds_last_error_check, message: "is invalid")
  end

  defp default_interval(changeset) do
    with nil <- get_field(changeset, :interval_minutes),
         class when is_atom(class) and not is_nil(class) <- get_field(changeset, :class) do
      put_change(changeset, :interval_minutes, Map.fetch!(@default_intervals, class))
    else
      _ -> changeset
    end
  end

  # §2: the class decides what the feed is bound to.
  defp validate_binding(changeset) do
    security_id = get_field(changeset, :security_id)
    category_id = get_field(changeset, :category_id)

    case get_field(changeset, :class) do
      class when class in [:issuer, :regulatory] ->
        changeset
        |> require_bound(:security_id, security_id, "an #{class} feed names its security")
        |> refuse_bound(:category_id, category_id, "an #{class} feed names no category")

      :thematic ->
        changeset
        |> require_bound(:category_id, category_id, "a thematic feed names its category")
        |> refuse_bound(:security_id, security_id, "a thematic feed names no security")

      :aggregator ->
        changeset
        |> refuse_bound(:security_id, security_id, "an aggregator feed names no security")
        |> refuse_bound(:category_id, category_id, "an aggregator feed names no category")

      nil ->
        changeset
    end
  end

  defp require_bound(changeset, field, nil, message), do: add_error(changeset, field, message)
  defp require_bound(changeset, _field, _id, _message), do: changeset

  defp refuse_bound(changeset, _field, nil, _message), do: changeset
  defp refuse_bound(changeset, field, _id, message), do: add_error(changeset, field, message)

  defp validate_last_ok(changeset) do
    last_ok_at = get_field(changeset, :last_ok_at)
    last_fetch_at = get_field(changeset, :last_fetch_at)

    cond do
      is_nil(last_ok_at) ->
        changeset

      is_nil(last_fetch_at) or DateTime.compare(last_ok_at, last_fetch_at) == :gt ->
        add_error(changeset, :last_ok_at, "must not be after the last fetch")

      true ->
        changeset
    end
  end

  defp validate_retry(changeset) do
    if get_field(changeset, :retry_at) && get_field(changeset, :failures) == 0,
      do: add_error(changeset, :retry_at, "is set only after a failure"),
      else: changeset
  end
end
