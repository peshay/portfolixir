defmodule PortfolixirWeb.PageAddress do
  @moduledoc """
  The address a top-bar switch (the language, the privacy mode) links to:
  the page's own path and query as its last `handle_params` saw them
  (`@page_address`, kept by `PortfolixirWeb.PrivacyMode.on_mount/4`), with
  the switch's own pair set (closing act of Sprint 26).

  - **The page stays the page:** its path and its other pairs as written,
    a list's repeated keys and their order included, so a switch keeps a
    tab, the filters and a comparison.
  - **No preference rides along unasked:** the preference parameters of the
    address (`view`, `locale`, `benchmark`, `benchmark_rate`, `rail`,
    `privacy`; `PortfolixirWeb.UiAuth.safe_return_path/1`) are left out and
    those the page carries itself in `current_path` put back (a remembered
    view). A switch's click is a request of this instance, which remembers
    a choice it carries (`PortfolixirWeb.FetchSite`), so a view another
    site's link put into the address would become the remembered one
    (S7E-2).
  - **A local path:** leading slashes are one, so a doubled one the router
    accepts never reads as a host (H26).
  """

  alias PortfolixirWeb.UiAuth

  # The preferences a page may carry in its `current_path` on purpose.
  @carried ~w(view benchmark benchmark_rate rail)

  @doc """
  `page_address` (or `current_path` where the page has none) without its
  preference pairs, the preferences `current_path` carries put back, and
  `pairs` appended.
  """
  @spec link(String.t() | nil, String.t() | nil, [String.t()]) :: String.t()
  def link(page_address, current_path, pairs) when is_list(pairs) do
    address = String.replace(page_address || current_path || "/", ~r{^/+}, "/")
    {path, kept} = address |> UiAuth.safe_return_path() |> path_and_pairs()

    {_path, own} = path_and_pairs(current_path)
    carried = Enum.filter(own, &(UiAuth.preference(&1) in @carried))

    path <> "?" <> Enum.join(kept ++ carried ++ pairs, "&")
  end

  defp path_and_pairs(nil), do: {"/", []}

  defp path_and_pairs(address) do
    case String.split(address, "?", parts: 2) do
      [path] -> {path, []}
      [path, query] -> {path, String.split(query, "&", trim: true)}
    end
  end
end
