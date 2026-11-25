defmodule Portfolixir.Dashboards.LayoutTest do
  # Sprint 31 D1 (FR-60, ADR-0062 §2, §4, §11): a layout is validated on
  # write and refused naming its first bad item; nothing is repaired
  # silently. The layout is input from the screen and from the API, so it is
  # bounded and its keys are matched as strings.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates

  defp item(kind, size, col, row, extra \\ %{}),
    do: Map.merge(%{"kind" => kind, "size" => size, "col" => col, "row" => row}, extra)

  defp refusal(layout) do
    assert {:error, refusal} = Layout.validate(layout)
    Map.take(refusal, [:index, :field, :reason])
  end

  # User story:
  # As the operator, or the agent I run, saving a dashboard,
  # I want a layout of registered widgets on the grid to be stored as sent,
  # so that the screen and the agent read back exactly what was saved.
  #
  # Acceptance criteria:
  # - A valid layout comes back normalized: each item's kind, size, col, row
  #   and settings (an empty map when none was sent), in the order sent.
  # - Atom keys from code are read as their strings; no item is moved.
  test "a valid layout is accepted and normalized, in the order sent" do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{"name" => "Synthetic Growth"})

    layout = [
      item("movers", "L", 7, 1, %{"settings" => %{"period" => "3m", "view_id" => view.id}}),
      %{kind: "total_value", size: "S", col: 1, row: 1},
      item("allocation_drift", "L", 1, 3, %{"settings" => %{}})
    ]

    assert {:ok, normalized} = Layout.validate(layout)

    assert normalized == [
             %{
               "kind" => "movers",
               "size" => "L",
               "col" => 7,
               "row" => 1,
               "settings" => %{"period" => "3m", "view_id" => view.id}
             },
             %{"kind" => "total_value", "size" => "S", "col" => 1, "row" => 1, "settings" => %{}},
             %{
               "kind" => "allocation_drift",
               "size" => "L",
               "col" => 1,
               "row" => 3,
               "settings" => %{}
             }
           ]

    assert Layout.validate([]) == {:ok, []}
  end

  # User story:
  # As the operator, or the agent I run,
  # I want a layout the server cannot draw refused with the first bad item
  # named,
  # so that I can correct it instead of finding a widget silently moved or
  # dropped.
  #
  # Acceptance criteria (ADR-0062 §2), each a refusal naming the item's
  # index (0-based), the field and the reason:
  # - an unknown kind; a missing kind;
  # - a missing size; a size the kind lacks; `full`, which is a page;
  # - a position off the grid: col below 1 or above 12, col + width - 1
  #   above 12, row below 1, a col or row that is not a whole number;
  # - two items overlapping (the later one is named, with the earlier);
  # - an unknown key in an item or in its settings;
  # - a view_id naming no view;
  # - a pinned period on a kind without one, or one the kind does not take;
  # - 41 items.
  test "an unknown or missing kind is refused naming the item" do
    ok = item("total_value", "S", 1, 1)

    assert refusal([ok, item("nope", "S", 4, 1)]) ==
             %{index: 1, field: "kind", reason: :unknown_kind}

    assert refusal([Map.delete(ok, "kind")]) == %{index: 0, field: "kind", reason: :missing}
    assert refusal([%{ok | "kind" => 7}]) == %{index: 0, field: "kind", reason: :unknown_kind}
  end

  test "a missing size, a size the kind lacks and full are refused" do
    assert refusal([Map.delete(item("movers", "L", 1, 1), "size")]) ==
             %{index: 0, field: "size", reason: :missing}

    assert refusal([item("movers", "M", 1, 1)]) ==
             %{index: 0, field: "size", reason: :unsupported_size}

    assert refusal([item("performance", "full", 1, 1)]) ==
             %{index: 0, field: "size", reason: :unsupported_size}

    assert refusal([item("movers", "XL", 1, 1)]) ==
             %{index: 0, field: "size", reason: :unsupported_size}

    # Sprint 31's W and T are no size any more (Sprint 32 E4).
    assert refusal([item("snapshots", "W", 1, 1)]) ==
             %{index: 0, field: "size", reason: :unsupported_size}

    assert refusal([item("allocation_drift", "T", 1, 1)]) ==
             %{index: 0, field: "size", reason: :unsupported_size}
  end

  test "a position off the grid is refused" do
    assert refusal([item("total_value", "S", 0, 1)]) == %{
             index: 0,
             field: "col",
             reason: :off_grid
           }

    assert refusal([item("total_value", "S", 13, 1)]) == %{
             index: 0,
             field: "col",
             reason: :off_grid
           }

    # S is 3 wide: col 10 ends at 12, col 11 at 13.
    assert {:ok, _} = Layout.validate([item("total_value", "S", 10, 1)])

    assert refusal([item("total_value", "S", 11, 1)]) == %{
             index: 0,
             field: "col",
             reason: :off_grid
           }

    assert refusal([item("performance", "XL", 2, 1)]) == %{
             index: 0,
             field: "col",
             reason: :off_grid
           }

    assert refusal([item("total_value", "S", 1, 0)]) == %{
             index: 0,
             field: "row",
             reason: :off_grid
           }

    assert refusal([item("total_value", "S", 1, -3)]) == %{
             index: 0,
             field: "row",
             reason: :off_grid
           }

    assert refusal([item("total_value", "S", 1, Layout.max_row() + 1)]) ==
             %{index: 0, field: "row", reason: :off_grid}

    assert refusal([item("total_value", "S", "1", 1)]) ==
             %{index: 0, field: "col", reason: :not_an_integer}

    assert refusal([item("total_value", "S", 1, 1.0)]) ==
             %{index: 0, field: "row", reason: :not_an_integer}

    assert refusal([Map.delete(item("total_value", "S", 1, 1), "row")]) ==
             %{index: 0, field: "row", reason: :missing}
  end

  test "two items overlapping are refused naming the later one and the earlier" do
    # L at col 1 row 1 covers cols 1–6, rows 1–4; an S at col 6 row 4 meets it.
    layout = [item("movers", "L", 1, 1), item("total_value", "S", 7, 1), item("due", "S", 6, 4)]

    assert {:error, %{index: 2, field: "col", reason: :overlap, other: 0}} =
             Layout.validate(layout)

    # Edge to edge is no overlap.
    assert {:ok, _} =
             Layout.validate([
               item("movers", "L", 1, 1),
               item("due", "S", 7, 3),
               item("due", "S", 1, 5)
             ])
  end

  test "unknown keys in an item or in its settings are refused" do
    assert refusal([item("due", "S", 1, 1, %{"colour" => "red"})]) ==
             %{index: 0, field: "colour", reason: :unknown_key}

    assert refusal([item("due", "S", 1, 1, %{"settings" => %{"title" => "Mine"}})]) ==
             %{index: 0, field: "settings.title", reason: :unknown_setting}

    assert refusal([item("due", "S", 1, 1, %{"settings" => ["period"]})]) ==
             %{index: 0, field: "settings", reason: :not_an_object}

    assert refusal([item("due", "S", 1, 1, %{7 => "x"})]) ==
             %{index: 0, field: nil, reason: :unknown_key}

    assert refusal(["movers"]) == %{index: 0, field: nil, reason: :not_an_object}
  end

  test "a view_id naming no view is refused" do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{"name" => "Synthetic Income"})
    with_view = fn id -> item("movers", "L", 1, 1, %{"settings" => %{"view_id" => id}}) end

    assert {:ok, _} = Layout.validate([with_view.(view.id)])

    assert refusal([with_view.(view.id + 1_000)]) ==
             %{index: 0, field: "settings.view_id", reason: :unknown_view}

    assert refusal([with_view.("#{view.id}")]) ==
             %{index: 0, field: "settings.view_id", reason: :unknown_view}

    assert refusal([with_view.(0)]) == %{
             index: 0,
             field: "settings.view_id",
             reason: :unknown_view
           }

    # Beyond bigint: refused, never sent to the database.
    assert refusal([with_view.(9_223_372_036_854_775_808)]) ==
             %{index: 0, field: "settings.view_id", reason: :unknown_view}
  end

  # A view on a kind that takes none (scope :none) is refused like a pin on
  # a kind without a period: the widget would carry a setting it never
  # reads.
  test "a view_id on a kind that takes no view is refused" do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{"name" => "Synthetic Scope"})

    assert {:ok, _} =
             Layout.validate([
               item("movers", "L", 1, 1, %{"settings" => %{"view_id" => view.id}})
             ])

    for kind <- ~w(due crashes snapshots) do
      size = if kind == "crashes", do: "L", else: "S"

      assert refusal([item(kind, size, 1, 1, %{"settings" => %{"view_id" => view.id}})]) ==
               %{index: 0, field: "settings.view_id", reason: :no_view}
    end
  end

  test "a pinned period on a kind without one, or one it does not take, is refused" do
    pin = fn kind, size, period ->
      item(kind, size, 1, 1, %{"settings" => %{"period" => period}})
    end

    assert {:ok, _} = Layout.validate([pin.("movers", "L", "max")])
    assert {:ok, _} = Layout.validate([pin.("performance", "XL", "1d")])
    assert {:ok, _} = Layout.validate([pin.("total_value", "S", "max")])

    assert refusal([pin.("crashes", "L", "1y")]) ==
             %{index: 0, field: "settings.period", reason: :no_period}

    # Sprint 32 T1: 5y is a key of the vocabulary now; 6y is none.
    assert {:ok, _} = Layout.validate([pin.("movers", "L", "5y")])
    assert {:ok, _} = Layout.validate([pin.("performance", "L", "prev_quarter")])
    assert {:ok, _} = Layout.validate([pin.("movers", "L", "year:2024")])

    assert refusal([pin.("movers", "L", "6y")]) ==
             %{index: 0, field: "settings.period", reason: :unsupported_period}

    assert refusal([pin.("movers", "L", "year:24")]) ==
             %{index: 0, field: "settings.period", reason: :unsupported_period}

    assert refusal([pin.("movers", "L", "quarter")]) ==
             %{index: 0, field: "settings.period", reason: :unsupported_period}

    assert refusal([pin.("movers", "L", nil)]) ==
             %{index: 0, field: "settings.period", reason: :unsupported_period}
  end

  test "41 items are refused, 40 are not, and a layout must be a list" do
    forty = for n <- 0..39, do: item("total_value", "S", rem(n, 4) * 3 + 1, div(n, 4) * 2 + 1)

    assert {:ok, stored} = Layout.validate(forty)
    assert length(stored) == 40
    assert Layout.max_items() == 40

    assert refusal(forty ++ [item("due", "S", 1, 21)]) ==
             %{index: 40, field: nil, reason: :too_many_items}

    assert refusal(%{"kind" => "due"}) == %{index: nil, field: nil, reason: :not_a_list}
    assert refusal(nil) == %{index: nil, field: nil, reason: :not_a_list}
  end

  test "the refusal names the first bad item and carries an English message" do
    assert {:error, refusal} =
             Layout.validate([
               item("due", "S", 1, 1),
               item("due", "L", 1, 1),
               item("nope", "S", 1, 1)
             ])

    assert refusal.index == 1
    assert refusal.reason == :unsupported_size

    assert refusal.message ==
             "is not a size this widget kind takes: the sizes are the families S, M, L and XL"
  end

  # User story:
  # As the operator on a fresh instance,
  # I want the shipped template „Überblick“ to be a layout the server
  # accepts,
  # so that „Anpassen“ copies a dashboard that saves.
  #
  # Acceptance criteria:
  # - The template's layout passes the validation unchanged.
  # - It is board ux-design-2026-11-25-sprint32/09's arrangement on Apple's
  #   families (Sprint 32 E4): four S widgets in rows 1 and 2, then
  #   Wertentwicklung XL, Allokation und Drift L and Tops und Flops L,
  #   Crashes L and Bitcoin-Zyklus L, Verkaufsrückblick L and Snapshots S.
  # - Only the template „Überblick“ is offered (ADR-0062 §3: a template whose
  #   kinds are not all built is not), and it names only registered kinds.
  test "the template Überblick passes the validation as it stands" do
    assert [%{key: "overview"} = overview] = Templates.templates()
    assert Templates.fetch("overview") == {:ok, overview}
    assert Templates.fetch("performance") == :error
    assert Templates.fetch(:overview) == :error

    assert {:ok, normalized} = Layout.validate(overview.layout)
    assert normalized == overview.layout

    assert Enum.map(overview.layout, &{&1["kind"], &1["size"], &1["col"], &1["row"]}) == [
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

    assert Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn -> Templates.title("overview") end) ==
             "Überblick"

    assert Gettext.with_locale(PortfolixirWeb.Gettext, "en", fn -> Templates.title("overview") end) ==
             overview.title
  end
end
