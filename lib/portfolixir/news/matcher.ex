defmodule Portfolixir.News.Matcher do
  @moduledoc """
  The alias matcher (ADR-0056 §2): which securities of the universe an
  `aggregator` item names. Pure: no database, no process, no atom made.

  **No pattern from input, no backtracking.** The text is read once, code
  point by code point, into sentences of tokens; every alias, ISIN and WKN
  of the universe is read the same way into a sequence of tokens and stored
  in a trie keyed by token. Matching walks the trie from each token of a
  sentence, one map lookup per step, and stops at the first token the trie
  does not continue with. The walk's depth is bounded by the longest alias
  (64 characters), never by the text, so the work is linear in the text for
  a given universe, whatever the text repeats.

  **Tokens.** A word is a maximal run of letters, marks, digits and
  connector punctuation (`_`), Unicode-aware; every other visible character
  is a token of its own (`.`, `&`, `'`, `-`, quotes); whitespace of any kind
  separates and is dropped; an invisible format character (a zero-width
  space, a soft hyphen) is dropped without separating, so `Lark\\u200Bspur`
  reads `Larkspur`, as a reader sees it; a byte that is not UTF-8 separates.
  An alias is a run of tokens, so the word boundary of §2 is implied:
  `Larkspur` matches in `Larkspur's` and `(Larkspur)` but not in `Larkspurs`,
  `BRK.B` matches `BRK.B` and not `BRK B`, and whitespace between an alias's
  words matches any whitespace.

  **Sentences.** A sentence ends at a line break, or at `.`, `!`, `?`, `…`
  (and their full-width forms) followed by whitespace or the end. A `.`
  after a single letter (an initial, `U.S.`) or after a short list of
  abbreviations that sit inside names (`Inc.`, `Corp.`, `Co.`, `Ltd.`, …)
  does not end one. An alias never spans two sentences.

  **Case.** A `sensitive` alias compares tokens as written; an
  `insensitive` alias compares them folded by `String.downcase/1`. Context
  words are always compared folded: "Shares of BOLT" opens a sentence with a
  capital. ISIN and WKN compare as written (they are upper-case by their
  definition).

  **Context.** An alias with context words matches only in a sentence that
  also holds at least one of them, as a whole word (a context word with
  punctuation, `S&P`, as its run of tokens).

  **Outcome** (§2): exactly one security named is `{:assigned, id}`, none
  is `:unassigned`, several are `{:ambiguous, ids}` with the ids sorted. A
  security is named when any of its aliases, its ISIN or its WKN matches in
  any sentence of the text.

  The caller decides which text it hands over and which securities make up
  the universe (`Portfolixir.News.Universe`); this module matches.
  """

  # Abbreviations whose dot does not end a sentence, folded; a single
  # letter's dot does not either.
  @abbreviations MapSet.new(~w(inc corp co ltd plc llc ag se sa nv mr mrs ms dr jr sr st vs))
  @terminators ["!", "?", "…", "。", "！", "？", "｡"]

  # Code points outside ASCII are classified by Unicode category. These are
  # fixed patterns of this module over one code point at a time, never a
  # pattern from input.
  @format_cp ~r/\A\p{Cf}\z/u
  @break_cp ~r/\A[\x{2028}\x{2029}\x{0085}]\z/u
  @space_cp ~r/\A[\p{Z}\s]\z/u
  @word_cp ~r/\A[\p{L}\p{M}\p{N}\p{Pc}]\z/u

  defstruct sensitive: %{}, insensitive: %{}, context: %{}, contexts?: false

  @typedoc "A trie node: the ids an alias ending here names, and its children by token."
  @type trie :: %{optional(String.t()) => node_}
  @type node_ :: %{
          key: term(),
          plain: [pos_integer()],
          context: %{optional([String.t()]) => [pos_integer()]},
          children: trie()
        }

  @opaque index :: %__MODULE__{}

  @typedoc "An alias as `Portfolixir.News.Alias` stores it, or the same as a plain map."
  @type alias_like :: %{
          required(:token) => String.t(),
          optional(:context) => [String.t()] | nil,
          required(:case) => :sensitive | :insensitive | String.t()
        }

  @typedoc "One security of the universe, as `Portfolixir.News.Universe` lists it."
  @type entry :: %{
          required(:id) => pos_integer(),
          optional(:aliases) => [alias_like()],
          optional(:isin) => String.t() | nil,
          optional(:wkn) => String.t() | nil,
          optional(atom()) => term()
        }

  @type outcome :: {:assigned, pos_integer()} | :unassigned | {:ambiguous, [pos_integer()]}

  @doc "Builds the lookup tables of a universe once, for many items."
  @spec compile([entry()]) :: index()
  def compile(entries) when is_list(entries) do
    Enum.reduce(entries, %__MODULE__{}, fn entry, index ->
      id = Map.fetch!(entry, :id)

      index
      |> add_literal(id, Map.get(entry, :isin))
      |> add_literal(id, Map.get(entry, :wkn))
      |> add_aliases(id, Map.get(entry, :aliases) || [])
    end)
  end

  @doc """
  The outcome of matching `text` against a universe (a compiled index, or
  the entries to compile).
  """
  @spec match(String.t(), index() | [entry()]) :: outcome()
  def match(text, universe), do: text |> matches(universe) |> outcome()

  @doc "The ids of the securities `text` names, sorted, each once."
  @spec matches(String.t(), index() | [entry()]) :: [pos_integer()]
  def matches(text, entries) when is_list(entries), do: matches(text, compile(entries))

  def matches(text, %__MODULE__{} = index) when is_binary(text) do
    text
    |> sentences()
    |> Enum.reduce(MapSet.new(), fn sentence, ids -> sentence_ids(sentence, index, ids) end)
    |> Enum.sort()
  end

  @doc "§2's rule: one id assigns, none leaves it unassigned, several are ambiguous."
  @spec outcome([pos_integer()]) :: outcome()
  def outcome(ids) when is_list(ids) do
    case ids |> Enum.uniq() |> Enum.sort() do
      [] -> :unassigned
      [id] -> {:assigned, id}
      several -> {:ambiguous, several}
    end
  end

  @doc """
  The text as sentences of tokens, each token `{as_written, folded}`. See
  the moduledoc for what a token and a sentence are.
  """
  @spec sentences(String.t()) :: [[{String.t(), String.t()}]]
  def sentences(text) when is_binary(text) do
    text
    |> scan()
    |> split_sentences()
  end

  # -- building -----------------------------------------------------------

  defp add_literal(index, _id, value) when value in [nil, ""], do: index

  defp add_literal(index, id, value) when is_binary(value) do
    case alias_tokens(value) do
      [] -> index
      tokens -> %{index | sensitive: insert(index.sensitive, keys(tokens, :sensitive), id, [])}
    end
  end

  defp add_aliases(index, id, aliases) do
    Enum.reduce(aliases, index, fn alias_row, acc -> add_alias(acc, id, alias_row) end)
  end

  defp add_alias(index, id, alias_row) do
    tokens = alias_tokens(Map.get(alias_row, :token) || "")
    mode = case_mode(Map.get(alias_row, :case))

    contexts =
      (Map.get(alias_row, :context) || [])
      |> Enum.map(fn word -> word |> alias_tokens() |> keys(:insensitive) end)
      |> Enum.reject(&(&1 == []))
      |> Enum.uniq()

    cond do
      tokens == [] ->
        index

      # A context list whose every word reads as nothing can never be met.
      (Map.get(alias_row, :context) || []) != [] and contexts == [] ->
        index

      true ->
        key = keys(tokens, mode)

        index =
          if contexts == [],
            do: index,
            else: %{
              index
              | context: Enum.reduce(contexts, index.context, &insert(&2, &1, :present, [])),
                contexts?: true
            }

        Map.update!(index, mode, &insert(&1, key, id, contexts))
    end
  end

  # Anything but an explicit `sensitive` folds: the stored alias always
  # states its case, so the fallback is never reached from a valid row.
  defp case_mode(mode) when mode in [:sensitive, "sensitive"], do: :sensitive
  defp case_mode(_mode), do: :insensitive

  defp alias_tokens(value) when is_binary(value), do: value |> scan() |> words_only()
  defp alias_tokens(_value), do: []

  defp keys(tokens, :sensitive), do: Enum.map(tokens, &elem(&1, 0))
  defp keys(tokens, :insensitive), do: Enum.map(tokens, &elem(&1, 1))

  defp insert(trie, [token], id, contexts) do
    node = Map.get(trie, token) || new_node()
    Map.put(trie, token, add_hit(node, id, contexts))
  end

  defp insert(trie, [token | rest], id, contexts) do
    node = Map.get(trie, token) || new_node()
    Map.put(trie, token, %{node | children: insert(node.children, rest, id, contexts)})
  end

  defp new_node, do: %{key: make_ref(), plain: [], context: %{}, children: %{}}

  defp add_hit(node, :present, []), do: %{node | plain: [:present]}
  defp add_hit(node, id, []), do: %{node | plain: [id | node.plain]}

  defp add_hit(node, id, contexts) do
    %{
      node
      | context:
          Enum.reduce(contexts, node.context, fn context, acc ->
            Map.update(acc, context, [id], &[id | &1])
          end)
    }
  end

  # -- matching -----------------------------------------------------------

  defp sentence_ids(sentence, index, ids) do
    nodes =
      walk_all(sentence, %{}, fn tail, acc ->
        acc
        |> walk(tail, index.sensitive, 0)
        |> walk(tail, index.insensitive, 1)
      end)

    present = present_contexts(sentence, nodes, index)

    Enum.reduce(nodes, ids, fn {_key, node}, acc ->
      acc
      |> add_ids(node.plain)
      |> add_context_ids(node.context, present)
    end)
  end

  defp walk_all([], acc, _fun), do: acc
  defp walk_all([_ | rest] = tail, acc, fun), do: walk_all(rest, fun.(tail, acc), fun)

  defp walk(acc, [], _trie, _position), do: acc

  defp walk(acc, [token | rest], trie, position) do
    case Map.fetch(trie, elem(token, position)) do
      {:ok, node} ->
        acc = if hit?(node), do: Map.put(acc, node.key, node), else: acc
        walk(acc, rest, node.children, position)

      :error ->
        acc
    end
  end

  defp hit?(%{plain: [], context: context}) when map_size(context) == 0, do: false
  defp hit?(_node), do: true

  # The context sequences present in the sentence, read only when a node
  # reached needs them: one walk of the context trie from each token.
  defp present_contexts(sentence, nodes, %{contexts?: true, context: trie}) do
    if Enum.any?(nodes, fn {_key, node} -> map_size(node.context) > 0 end) do
      sentence
      |> walk_all(%{}, fn tail, acc -> walk_context(acc, tail, trie, []) end)
      |> Map.keys()
      |> MapSet.new()
    else
      MapSet.new()
    end
  end

  defp present_contexts(_sentence, _nodes, _index), do: MapSet.new()

  defp walk_context(acc, [], _trie, _path), do: acc

  defp walk_context(acc, [{_written, folded} | rest], trie, path) do
    case Map.fetch(trie, folded) do
      {:ok, node} ->
        path = [folded | path]
        acc = if node.plain == [], do: acc, else: Map.put(acc, Enum.reverse(path), true)
        walk_context(acc, rest, node.children, path)

      :error ->
        acc
    end
  end

  defp add_ids(acc, ids), do: Enum.reduce(ids, acc, &MapSet.put(&2, &1))

  # Iterates the smaller side, so a node with many contexts in a short
  # sentence, or a long sentence against a node with few, stays cheap.
  defp add_context_ids(acc, context, _present) when map_size(context) == 0, do: acc

  defp add_context_ids(acc, context, present) do
    if map_size(context) <= MapSet.size(present) do
      Enum.reduce(context, acc, fn {sequence, ids}, inner ->
        if MapSet.member?(present, sequence), do: add_ids(inner, ids), else: inner
      end)
    else
      Enum.reduce(present, acc, fn sequence, inner ->
        add_ids(inner, Map.get(context, sequence, []))
      end)
    end
  end

  # -- scanning -----------------------------------------------------------

  # One pass over the text: `{:word, written}`, `{:punct, char}`, `:space`
  # or `:break`, in order.
  defp scan(text), do: scan(text, "", [])

  defp scan(<<>>, word, acc), do: Enum.reverse(flush(word, acc))

  defp scan(<<cp::utf8, rest::binary>>, word, acc) do
    case class(cp) do
      :word -> scan(rest, <<word::binary, cp::utf8>>, acc)
      :format -> scan(rest, word, acc)
      :space -> scan(rest, "", [:space | flush(word, acc)])
      :break -> scan(rest, "", [:break | flush(word, acc)])
      :punct -> scan(rest, "", [{:punct, <<cp::utf8>>} | flush(word, acc)])
    end
  end

  defp scan(<<_invalid, rest::binary>>, word, acc),
    do: scan(rest, "", [:space | flush(word, acc)])

  defp flush("", acc), do: acc
  defp flush(word, acc), do: [{:word, word} | acc]

  defp class(cp) when cp in ?a..?z or cp in ?A..?Z or cp in ?0..?9 or cp == ?_, do: :word
  defp class(cp) when cp in [?\n, ?\r], do: :break
  defp class(cp) when cp in [?\s, ?\t, ?\v, ?\f], do: :space
  defp class(cp) when cp < 0x20 or cp == 0x7F, do: :space
  defp class(cp) when cp < 0x80, do: :punct

  defp class(cp) do
    char = <<cp::utf8>>

    cond do
      Regex.match?(@format_cp, char) -> :format
      Regex.match?(@break_cp, char) -> :break
      Regex.match?(@space_cp, char) -> :space
      Regex.match?(@word_cp, char) -> :word
      true -> :punct
    end
  end

  defp words_only(tokens) do
    for token <- tokens, token not in [:space, :break], do: as_pair(token)
  end

  defp as_pair({_kind, written}), do: {written, String.downcase(written)}

  # One pass over the tokens: a sentence ends at a break, or at a
  # terminator followed by whitespace, a break or the end, unless the
  # terminator is the dot of an abbreviation.
  defp split_sentences(tokens), do: split_sentences(tokens, [], [], nil)

  defp split_sentences([], current, done, _previous), do: Enum.reverse(close(current, done))

  defp split_sentences([:break | rest], current, done, _previous),
    do: split_sentences(rest, [], close(current, done), nil)

  defp split_sentences([:space | rest], current, done, previous),
    do: split_sentences(rest, current, done, previous)

  defp split_sentences([{:punct, char} = token | rest], current, done, previous) do
    current = [as_pair(token) | current]

    if ends_sentence?(char, previous) and boundary_follows?(rest),
      do: split_sentences(rest, [], close(current, done), nil),
      else: split_sentences(rest, current, done, token)
  end

  defp split_sentences([{:word, _written} = token | rest], current, done, _previous),
    do: split_sentences(rest, [as_pair(token) | current], done, token)

  defp close([], done), do: done
  defp close(current, done), do: [Enum.reverse(current) | done]

  defp ends_sentence?(".", {:word, written}), do: not abbreviation?(written)
  defp ends_sentence?(".", _previous), do: true
  defp ends_sentence?(char, _previous), do: char in @terminators

  defp abbreviation?(written) do
    String.length(written) == 1 or MapSet.member?(@abbreviations, String.downcase(written))
  end

  defp boundary_follows?([]), do: true
  defp boundary_follows?([token | _rest]), do: token in [:space, :break]
end
