defmodule PortfolixirWeb.SecurityNames do
  @moduledoc """
  Same-named securities told apart wherever the operator picks or names one
  (the closing act, UAT-13) — the F1 rule the import preview applies to
  same-named accounts (DESIGN.md, G4b), for the twins a security merge
  exists for.

  A security whose name another security of the same list carries adds,
  after a middle dot, what tells it apart: its ISIN, else its ticker, else
  "no. <id>" — the first of them present and different on every twin.
  Unique names are unchanged.

  **The table rows' rule** (issue 1057, board
  `mockups/ux-design-2026-10-04/06-phone-wealth`, pick J6.2 A) is the same
  rule for a table that reads a payload rather than the catalog:
  `put_twin_ids/2` finds the rows of one table whose names read the same for
  different securities, and gives each the identifier that tells it apart —
  its ISIN, else its WKN, else "no. <id>", the first of them present and
  different on every twin; `twin_id/1` renders it after the name. Both the
  Positions and the contribution table decide over every row of their
  payload, hidden rows included, by the displayed name alone: no other cell
  tells two securities apart, because a depot's name need not be unique to
  a reader and the Positions' Depot column can be switched off.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  @doc """
  Per security whose name another one of `securities` also carries, the tag
  that tells it apart; securities with a unique name carry none.
  """
  @spec tags([map()]) :: %{optional(integer()) => String.t()}
  def tags(securities) when is_list(securities) do
    securities
    |> Enum.uniq_by(& &1.id)
    |> Enum.group_by(& &1.name)
    |> Enum.flat_map(fn
      {_name, [_single]} ->
        []

      {_name, twins} ->
        feature = Enum.find(features(), &tells_apart?(&1, twins)) || (&number_tag/1)
        Enum.map(twins, &{&1.id, feature.(&1)})
    end)
    |> Map.new()
  end

  @doc "`security`'s name, with its tag when `tags` gives it one."
  @spec label(%{optional(integer()) => String.t()}, map()) :: String.t()
  def label(tags, security) do
    case Map.get(tags, security.id) do
      nil -> security.name
      tag -> "#{security.name} · #{tag}"
    end
  end

  @doc "The tag alone, prefixed with its middle dot, or an empty string."
  @spec suffix(%{optional(integer()) => String.t()}, map()) :: String.t()
  def suffix(tags, security) do
    case Map.get(tags, security.id) do
      nil -> ""
      tag -> " · " <> tag
    end
  end

  # The spaces `String.split/1` does not split on but a cell prints as a
  # space (`display_key/1`): no-break, figure and narrow no-break.
  @no_break_spaces [" ", " ", " "]

  @typedoc "What tells a table row's security from its twins, or `nil`."
  @type twin_id :: {:isin | :wkn, String.t()} | {:number, integer()} | nil

  @doc """
  `rows`, each with `:twin_id` put: `nil` where no other row of the list
  shows a name that reads the same (`name.(row)`, compared by
  `display_key/1`) for another security, else the identifier that tells the
  row's security apart from its twins.

  A row carries `:security_id`, `:isin` and, where its payload has it,
  `:wkn`. Within a colliding name the identifier is the first of ISIN and
  WKN that every twin carries (an empty string counts as absent) and no two
  twins share; failing both, each twin's number. One security on several
  rows (held in two depots) is one twin, and every row of it carries the
  same identifier. A row without a name never collides.
  """
  @spec put_twin_ids([map()], (map() -> String.t() | nil)) :: [map()]
  def put_twin_ids(rows, name) when is_list(rows) and is_function(name, 1) do
    keyed = Enum.map(rows, &{display_key(name.(&1)), &1})

    ids =
      keyed
      |> Enum.reject(fn {key, _row} -> is_nil(key) end)
      |> Enum.group_by(fn {key, _row} -> key end, fn {_key, row} -> row end)
      |> Enum.flat_map(fn {key, group} -> group_ids(key, group) end)
      |> Map.new()

    Enum.map(keyed, fn {key, row} ->
      Map.put(row, :twin_id, Map.get(ids, {key, row.security_id}))
    end)
  end

  @doc """
  The key two displayed names are compared by: Unicode NFC, and every run
  of whitespace one space with the edges trimmed — what an HTML table cell
  shows, so a decomposed "Müller AG" and a doubled space read as the names
  they render as. `nil` for a name with nothing left.

  A no-break space (U+00A0), a figure space (U+2007) and a narrow no-break
  space (U+202F) print as a space, so they count as one (the PR γ closing
  act): `String.split/1` keeps them inside a word, and a name pasted from a
  web page or a PDF would otherwise print the same as its twin and carry no
  identifier.

  Deliberately not `Portfolixir.Imports.SecurityResolver.skeleton/1`: that
  key is "looks alike to a reader" for the import's at-risk check, and also
  lowercases, folds compatibility forms (NFKC) and folds Cyrillic and Greek
  lookalikes onto Latin. Here two names collide only where the table prints
  the same text, so case stays significant.
  """
  @spec display_key(term()) :: String.t() | nil
  def display_key(name) when is_binary(name) do
    if String.valid?(name) do
      name
      |> String.normalize(:nfc)
      |> String.replace(@no_break_spaces, " ")
      |> String.split()
      |> Enum.join(" ")
      |> case do
        "" -> nil
        key -> key
      end
    end
  end

  def display_key(_name), do: nil

  defp group_ids(group_key, group) do
    twins = Enum.uniq_by(group, & &1.security_id)

    if length(twins) < 2 do
      []
    else
      kind = Enum.find([:isin, :wkn], fn kind -> tells_apart?(&Map.get(&1, kind), twins) end)

      Enum.map(twins, fn twin ->
        id = if kind, do: {kind, Map.fetch!(twin, kind)}, else: {:number, twin.security_id}
        {{group_key, twin.security_id}, id}
      end)
    end
  end

  attr(:tag, :any, required: true, doc: "a `t:twin_id/0` from `put_twin_ids/2`")

  @doc """
  The identifier after a twin's name (rule ②, `.twin-id`): muted mono, with
  a visually hidden "ISIN"/"WKN" before the value. Every separating space is
  a real space in the normal flow, never inside the hidden span: a
  `.visually-hidden` box is absolutely positioned, so the spaces at its
  edges collapse and separate nothing. One space before `.twin-id` gives the
  name a break opportunity and keeps the text from running together; one
  between the hidden label and the value makes the text read
  "<name> ISIN <value>", and on the screen it collapses into the first. A
  number reads "no. <id>" and needs no label. `nil` renders nothing, not
  even the space.
  """
  def twin_id(assigns) do
    assigns = assign(assigns, :label, twin_label(assigns.tag))

    ~H"""
    <%= if @tag do %><%= " " %><span class="twin-id"><%= if @label do %><span class="visually-hidden"><%= @label %></span><%= " " %><% end %><%= twin_value(@tag) %></span><% end %>
    """
  end

  defp twin_label({:isin, _value}), do: gettext("ISIN")
  defp twin_label({:wkn, _value}), do: gettext("WKN")
  defp twin_label(_number_or_nil), do: nil

  defp twin_value({:number, id}), do: gettext("no. %{id}", id: id)
  defp twin_value({_kind, value}), do: value

  defp features, do: [&Map.get(&1, :isin), &Map.get(&1, :ticker_symbol), &number_tag/1]

  defp tells_apart?(feature, twins) do
    values = Enum.map(twins, feature)
    Enum.all?(values, &(&1 not in [nil, ""])) and length(Enum.uniq(values)) == length(values)
  end

  defp number_tag(security), do: gettext("no. %{id}", id: security.id)
end
