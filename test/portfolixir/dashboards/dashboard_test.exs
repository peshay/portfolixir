defmodule Portfolixir.Dashboards.DashboardTest do
  # Sprint 31 D1 (FR-60, ADR-0062 §2, §3): a dashboard is a row — a name,
  # its place in the menu, a layout and a lock_version — in a table armed
  # with the journal-actor guard, so no write lands unjournaled. A read
  # never writes, and a fresh instance stores nothing.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Journal

  defp errors(changeset), do: Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)

  defp layout_error(changeset) do
    [{message, meta}] = Keyword.get_values(changeset.errors, :layout)
    {message, Map.new(meta)}
  end

  # User story:
  # As the operator naming a dashboard,
  # I want a name of one to sixty characters, on one line,
  # so that the menu shows every name whole and nothing hidden in it.
  #
  # Acceptance criteria:
  # - A name is trimmed; an empty or whitespace-only one is refused.
  # - 60 characters (code points) pass; 61 are refused.
  # - A control character (a line break, a NUL, DEL) is refused.
  test "the name is trimmed, 1 to 60 characters, without a control character" do
    assert Dashboard.changeset(%Dashboard{}, %{"name" => "  Kurzfristig  "}).changes.name ==
             "Kurzfristig"

    sixty = String.duplicate("ä", 60)
    assert Dashboard.changeset(%Dashboard{}, %{"name" => sixty}).valid?

    assert %{name: [_too_long]} =
             errors(Dashboard.changeset(%Dashboard{}, %{"name" => sixty <> "b"}))

    for blank <- ["", "   ", "\t\n"] do
      assert %{name: ["can't be blank"]} =
               errors(Dashboard.changeset(%Dashboard{}, %{"name" => blank}))
    end

    assert %{name: ["can't be blank"]} = errors(Dashboard.changeset(%Dashboard{}, %{}))

    for control <- ["Line\nbreak", "Nul\0", "Del\x7F", "Bell\a"] do
      assert %{name: [_control]} = errors(Dashboard.changeset(%Dashboard{}, %{"name" => control}))
    end

    assert %{name: ["is invalid"]} = errors(Dashboard.changeset(%Dashboard{}, %{"name" => 7}))
  end

  # User story:
  # As the agent writing a layout through the API,
  # I want a refused layout to name the first bad item on the changeset,
  # so that the 422 can say which widget to fix.
  #
  # Acceptance criteria:
  # - A valid layout is put normalized; an absent one is the empty layout.
  # - A refused one is one error on :layout carrying index, field and reason.
  test "the layout is validated on the changeset, naming the first bad item" do
    changeset =
      Dashboard.changeset(%Dashboard{}, %{
        "name" => "Mine",
        "layout" => [%{"kind" => "due", "size" => "S", "col" => 1, "row" => 1}]
      })

    assert changeset.valid?

    assert Ecto.Changeset.get_change(changeset, :layout) == [
             %{"kind" => "due", "size" => "S", "col" => 1, "row" => 1, "settings" => %{}}
           ]

    assert Ecto.Changeset.get_field(Dashboard.changeset(%Dashboard{}, %{"name" => "M"}), :layout) ==
             []

    refused =
      Dashboard.changeset(%Dashboard{}, %{
        "name" => "Mine",
        "layout" => [
          %{"kind" => "due", "size" => "S", "col" => 1, "row" => 1},
          %{"kind" => "due", "size" => "S", "col" => 12, "row" => 1}
        ]
      })

    refute refused.valid?

    assert {"is off the grid", %{index: 1, field: "col", reason: :off_grid}} =
             layout_error(refused)
  end

  # User story:
  # As the operator auditing my instance,
  # I want the dashboards table to refuse a write that carries no actor,
  # so that every stored dashboard write is journaled (ADR-0017).
  #
  # Acceptance criteria:
  # - An insert outside the journal is refused by the guard trigger.
  # - The table's bounds stand behind the changeset: a name of 61
  #   characters, a layout of 41 items, a position below 1.
  test "the table refuses an unjournaled write and holds its bounds" do
    insert = fn name, layout, position ->
      Repo.query(
        "INSERT INTO dashboards (name, position, layout, lock_version, inserted_at, updated_at) " <>
          "VALUES ($1, $2, $3, 1, now(), now())",
        [name, position, layout]
      )
    end

    assert {:error, %Postgrex.Error{postgres: %{message: message}}} = insert.("Mine", [], 1)
    assert message =~ "journal"

    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

      for {name, layout, position, constraint} <- [
            {String.duplicate("a", 61), [], 1, nil},
            {"Mine", List.duplicate(%{}, 41), 1, "dashboards_layout_check"},
            {"Mine", %{}, 1, "dashboards_layout_check"},
            {"Mine", [], 0, "dashboards_position_check"},
            {"", [], 1, "dashboards_name_check"}
          ] do
        Repo.query!("SAVEPOINT bound")
        assert {:error, %Postgrex.Error{postgres: postgres}} = insert.(name, layout, position)
        if constraint, do: assert(postgres.constraint == constraint)
        Repo.query!("ROLLBACK TO SAVEPOINT bound")
      end
    end)
  end

  # User story:
  # As the operator opening a fresh instance,
  # I want the template „Überblick“ offered and nothing stored by the read,
  # so that looking at the app never writes (ADR-0062 §3).
  #
  # Acceptance criteria:
  # - Listing on an empty table answers [] and leaves the table empty and
  #   the journal without a dashboard entry.
  # - The entries are the templates, each marked as one.
  test "a read on an empty table writes nothing and offers the template" do
    assert Dashboards.list_dashboards() == []
    assert [%{type: :template, template: %{key: "overview"}}] = Dashboards.entries()
    assert Dashboards.get_dashboard(1) == nil
    assert Dashboards.get_dashboard(-1) == nil
    assert Dashboards.get_dashboard(9_223_372_036_854_775_808) == nil
    assert Dashboards.get_dashboard("1") == nil

    assert Repo.aggregate(Dashboard, :count) == 0

    assert Journal.list_entries(resource_type: "dashboard") == []
  end

  test "the context answers the registry, the templates and the limits" do
    assert Dashboards.widgets() == Widgets.kinds()
    assert {:ok, %{key: "movers"}} = Dashboards.fetch_widget("movers")
    assert Dashboards.fetch_widget("nope") == :error

    assert [%{key: "overview"}, %{key: "krypto_lover"}, %{key: "pullbacks"}] =
             Dashboards.templates()

    assert {:ok, %{key: "overview"}} = Dashboards.fetch_template("overview")
    assert Dashboards.max_dashboards() == 50
    assert Dashboards.name_max() == 60
    assert {:error, %{index: 0}} = Dashboards.validate_layout([%{}])
  end
end
