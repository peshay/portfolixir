defmodule PortfolixirWeb.BenchmarkChoices do
  @moduledoc """
  The labelled groups a screen's benchmark picker offers (#1416, B2;
  ADR-0046's amendment of 2026-11-07, point 3; ADR-0058 F5; board
  `ux-design-2026-11-12-sprint29/02`, Q1 A): „Benchmarks“, the flagged
  securities, then „Im Bestand“, the ones held today in any depot, each by
  name and only with a stored quote — `Portfolixir.Catalog.BenchmarkSecurity.choices/0`,
  the same rule `resolve/1` applies, so whatever is offered compares.

  Both pickers read it: Holdings' „Benchmark…“ (`PortfolioLive`) and
  „Nach dem Verkauf“'s select (`SaleHindsightSection`).

  A security the address names that the rule accepts but neither group
  holds — an unheld one with a quote, as an agent's link may carry — is
  chosen all the same, as the API takes it, and shown in a third group,
  „Weitere“, so the picker shows what is compared and applying it again
  keeps it. The group is there only while such a security is chosen.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Catalog.Security

  @type group :: %{key: :flagged | :held | :other, label: String.t(), securities: [Security.t()]}

  @doc """
  The picker's non-empty groups in their order, with `chosen` (the
  securities the screen resolved as active) added as „Weitere“ where
  neither group offers them.
  """
  @spec groups([Security.t()]) :: [group()]
  def groups(chosen \\ []) do
    %{flagged: flagged, held: held} = BenchmarkSecurity.choices()

    [
      %{key: :flagged, label: pgettext("benchmark picker", "Benchmarks"), securities: flagged},
      %{key: :held, label: pgettext("benchmark picker", "In holdings"), securities: held}
    ]
    |> Enum.reject(&(&1.securities == []))
    |> with_chosen(chosen)
  end

  @doc """
  `groups` with „Weitere“ added for each of `chosen` that no group offers;
  unchanged when every one is offered.
  """
  @spec with_chosen([group()], [Security.t()]) :: [group()]
  def with_chosen(groups, chosen) do
    offered =
      for %{securities: securities} <- groups, s <- securities, into: MapSet.new(), do: s.id

    case chosen |> Enum.reject(&MapSet.member?(offered, &1.id)) |> Enum.uniq_by(& &1.id) do
      [] ->
        groups

      other ->
        groups ++
          [%{key: :other, label: pgettext("benchmark picker", "Other"), securities: other}]
    end
  end

  @doc "The first security the groups offer, in their order: the default choice."
  @spec first([group()]) :: Security.t() | nil
  def first(groups) do
    Enum.find_value(groups, fn %{securities: securities} -> List.first(securities) end)
  end
end
