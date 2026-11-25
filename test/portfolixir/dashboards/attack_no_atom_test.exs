defmodule Portfolixir.Dashboards.AttackNoAtomTest do
  # Sprint 31 D1's attack lens (ADR-0062 §1, §11; AGENTS.md, "Never create
  # atoms from external input"): thousands of distinct unknown keys in one
  # write, keys that are not strings, and unknown periods handed to the
  # registry's period functions, all refused or answered without one new
  # atom.
  #
  # async: false -- the atom table is the VM's, and the synchronous modules
  # run after every asynchronous one, so no other test makes atoms while
  # this one counts. It stores no dashboard.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Widgets

  @keys 5_000

  defp fresh(prefix), do: "#{prefix}_aq#{System.unique_integer([:positive])}y"

  defp many(prefix), do: Map.new(1..@keys, &{fresh("#{prefix}#{&1}"), &1})

  defp attempt do
    agent = Actor.api_token_rw("mcp")
    base = %{"kind" => "movers", "size" => "L", "col" => 1, "row" => 1}

    layouts = [
      [Map.merge(base, many("item"))],
      [Map.put(base, "settings", many("setting"))],
      [Map.put(base, "settings", %{"period" => fresh("period")})],
      [Map.merge(base, %{{:tuple, fresh("t")} => 1, 1.5 => 2})],
      [Map.put(base, "kind", fresh("kind"))],
      [Map.put(base, "size", fresh("size"))]
    ]

    for layout <- layouts do
      {:error, _refusal} = Dashboards.validate_layout(layout)

      {:error, %Ecto.Changeset{}} =
        Dashboards.create_dashboard(agent, %{"name" => "N", "layout" => layout})
    end

    {:error, {:unknown_fields, unknown}} =
      Dashboards.create_dashboard(agent, Map.put(many("attr"), "name", "N"))

    @keys = map_size(unknown)

    {:error, {:unknown_fields, _}} =
      Dashboards.replace_dashboard(agent, 1, Map.put(many("replace"), {:k, fresh("k")}, 1))

    {:error, {:unknown_fields, _}} = Dashboards.copy_template(agent, "overview", many("copy"))

    false = Widgets.takes_period?("movers", fresh("period"))
    false = Widgets.takes_period?(fresh("kind"), "1y")

    {:error, :unknown_period} =
      Widgets.source_params("movers", fresh("period"), ~D[2026-11-21])

    {:error, :unknown_kind} = Widgets.source_params(fresh("kind"), "1y", ~D[2026-11-21])
    nil = Widgets.title(fresh("title"))
    :error = Dashboards.fetch_template(fresh("template"))
  end

  # User story:
  # As the operator,
  # I want a write carrying thousands of unknown keys, or keys that are not
  # strings, and unknown periods sent to the registry to make no atom,
  # so that a crafted request cannot fill the VM's atom table.
  #
  # Acceptance criteria:
  # - Ten rounds of writes, each with 5,000 fresh unknown keys in the
  #   attributes, an item and its settings, plus tuple and float keys and
  #   fresh periods and kinds, leave the atom count unchanged.
  # - The unknown attributes are all named in the refusal, as strings.
  # - Nothing is stored.
  test "thousands of distinct unknown keys and periods make no atom" do
    attempt()
    before = :erlang.system_info(:atom_count)

    for _round <- 1..10, do: attempt()

    assert :erlang.system_info(:atom_count) == before
    assert Dashboards.list_dashboards() == []
  end
end
