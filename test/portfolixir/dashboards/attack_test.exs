defmodule Portfolixir.Dashboards.AttackTest do
  # Sprint 31 D1's attack lens (ADR-0062 §2, §3, §11; the plan's D-8 point
  # 10): the layout's refusals at their boundaries, the name's bounds in
  # code points against multi-byte, combining and invisible characters, the
  # journal's one entry per write and none per refusal, a stale
  # lock_version after a rename or a reposition, the template never stored,
  # and reads that send nothing but SELECTs. Written by a reviewer who did
  # not write the context, to break it.
  #
  # group: :dashboards -- a create takes the transaction advisory lock that
  # counts the dashboards (`Portfolixir.LockTable` row 30). Every name is
  # synthetic.
  use Portfolixir.DataCase, async: true, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Journal

  defp agent, do: Actor.api_token_rw("mcp")

  defp item(kind, size, col, row, extra \\ %{}),
    do: Map.merge(%{"kind" => kind, "size" => size, "col" => col, "row" => row}, extra)

  defp refusal(layout) do
    assert {:error, refusal} = Layout.validate(layout)
    Map.take(refusal, [:index, :field, :reason])
  end

  defp entries, do: Journal.list_entries(resource_type: "dashboard", order: :asc)

  defp create!(name, layout \\ []) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name, "layout" => layout})

    dashboard
  end

  defp name_errors(name),
    do: errors_on(Dashboard.changeset(%Dashboard{}, %{"name" => name}))[:name]

  # User story:
  # As the operator, or the agent I run, placing widgets on the grid,
  # I want every position at the grid's edge judged exactly,
  # so that a layout one cell off the grid is refused and one that fits is
  # stored as sent.
  #
  # Acceptance criteria:
  # - An S widget (3 columns) fits at col 10, not at col 11 or 12; an XL
  #   widget (12 columns) at col 1, not at 2.
  # - col 0, a negative col, row 0, a negative row and a row past the cap
  #   are off the grid; the cap's own row is on it.
  # - A float, a numeric string, a boolean or nil is not a whole number,
  #   even when it reads as one (1.0, "1").
  # - A number beyond any machine word is off the grid, never an overflow.
  test "the grid's edges are judged to the cell" do
    assert {:ok, _} = Layout.validate([item("due", "S", 10, 1)])
    assert refusal([item("due", "S", 11, 1)]) == %{index: 0, field: "col", reason: :off_grid}
    assert refusal([item("due", "S", 12, 1)]) == %{index: 0, field: "col", reason: :off_grid}
    assert {:ok, _} = Layout.validate([item("performance", "XL", 1, 1)])

    assert refusal([item("performance", "XL", 2, 1)]) ==
             %{index: 0, field: "col", reason: :off_grid}

    for col <- [0, -1, -12, 13, 10 ** 40, -(10 ** 40)] do
      assert refusal([item("due", "S", col, 1)]) == %{index: 0, field: "col", reason: :off_grid}
    end

    max_row = Layout.max_row()
    assert {:ok, _} = Layout.validate([item("allocation_drift", "L", 1, max_row)])

    for row <- [0, -1, max_row + 1, 10 ** 40] do
      assert refusal([item("due", "S", 1, row)]) == %{index: 0, field: "row", reason: :off_grid}
    end

    for not_whole <- [1.0, 1.5, "1", true, nil, [1], %{"n" => 1}] do
      assert refusal([item("due", "S", not_whole, 1)]) ==
               %{index: 0, field: "col", reason: :not_an_integer}

      assert refusal([item("due", "S", 1, not_whole)]) ==
               %{index: 0, field: "row", reason: :not_an_integer}
    end

    assert refusal([Map.delete(item("due", "S", 1, 1), "row")]) ==
             %{index: 0, field: "row", reason: :missing}

    # full is a page: refused as a size wherever it is placed.
    for kind <- Enum.filter(Dashboards.widgets(), &("full" in &1.sizes)) do
      assert refusal([item(kind.key, "full", 1, 1)]) ==
               %{index: 0, field: "size", reason: :unsupported_size}
    end

    for size <- ["s", " S", "S ", "", 3, nil] do
      assert refusal([item("due", size, 1, 1)]) ==
               %{index: 0, field: "size", reason: :unsupported_size}
    end
  end

  # User story:
  # As the operator arranging widgets edge to edge,
  # I want two widgets that touch accepted and two that share one cell
  # refused,
  # so that the grid holds what I placed and never two widgets on one cell.
  #
  # Acceptance criteria:
  # - An M widget (6 × 2) at col 4, row 4 covers cols 4–9, rows 4–5: an S
  #   widget (3 × 2 since Sprint 32 E4) touching it on any side or corner
  #   is accepted.
  # - An S widget sharing a cell with it at any edge or corner is refused,
  #   naming the later item and the earlier one.
  # - The same item twice is refused as an overlap.
  test "touching widgets are accepted, one shared cell is an overlap" do
    anchor = item("snapshots", "M", 4, 4)

    # S covers {col..col+2, row..row+1}.
    touching = [{1, 4}, {10, 4}, {1, 5}, {10, 5}, {4, 2}, {7, 2}, {4, 6}, {7, 6}, {1, 2}, {10, 6}]

    for {col, row} <- touching do
      assert {:ok, _} = Layout.validate([anchor, item("due", "S", col, row)]),
             "S at #{col},#{row} touches the M widget and should be accepted"
    end

    one_cell = [{2, 3}, {9, 3}, {2, 5}, {9, 5}, {4, 5}, {7, 3}]

    for {col, row} <- one_cell do
      assert {:error, %{index: 1, reason: :overlap, other: 0}} =
               Layout.validate([anchor, item("due", "S", col, row)]),
             "S at #{col},#{row} shares a cell with the M widget and should be refused"
    end

    # An L widget (6 × 4) reaches three rows below its start.
    tall = item("allocation_drift", "L", 7, 1)
    assert {:error, %{index: 1, other: 0}} = Layout.validate([tall, item("due", "S", 10, 4)])
    assert {:ok, _} = Layout.validate([tall, item("due", "S", 10, 5)])

    assert {:error, %{index: 1, reason: :overlap, other: 0}} =
             Layout.validate([item("due", "S", 1, 1), item("due", "S", 1, 1)])
  end

  # User story:
  # As the agent fixing a refused layout,
  # I want the refusal to name the first bad item whatever is wrong with the
  # later ones,
  # so that I fix the layout in the order it is read.
  #
  # Acceptance criteria:
  # - Of two bad items, the earlier one is named, whichever reason each has.
  # - A layout that is not a list (an object, a string, a number) is refused
  #   as a whole, with no index.
  # - An item that is not an object, and settings that are not one, are
  #   refused naming the item.
  test "the refusal names the first of two bad items, whatever their reasons" do
    good = item("due", "S", 1, 1)

    pairs = [
      {item("nope", "S", 4, 1), item("due", "S", 1, 1)},
      {item("due", "S", 0, 2), item("nope", "S", 1, 3)},
      {item("due", "S", 1, 1), item("due", "S", 0, 3)},
      {item("due", "S", 4, 1, %{"settings" => %{"period" => "1y"}}), "junk"},
      {item("due", "S", 4, 1, %{"x" => 1}), item("nope", "S", 1, 3)}
    ]

    for {first_bad, second_bad} <- pairs do
      assert {:error, %{index: 1}} = Layout.validate([good, first_bad, second_bad])
    end

    for not_a_list <- [%{"0" => good}, "[]", 1, true] do
      assert refusal(not_a_list) == %{index: nil, field: nil, reason: :not_a_list}
    end

    for not_an_object <- ["due", 1, nil, [good]] do
      assert refusal([good, not_an_object]) == %{index: 1, field: nil, reason: :not_an_object}
    end

    for settings <- [[], "view", 1, [%{"view_id" => 1}]] do
      assert refusal([item("movers", "L", 1, 1, %{"settings" => settings})]) ==
               %{index: 0, field: "settings", reason: :not_an_object}
    end
  end

  # User story:
  # As the operator, whose layout an agent writes,
  # I want a layout's settings to carry only a view and a period, of the
  # right types,
  # so that nothing the server does not read is stored.
  #
  # Acceptance criteria:
  # - Nested junk in settings (a map, a list, a float, a string) as a
  #   view_id is refused as naming no view; a negative one too.
  # - An unknown settings key is refused by name, a non-string key unnamed.
  # - A pinned period is matched exactly: "1Y", " 1y", "1J" and a number are
  #   refused; a period on a kind without one is refused as such.
  # - Settings that are empty or null are stored as the empty map.
  test "settings carry a view and a period of the right type, nothing else" do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{"name" => "Synthetic Growth"})
    with_settings = fn settings -> [item("movers", "L", 1, 1, %{"settings" => settings})] end

    assert {:ok, [%{"settings" => %{"view_id" => id}}]} =
             Layout.validate(with_settings.(%{"view_id" => view.id}))

    assert id == view.id

    for junk <- [-view.id, view.id * 1.0, %{"id" => view.id}, [view.id], "x", true, nil] do
      assert refusal(with_settings.(%{"view_id" => junk})) ==
               %{index: 0, field: "settings.view_id", reason: :unknown_view}
    end

    assert refusal(with_settings.(%{"view" => view.id})) ==
             %{index: 0, field: "settings.view", reason: :unknown_setting}

    assert refusal(with_settings.(%{"period" => "1y", "nested" => %{"deep" => [1, 2]}})) ==
             %{index: 0, field: "settings.nested", reason: :unknown_setting}

    assert refusal(with_settings.(%{1 => "x"})) ==
             %{index: 0, field: "settings", reason: :unknown_setting}

    for period <- ["1Y", " 1y", "1y ", "1J", "", 1, 1.0, ["1y"]] do
      assert refusal(with_settings.(%{"period" => period})) ==
               %{index: 0, field: "settings.period", reason: :unsupported_period}
    end

    assert refusal([item("due", "S", 1, 1, %{"settings" => %{"period" => "max"}})]) ==
             %{index: 0, field: "settings.period", reason: :no_period}

    assert {:ok, [%{"settings" => %{}}]} = Layout.validate(with_settings.(nil))
    assert {:ok, [%{"settings" => %{}}]} = Layout.validate(with_settings.(%{}))
  end

  # User story:
  # As the operator who deleted a view a dashboard named,
  # I want a new save that names the deleted view refused,
  # so that no layout is written naming a view that is gone.
  #
  # Acceptance criteria:
  # - A layout naming a live view is stored; once the view is deleted, the
  #   stored layout keeps its id (no cascade rewrites a layout, §2).
  # - A rename and a reposition of that dashboard still pass: they do not
  #   resend the layout.
  test "a deleted view leaves the stored id dangling; a rename still passes" do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{"name" => "Synthetic Short"})
    pinned = item("movers", "L", 1, 1, %{"settings" => %{"view_id" => view.id}})
    dashboard = create!("With a view", [pinned])

    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), view)

    assert %Dashboard{layout: [%{"settings" => %{"view_id" => stale}}]} =
             Dashboards.get_dashboard(dashboard.id)

    assert stale == view.id

    assert {:error, %{index: 0, field: "settings.view_id", reason: :unknown_view}} =
             Layout.validate([pinned])

    assert {:ok, %Dashboard{lock_version: 2}} =
             Dashboards.rename_dashboard(agent(), dashboard.id, "Renamed")

    assert {:ok, %Dashboard{lock_version: 3}} =
             Dashboards.reposition_dashboard(agent(), dashboard.id, 7)
  end

  # User story:
  # As the operator naming a dashboard in any script,
  # I want the 60-character bound counted as the database counts it, in
  # code points, and every invisible or control character refused,
  # so that a name never fails in the database and never hides text.
  #
  # Acceptance criteria:
  # - 60 two-byte, three-byte and four-byte characters pass; 61 are refused.
  # - Combining marks count each: 30 letters with an accent each (60 code
  #   points, 30 graphemes) pass; 31 are refused (62 code points).
  # - Emoji sequences count every code point: twelve 5-code-point families
  #   pass, thirteen are refused.
  # - Whitespace around the name, an NBSP and an ideographic space included,
  #   is trimmed before the bound is counted.
  # - NUL, DEL, a C1 control (NEL, U+0085) inside the name, the bidi
  #   override U+202E, the zero-width space U+200B and the byte-order mark
  #   U+FEFF are refused.
  # - The longest name the changeset passes is stored without a database
  #   error.
  test "the name's bound is counted in code points; invisible characters are refused" do
    for char <- ["ä", "€", "𝄞", "😀"] do
      assert name_errors(String.duplicate(char, 60)) == nil
      assert [_too_long] = name_errors(String.duplicate(char, 61))
    end

    accented = "e\u0301"
    assert name_errors(String.duplicate(accented, 30)) == nil
    assert [_too_long] = name_errors(String.duplicate(accented, 31))

    family = "👨\u200D👩\u200D👧"
    assert String.length(family) == 1
    assert name_errors(String.duplicate(family, 12)) == nil
    assert [_too_long] = name_errors(String.duplicate(family, 13))

    sixty = String.duplicate("x", 60)

    for padding <- [" ", "\t", "\u00A0", "\u3000", "\n"] do
      assert name_errors(padding <> sixty <> padding) == nil
    end

    for invisible <- ["\u0000", "\u007F", "\u0085", "\u009B", "\u202E", "\u200B", "\uFEFF"] do
      assert [_refused] = name_errors("Syn" <> invisible <> "thetic"),
             "#{inspect(invisible)} inside a name should be refused"
    end

    for name <- [
          String.duplicate("😀", 60),
          String.duplicate(accented, 30),
          String.duplicate(family, 12)
        ] do
      assert {:ok, %Dashboard{name: ^name}} =
               Dashboards.create_dashboard(agent(), %{"name" => name})
    end
  end

  # User story:
  # As the operator whose dashboard my agent renames,
  # I want a replace built on the lock_version I read before the rename
  # refused, with the renamed dashboard,
  # so that my replace never silently sets back the agent's rename.
  #
  # Acceptance criteria:
  # - A rename and a reposition each raise lock_version by one; a replace
  #   on the lock_version read before either is stale, answering the stored
  #   dashboard with the new name and position.
  # - The stale replace writes and journals nothing.
  # - An unchanged rename writes and journals nothing, and leaves the
  #   lock_version.
  test "a replace read before a rename or a reposition is stale" do
    dashboard = create!("Original", [item("due", "S", 1, 1)])
    replace = %{"name" => "Original", "layout" => [item("due", "S", 4, 1)], "lock_version" => 1}

    assert {:ok, %Dashboard{lock_version: 2}} =
             Dashboards.rename_dashboard(agent(), dashboard.id, "Agent's name")

    before = length(entries())

    assert {:error, :stale, %Dashboard{name: "Agent's name", lock_version: 2}} =
             Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, replace)

    assert {:ok, %Dashboard{lock_version: 3, position: 9}} =
             Dashboards.reposition_dashboard(agent(), dashboard.id, 9)

    assert {:error, :stale, %Dashboard{position: 9, lock_version: 3}} =
             Dashboards.replace_dashboard(
               Actor.owner_ui(),
               dashboard.id,
               Map.put(replace, "lock_version", 2)
             )

    assert length(entries()) == before + 1

    assert %Dashboard{name: "Agent's name", layout: [%{"col" => 1}]} =
             Dashboards.get_dashboard(dashboard.id)

    assert {:ok, %Dashboard{lock_version: 3}} =
             Dashboards.rename_dashboard(agent(), dashboard.id, " Agent's name ")

    assert length(entries()) == before + 1
  end

  # User story:
  # As the operator reading the journal,
  # I want exactly one entry per stored write, under the writer who made
  # it, and none for a write that was refused,
  # so that the journal says who changed a dashboard, and only when one
  # changed.
  #
  # Acceptance criteria:
  # - A template's copy, a create, a replace, a rename, a reposition and a
  #   delete, each by a different actor, journal one entry each under it.
  # - A refused create (name, layout), template copy, replace (stale, a bad
  #   lock_version of any type, a missing field), rename, reposition (0,
  #   negative, past the cap, a string, a float, nil) and a delete's dry run
  #   journal nothing and leave the row as it was.
  test "one journal entry per write under its actor, none per refusal" do
    owner = Actor.owner_ui()
    rw = agent()
    other = Actor.api_token_rw("second")

    {:ok, copy} = Dashboards.copy_template(owner, "overview", %{})
    {:ok, made} = Dashboards.create_dashboard(rw, %{"name" => "Made"})

    {:ok, made} =
      Dashboards.replace_dashboard(other, made.id, %{
        "name" => "Made",
        "layout" => [item("due", "S", 1, 1)],
        "lock_version" => 1
      })

    {:ok, made} = Dashboards.rename_dashboard(owner, made.id, "Renamed")
    {:ok, made} = Dashboards.reposition_dashboard(rw, made.id, 5)
    {:ok, _} = Dashboards.delete_dashboard(other, copy.id)

    assert Enum.map(entries(), &{&1.operation, &1.actor_type, &1.actor_label}) == [
             {:create, :owner_ui, nil},
             {:create, :api_token_rw, "mcp"},
             {:update, :api_token_rw, "second"},
             {:update, :owner_ui, nil},
             {:update, :api_token_rw, "mcp"},
             {:delete, :api_token_rw, "second"}
           ]

    counted = length(entries())
    stored = Dashboards.get_dashboard(made.id)

    refused = [
      fn -> Dashboards.create_dashboard(rw, %{"name" => ""}) end,
      fn -> Dashboards.create_dashboard(rw, %{"name" => "X", "layout" => [%{}]}) end,
      fn -> Dashboards.copy_template(rw, "overview", %{"name" => String.duplicate("x", 61)}) end,
      fn -> Dashboards.copy_template(rw, "overview", %{"layout" => []}) end,
      fn -> Dashboards.copy_template(rw, "no-such-template", %{}) end,
      fn -> Dashboards.rename_dashboard(rw, made.id, "Bad\u0000") end,
      fn -> Dashboards.rename_dashboard(rw, made.id, nil) end,
      fn -> Dashboards.rename_dashboard(rw, made.id + 1_000, "Gone") end
    ]

    replaces =
      for version <- [1, 2, 0, -1, "4", 4.0, nil, 10 ** 30] do
        fn ->
          Dashboards.replace_dashboard(rw, made.id, %{
            "name" => "Other",
            "layout" => [],
            "lock_version" => version
          })
        end
      end

    missing = fn ->
      Dashboards.replace_dashboard(rw, made.id, %{"name" => "Other", "layout" => []})
    end

    positions =
      for position <- [0, -1, Dashboard.max_position() + 1, "2", 2.0, nil, 10 ** 30] do
        fn -> Dashboards.reposition_dashboard(rw, made.id, position) end
      end

    for write <- refused ++ replaces ++ [missing | positions] do
      assert refused?(write.())
    end

    assert {:ok, %{dashboards: %{count: 1}}} = Dashboards.dry_run_delete_dashboard(rw, made.id)

    assert length(entries()) == counted
    assert Dashboards.get_dashboard(made.id) == stored
  end

  # {:error, :stale, stored} is a refusal of three elements; every other
  # refusal is a pair.
  defp refused?({:error, _reason}), do: true
  defp refused?({:error, _reason, _detail}), do: true
  defp refused?(_written), do: false

  # User story:
  # As the operator,
  # I want the template „Überblick“ to stay as shipped whatever I do with
  # my copy,
  # so that „Anpassen“ always starts from the curated layout.
  #
  # Acceptance criteria:
  # - Copying it stores a dashboard; replacing, renaming and deleting the
  #   copy leave the template's layout unchanged, and the template is never
  #   a row of its own.
  # - An unknown, a differently cased or a non-string key is not found,
  #   and writes nothing.
  # - A copy takes a name only; a stray key is refused by name.
  test "the template is never stored and never changed by its copy" do
    {:ok, shipped} = Dashboards.fetch_template("overview")

    {:ok, copy} = Dashboards.copy_template(agent(), "overview", %{"name" => "Mine"})

    {:ok, copy} =
      Dashboards.replace_dashboard(agent(), copy.id, %{
        "name" => "Mine",
        "layout" => [item("due", "S", 1, 1)],
        "lock_version" => copy.lock_version
      })

    {:ok, _} = Dashboards.delete_dashboard(agent(), copy.id)

    assert Dashboards.fetch_template("overview") == {:ok, shipped}
    assert hd(Templates.templates()) == shipped
    assert Dashboards.list_dashboards() == []

    for key <- ["Overview", "overview ", :overview, nil, 1, ""] do
      assert Dashboards.copy_template(agent(), key, %{}) == {:error, :not_found}
    end

    assert {:error, {:unknown_fields, %{"position" => [_]}}} =
             Dashboards.copy_template(agent(), "overview", %{"position" => 1})

    assert Dashboards.list_dashboards() == []
  end

  # User story:
  # As the operator ordering the menu,
  # I want a new dashboard placed after the last one however the menu was
  # reordered and thinned,
  # so that a create never lands in the middle or on a taken place.
  #
  # Acceptance criteria:
  # - After deletes leave gaps, a create takes one past the highest stored
  #   position.
  # - A reposition to the cap is accepted; one past it, 0 or a negative
  #   number is refused and moves nothing.
  # - Two dashboards may share a position; the menu then reads by id.
  test "a create goes one past the highest position, across gaps" do
    [a, b, c] = for name <- ~w(A B C), do: create!(name)
    {:ok, _} = Dashboards.delete_dashboard(agent(), b.id)
    {:ok, _} = Dashboards.reposition_dashboard(agent(), a.id, 40)

    d = create!("D")
    assert d.position == 41

    {:ok, _} = Dashboards.reposition_dashboard(agent(), c.id, 41)
    assert Enum.map(Dashboards.list_dashboards(), & &1.name) == ["A", "C", "D"]

    assert {:ok, %Dashboard{position: max}} =
             Dashboards.reposition_dashboard(agent(), c.id, Dashboard.max_position())

    assert max == Dashboard.max_position()

    for position <- [0, -5, Dashboard.max_position() + 1] do
      assert {:error, %Ecto.Changeset{}} =
               Dashboards.reposition_dashboard(agent(), c.id, position)
    end

    assert Dashboards.get_dashboard(c.id).position == Dashboard.max_position()
  end

  # User story:
  # As the operator opening the dashboards on a fresh instance,
  # I want every read to send the database nothing but reads,
  # so that looking at the menu never writes.
  #
  # Acceptance criteria:
  # - list_dashboards/0, entries/0 and get_dashboard/1 (a present id, an
  #   absent one, an id past bigint, a string and nil) send only SELECTs.
  # - On an empty table, entries/0 offers the template, and nothing is
  #   stored or journaled.
  test "reads send only SELECTs and store nothing" do
    handler = "dashboards-attack-reads-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        # The handler is global and this module is async: only the queries
        # this test's own process sends count, never a neighbour's.
        fn _event, _measurements, %{query: query}, _config ->
          if self() == parent, do: send(parent, {:query, query})
        end,
        nil
      )

    try do
      assert [%{type: :template, template: %{key: "overview"}}] = Dashboards.entries()
      assert Dashboards.list_dashboards() == []

      for id <- [1, 9_223_372_036_854_775_807, 9_223_372_036_854_775_808, "1", nil, -1] do
        assert Dashboards.get_dashboard(id) == nil
      end

      assert Dashboards.widgets() != []
      assert {:ok, _} = Dashboards.validate_layout([item("due", "S", 1, 1)])
    after
      :telemetry.detach(handler)
    end

    queries = drain_queries([])
    assert queries != []

    for query <- queries do
      assert query =~ ~r/^\s*SELECT\b/i, "a read sent #{inspect(query)}"
    end

    assert entries() == []
  end

  defp drain_queries(acc) do
    receive do
      {:query, query} -> drain_queries([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
