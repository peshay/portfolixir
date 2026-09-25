defmodule Portfolixir.Input.Text do
  @moduledoc """
  The one rule for text a writer stores (E25 S4, G24 and G17).

  PostgreSQL refuses a NUL character in any text value and a varchar value
  longer than its column, counted in **code points**; Ecto's default length
  count is graphemes, so a name made of combining marks passed the changeset
  and failed in the database. A refusal there is a server error, not a field
  error. This module refuses the same values first, with a field error:

    * invalid UTF-8;
    * NUL and every other C0 control character, DEL and the C1 controls —
      except tab, line feed and carriage return in text that is multi-line by
      nature (`multiline: true`: notes, descriptions);
    * a value longer than `max:` code points, when given.

  `validate/3` is the changeset form every schema uses; `check/2` returns the
  same verdict for a value outside a changeset, so the import parsers name the
  row that carries it before anything is written. `validate_map/3` and
  `check_map/2` apply the rule to a free-form map stored as `jsonb` (a
  security's `attributes`) at any depth: PostgreSQL refuses a NUL there too,
  in a key or in a value.
  """

  import Ecto.Changeset

  # C0 minus tab, line feed and carriage return; DEL; C1.
  @multiline_controls ~r/[\x{0}-\x{8}\x{B}\x{C}\x{E}-\x{1F}\x{7F}-\x{9F}]/u
  @single_line_controls ~r/[\x{0}-\x{1F}\x{7F}-\x{9F}]/u

  @type opts :: [max: pos_integer(), multiline: boolean()]
  @type refusal :: :invalid_encoding | :control_characters | :too_long

  @doc """
  The verdict on one value: `:ok` or the first refusal. `nil` is `:ok`.
  """
  @spec check(term(), opts()) :: :ok | {:error, refusal()}
  def check(nil, _opts), do: :ok

  def check(value, opts) when is_binary(value) do
    cond do
      not String.valid?(value) -> {:error, :invalid_encoding}
      Regex.match?(controls(opts), value) -> {:error, :control_characters}
      too_long?(value, opts[:max]) -> {:error, :too_long}
      true -> :ok
    end
  end

  def check(_value, _opts), do: :ok

  @doc "The field error message for a refusal."
  @spec message(refusal(), opts()) :: {String.t(), keyword()}
  def message(:invalid_encoding, _opts),
    do: {"must be valid UTF-8 text", validation: :text}

  def message(:control_characters, opts) do
    if opts[:multiline],
      do:
        {"must not contain control characters other than tabs and line breaks", validation: :text},
      else: {"must not contain control characters or line breaks", validation: :text}
  end

  def message(:too_long, opts),
    do:
      {"should be at most %{count} character(s)",
       count: opts[:max], validation: :length, kind: :max, type: :string}

  @doc """
  Adds the rule to a changeset for each of `fields` (one atom or a list).
  Options: `max:` (code points) and `multiline:` (default `false`).
  """
  @spec validate(Ecto.Changeset.t(), atom() | [atom()], opts()) :: Ecto.Changeset.t()
  def validate(changeset, fields, opts \\ [])

  def validate(changeset, fields, opts) when is_list(fields) do
    Enum.reduce(fields, changeset, &validate(&2, &1, opts))
  end

  def validate(changeset, field, opts) when is_atom(field) do
    validate_change(changeset, field, fn ^field, value ->
      case check(value, opts) do
        :ok ->
          []

        {:error, refusal} ->
          {message, keys} = message(refusal, opts)
          [{field, {message, keys}}]
      end
    end)
  end

  @doc """
  The verdict on a free-form map at any depth: every key is one-line text of
  at most `key_max:` code points (default 255); every string value, in a
  nested map or list too, is text by `multiline:` (default `true`: a value is
  free text and keeps its tabs and line breaks). A number, a boolean or `nil`
  passes; a key that is not a string is `:invalid_key`.
  """
  @spec check_map(term(), keyword()) :: :ok | {:error, refusal() | :invalid_key}
  def check_map(value, opts \\ []) do
    key_opts = [max: Keyword.get(opts, :key_max, 255)]
    value_opts = [multiline: Keyword.get(opts, :multiline, true)]
    walk(value, key_opts, value_opts)
  end

  defp walk(map, key_opts, value_opts) when is_map(map) do
    Enum.reduce_while(map, :ok, fn {key, nested}, :ok ->
      map_entry(key, nested, key_opts, value_opts)
    end)
  end

  defp walk(list, key_opts, value_opts) when is_list(list) do
    Enum.reduce_while(list, :ok, fn nested, :ok ->
      halt_on_refusal(walk(nested, key_opts, value_opts))
    end)
  end

  defp walk(text, _key_opts, value_opts) when is_binary(text), do: check(text, value_opts)
  defp walk(_scalar, _key_opts, _value_opts), do: :ok

  defp map_entry(key, nested, key_opts, value_opts) when is_binary(key) do
    case check(key, key_opts) do
      :ok -> halt_on_refusal(walk(nested, key_opts, value_opts))
      refused -> {:halt, refused}
    end
  end

  defp map_entry(_key, _nested, _key_opts, _value_opts), do: {:halt, {:error, :invalid_key}}

  defp halt_on_refusal(:ok), do: {:cont, :ok}
  defp halt_on_refusal(refused), do: {:halt, refused}

  @doc """
  Adds `check_map/2` to a changeset's map `field` (options as there), with
  one field error per refusal.
  """
  @spec validate_map(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_map(changeset, field, opts \\ []) when is_atom(field) do
    validate_change(changeset, field, fn ^field, value ->
      case check_map(value, opts) do
        :ok -> []
        {:error, refusal} -> [{field, map_message(refusal, opts)}]
      end
    end)
  end

  defp map_message(:invalid_key, _opts), do: {"must have text keys", validation: :text}
  defp map_message(:invalid_encoding, _opts), do: {"must be valid UTF-8 text", validation: :text}

  defp map_message(:control_characters, _opts),
    do:
      {"must not contain control characters (a value keeps its tabs and line breaks)",
       validation: :text}

  defp map_message(:too_long, opts),
    do:
      {"must have keys of at most %{count} character(s)",
       count: Keyword.get(opts, :key_max, 255), validation: :text}

  @doc """
  The length of `text` in Unicode code points, the unit the database counts
  a column's width in (a grapheme can be several code points).
  """
  @spec codepoint_length(String.t()) :: non_neg_integer()
  def codepoint_length(text) when is_binary(text), do: text |> String.codepoints() |> length()

  @doc """
  Cuts `text` to at most `max` code points without splitting a grapheme: the
  bound a name a context derives itself (a copy's name, a seeded name) must
  meet, counted the way `validate/3` counts it.
  """
  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  def truncate(text, max) when is_binary(text) and is_integer(max) and max >= 0 do
    text
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {kept, count} ->
      count = count + codepoint_length(grapheme)
      if count <= max, do: {:cont, {[grapheme | kept], count}}, else: {:halt, {kept, count}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
  end

  # Unicode format characters (general category Cf): zero-width spaces and
  # joiners, the byte-order mark, the soft hyphen, bidirectional controls.
  @format_characters ~r/\p{Cf}/u

  @doc """
  `text` without its Unicode format characters (general category `Cf`: the
  zero-width space and joiners, the word joiner, the byte-order mark, the
  soft hyphen, the bidirectional controls). They render as nothing, so two
  names that differ only by them look identical (E25 S5, G23). Text that is
  not valid UTF-8 is returned unchanged for `check/2` to refuse.
  """
  @spec strip_format_characters(String.t()) :: String.t()
  def strip_format_characters(text) when is_binary(text) do
    if String.valid?(text), do: String.replace(text, @format_characters, ""), else: text
  end

  defp controls(opts) do
    if opts[:multiline], do: @multiline_controls, else: @single_line_controls
  end

  defp too_long?(_value, nil), do: false
  defp too_long?(value, max), do: codepoint_length(value) > max
end
