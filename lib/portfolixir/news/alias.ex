defmodule Portfolixir.News.Alias do
  @moduledoc """
  One alias of a security's news identity (ADR-0056 §2), embedded in
  `securities.news_aliases`.

    * `token` — a name or a symbol, matched **literally** as a word or a
      run of words, with a word boundary around it: 1 to 64 characters,
      none of a pattern's characters (`\\ * ? [ ] ( ) { } | ^ $`), no
      control or invisible characters, and at least one letter or digit
      (a token of punctuation alone matches nearly anything). **No regular expression is accepted
      from input** (§2): a pattern from data would run against foreign text,
      and the matcher tokenizes a sentence and looks words up instead, with
      no backtracking at all.
    * `context` — optional words, one of which must appear in the same
      sentence (a ticker that is also an English word, matched only beside
      "stock", "shares" or the company's name): each one word of at most 64
      characters under the same rule, at most 20, stored trimmed and without
      repeats; none (or `null`) is an empty list, and a blank word is
      refused.
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
  # Closing act, POLISH: a token holds at least one letter or digit; a
  # single letter stays allowed (one-letter tickers exist).
  @letter_or_digit ~r/[\p{L}\p{N}]/u

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
    |> cast(attrs, [:token, :case])
    # A blank context word is not dropped by the cast (Ecto drops blank list
    # elements by default), so the check below refuses it (EDGE3).
    |> cast(attrs, [:context], empty_values: [nil])
    |> update_change(:token, &String.trim/1)
    |> update_change(:context, &trim_words/1)
    |> put_default_context()
    |> validate_required([:token, :case])
    |> Text.validate(:token, max: @token_max)
    |> validate_change(:token, fn :token, token ->
      cond do
        Regex.match?(@pattern_characters, token) ->
          [token: "is matched literally as a name or symbol; patterns are not accepted"]

        not Regex.match?(@letter_or_digit, token) ->
          [
            token:
              "must hold a letter or a digit: a token of punctuation alone matches nearly anything"
          ]

        true ->
          []
      end
    end)
    |> validate_length(:context, max: @context_max)
    |> validate_context_words()
  end

  # Closing act, EDGE3: a `null` context is none (no crash); a blank word is
  # kept blank here, so `validate_context_words/1` refuses it instead of the
  # alias turning unconditional in silence.
  defp trim_words(nil), do: []
  defp trim_words(words), do: words |> Enum.map(&String.trim/1) |> Enum.uniq()

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
