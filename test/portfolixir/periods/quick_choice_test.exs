defmodule Portfolixir.Periods.QuickChoiceTest do
  # Sprint 32 T3 (I59; ADR-0062's amendment of 2026-11-25, point 6): the
  # quick choice in the dashboard's top bar is the operator's — up to six
  # keys of the vocabulary, stored on the server, defaulting to 1w mtd ytd
  # 1y max; journaled as a setting under its writer. A key that names a
  # deleted period drops from it, and the read says which. Every name is
  # synthetic.
  #
  # group: :periods -- a period's create takes the count lock of
  # `Portfolixir.LockTable` row 31.
  use Portfolixir.DataCase, async: true, group: :periods

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Periods

  defp agent, do: Actor.api_token_rw("mcp")

  defp entries,
    do:
      Journal.list_entries(resource_type: "setting", order: :asc)
      |> Enum.filter(&((&1.after || %{})["key"] == "period_quick_choice"))

  # User story:
  # As the operator,
  # I want my own choice of up to six periods in the top bar, the same on
  # every device,
  # so that the periods I use are one tap away and the rest stay in the
  # menu.
  #
  # Acceptance criteria:
  # - Unset, the quick choice is 1w mtd ytd 1y max, marked as the default.
  # - A write stores up to six keys in their order, the vocabulary's and
  #   saved:<id> of a stored period, journaled as a setting upsert under
  #   the writer; none at all is a choice too.
  # - Refused, each writing nothing: a seventh key, a key twice, a key that
  #   is none, a saved key that names no stored period, a list that is no
  #   list of strings.
  test "the default, a stored choice, and every refusal" do
    assert Periods.quick_choice() == %{keys: ~w(1w mtd ytd 1y max), default: true, dropped: []}
    assert Periods.default_quick_choice() == ~w(1w mtd ytd 1y max)
    assert Periods.max_quick() == 6

    {:ok, own} =
      Periods.create_saved(Actor.owner_ui(), %{
        "name" => "Seit Umschichtung",
        "from" => "2025-03-01"
      })

    keys = ["1m", "saved:#{own.id}", "qtd", "year:2024", "max"]

    assert Periods.put_quick_choice(agent(), keys) == {:ok, keys}
    assert Periods.quick_choice() == %{keys: keys, default: false, dropped: []}

    assert [entry] = entries()
    assert entry.actor_type == :api_token_rw
    assert entry.operation == :upsert

    for {refused, why} <- [
          {~w(1d 1w 1m 3m 6m 1y 3y), :too_many},
          {~w(1w 1w), :duplicate},
          {~w(1w week), :unknown_key},
          {["saved:#{own.id + 1000}"], :unknown_key},
          {[:"1w"], :unknown_key},
          {"1w,mtd", :not_a_list}
        ] do
      assert {:error, {^why, _message}} = Periods.put_quick_choice(agent(), refused),
             inspect(refused)
    end

    assert Periods.quick_choice().keys == keys
    assert length(entries()) == 1

    assert Periods.put_quick_choice(agent(), []) == {:ok, []}
    assert Periods.quick_choice() == %{keys: [], default: false, dropped: []}
  end

  # User story:
  # As the operator who deleted „Sommer 2026“, which stood in the quick
  # choice,
  # I want it gone from the bar and the menu to say so once,
  # so that the bar never shows a period that is not there.
  #
  # Acceptance criteria:
  # - The read leaves the deleted period's key out and names it under
  #   dropped; the stored value is not rewritten by a read.
  # - The next write is the choice without it.
  test "a key that names a deleted period drops from the choice, and the read says which" do
    {:ok, summer} =
      Periods.create_saved(Actor.owner_ui(), %{
        "name" => "Sommer 2026",
        "from" => "2026-06-01",
        "to" => "2026-08-31"
      })

    key = "saved:#{summer.id}"
    {:ok, _} = Periods.put_quick_choice(agent(), ["1w", key, "ytd"])
    {:ok, _} = Periods.delete_saved(Actor.owner_ui(), summer.id)

    assert Periods.quick_choice() == %{keys: ~w(1w ytd), default: false, dropped: [key]}
    assert length(entries()) == 1

    {:ok, _} = Periods.put_quick_choice(agent(), ~w(1w ytd 1y))
    assert Periods.quick_choice() == %{keys: ~w(1w ytd 1y), default: false, dropped: []}
  end
end
