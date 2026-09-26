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
    * **invisible characters** (E25 S7, G20): the Unicode tag characters
      (U+E0000–U+E007F), the bidirectional controls (U+061C, U+200E, U+200F,
      U+202A–U+202E, U+2066–U+2069), the other invisible format characters
      (the soft hyphen U+00AD, U+180E, the zero-width space and joiners
      U+200B–U+200D, U+2060–U+2065, U+206A–U+206F, the byte-order mark
      U+FEFF, U+FFF9–U+FFFB, U+1BCA0–U+1BCA3, U+1D173–U+1D17A) and a run of
      two or more variation selectors (U+FE00–U+FE0F, U+E0100–U+E01EF; one
      selector alone is an emoji's presentation and passes). They render as
      nothing on the operator's screen but reach an agent intact, so text
      that carries them could hide an instruction in a record the operator
      reviewed. One exception keeps emoji whole (E25 S7 review round,
      S7E-3): the zero-width joiner U+200D passes where it **joins two
      pictographs** — the character before it is a pictograph, or a VS16
      (U+FE0F) right after one, and the character after it is one — since
      there it renders as the one glyph it builds (a person at a laptop, a
      family, the rainbow flag). A pictograph here is U+00A9, U+00AE,
      U+203C, U+2049, U+2122, U+2139, U+2190–U+21FF, U+2300–U+23FF, U+24C2,
      U+25A0–U+27BF, U+2934–U+2935, U+2B00–U+2BFF, U+3030, U+303D, U+3297,
      U+3299 or U+1F000–U+1FAFF (a written-out superset of Unicode's
      Extended_Pictographic below U+1FB00, skin tones included). The tag
      characters stay refused, and with them the three subdivision flags
      built from them; so does the zero-width non-joiner U+200C, which some
      scripts' words carry. `escape_invisible/1` spells each refused
      character as `[U+XXXX]` — the spelling the MCP companion gives the
      agent and the screen gives the operator for a row stored before the
      rule — and `invisible_count/1` counts them;
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

  # E25 S7, G20: the characters an operator cannot see. The ranges are
  # written out rather than read from the Unicode tables (`\p{Cf}`), so this
  # module and the MCP companion's escape (mcp-server/src/invisible-text.ts)
  # name the same set whatever Unicode version either runtime ships; the
  # shared cases in mcp-server/test/fixtures/invisible-text.json pin both.
  #
  # The alternatives: every refused format character but the zero-width
  # joiner; a joiner not preceded by a pictograph (or a pictograph and a
  # VS16); a joiner not followed by a pictograph (S7E-3); a run of variation
  # selectors.
  @pictograph "\\x{00A9}\\x{00AE}\\x{203C}\\x{2049}\\x{2122}\\x{2139}\\x{2190}-\\x{21FF}\\x{2300}-\\x{23FF}\\x{24C2}\\x{25A0}-\\x{27BF}\\x{2934}\\x{2935}\\x{2B00}-\\x{2BFF}\\x{3030}\\x{303D}\\x{3297}\\x{3299}\\x{1F000}-\\x{1FAFF}"
  @invisible ~r/[\x{00AD}\x{061C}\x{180E}\x{200B}\x{200C}\x{200E}\x{200F}\x{202A}-\x{202E}\x{2060}-\x{206F}\x{FEFF}\x{FFF9}-\x{FFFB}\x{1BCA0}-\x{1BCA3}\x{1D173}-\x{1D17A}\x{E0000}-\x{E007F}]|(?<![#{@pictograph}])(?<![#{@pictograph}]\x{FE0F})\x{200D}|\x{200D}(?![#{@pictograph}])|[\x{FE00}-\x{FE0F}\x{E0100}-\x{E01EF}]{2,}/u

  # How many distinct characters a field error names.
  @named_characters 5

  @type opts :: [max: pos_integer(), multiline: boolean()]
  @type refusal :: :invalid_encoding | :control_characters | :invisible_characters | :too_long

  # The code-point caps of free text in a `text` column (E25 S6, G01, G02):
  # the column bounds nothing itself, and the journal copies a row whole on
  # every change, so the changeset bounds it and a CHECK of the same number
  # stands behind it (the migrations name the number, since they are frozen).
  @free_text_max 10_000
  @entry_body_max 20_000

  @doc """
  The code-point cap of a free-text note or description: a record's notes, an
  event's note, a rule version's note, a thesis's invalidation condition.
  """
  @spec free_text_max() :: pos_integer()
  def free_text_max, do: @free_text_max

  @doc "The code-point cap of a research-log entry's body."
  @spec entry_body_max() :: pos_integer()
  def entry_body_max, do: @entry_body_max

  # A security's free-form attributes, as stored after a write merges them
  # with the stored ones (E25 S6, G02): at most this many bytes as compact
  # JSON. The database CHECK behind it bounds the jsonb's text form at twice
  # this, which a map the changeset accepts never reaches (the text form adds
  # at most a space after each separator).
  @attributes_max_bytes 65_536

  @doc "The byte bound of a security's attributes map, encoded as compact JSON."
  @spec attributes_max_bytes() :: pos_integer()
  def attributes_max_bytes, do: @attributes_max_bytes

  @doc """
  The verdict on one value: `:ok` or the first refusal. `nil` is `:ok`.
  """
  @spec check(term(), opts()) :: :ok | {:error, refusal()}
  def check(nil, _opts), do: :ok

  def check(value, opts) when is_binary(value) do
    cond do
      not String.valid?(value) -> {:error, :invalid_encoding}
      Regex.match?(controls(opts), value) -> {:error, :control_characters}
      Regex.match?(@invisible, value) -> {:error, :invisible_characters}
      too_long?(value, opts[:max]) -> {:error, :too_long}
      true -> :ok
    end
  end

  def check(_value, _opts), do: :ok

  @doc """
  How many invisible characters (see the moduledoc) `text` carries: every
  refused code point, each selector of a run. `0` for `nil`, for text
  without any and for text that is not valid UTF-8.
  """
  @spec invisible_count(String.t() | nil) :: non_neg_integer()
  def invisible_count(text) when is_binary(text) do
    if String.valid?(text) do
      @invisible
      |> Regex.scan(text)
      |> Enum.reduce(0, fn [match], acc -> acc + codepoint_length(match) end)
    else
      0
    end
  end

  def invisible_count(_text), do: 0

  @doc """
  `text` with every invisible character spelled `[U+XXXX]` (upper-case hex,
  at least four digits) and every other character as it is: what the screen
  shows in a stored row's disclosure (pick G12.2 = B) and what the MCP
  companion hands the agent. Text that is not valid UTF-8 is returned as it
  is.
  """
  @spec escape_invisible(String.t()) :: String.t()
  def escape_invisible(text) when is_binary(text) do
    if String.valid?(text) do
      Regex.replace(@invisible, text, fn match ->
        match |> String.to_charlist() |> Enum.map_join(&spell/1)
      end)
    else
      text
    end
  end

  @doc "The code points of the invisible characters in `text`, distinct, in order."
  @spec invisible_characters(String.t()) :: [String.t()]
  def invisible_characters(text) when is_binary(text) do
    @invisible
    |> Regex.scan(text)
    |> Enum.flat_map(fn [match] -> String.to_charlist(match) end)
    |> Enum.uniq()
    |> Enum.map(&code_point/1)
  end

  defp spell(code_point), do: "[" <> code_point(code_point) <> "]"

  defp code_point(code_point),
    do: "U+" <> (code_point |> Integer.to_string(16) |> String.pad_leading(4, "0"))

  @doc "The field error message for a refusal."
  @spec message(refusal(), opts()) :: {String.t(), keyword()}
  def message(:invalid_encoding, _opts),
    do: {"must be valid UTF-8 text", validation: :text}

  def message(:invisible_characters, _opts),
    do:
      {"must not contain invisible characters (%{characters}); retype the text without them",
       characters: "format, bidirectional or tag characters", validation: :text}

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

        {:error, :invisible_characters} ->
          [{field, invisible_message(value)}]

        {:error, refusal} ->
          {message, keys} = message(refusal, opts)
          [{field, {message, keys}}]
      end
    end)
  end

  # The refusal names what it found (E25 S7, G20), since the operator cannot
  # see it: "U+200B, U+00AD".
  defp invisible_message(value) do
    {message, keys} = message(:invisible_characters, [])

    named =
      case invisible_characters(value) do
        found when length(found) > @named_characters ->
          Enum.join(Enum.take(found, @named_characters), ", ") <> ", …"

        found ->
          Enum.join(found, ", ")
      end

    {message, Keyword.put(keys, :characters, named)}
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

  defp map_message(:invisible_characters, _opts),
    do:
      {"must not contain invisible characters (format, bidirectional or tag characters)",
       validation: :text}

  defp map_message(:too_long, opts),
    do:
      {"must have keys of at most %{count} character(s)",
       count: Keyword.get(opts, :key_max, 255), validation: :text}

  @doc """
  Refuses a change of the map `field` whose compact JSON encoding is longer
  than `max_bytes:` bytes (E25 S6, G02). Run it on the map as it will be
  stored, after any merge with the stored map.
  """
  @spec validate_map_size(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_map_size(changeset, field, opts) when is_atom(field) do
    max = Keyword.fetch!(opts, :max_bytes)

    validate_change(changeset, field, fn ^field, value ->
      case Jason.encode(value) do
        {:ok, json} when byte_size(json) <= max ->
          []

        _too_large_or_unencodable ->
          [{field, {"must be at most %{count} bytes as JSON", count: max, validation: :length}}]
      end
    end)
  end

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
