defmodule PortfolixirWeb.StoredText do
  @moduledoc """
  Stored text set inside a translated sentence, isolated in `<bdi>`
  (DESIGN.md, "Stored text with invisible characters", G12.2-B; #968,
  Sprint 18 pick H8.8).

  A name stored before every writer refused direction controls can carry a
  U+202E RIGHT-TO-LEFT OVERRIDE with nothing to end it, and a legitimate
  right-to-left name reorders the text around it. Interpolated as plain text
  into a finished sentence ("Retired %{name}"), either reverses the rest of
  the line — the app's own words included. In `<bdi>` the reordering ends
  with the name.

  The translated sentence is split around its placeholders before any stored
  text is put in: the caller translates with `slot/1` in place of each stored
  value, and `isolate/2` escapes the translation and sets each stored value
  in its own `<bdi>`. A slot is a NUL-delimited key no translation carries,
  so a stored value can never be mistaken for one. An ordinary name renders
  exactly as before; only the markup changes.

      StoredText.isolate(
        gettext("Retired %{name}", name: StoredText.slot(:name)),
        name: security.name
      )

  A stored value may also be markup the caller built safely (a link whose
  label is itself isolated, `link/2`); it is put in as it is.

  Attribute strings (`aria-label`, `data-confirm`, `title`) cannot hold
  `<bdi>`; they are not covered here.
  """

  alias Phoenix.HTML

  @slot ~r/\x{0}([a-z_]+)\x{0}/u

  @doc "The value to translate with in place of the stored text under `key`."
  @spec slot(atom()) :: String.t()
  def slot(key) when is_atom(key), do: <<0>> <> Atom.to_string(key) <> <<0>>

  @doc """
  `translated` as safe markup, each of its slots replaced by the stored value
  under the slot's key, isolated in `<bdi>`. A slot without a value is left
  out; text around the slots is escaped.
  """
  @spec isolate(String.t(), keyword() | map()) :: HTML.safe()
  def isolate(translated, stored) when is_binary(translated) do
    values = Map.new(stored, fn {key, value} -> {Atom.to_string(key), value} end)

    iodata =
      @slot
      |> Regex.split(translated, include_captures: true)
      |> Enum.map(&piece(&1, values))

    {:safe, iodata}
  end

  @doc "`text` alone, isolated: `<bdi>text</bdi>`, escaped."
  @spec bdi(String.t()) :: HTML.safe()
  def bdi(text) when is_binary(text), do: {:safe, bdi_iodata(text)}

  @doc """
  A link to `href` whose label is the stored `label`, isolated, as markup a
  slot can take.
  """
  @spec link(String.t(), String.t()) :: HTML.safe()
  def link(href, label) when is_binary(href) and is_binary(label) do
    {:safe, [~s(<a href="), escape(href), ~s(">), bdi_iodata(label), "</a>"]}
  end

  defp piece(part, values) do
    case Regex.run(@slot, part) do
      [^part, key] -> stored(Map.get(values, key))
      _text -> escape(part)
    end
  end

  defp stored(nil), do: []
  defp stored({:safe, iodata}), do: iodata
  defp stored(text) when is_binary(text), do: bdi_iodata(text)

  defp bdi_iodata(text), do: ["<bdi>", escape(text), "</bdi>"]

  defp escape(text), do: text |> HTML.html_escape() |> HTML.safe_to_string()
end
