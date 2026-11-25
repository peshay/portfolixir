defmodule Portfolixir.DashboardFixtures do
  @moduledoc """
  Stored dashboards for the tests of the dashboard page (Sprint 31 D4).

  The template „Überblick“ draws „Gesamtwert“ and „Datenqualität“ at S
  (planning board 01 ①): the total with its period's change, and each
  data-quality finding as a short counted line. The tests that pin the
  value card's exclusion line, its change and the data-quality line's
  full sentences read them at L (Sprint 31's M, read as L since Sprint 32
  E4), the size that draws them, from `overview_at_m!/0`: the template's
  widgets with those two at L, stored
  as the first dashboard, so `/` opens it. A module that calls it from an
  async test joins `group: :dashboards` (`Portfolixir.LockTable` row 30).
  """

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  # Sprint 32 E4: on Apple's families. Sprint 31's M of the two is L (the
  # figure with its course; the list of findings), the rest as the
  # template reads them.
  @layout [
    {"total_value", "L", 1, 1},
    {"data_quality", "L", 7, 1},
    {"due", "S", 1, 5},
    {"off_target", "S", 4, 5},
    {"performance", "XL", 1, 7},
    {"allocation_drift", "L", 1, 11},
    {"movers", "L", 7, 11},
    {"crashes", "L", 1, 15},
    {"bitcoin_cycle", "L", 7, 15},
    {"sale_review", "L", 1, 19},
    {"snapshots", "S", 7, 19}
  ]

  @doc """
  Stores „Überblick“ with „Gesamtwert“ and „Datenqualität“ at L as the
  first dashboard, named as the template is, and returns it.
  """
  def overview_at_m! do
    layout =
      Enum.map(@layout, fn {kind, size, col, row} ->
        %{"kind" => kind, "size" => size, "col" => col, "row" => row}
      end)

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Overview", "layout" => layout})

    dashboard
  end

  @doc "`overview_at_m!/0` as an ExUnit `setup` callback."
  def overview_at_m(_context) do
    overview_at_m!()
    :ok
  end
end
