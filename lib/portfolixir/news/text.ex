defmodule Portfolixir.News.Text do
  @moduledoc """
  What the app makes of a feed's text (ADR-0056 §9, "Stored text is data";
  Sprint 27 plan D-6). A title or an excerpt is foreign text, and it leaves
  here as plain text that no surface ever renders as markup:

    1. **HTML is removed** by a single linear pass over the bytes: tags,
       comments, declarations and the content of `script` and `style`
       elements go; a block-level tag leaves a space, an inline one nothing.
       A `<` that opens no tag (`a < b`) is text. The pass never looks back,
       so its time is linear in the input whatever the input is: no regular
       expression runs on it.
    2. **Entities are decoded once, after it**: the five XML entities, a
       short table of the named entities feeds commonly carry, and numeric
       references to a valid code point. `&lt;script&gt;` therefore becomes
       the visible text `<script>`, which every surface escapes; it is never
       stripped again.
    3. **Control characters are removed**: tab, line feed and carriage
       return become a space, every other C0 control, DEL and every C1
       control goes. Bytes that are not UTF-8 become U+FFFD.
    4. **Whitespace collapses** to single spaces, the ends trimmed.
    5. **The length is capped**: 160 code points for a title, 600 for an
       excerpt, cut between graphemes, counted as PostgreSQL counts a
       text's length (`Portfolixir.Input.Text`).

  **Invisible characters are kept as received** (zero-width, bidirectional
  controls, the byte-order mark): dropping them would change the evidence,
  so the companion and the screen spell them `[U+XXXX]` instead (ADR-0054
  §4). Text that is empty after cleaning is `nil`.
  """

  alias Portfolixir.Input.Text, as: InputText

  @title_max 160
  @excerpt_max 600

  # Tags whose removal leaves a word break.
  @block_tags ~w(address article aside blockquote br dd div dl dt figcaption figure footer
                 h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre section table tbody td tfoot
                 th thead tr ul)

  # Tags whose content is not text.
  @raw_text_tags ~w(script style)

  # The longest tag name worth reading for the two lists above.
  @tag_name_max 10

  # The named entities decoded: the five of XML and those a feed's HTML
  # commonly carries. Anything else stays as written.
  @entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => "\u00A0",
    "ndash" => "–",
    "mdash" => "—",
    "lsquo" => "‘",
    "rsquo" => "’",
    "sbquo" => "‚",
    "ldquo" => "“",
    "rdquo" => "”",
    "bdquo" => "„",
    "laquo" => "«",
    "raquo" => "»",
    "hellip" => "…",
    "bull" => "•",
    "middot" => "·",
    "copy" => "©",
    "reg" => "®",
    "trade" => "™",
    "deg" => "°",
    "euro" => "€",
    "pound" => "£",
    "yen" => "¥",
    "cent" => "¢",
    "sect" => "§",
    "para" => "¶",
    "times" => "×",
    "divide" => "÷",
    "plusmn" => "±",
    "percnt" => "%",
    "auml" => "ä",
    "ouml" => "ö",
    "uuml" => "ü",
    "Auml" => "Ä",
    "Ouml" => "Ö",
    "Uuml" => "Ü",
    "szlig" => "ß",
    "aacute" => "á",
    "eacute" => "é",
    "iacute" => "í",
    "oacute" => "ó",
    "uacute" => "ú",
    "agrave" => "à",
    "egrave" => "è",
    "ccedil" => "ç",
    "ntilde" => "ñ",
    "Eacute" => "É"
  }

  @entity_name_max 8
  @reference_digits_max 7

  @doc "The code-point cap of a title."
  @spec title_max() :: pos_integer()
  def title_max, do: @title_max

  @doc "The code-point cap of an excerpt."
  @spec excerpt_max() :: pos_integer()
  def excerpt_max, do: @excerpt_max

  @doc "A feed's title as plain text of at most 160 code points, or nil."
  @spec title(String.t() | nil) :: String.t() | nil
  def title(raw), do: plain(raw, @title_max)

  @doc "A feed's excerpt as plain text of at most 600 code points, or nil."
  @spec excerpt(String.t() | nil) :: String.t() | nil
  def excerpt(raw), do: plain(raw, @excerpt_max)

  @doc """
  `raw` as plain text of at most `max` code points: HTML removed, entities
  decoded once, controls removed, whitespace collapsed. Nil when nothing is
  left.
  """
  @spec plain(String.t() | nil, pos_integer()) :: String.t() | nil
  def plain(nil, _max), do: nil

  def plain(raw, max) when is_binary(raw) and is_integer(max) and max > 0 do
    raw
    |> String.replace_invalid()
    |> strip_html()
    |> decode_entities()
    |> token(max)
  end

  @doc """
  `raw` with controls removed, whitespace collapsed and at most `max` code
  points, its markup left as text: for an identifier such as a guid. Nil
  when nothing is left.
  """
  @spec token(String.t() | nil, pos_integer()) :: String.t() | nil
  def token(nil, _max), do: nil

  def token(raw, max) when is_binary(raw) and is_integer(max) and max > 0 do
    raw
    |> String.replace_invalid()
    |> clean(max)
    |> cap(max)
    |> case do
      "" -> nil
      text -> text
    end
  end

  # -- 1. the tag stripper ---------------------------------------------------
  #
  # One pass over the bytes. Each clause consumes at least one byte or hands
  # the rest to a forward scan that starts where the pass stands
  # and never revisits a byte, so the work is linear in the input.

  defp strip_html(text), do: strip(text, <<>>)

  # The text up to the next `<` is copied whole; the `<` decides the rest.
  defp strip(text, acc) do
    case find_byte(text, ?<, 0) do
      :nomatch ->
        <<acc::binary, text::binary>>

      at ->
        rest = binary_part(text, at, byte_size(text) - at)
        markup(rest, <<acc::binary, binary_part(text, 0, at)::binary>>)
    end
  end

  defp markup(<<"<!--", rest::binary>>, acc), do: rest |> skip_past("-->") |> strip(acc)

  defp markup(<<"<", next, _::binary>> = text, acc)
       when next in ?a..?z or next in ?A..?Z or next in [?/, ?!, ??] do
    open_tag(text, acc)
  end

  # A `<` that opens no tag is text.
  defp markup(<<"<", rest::binary>>, acc), do: strip(rest, <<acc::binary, ?<>>)

  # A tag: its name decides whether it leaves a space or starts raw text;
  # the tag runs to the first `>` outside quotes.
  defp open_tag(<<"<", rest::binary>>, acc) do
    {closing?, after_slash} =
      case rest do
        <<"/", tail::binary>> -> {true, tail}
        _ -> {false, rest}
      end

    name = tag_name(after_slash, <<>>)
    rest = skip_tag(after_slash)
    acc = if name in @block_tags, do: <<acc::binary, ?\s>>, else: acc

    if name in @raw_text_tags and not closing? do
      rest |> skip_raw_text(name) |> strip(<<acc::binary, ?\s>>)
    else
      strip(rest, acc)
    end
  end

  defp tag_name(<<char, rest::binary>>, name)
       when byte_size(name) < @tag_name_max and
              (char in ?a..?z or char in ?A..?Z or char in ?0..?9) do
    tag_name(rest, <<name::binary, char>>)
  end

  defp tag_name(_rest, name), do: String.downcase(name)

  # Past the `>` that ends the tag, a quoted `>` not counting; an unclosed
  # tag or quote swallows the rest.
  defp skip_tag(<<">", rest::binary>>), do: rest

  defp skip_tag(<<quote, rest::binary>>) when quote in [?", ?'],
    do: rest |> skip_past_byte(quote) |> skip_tag()

  defp skip_tag(<<_byte, rest::binary>>), do: skip_tag(rest)
  defp skip_tag(<<>>), do: <<>>

  # Past the closing tag of a raw-text element (`</script` followed by a
  # character that ends a name), in any letter case; unclosed, the rest.
  defp skip_raw_text(text, name) do
    case find_byte(text, ?<, 0) do
      :nomatch ->
        <<>>

      at ->
        candidate = binary_part(text, at + 1, byte_size(text) - at - 1)
        size = byte_size(name)

        case candidate do
          <<"/", head::binary-size(size), boundary, _::binary>>
          when boundary in [?>, ?\s, ?\t, ?\n, ?\r, ?/] ->
            if String.downcase(head) == name,
              do: skip_tag(candidate),
              else: skip_raw_text(candidate, name)

          _ ->
            skip_raw_text(candidate, name)
        end
    end
  end

  # The position of the first `byte` in `text`, by a loop the VM runs on a
  # match context: no pattern is compiled per call.
  defp find_byte(<<byte, _::binary>>, byte, at), do: at
  defp find_byte(<<_other, rest::binary>>, byte, at), do: find_byte(rest, byte, at + 1)
  defp find_byte(<<>>, _byte, _at), do: :nomatch

  defp skip_past_byte(text, byte) do
    case find_byte(text, byte, 0) do
      :nomatch -> <<>>
      at -> binary_part(text, at + 1, byte_size(text) - at - 1)
    end
  end

  defp skip_past(text, marker) do
    case :binary.match(text, marker) do
      {at, size} -> binary_part(text, at + size, byte_size(text) - at - size)
      :nomatch -> <<>>
    end
  end

  # -- 2. entities, decoded once ---------------------------------------------

  defp decode_entities(text), do: decode_runs(text, <<>>)

  # The text up to the next `&` is copied whole; the `&` decides the rest.
  defp decode_runs(text, acc) do
    case find_byte(text, ?&, 0) do
      :nomatch ->
        <<acc::binary, text::binary>>

      at ->
        rest = binary_part(text, at, byte_size(text) - at)
        decode(rest, <<acc::binary, binary_part(text, 0, at)::binary>>)
    end
  end

  defp decode(<<"&#", rest::binary>>, acc) do
    {base, digits_from} =
      case rest do
        <<x, tail::binary>> when x in [?x, ?X] -> {16, tail}
        _ -> {10, rest}
      end

    case reference(digits_from, base, <<>>) do
      {:ok, code_point, tail} -> decode_runs(tail, <<acc::binary, code_point::utf8>>)
      :error -> decode_runs(rest, <<acc::binary, "&#">>)
    end
  end

  defp decode(<<"&", rest::binary>>, acc) do
    case entity(rest, <<>>) do
      {:ok, text, tail} -> decode_runs(tail, <<acc::binary, text::binary>>)
      :error -> decode_runs(rest, <<acc::binary, ?&>>)
    end
  end

  defp reference(<<";", rest::binary>>, base, digits) when digits != <<>> do
    code_point = String.to_integer(digits, base)

    if code_point <= 0x10FFFF and code_point not in 0xD800..0xDFFF,
      do: {:ok, code_point, rest},
      else: :error
  end

  defp reference(<<char, rest::binary>>, base, digits)
       when byte_size(digits) < @reference_digits_max and
              (char in ?0..?9 or (base == 16 and (char in ?a..?f or char in ?A..?F))) do
    reference(rest, base, <<digits::binary, char>>)
  end

  defp reference(_rest, _base, _digits), do: :error

  defp entity(<<";", rest::binary>>, name) when name != <<>> do
    case Map.fetch(@entities, name) do
      {:ok, text} -> {:ok, text, rest}
      :error -> :error
    end
  end

  defp entity(<<char, rest::binary>>, name)
       when byte_size(name) < @entity_name_max and
              (char in ?a..?z or char in ?A..?Z or char in ?0..?9) do
    entity(rest, <<name::binary, char>>)
  end

  defp entity(_rest, _name), do: :error

  # -- 3. and 4. controls and whitespace -------------------------------------
  #
  # One pass over the code points: whitespace sets a pending space, written
  # only before the next kept character, so runs collapse and the ends trim.
  # The pass stops once it has kept one code point more than the cap, enough
  # for the cap to cut between graphemes exactly.

  # Unicode's White_Space set; the bidirectional marks are not in it, and
  # stay as the invisible characters they are.
  @spaces [?\s, ?\t, ?\n, ?\r, ?\v, ?\f, 0x00A0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000] ++
            Enum.to_list(0x2000..0x200A)

  defp clean(text, max), do: clean(text, <<>>, :start, max + 1)

  defp clean(_text, acc, _state, 0), do: acc

  defp clean(<<cp::utf8, rest::binary>>, acc, state, left) when cp in @spaces,
    do: clean(rest, acc, if(state == :start, do: :start, else: :pending), left)

  defp clean(<<cp::utf8, rest::binary>>, acc, state, left)
       when cp < 0x20 or cp in 0x7F..0x9F,
       do: clean(rest, acc, state, left)

  defp clean(<<cp::utf8, rest::binary>>, acc, :pending, left) when left >= 2,
    do: clean(rest, <<acc::binary, ?\s, cp::utf8>>, :text, left - 2)

  defp clean(<<_cp::utf8, _rest::binary>>, acc, :pending, _left),
    do: <<acc::binary, ?\s>>

  defp clean(<<cp::utf8, rest::binary>>, acc, _state, left),
    do: clean(rest, <<acc::binary, cp::utf8>>, :text, left - 1)

  defp clean(<<>>, acc, _state, _left), do: acc

  # -- 5. the cap -------------------------------------------------------------

  # Whole graphemes while their code points fit; stops at the cap without
  # walking the rest.
  defp cap(text, max), do: cap(text, max, <<>>)

  defp cap(text, budget, acc) do
    case String.next_grapheme(text) do
      {grapheme, rest} ->
        cost = InputText.codepoint_length(grapheme)

        if cost <= budget,
          do: cap(rest, budget - cost, <<acc::binary, grapheme::binary>>),
          else: String.trim_trailing(acc, " ")

      nil ->
        acc
    end
  end
end
