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
  """

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

  defp features, do: [&Map.get(&1, :isin), &Map.get(&1, :ticker_symbol), &number_tag/1]

  defp tells_apart?(feature, twins) do
    values = Enum.map(twins, feature)
    Enum.all?(values, &(&1 not in [nil, ""])) and length(Enum.uniq(values)) == length(values)
  end

  defp number_tag(security), do: gettext("no. %{id}", id: security.id)
end
