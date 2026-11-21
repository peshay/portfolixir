defmodule Portfolixir.DashboardFixtures do
  @moduledoc """
  Stored dashboards for the tests of the dashboard page (Sprint 31 D4).

  The template „Überblick“ draws „Gesamtwert“ and „Datenqualität“ at S
  (planning board 01 ①): the total with its period's change, and each
  data-quality finding as a short counted line. The tests that pin the
  value card's strip, its year-to-date change and the data-quality line's
  full sentences read them at M, the size that draws them, from
  `overview_at_m!/0`: the template's widgets with those two at M, stored
  as the first dashboard, so `/` opens it. A module that calls it from an
  async test joins `group: :dashboards` (`Portfolixir.LockTable` row 28).
  """

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  @layout [
    {"total_value", "M", 1, 1},
    {"data_quality", "M", 7, 1},
    {"due", "S", 1, 3},
    {"off_target", "S", 4, 3},
    {"performance", "L", 1, 4},
    {"allocation_drift", "T", 9, 4},
    {"movers", "M", 1, 7},
    {"crashes", "M", 7, 7},
    {"bitcoin_cycle", "M", 1, 9},
    {"sale_review", "M", 7, 9},
    {"snapshots", "S", 1, 11}
  ]

  @doc """
  Stores „Überblick“ with „Gesamtwert“ and „Datenqualität“ at M as the
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
