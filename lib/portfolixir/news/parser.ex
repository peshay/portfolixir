defmodule Portfolixir.News.Parser.Item do
  @moduledoc """
  One item of a news feed as the parser hands it over (ADR-0056 A1): plain
  text and checked values only, never the feed's XML.

    * `title`, `excerpt` — plain text (`Portfolixir.News.Text`), capped at
      160 and 600 code points; nil when the feed sent none.
    * `link` — an absolute `http` or `https` URL of at most 2,048 bytes, or
      nil.
    * `guid` — RSS `guid` or Atom `id` as plain text of at most 512 code
      points, or nil.
    * `published_at` — a UTC `DateTime` to the second, or nil when the feed's
      date is missing or unreadable.
    * `source_domain` — the lower-cased host of the item's original source
      (RSS `<source url=…>`, Atom `<source>`'s alternate link), or nil.
  """

  defstruct [:title, :link, :guid, :published_at, :excerpt, :source_domain]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          link: String.t() | nil,
          guid: String.t() | nil,
          published_at: DateTime.t() | nil,
          excerpt: String.t() | nil,
          source_domain: String.t() | nil
        }
end

defmodule Portfolixir.News.Parser do
  @moduledoc """
  The news feed parser (ADR-0056 A1; Sprint 27 plan D-7). A feed is XML from
  a host the operator registered and does not control, so this is a
  hostile-input surface in its own right. It reads **RSS 2.0 and Atom 1.0
  only**, into `Portfolixir.News.Parser.Item` structs, and:

    * **parses at most `max_bytes/0`** (8 MiB, the cap the fetcher's bounded
      client is given): a longer body is refused before a byte is parsed;
    * **reads UTF-8, and Latin-1 by transcoding** (#1442): one UTF-8
      byte-order mark is skipped; a body declaring ISO-8859-1 or US-ASCII
      (regulators' Atom feeds do) is transcoded to UTF-8, its UTF-8 size
      held to the same cap before anything is transcoded; every other
      declared encoding is refused;
    * **processes no document type declaration**: a document whose prolog
      carries one (or any other `<!` declaration) is refused before the XML
      reader sees it, so no external entity is resolved (no file, no URL)
      and no internal entity is expanded. Behind that, the reader
      (`Saxy`, SAX mode) is told to keep an undeclared entity reference as
      the text it is; only the five predefined entities and numeric
      character references are decoded;
    * **never turns a name into an atom**: element and attribute names are
      compared as binaries (Saxy makes no atom either);
    * **refuses nesting deeper than 64 and more than 5,000 items** at the
      start tag that breaches the bound, reading nothing past it;
    * runs under `Portfolixir.Net.ParseGuard`'s wall-clock bound.

  A refusal is `{:error, {:parse_refused, reason}}`, its reason one of
  `refusal_reasons/0`; the fetcher records it as the feed's `last_error`
  and it never stops another feed.
  """

  @behaviour Saxy.Handler

  alias Portfolixir.Net.ParseGuard
  alias Portfolixir.News.Parser.Item
  alias Portfolixir.News.Shapes
  alias Portfolixir.News.Text

  @max_bytes 8 * 1024 * 1024
  @max_depth 64
  @max_items 5_000
  @guid_max 512
  @link_max_bytes 2_048
  @date_max_bytes 64
  @timeout_ms 5_000

  @atom_namespace "http://www.w3.org/2005/Atom"

  @refusal_reasons [
    :too_large,
    :dtd,
    :too_deep,
    :too_many_items,
    :malformed,
    :unsupported_encoding,
    :not_a_feed,
    :timeout,
    :failed
  ]

  # The child elements of an item whose text is read, by format.
  @rss_fields ~w(title link guid pubDate dc:date description content:encoded)
  @atom_fields ~w(title id published updated summary content)

  @type reason ::
          :too_large
          | :dtd
          | :too_deep
          | :too_many_items
          | :malformed
          | :unsupported_encoding
          | :not_a_feed
          | :timeout
          | :failed

  @type feed :: %{format: :rss | :atom, items: [Item.t()]}

  @typedoc """
  How far a scan got: the start tags it read, the deepest level it reached,
  the items it began and the bytes of the body it left unread.
  """
  @type stats :: %{
          elements: non_neg_integer(),
          depth: non_neg_integer(),
          items: non_neg_integer(),
          unread: non_neg_integer()
        }

  @doc "The byte cap of a feed's body: the fetcher's bounded client uses it too."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "The deepest nesting a feed may have."
  @spec max_depth() :: pos_integer()
  def max_depth, do: @max_depth

  @doc "The most items one feed answer may carry."
  @spec max_items() :: pos_integer()
  def max_items, do: @max_items

  @doc "The code-point cap of an item's guid."
  @spec guid_max() :: pos_integer()
  def guid_max, do: @guid_max

  @doc "Every reason a refusal can carry."
  @spec refusal_reasons() :: [reason()]
  def refusal_reasons, do: @refusal_reasons

  @doc """
  Parses a feed's body under `Portfolixir.Net.ParseGuard`. Options:
  `:timeout_ms` (default 5 s).
  """
  @spec parse(binary(), keyword()) :: {:ok, feed()} | {:error, {:parse_refused, reason()}}
  def parse(body, opts \\ []) when is_binary(body) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @timeout_ms)

    case ParseGuard.run(fn -> scan(body) end, timeout_ms) do
      {:ok, {:ok, feed, _stats}} -> {:ok, feed}
      {:ok, {:refused, reason, _stats}} -> {:error, {:parse_refused, reason}}
      {:error, :parse_timeout} -> {:error, {:parse_refused, :timeout}}
      {:error, {:parse_failed, _reason}} -> {:error, {:parse_refused, :failed}}
    end
  end

  @doc """
  The parse itself, in the caller's process, with how far it got: what
  `parse/2` runs under its guard, and what the attack tests read to prove a
  refusal stopped at its bound.
  """
  @spec scan(binary()) :: {:ok, feed(), stats()} | {:refused, reason(), stats()}
  def scan(body) when is_binary(body) do
    cond do
      byte_size(body) > @max_bytes ->
        {:refused, :too_large, unread(body)}

      declares_dtd?(body) ->
        {:refused, :dtd, unread(body)}

      true ->
        case to_utf8(body) do
          {:ok, utf8} -> read(utf8)
          {:refused, reason} -> {:refused, reason, unread(body)}
        end
    end
  end

  defp unread(body), do: %{elements: 0, depth: 0, items: 0, unread: byte_size(body)}

  defp read(body) do
    case Saxy.parse_string(body, __MODULE__, initial_state(), expand_entity: :keep) do
      {:ok, %{format: format} = state} when format != nil ->
        {:ok, %{format: format, items: Enum.reverse(state.done)}, stats(state, 0)}

      {:ok, state} ->
        {:refused, :not_a_feed, stats(state, 0)}

      {:halt, {:refused, reason, state}, rest} ->
        {:refused, reason, stats(state, byte_size(rest))}

      {:error, %Saxy.ParseError{reason: {:invalid_encoding, _encoding}} = error} ->
        {:refused, :unsupported_encoding, error_stats(body, error)}

      {:error, %Saxy.ParseError{} = error} ->
        {:refused, :malformed, error_stats(body, error)}
    end
  end

  defp stats(state, unread),
    do: %{elements: state.elements, depth: state.max_depth, items: state.items, unread: unread}

  defp error_stats(body, %Saxy.ParseError{position: position}) when is_integer(position),
    do: %{elements: 0, depth: 0, items: 0, unread: max(byte_size(body) - position, 0)}

  defp error_stats(body, _error), do: unread(body)

  # -- the prolog: no document type declaration ------------------------------
  #
  # The prolog is a byte-order mark, whitespace, the XML declaration,
  # processing instructions and comments; a `<!` that does not open a
  # comment there is a declaration, and refused. Saxy would skip a DTD
  # silently, so it is refused here, before the reader sees the document.
  # Each step moves forward, so the scan is linear.

  defp declares_dtd?(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: prolog_dtd?(rest)
  defp declares_dtd?(body), do: prolog_dtd?(body)

  defp prolog_dtd?(<<char, rest::binary>>) when char in [?\s, ?\t, ?\r, ?\n],
    do: prolog_dtd?(rest)

  defp prolog_dtd?(<<"<?", rest::binary>>), do: rest |> skip_past("?>") |> prolog_dtd?()
  defp prolog_dtd?(<<"<!--", rest::binary>>), do: rest |> skip_past("-->") |> prolog_dtd?()
  defp prolog_dtd?(<<"<!", _rest::binary>>), do: true
  defp prolog_dtd?(_body), do: false

  defp skip_past(text, marker) do
    case :binary.match(text, marker) do
      {at, size} -> binary_part(text, at + size, byte_size(text) - at - size)
      :nomatch -> <<>>
    end
  end

  # -- the encoding: UTF-8 for the reader (#1442) ------------------------------
  #
  # The reader takes UTF-8 only. One UTF-8 byte-order mark is skipped; it
  # says UTF-8, so a Latin-1 declaration behind it contradicts it and is
  # refused. A body declaring Latin-1 or US-ASCII (regulators' Atom feeds
  # do) is transcoded from Latin-1, which maps every byte, so a byte above
  # 0x7F under a US-ASCII declaration is read as Latin-1 too; C1 controls
  # are dropped later by `News.Text`. Its UTF-8 size (one byte more per byte
  # above 0x7F) is checked against `max_bytes/0` before anything is
  # transcoded. Every other declared encoding reaches the reader unchanged
  # and is refused there. The declaration is the document's first bytes
  # (XML 1.0 §2.8), read within its first 256 bytes.

  @declaration_scope 256
  @encoding_attribute ~r/\sencoding\s*=\s*(["'])([A-Za-z][A-Za-z0-9._-]*)\1/
  @latin1_labels ~w(iso-8859-1 iso_8859-1 latin1 latin-1 us-ascii ascii)

  defp to_utf8(<<0xEF, 0xBB, 0xBF, rest::binary>>) do
    case latin1_declaration(rest) do
      nil -> {:ok, rest}
      _declaration -> {:refused, :unsupported_encoding}
    end
  end

  defp to_utf8(body) do
    case latin1_declaration(body) do
      nil -> {:ok, body}
      declaration -> transcode(body, declaration)
    end
  end

  # `<?xml` followed by whitespace: `<?xml-stylesheet …?>` is a processing
  # instruction, not the declaration.
  defp latin1_declaration(<<"<?xml", space, _rest::binary>> = body)
       when space in [?\s, ?\t, ?\r, ?\n] do
    scope = min(byte_size(body), @declaration_scope)

    with {at, 2} <- :binary.match(body, "?>", scope: {0, scope}),
         declaration = binary_part(body, 0, at + 2),
         [_attribute, _quote, label] <- Regex.run(@encoding_attribute, declaration),
         true <- String.downcase(label) in @latin1_labels do
      declaration
    else
      _other -> nil
    end
  end

  defp latin1_declaration(_body), do: nil

  defp transcode(body, declaration) do
    if byte_size(body) + high_bytes(body) > @max_bytes do
      {:refused, :too_large}
    else
      rest = binary_part(body, byte_size(declaration), byte_size(body) - byte_size(declaration))

      utf8_declaration =
        Regex.replace(@encoding_attribute, declaration, " encoding=\"UTF-8\"", global: false)

      {:ok, utf8_declaration <> :unicode.characters_to_binary(rest, :latin1, :utf8)}
    end
  end

  defp high_bytes(body),
    do: for(<<byte <- body>>, byte > 0x7F, reduce: 0, do: (count -> count + 1))

  # -- the SAX handler ---------------------------------------------------------
  #
  # `path` holds the open elements' names, innermost first. Inside an item,
  # `item_depth` is the item element's level and `raw` collects its fields'
  # text as received; `field` is the field being read and its level.

  defp initial_state do
    %{
      format: nil,
      depth: 0,
      max_depth: 0,
      elements: 0,
      items: 0,
      path: [],
      item_depth: nil,
      raw: nil,
      field: nil,
      done: []
    }
  end

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attributes}, state) do
    depth = state.depth + 1

    state = %{
      state
      | depth: depth,
        max_depth: max(state.max_depth, depth),
        elements: state.elements + 1
    }

    cond do
      depth > @max_depth -> {:halt, {:refused, :too_deep, state}}
      depth == 1 -> root(name, attributes, state)
      true -> start(name, attributes, %{state | path: [name | state.path]})
    end
  end

  def handle_event(:end_element, name, state), do: {:ok, finish(name, state)}

  def handle_event(:characters, text, %{field: {_key, _depth, acc}} = state),
    do: {:ok, %{state | field: put_elem(state.field, 2, [acc, text])}}

  def handle_event(_event, _data, state), do: {:ok, state}

  # The root decides the format, or refuses the document at its first tag.
  defp root(name, attributes, state) do
    case {name, attribute(attributes, "version"), attribute(attributes, "xmlns")} do
      {"rss", "2." <> _minor, _xmlns} -> {:ok, %{state | format: :rss, path: [name]}}
      {"feed", _version, @atom_namespace} -> {:ok, %{state | format: :atom, path: [name]}}
      _other -> {:halt, {:refused, :not_a_feed, state}}
    end
  end

  # An item begins: only `rss > channel > item` and `feed > entry` are items.
  defp start(name, _attributes, %{item_depth: nil} = state) do
    if item?(state.format, name, state.path),
      do: begin_item(state),
      else: {:ok, state}
  end

  # Inside an item: a field begins, a link or source is noted, or the text of
  # a nested element (XHTML content) is read with a word break around it.
  defp start(name, attributes, %{item_depth: item_depth, depth: depth} = state) do
    cond do
      state.field != nil ->
        {:ok, append(state, " ")}

      depth == item_depth + 1 ->
        {:ok, item_child(state.format, name, attributes, state)}

      depth == item_depth + 2 and state.format == :atom and name == "link" and
          match?([_link, "source" | _], state.path) ->
        {:ok, note_link(state, :source_link, attributes)}

      true ->
        {:ok, state}
    end
  end

  defp item?(:rss, "item", ["item", "channel", "rss"]), do: true
  defp item?(:atom, "entry", ["entry", "feed"]), do: true
  defp item?(_format, _name, _path), do: false

  defp begin_item(state) do
    items = state.items + 1
    state = %{state | items: items}

    if items > @max_items,
      do: {:halt, {:refused, :too_many_items, state}},
      else: {:ok, %{state | item_depth: state.depth, raw: %{}}}
  end

  defp item_child(:rss, "source", attributes, state),
    do: put_raw(state, :source_url, attribute(attributes, "url"))

  defp item_child(:atom, "link", attributes, state), do: note_link(state, :link, attributes)

  defp item_child(format, name, _attributes, state) do
    if name in fields(format),
      do: %{state | field: {name, state.depth, []}},
      else: state
  end

  defp fields(:rss), do: @rss_fields
  defp fields(:atom), do: @atom_fields

  # An Atom link counts when it is the alternate one (`rel` absent or
  # "alternate"); the first such wins.
  defp note_link(state, key, attributes) do
    if attribute(attributes, "rel") in [nil, "alternate"],
      do: put_raw(state, key, attribute(attributes, "href")),
      else: state
  end

  defp put_raw(state, _key, nil), do: state
  defp put_raw(state, key, value), do: %{state | raw: Map.put_new(state.raw, key, value)}

  defp append(%{field: {key, depth, acc}} = state, text),
    do: %{state | field: {key, depth, [acc, text]}}

  defp finish(_name, %{depth: depth} = state) do
    state = %{state | depth: depth - 1, path: tl_or_empty(state.path)}

    cond do
      match?({_key, ^depth, _acc}, state.field) ->
        {key, _depth, acc} = state.field
        put_raw(%{state | field: nil}, key, IO.iodata_to_binary(acc))

      state.field != nil ->
        append(state, " ")

      depth == state.item_depth ->
        item = build(state.format, state.raw)
        %{state | item_depth: nil, raw: nil, done: [item | state.done]}

      true ->
        state
    end
  end

  defp tl_or_empty([_head | tail]), do: tail
  defp tl_or_empty([]), do: []

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  # -- an item's values ---------------------------------------------------------

  defp build(:rss, raw) do
    %Item{
      title: Text.title(raw["title"]),
      link: http_url(raw["link"]),
      guid: Text.token(raw["guid"], @guid_max),
      published_at: rfc822(raw["pubDate"]) || rfc3339(raw["pubDate"]) || rfc3339(raw["dc:date"]),
      excerpt: Text.excerpt(raw["description"]) || Text.excerpt(raw["content:encoded"]),
      source_domain: host(raw[:source_url])
    }
  end

  defp build(:atom, raw) do
    %Item{
      title: Text.title(raw["title"]),
      link: http_url(raw[:link]),
      guid: Text.token(raw["id"], @guid_max),
      published_at: rfc3339(raw["published"]) || rfc3339(raw["updated"]),
      excerpt: Text.excerpt(raw["summary"]) || Text.excerpt(raw["content"]),
      source_domain: host(raw[:source_link])
    }
  end

  # An absolute http or https URL with a host, no whitespace (Unicode's, as
  # `News.Shapes` refuses it: closing act, SEC2/EDGE1) or control byte
  # inside and at most 2,048 bytes; anything else (a relative path, a
  # `javascript:` or `data:` URL) is nil. So is a link with a backslash
  # (closing act of Sprint 29, F2; A1): a browser reads `\` as `/` where
  # RFC 3986 does not, so `https://attacker.example\@ir.example/` would be
  # stored under one host and open another.
  defp http_url(nil), do: nil

  defp http_url(raw) do
    url = String.trim(raw)

    with true <- byte_size(url) <= @link_max_bytes,
         true <- String.valid?(url),
         false <- has_control_or_space?(url),
         false <- Shapes.space?(url),
         false <- String.contains?(url, "\\"),
         %URI{scheme: scheme, host: host}
         when is_binary(scheme) and is_binary(host) and host != "" <-
           URI.parse(url),
         true <- String.downcase(scheme) in ["http", "https"] do
      url
    else
      _invalid -> nil
    end
  end

  defp has_control_or_space?(<<byte, _rest::binary>>) when byte <= 0x20 or byte == 0x7F, do: true
  defp has_control_or_space?(<<_byte, rest::binary>>), do: has_control_or_space?(rest)
  defp has_control_or_space?(<<>>), do: false

  defp host(raw) do
    case http_url(raw) do
      nil -> nil
      url -> String.downcase(URI.parse(url).host)
    end
  end

  # -- dates ------------------------------------------------------------------

  # RFC 3339 (Atom, `dc:date`): a full date-time with its offset, kept to the
  # second in UTC.
  defp rfc3339(nil), do: nil

  defp rfc3339(raw) do
    raw = String.trim(raw)

    with true <- byte_size(raw) <= @date_max_bytes,
         {:ok, datetime, _offset} <- DateTime.from_iso8601(raw) do
      DateTime.truncate(datetime, :second)
    else
      _unreadable -> nil
    end
  end

  @months %{
    "jan" => 1,
    "feb" => 2,
    "mar" => 3,
    "apr" => 4,
    "may" => 5,
    "jun" => 6,
    "jul" => 7,
    "aug" => 8,
    "sep" => 9,
    "oct" => 10,
    "nov" => 11,
    "dec" => 12
  }

  # RFC 822 / 2822 zones in hours east of UTC: RFC 822's names and nothing
  # else (closing act, COR2). A name outside them (CET, IST, ...) is not
  # guessed: IST alone names three offsets. RFC 822's single-letter
  # military zones read as UTC (`military?/1`), as RFC 5322 §4.3 says,
  # because RFC 822 gave their signs backwards.
  @zones %{
    "ut" => 0,
    "utc" => 0,
    "gmt" => 0,
    "z" => 0,
    "est" => -5,
    "edt" => -4,
    "cst" => -6,
    "cdt" => -5,
    "mst" => -7,
    "mdt" => -6,
    "pst" => -8,
    "pdt" => -7
  }

  # RFC 822 (`pubDate`): `[Day,] DD Mon YY[YY] H[H]:MM[:SS] Zone`, any letter
  # case; anything else is nil (and then read as RFC 3339, which some feeds
  # write in `pubDate`).
  defp rfc822(nil), do: nil

  defp rfc822(raw) when byte_size(raw) > @date_max_bytes, do: nil

  defp rfc822(raw) do
    raw
    |> String.downcase()
    |> String.split()
    |> drop_weekday()
    |> rfc822_parts()
  end

  defp drop_weekday([first | rest]) do
    if String.ends_with?(first, ",") or Map.has_key?(weekdays(), first),
      do: rest,
      else: [first | rest]
  end

  defp drop_weekday([]), do: []

  defp weekdays,
    do: %{"mon" => 1, "tue" => 2, "wed" => 3, "thu" => 4, "fri" => 5, "sat" => 6, "sun" => 7}

  defp rfc822_parts([day, month, year, time, zone]) do
    with {:ok, day} <- digits(day, 1..2),
         {:ok, month} <- Map.fetch(@months, month),
         {:ok, year} <- year(year),
         {:ok, {hour, minute, second}} <- clock(time),
         {:ok, offset_seconds} <- zone(zone),
         {:ok, naive} <- NaiveDateTime.new(year, month, day, hour, minute, second) do
      naive
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.add(-offset_seconds, :second)
    else
      _unreadable -> nil
    end
  end

  defp rfc822_parts(_parts), do: nil

  defp year(text) do
    case digits(text, [2, 4]) do
      {:ok, year} when byte_size(text) == 2 and year < 50 -> {:ok, 2000 + year}
      {:ok, year} when byte_size(text) == 2 -> {:ok, 1900 + year}
      other -> other
    end
  end

  defp clock(text) do
    case String.split(text, ":") do
      [hour, minute] -> clock_parts([hour, minute, "00"])
      [_hour, _minute, _second] = parts -> clock_parts(parts)
      _other -> :error
    end
  end

  # A one-digit hour is read too (`9:05:00`), as feeds write it.
  defp clock_parts([hour, minute, second]) do
    with {:ok, hour} <- digits(hour, [1, 2]),
         {:ok, minute} <- digits(minute, [2]),
         {:ok, second} <- digits(second, [2]) do
      {:ok, {hour, minute, second}}
    end
  end

  defp zone(<<sign, hours::binary-size(2), minutes::binary-size(2)>>) when sign in [?+, ?-] do
    with {:ok, hours} <- digits(hours, [2]),
         {:ok, minutes} <- digits(minutes, [2]),
         true <- minutes < 60 do
      seconds = hours * 3_600 + minutes * 60
      {:ok, if(sign == ?-, do: -seconds, else: seconds)}
    else
      _invalid -> :error
    end
  end

  defp zone(name) do
    case Map.fetch(@zones, name) do
      {:ok, hours} -> {:ok, hours * 3_600}
      :error -> if military?(name), do: {:ok, 0}, else: :error
    end
  end

  # A to I, K to Z (lower-cased here); J names no zone.
  defp military?(<<letter>>) when letter in ?a..?z and letter != ?j, do: true
  defp military?(_name), do: false

  # A number of only ASCII digits, of one of the given lengths.
  defp digits(text, sizes) do
    if byte_size(text) in sizes and text =~ ~r/\A[0-9]+\z/,
      do: {:ok, String.to_integer(text)},
      else: :error
  end
end
