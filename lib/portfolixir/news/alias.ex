defmodule Portfolixir.News.Alias do
  @moduledoc """
  One alias of a security's news identity (ADR-0056 §2), embedded in
  `securities.news_aliases`.

    * `token` — a name or a symbol, matched **literally** as a word or a
      run of words, with a word boundary around it: 1 to 64 characters,
      none of a pattern's characters (`\\ * ? [ ] ( ) { } | ^ $`), no
      control or invisible characters. **No regular expression is accepted
      from input** (§2): a pattern from data would run against foreign text,
      and the matcher tokenizes a sentence and looks words up instead, with
      no backtracking at all.
    * `context` — optional words, one of which must appear in the same
      sentence (a ticker that is also an English word, matched only beside
      "stock", "shares" or the company's name): each one word of at most 64
      characters under the same rule, at most 20, stored trimmed and without
      repeats; none is an empty list.
    * `case` — `sensitive` or `insensitive`, always stated.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text

  @derive {Jason.Encoder, only: [:token, :context, :case]}
  @primary_key false

  @token_max 64
  @context_max 20
  # The characters that make a string a pattern in the common syntaxes. A
  # dot, a hyphen, an ampersand or an apostrophe are literal in a name
  # ("BRK.B", "Procter & Gamble") and stay allowed.
  @pattern_characters ~r/[\\*?\[\](){}|^$]/

  @type t :: %__MODULE__{}

  embedded_schema do
    field(:token, :string)
    field(:context, {:array, :string}, default: [])
    field(:case, Ecto.Enum, values: [:sensitive, :insensitive])
  end

  @doc "The most aliases a security carries."
  @spec max_aliases() :: pos_integer()
  def max_aliases, do: 50

  @doc "Casts and checks one alias."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(alias_row, attrs) do
    alias_row
    |> cast(attrs, [:token, :context, :case])
    |> update_change(:token, &String.trim/1)
    |> update_change(:context, fn words -> words |> Enum.map(&String.trim/1) |> Enum.uniq() end)
    |> put_default_context()
    |> validate_required([:token, :case])
    |> Text.validate(:token, max: @token_max)
    |> validate_change(:token, fn :token, token ->
      if Regex.match?(@pattern_characters, token),
        do: [token: "is matched literally as a name or symbol; patterns are not accepted"],
        else: []
    end)
    |> validate_length(:context, max: @context_max)
    |> validate_context_words()
  end

  defp put_default_context(changeset) do
    if is_nil(get_field(changeset, :context)),
      do: put_change(changeset, :context, []),
      else: changeset
  end

  defp validate_context_words(changeset) do
    validate_change(changeset, :context, fn :context, words ->
      if Enum.all?(words, &context_word?/1),
        do: [],
        else: [context: "each word is one word of at most 64 characters, matched literally"]
    end)
  end

  defp context_word?(word) do
    word != "" and Text.check(word, max: @token_max) == :ok and
      not String.match?(word, ~r/\s/u) and not Regex.match?(@pattern_characters, word)
  end
end
