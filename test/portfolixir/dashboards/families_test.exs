defmodule Portfolixir.Dashboards.FamiliesTest do
  # Sprint 32 E4 (ADR-0062's amendment of 2026-11-25, point 3; D-13;
  # planning board ux-design-2026-11-25-sprint32/09 ①): the sizes become
  # Apple's widget families S, M, L and XL, each a multiple of one square
  # unit and each of a fixed height; each size of a kind shows more of the
  # same, and a size that adds nothing is not offered. A layout stored by
  # Sprint 31 in the old names (S, W, M, T, L on a grid whose rows grew with
  # their content) is read as S → S, W → M, M → L, T → L, L → XL with its
  # rows doubled, and arranged by the edit mode's rule (E1), on the context's
  # load path, so the screen, the API and the MCP companion read the same;
  # the next save stores it on the new grid. Every name is synthetic.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30).
  use Portfolixir.DataCase, async: true, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Grid
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Repo

  # „Überblick“ exactly as Sprint 31's release shipped it and stored it in
  # every copy („Anpassen“), in the old names.
  @sprint31_overview [
    %{"kind" => "total_value", "size" => "S", "col" => 1, "row" => 1, "settings" => %{}},
    %{"kind" => "data_quality", "size" => "S", "col" => 4, "row" => 1, "settings" => %{}},
    %{"kind" => "due", "size" => "S", "col" => 7, "row" => 1, "settings" => %{}},
    %{"kind" => "off_target", "size" => "S", "col" => 10, "row" => 1, "settings" => %{}},
    %{"kind" => "performance", "size" => "L", "col" => 1, "row" => 2, "settings" => %{}},
    %{"kind" => "allocation_drift", "size" => "T", "col" => 9, "row" => 2, "settings" => %{}},
    %{"kind" => "movers", "size" => "M", "col" => 1, "row" => 5, "settings" => %{}},
    %{"kind" => "crashes", "size" => "M", "col" => 7, "row" => 5, "settings" => %{}},
    %{"kind" => "bitcoin_cycle", "size" => "M", "col" => 1, "row" => 7, "settings" => %{}},
    %{"kind" => "sale_review", "size" => "M", "col" => 7, "row" => 7, "settings" => %{}},
    %{"kind" => "snapshots", "size" => "S", "col" => 1, "row" => 9, "settings" => %{}}
  ]

  defp places(layout), do: Enum.map(layout, &{&1["kind"], &1["size"], &1["col"], &1["row"]})

  # A dashboard as Sprint 31 stored it: on the old grid (1), its layout in
  # the old names, written under a journal actor as every write was.
  defp stored_by_sprint31!(layout) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alt", "layout" => []})

    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system_job:test', true)")

      Repo.query!("UPDATE dashboards SET grid = 1, layout = $1 WHERE id = $2", [
        layout,
        dashboard.id
      ])
    end)

    dashboard
  end

  # User story:
  # As the operator, or the agent I run, composing a dashboard,
  # I want the sizes to be Apple's families, each a multiple of one unit
  # and of a fixed height,
  # so that a dashboard reads as calm rows and a native widget can later
  # take the same sizes.
  #
  # Acceptance criteria:
  # - The grid sizes are S (3 × 2), M (6 × 2), L (6 × 4) and XL (12 × 4),
  #   named small, medium, large and extra large; `full` stays a page; W
  #   and T are no size any more.
  # - Each kind takes the families its old sizes map to, less a size that
  #   adds nothing: „Gesamtwert“ S, M and L (board 01 ④); Crashes im
  #   Vergleich L only (its L showed what M did, with space: board 07 ①,
  #   finding 6); Allokation und Drift L (M and T both read as L).
  # - Each kind's sizes are listed smallest first, each larger than the
  #   one before it.
  test "the sizes are Apple's families, each kind's smallest first" do
    # Sprint 32 S2: and „Zeile“ (`row`), no family, as tall as its content.
    assert Widgets.sizes() == ~w(S M L XL row full)
    assert Widgets.dimensions("S") == {:ok, {3, 2}}
    assert Widgets.dimensions("M") == {:ok, {6, 2}}
    assert Widgets.dimensions("L") == {:ok, {6, 4}}
    assert Widgets.dimensions("XL") == {:ok, {12, 4}}
    assert Widgets.dimensions("W") == :error
    assert Widgets.dimensions("T") == :error
    assert Widgets.dimensions("full") == :error

    assert Widgets.family("S") == "small"
    assert Widgets.family("M") == "medium"
    assert Widgets.family("L") == "large"
    assert Widgets.family("XL") == "extra large"
    assert Widgets.family("W") == nil

    assert %{
             "total_value" => ~w(S M L),
             "data_quality" => ~w(S L),
             "due" => ~w(S),
             "off_target" => ~w(S L),
             "performance" => ~w(S L XL full),
             "movers" => ~w(S L),
             "snapshots" => ~w(S M),
             "allocation_drift" => ~w(L),
             "crashes" => ~w(L),
             "bitcoin_cycle" => ~w(L XL full),
             "sale_review" => ~w(L row),
             "distance_to_high" => ~w(L XL),
             "crash_chart" => ~w(L XL),
             "rebounders" => ~w(L XL)
           } == Map.new(Widgets.kinds(), &{&1.key, &1.sizes})

    area = fn size ->
      {:ok, {w, h}} = Widgets.dimensions(size)
      w * h
    end

    for kind <- Widgets.kinds() do
      # The families only: „Zeile“ is drawn at its content's height, no
      # multiple of S (Sprint 32 S2), and listed after them.
      grid = Enum.filter(kind.sizes, &(&1 not in ["full", "row"]))
      assert grid == Enum.sort_by(grid, area), kind.key
      assert grid == Enum.uniq_by(grid, area), kind.key
    end
  end

  # User story:
  # As the operator upgrading from Sprint 31,
  # I want my stored dashboards read on the new grid without a widget lost
  # or laid over another,
  # so that the update changes how they look, never what they hold.
  #
  # Acceptance criteria:
  # - Sprint 31's „Überblick“, read from the old grid: every item kept, in
  #   its order, each in the family its old size maps to (S → S, W → M,
  #   M → L, T → L, L → XL), the rows doubled and the layout arranged (no
  #   overlap, no gap a widget could float into): it is the new template,
  #   board 09's „Überblick“ on Apple's tiles.
  # - A size a kind no longer takes is read as the one of its sizes
  #   nearest to it: Crashes' old L as L.
  # - A layout on the current grid is read as stored.
  test "Sprint 31's Überblick is read on the families, nothing lost, nothing overlapping" do
    read = Grid.read(1, @sprint31_overview)

    assert {:ok, ^read} = Layout.validate(read)
    assert Enum.map(read, & &1["kind"]) == Enum.map(@sprint31_overview, & &1["kind"])

    assert places(read) == [
             {"total_value", "S", 1, 1},
             {"data_quality", "S", 4, 1},
             {"due", "S", 7, 1},
             {"off_target", "S", 10, 1},
             {"performance", "XL", 1, 3},
             {"allocation_drift", "L", 1, 7},
             {"movers", "L", 7, 7},
             {"crashes", "L", 1, 11},
             {"bitcoin_cycle", "L", 7, 11},
             {"sale_review", "L", 1, 15},
             {"snapshots", "S", 7, 15}
           ]

    {:ok, overview} = Templates.fetch("overview")
    assert places(overview.layout) == places(read)

    assert places(Grid.read(1, [%{"kind" => "crashes", "size" => "L", "col" => 1, "row" => 1}])) ==
             [{"crashes", "L", 1, 1}]

    assert Grid.read(Grid.current(), read) == read
  end

  # Acceptance criteria:
  # - A dashboard Sprint 31 stored reads through the context — one, the
  #   list and the menu — on the families, arranged, the same for the
  #   screen, the API and the companion; a read writes nothing.
  # - The next save stores it on the current grid, in the new names; a
  #   rename alone leaves the layout stored as it was and reads the same.
  test "a dashboard stored on the old grid reads on the families; the next save stores it so" do
    dashboard = stored_by_sprint31!(@sprint31_overview)

    read = Dashboards.get_dashboard(dashboard.id)
    assert places(read.layout) == places(Grid.read(1, @sprint31_overview))
    assert [%Dashboard{} = listed] = Dashboards.list_dashboards()
    assert listed.layout == read.layout
    assert [%{dashboard: %{layout: menu_layout}}] = Dashboards.entries()
    assert menu_layout == read.layout

    assert %{rows: [[1]]} =
             Repo.query!("SELECT grid FROM dashboards WHERE id = $1", [dashboard.id])

    {:ok, renamed} = Dashboards.rename_dashboard(Actor.owner_ui(), dashboard.id, "Neu")
    assert renamed.layout == read.layout

    assert %{rows: [[1]]} =
             Repo.query!("SELECT grid FROM dashboards WHERE id = $1", [dashboard.id])

    {:ok, saved} =
      Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
        "name" => "Neu",
        "layout" => read.layout,
        "lock_version" => renamed.lock_version
      })

    assert saved.layout == read.layout

    assert %{rows: [[2, stored]]} =
             Repo.query!("SELECT grid, layout FROM dashboards WHERE id = $1", [dashboard.id])

    assert places(stored) == places(read.layout)
  end

  # Acceptance criteria:
  # - DESIGN.md states the families with their columns and rows, the
  #   fixed row and the rule each kind's sizes are read against.
  test "DESIGN.md gains the families, the fixed row and the size rule" do
    design =
      "_bmad-output/planning-artifacts/design-language/DESIGN.md"
      |> File.read!()
      |> String.replace(~r/\s+/, " ")

    for line <- [
          "| **S** | small | 3 × 2 |",
          "| **M** | medium | 6 × 2 |",
          "| **L** | large | 6 × 4 |",
          "| **XL** | extra large | 12 × 4 |",
          "Every row is a fixed 7rem",
          "Each size shows more of the same, never something else",
          "A size that adds nothing readable is not offered."
        ] do
      assert design =~ line, line
    end
  end

  # Acceptance criteria:
  # - A write names the new families only: an item sized W or T, which no
  #   kind takes any more, is refused naming the families S, M, L and XL.
  test "a write in the old names W and T is refused naming the families" do
    for size <- ~w(W T) do
      assert {:error, %{reason: :unsupported_size, field: "size", message: message}} =
               Layout.validate([
                 %{"kind" => "snapshots", "size" => size, "col" => 1, "row" => 1}
               ])

      assert message =~ "S, M, L and XL"
    end
  end
end
