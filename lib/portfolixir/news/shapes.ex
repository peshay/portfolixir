defmodule Portfolixir.News.Shapes do
  @moduledoc """
  The value shapes the news tables share (ADR-0056 §3, §4, B2), as
  changeset validations. Each mirrors a CHECK of the `create_news_tables`
  migration, so a changeset refuses with a field error what the database
  would refuse with a constraint error.
  """
  import Ecto.Changeset

  alias Portfolixir.Input.Text

  @classes ~w(issuer regulatory aggregator thematic)a
  @tiers ~w(primary secondary awareness blocked)a
  # A stored item or story is never `blocked`: a blocked domain's items are
  # dropped at ingest (§3).
  @stored_tiers ~w(primary secondary awareness)a

  @url_max 2048
  @domain_max 253
  @domain ~r/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\z/
  @language ~r/\A[a-z]{2,3}(-[a-z0-9]{1,5})?\z/
  @hex64 ~r/\A[0-9a-f]{64}\z/
  # A feed's URL (B2): https, a host of letters, digits, dots and hyphens
  # (an international name in its punycode form), an optional port, no
  # userinfo, no whitespace. "Whitespace" is Unicode's (`/u`: U+3000, U+2028,
  # U+2000 to U+200A, U+1680, U+00A0 and the rest), at least what the
  # migration's `[^[:space:]]` refuses, so the database never refuses a URL
  # the changeset let through (closing act, SEC2/EDGE1).
  @feed_url ~r/\Ahttps:\/\/[A-Za-z0-9.-]+(:[0-9]{1,5})?([\/?#]\S*)?\z/u
  # An item's link: shown, never fetched (§2 follows no redirect), so http
  # is kept as the publisher gave it.
  @item_url ~r/\Ahttps?:\/\/\S+\z/u
  @space ~r/\s/u

  @doc "The four feed classes (§2)."
  @spec classes() :: [atom()]
  def classes, do: @classes

  @doc "The four tiers a source can carry (§3)."
  @spec tiers() :: [atom()]
  def tiers, do: @tiers

  @doc "The tiers a stored item or story can carry: every tier but `blocked`."
  @spec stored_tiers() :: [atom()]
  def stored_tiers, do: @stored_tiers

  @doc "The longest URL a feed or an item stores."
  @spec url_max() :: pos_integer()
  def url_max, do: @url_max

  @doc """
  Whether `text` holds a Unicode space (`\\s` with `/u`), the class the URL
  shapes refuse; the parser drops a link that holds one.
  """
  @spec space?(String.t()) :: boolean()
  def space?(text) when is_binary(text), do: Regex.match?(@space, text)

  @doc "Trims and lower-cases a domain, then checks its shape."
  @spec domain(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def domain(changeset, field) do
    changeset
    |> update_change(field, &normalize/1)
    |> validate_length(field, max: @domain_max, count: :codepoints)
    |> validate_format(field, @domain,
      message: "is not a domain (lower-case letters, digits, dots and hyphens)"
    )
  end

  @doc "Trims and lower-cases a language code, then checks its shape (2 to 8 characters)."
  @spec language(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def language(changeset, field) do
    changeset
    |> update_change(field, &normalize/1)
    |> validate_format(field, @language,
      message: "is not a language code (\"en\", \"de\", \"pt-br\")"
    )
  end

  @doc "Checks a feed's URL: https, no userinfo, no whitespace, bounded."
  @spec feed_url(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def feed_url(changeset, field) do
    changeset
    |> update_change(field, &trim/1)
    |> validate_length(field, max: @url_max, count: :codepoints)
    |> validate_format(field, @feed_url,
      message: "must be an https URL without user name, password or spaces"
    )
  end

  @doc "Checks an item's link: http or https, no whitespace, bounded."
  @spec item_url(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def item_url(changeset, field) do
    changeset
    |> validate_length(field, max: @url_max, count: :codepoints)
    |> validate_format(field, @item_url, message: "must be an http or https URL without spaces")
  end

  @doc "Checks a SHA-256 digest in lower-case hex."
  @spec hex64(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def hex64(changeset, field),
    do: validate_format(changeset, field, @hex64, message: "must be 64 lower-case hex digits")

  @doc """
  Checks foreign text a feed supplied (§9; plan D-6): valid UTF-8, at most
  `max` characters, no control characters (line breaks allowed with
  `multiline: true`), and **invisible characters kept as received** — they
  are evidence, spelled `[U+XXXX]` by the companion and the screen
  (ADR-0054 §4), never refused or dropped here.
  """
  @spec feed_text(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def feed_text(changeset, field, opts) do
    max = Keyword.fetch!(opts, :max)

    controls =
      if opts[:multiline],
        do: ~r/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]/u,
        else: ~r/[\x00-\x1f\x7f-\x9f]/u

    validate_change(changeset, field, fn ^field, value ->
      cond do
        not String.valid?(value) ->
          [{field, {"must be valid UTF-8 text", validation: :text}}]

        Text.codepoint_length(value) > max ->
          [{field, {"should be at most %{count} character(s)", count: max, validation: :length}}]

        Regex.match?(controls, value) ->
          [{field, {"must not contain control characters", validation: :text}}]

        true ->
          []
      end
    end)
  end

  defp normalize(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize(value), do: value

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
