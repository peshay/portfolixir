defmodule Portfolixir.Dashboards.HoldingsStarterTest do
  # Sprint 32 W1 (I57; ADR-0062's amendment of 2026-11-25, point 5; board
  # ux-design-2026-11-25-sprint32/02 ①): Wealth's tab „Bestände“ as the
  # starter dashboard „Bestände“, its sections as section widgets in the
  # tab's order, each a „Zeile“.
  use ExUnit.Case, async: true

  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates

  defp german(fun), do: Gettext.with_locale(PortfolixirWeb.Gettext, "de", fun)

  # User story:
  # As the operator who knows Wealth's tab „Bestände“,
  # I want a starter dashboard „Bestände“ that lists its sections as
  # widgets, in the tab's order,
  # so that it looks like the tab and I can change it piece by piece.
  #
  # Acceptance criteria:
  # - The template „holdings“ is a starter, offered after „Überblick“,
  #   named „Bestände“ in German, asking for no scope.
  # - It lists exactly board 02 ①'s widgets in order, each at „Zeile“, one
  #   under the other: Kennzahlen, Datenhinweise, Performance, Beitrag je
  #   Position, Positionen, Verrechnungskonten.
  # - Its layout passes the validation as it stands.
  test "the starter „Bestände“ lists the tab's sections in order, each a Zeile" do
    assert {:ok, holdings} = Templates.fetch("holdings")
    assert holdings.starter
    refute holdings.asks_scope
    assert ["overview", "holdings" | _others] = Enum.map(Templates.starters(), & &1.key)
    assert german(fn -> Templates.title("holdings") end) == "Bestände"

    assert Enum.map(holdings.layout, &{&1["kind"], &1["size"], &1["col"], &1["row"]}) == [
             {"wealth_key_figures", "row", 1, 1},
             {"data_notes", "row", 1, 2},
             {"performance", "row", 1, 3},
             {"contribution", "row", 1, 4},
             {"positions", "row", 1, 5},
             {"cash_accounts", "row", 1, 6}
           ]

    assert Layout.validate(holdings.layout) == {:ok, holdings.layout}
    assert Templates.offered([holdings]) == [holdings]
  end
end
