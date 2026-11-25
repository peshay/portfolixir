defmodule Portfolixir.Dashboards.NoAtomTest do
  # Sprint 31 D1 (ADR-0062 §1, §11; AGENTS.md, "Never create atoms from
  # external input"): a layout and a write's attributes come from the screen
  # and from the API, so an unknown kind, an unknown key in an item or in its
  # settings, and an unknown attribute are matched as strings and refused,
  # never turned into an atom.
  #
  # async: false -- the atom table is the VM's, and the synchronous modules
  # run after every asynchronous one, so no other test makes atoms while
  # this one counts.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  defp fresh(prefix), do: "#{prefix}_zq#{System.unique_integer([:positive])}x"

  defp attempt(n) do
    item = %{
      "kind" => fresh("kind#{n}"),
      "size" => fresh("size"),
      "col" => 1,
      "row" => 1
    }

    stray_key = %{"kind" => "due", "size" => "S", "col" => 1, "row" => 1, fresh("key") => 1}

    stray_setting = %{
      "kind" => "movers",
      "size" => "L",
      "col" => 1,
      "row" => 1,
      "settings" => %{fresh("setting") => true, "period" => fresh("period")}
    }

    pinned = %{
      "kind" => "movers",
      "size" => "L",
      "col" => 1,
      "row" => 1,
      "settings" => %{"period" => fresh("period")}
    }

    for layout <- [[item], [stray_key], [stray_setting], [pinned]] do
      {:error, _refusal} = Dashboards.validate_layout(layout)

      {:error, %Ecto.Changeset{}} =
        Dashboards.create_dashboard(Actor.api_token_rw("mcp"), %{
          "name" => "N",
          "layout" => layout
        })
    end

    {:error, {:unknown_fields, _}} =
      Dashboards.create_dashboard(Actor.api_token_rw("mcp"), %{
        fresh("attr") => "x",
        "name" => "N"
      })

    {:error, :not_found} =
      Dashboards.copy_template(Actor.api_token_rw("mcp"), fresh("template"), %{})

    :error = Dashboards.fetch_widget(fresh("widget"))
  end

  # User story:
  # As the operator,
  # I want unknown widget kinds, item keys, setting keys, periods and
  # attributes to make no atom,
  # so that an agent or a crafted request cannot fill the VM's atom table
  # through the dashboard writes.
  #
  # Acceptance criteria:
  # - 300 refused writes, each with fresh unknown names everywhere a key or
  #   a kind is read, leave the VM's atom count unchanged.
  # - The count would see a writer that made atoms from them.
  test "unknown kinds, keys, settings, periods and attributes make no atom" do
    attempt(0)
    before = :erlang.system_info(:atom_count)

    for n <- 1..300, do: attempt(n)

    assert :erlang.system_info(:atom_count) == before
    assert Dashboards.list_dashboards() == []
  end

  test "the count would see a writer that makes atoms" do
    before = :erlang.system_info(:atom_count)
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    _made = for n <- 1..10, do: String.to_atom(fresh("made#{n}"))
    assert :erlang.system_info(:atom_count) - before >= 10
  end
end
