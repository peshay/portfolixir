defmodule PortfolixirWeb.ReferenceCounts do
  @moduledoc """
  What references a record, counted per referencing table
  (`Portfolixir.Lifecycle.Delete.referenced_by/1`), in the operator's words:
  "12 bookings", "840 quotes", "3 research entries" (de "12 Buchungen",
  "840 Kurse", "3 Research-Einträge").

  Two surfaces read it (Sprint 18 pick H8): the security dialog's currency
  freeze at the field (#921, H8.3) and the securities page's "Cannot delete"
  (#918, H8.2). The domain builds its own English counts for the API and MCP
  (`Portfolixir.Lifecycle.Freeze`); this is the page's half, so the counts
  read in the page's language and with the page's nouns.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  # The order the parts are named in: what moves with a merge first, then
  # what holds the record whatever happens.
  @order ~w(transactions security_quotes security_events security_notes policy_rule_versions)

  @typedoc "A count per referencing table, as `Delete.referenced_by/1` answers it."
  @type counts :: %{optional(String.t()) => non_neg_integer()}

  @doc """
  One counted part per referencing table with a count above zero, in a fixed
  order; a table this module has no noun for is counted as "other records".
  """
  @spec parts(counts()) :: [String.t()]
  def parts(counts) when is_map(counts) do
    known =
      @order
      |> Enum.map(&{&1, Map.get(counts, &1, 0)})
      |> Enum.filter(fn {_table, n} -> n > 0 end)
      |> Enum.map(fn {table, n} -> part(table, n) end)

    other =
      counts
      |> Map.drop(@order)
      |> Map.values()
      |> Enum.sum()

    if other > 0,
      do: known ++ [ngettext("%{count} other record", "%{count} other records", other)],
      else: known
  end

  @doc ~S"""
  The parts joined as a sentence lists them: "a", "a and b", "a, b and c"
  (de "a, b und c").
  """
  @spec and_list([String.t()]) :: String.t()
  def and_list([only]), do: only

  def and_list([_ | _] = parts) do
    {init, [last]} = Enum.split(parts, -1)
    gettext("%{first} and %{second}", first: Enum.join(init, ", "), second: last)
  end

  @doc """
  The field error of an identity field that froze once something referenced
  the record (ADR-0050 §11): "is frozen once referenced (2 bookings,
  1 quote)" (de "steht fest, sobald etwas darauf verweist (2 Buchungen,
  1 Kurs)").
  """
  @spec frozen(counts()) :: String.t()
  def frozen(counts) when is_map(counts) do
    gettext("is frozen once referenced (%{counts})", counts: counts |> parts() |> Enum.join(", "))
  end

  defp part("transactions", n), do: ngettext("%{count} booking", "%{count} bookings", n)
  defp part("security_quotes", n), do: ngettext("%{count} quote", "%{count} quotes", n)
  defp part("security_events", n), do: ngettext("%{count} event", "%{count} events", n)

  defp part("security_notes", n),
    do: ngettext("%{count} research entry", "%{count} research entries", n)

  defp part("policy_rule_versions", n),
    do: ngettext("%{count} rule version", "%{count} rule versions", n)
end
