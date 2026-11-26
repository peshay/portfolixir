defmodule Portfolixir.Dashboards.ThemesTest do
  # Sprint 32 S5 (I61; ADR-0062's amendment of 2026-11-25, point 5; boards
  # ux-design-2026-11-25-sprint32/03 ①, 09, 11; D-15): the themes the
  # gallery offers beside the starters, „Krypto Lover“ and „Rücksetzer“
  # (the owner's silence on „What you need to do“ 2 kept the
  # recommended name; its key is `pullbacks`).
  use ExUnit.Case, async: true

  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates

  defp places(template),
    do: Enum.map(template.layout, &{&1["kind"], &1["size"], &1["col"], &1["row"], &1["settings"]})

  defp german(fun), do: Gettext.with_locale(PortfolixirWeb.Gettext, "de", fun)

  # User story:
  # As the operator starting a dashboard from a theme,
  # I want „Krypto Lover“ with the cycle, the performance, the tops and
  # flops, the distance to the high and the crashes, asking for my crypto
  # view, and „Rücksetzer“ as board 11 draws it,
  # so that each opens with what the owner described.
  #
  # Acceptance criteria:
  # - „Krypto Lover“: Bitcoin-Zyklus XL, Wertentwicklung L, Tops und Flops
  #   L, Abstand zum Hoch L, Crashes im Vergleich L; it asks for a scope.
  # - „Rücksetzer“: Crash-Chart XL following the period (1J by default),
  #   Crash-Chart L pinned to 1M, Crashes im Vergleich L, Tops und Flops L
  #   pinned to 1W and L pinned to 1M, Erholer nach Crashes XL; it asks for
  #   no scope.
  # - Both are themes, not starters; both validate as stored layouts, every
  #   kind built, so the gallery offers both; their German titles and lines.
  test "„Krypto Lover“ and „Rücksetzer“ hold the widgets their boards draw" do
    {:ok, krypto} = Templates.fetch("krypto_lover")
    {:ok, pullbacks} = Templates.fetch("pullbacks")

    assert places(krypto) == [
             {"bitcoin_cycle", "XL", 1, 1, %{}},
             {"performance", "L", 1, 5, %{}},
             {"movers", "L", 7, 5, %{}},
             {"distance_to_high", "L", 1, 9, %{}},
             {"crashes", "L", 7, 9, %{}}
           ]

    assert places(pullbacks) == [
             {"crash_chart", "XL", 1, 1, %{}},
             {"crash_chart", "L", 1, 5, %{"period" => "1m"}},
             {"crashes", "L", 7, 5, %{}},
             {"movers", "L", 1, 9, %{"period" => "1w"}},
             {"movers", "L", 7, 9, %{"period" => "1m"}},
             {"rebounders", "XL", 1, 13, %{}}
           ]

    assert {krypto.asks_scope, pullbacks.asks_scope} == {true, false}
    assert {krypto.starter, pullbacks.starter} == {false, false}
    # The starters are the screens (Sprint 32 W2: „Allokation & Ziele“).
    assert Enum.map(Templates.starters(), & &1.key) == ~w(overview allocation_targets)

    for template <- [krypto, pullbacks] do
      assert Layout.validate(template.layout) == {:ok, template.layout}, template.key
      assert Templates.group(template) == "theme"
    end

    assert Templates.offered(Templates.templates()) == Templates.templates()

    assert Enum.map(Templates.templates(), & &1.key) ==
             ~w(overview allocation_targets krypto_lover pullbacks)

    assert german(fn -> Templates.title("krypto_lover") end) == "Krypto Lover"
    assert german(fn -> Templates.title("pullbacks") end) == "Rücksetzer"

    assert german(fn -> Templates.subtitle("krypto_lover") end) ==
             "Zyklus, Halving, Krypto-Ansicht"

    assert german(fn -> Templates.subtitle("pullbacks") end) ==
             "Crashes im Vergleich, kurze Tops und Flops, Erholer"
  end
end
