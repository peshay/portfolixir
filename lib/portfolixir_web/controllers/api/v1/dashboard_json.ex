defmodule PortfolixirWeb.Api.V1.DashboardJSON do
  @moduledoc """
  The payloads of `PortfolixirWeb.Api.V1.DashboardController` (ADR-0062 §1,
  §8): the widget catalogue, a menu entry, and a dashboard or a template
  with its layout.

  Every string a payload carries comes from the registry and the templates
  in code (`Portfolixir.Dashboards.Widgets`, `Portfolixir.Dashboards.Templates`)
  or from the stored row; an item's `source` is the registry's for its
  kind, never anything the layout says (§11). Titles are English, the
  msgids the screen translates. No payload carries a figure: a dashboard is
  arrangement, not data (§2).
  """

  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.Api.V1.JSON

  @full_size "full is a page of its own, reached through the widget's full view, never placed " <>
               "on the grid"

  # ADR-0062's amendment of 2026-11-25, point 3 (Sprint 32 E4).
  @size_rule "Apple's widget families: every size a multiple of S and of a fixed height " <>
               "(rows of 7rem at the wide class, none growing with its content); each size " <>
               "of a kind shows more of the same: S one figure, M the figure with two or " <>
               "three companions, L the figure with its course, XL the figure, its course " <>
               "and a breakdown; a size that adds nothing is not offered. row („Zeile“) is " <>
               "the size of a section widget: the full width, 12 x 1 in the grid, drawn at " <>
               "its content's height, every row after it starting below it"

  @doc "The widget catalogue (§1): every kind, the groups, the grid, the periods, the limits."
  @spec catalogue() :: map()
  def catalogue do
    %{
      widgets: Enum.map(Widgets.kinds(), &kind/1),
      groups: Enum.map(Widgets.groups(), &%{key: &1, title: Widgets.group_title(&1)}),
      grid: %{
        columns: Layout.columns(),
        max_row: Layout.max_row(),
        max_items: Layout.max_items(),
        sizes: grid_sizes(),
        row_height: "7rem",
        size_rule: @size_rule,
        full: @full_size
      },
      # Sprint 32 T1: the period vocabulary's fixed keys and its keyed
      # forms (`Portfolixir.Periods`).
      periods: %{
        values: Widgets.periods(),
        keyed: ["year:YYYY", "saved:<id>"],
        default: Widgets.default_period()
      },
      max_dashboards: Dashboards.max_dashboards(),
      name_max: Dashboards.name_max()
    }
  end

  defp kind(kind) do
    %{
      key: kind.key,
      title: kind.title,
      title_key: %{context: "widget kind", msgid: kind.title},
      group: kind.group,
      sizes: kind.sizes,
      source: source(kind),
      period: period(kind.period),
      scope: Atom.to_string(kind.scope),
      compact: kind.compact
    }
  end

  defp grid_sizes do
    for size <- Widgets.sizes(),
        {:ok, {columns, rows}} <- [Widgets.dimensions(size)],
        into: %{},
        do:
          {size,
           %{
             columns: columns,
             rows: rows,
             family: Widgets.family(size),
             height: Widgets.height(size)
           }}
  end

  defp source(kind) do
    %{
      routes: kind.source.routes,
      function: Widgets.function_name(kind.source.function),
      note: kind.source.note
    }
  end

  defp period(:none), do: "none"

  defp period(rule) do
    Map.take(rule, [
      :periods,
      :param,
      :values,
      :ranges,
      :years,
      :keyed,
      :spans,
      :spans_else,
      :translated
    ])
  end

  @doc """
  A menu entry of `Portfolixir.Dashboards.entries/0`'s kind, or a template
  offered beside the stored dashboards: its type, its id (a stored one) or
  key (a template), its name, `read_only`, `in_menu` and its item count; a
  template also its `group`, `starter`, `asks_scope` and `subtitle`; a
  stored one also its own view (`view_id`, `view_dangling`) and its
  origin (`template_key`).
  """
  @spec entry(Dashboard.t() | Templates.t(), boolean()) :: map()
  def entry(%Dashboard{} = dashboard, _in_menu) do
    %{
      type: "dashboard",
      id: dashboard.id,
      key: nil,
      name: dashboard.name,
      position: dashboard.position,
      lock_version: dashboard.lock_version,
      # Sprint 32 S1: the own view, dangling once its view was deleted
      # (read as the default until the next save drops it), and the
      # template it was copied from.
      view_id: dashboard.view_id,
      view_dangling: match?({:dangling, _id}, Dashboards.own_view(dashboard)),
      template_key: dashboard.template_key,
      read_only: false,
      in_menu: true,
      item_count: length(dashboard.layout),
      inserted_at: JSON.datetime(dashboard.inserted_at),
      updated_at: JSON.datetime(dashboard.updated_at)
    }
  end

  def entry(%{key: key, layout: layout} = template, in_menu) do
    %{
      type: "template",
      id: nil,
      key: key,
      name: Templates.title(key),
      # Sprint 32 S4 (board 03 ①): the gallery's group, whether the boot
      # stores it once (a starter), whether it asks for a scope (the
      # dashboard's own view_id on its copy), and its line.
      group: Templates.group(template),
      starter: template.starter,
      asks_scope: template.asks_scope,
      subtitle: Templates.subtitle(key),
      read_only: true,
      in_menu: in_menu,
      item_count: length(layout)
    }
  end

  @doc """
  A dashboard or a template as its read answers it: the entry and its
  layout, each item with its title and the registry's source for its kind.
  """
  @spec dashboard(Dashboard.t() | Templates.t(), boolean()) :: map()
  def dashboard(dashboard_or_template, in_menu \\ true) do
    dashboard_or_template
    |> entry(in_menu)
    |> Map.delete(:item_count)
    |> Map.put(:layout, Enum.map(dashboard_or_template.layout, &item/1))
  end

  # A stored or template item is normalized (`Layout.validate/2`): exactly
  # kind, size, col, row and settings, every kind registered. A kind a later
  # release removed reads with no title and no source, never one the item
  # names.
  defp item(item) do
    kind = item["kind"]

    base = %{
      kind: kind,
      size: item["size"],
      col: item["col"],
      row: item["row"],
      settings: item["settings"] || %{}
    }

    case Widgets.fetch(kind) do
      {:ok, registered} -> Map.merge(base, %{title: registered.title, source: source(registered)})
      :error -> Map.merge(base, %{title: nil, source: nil})
    end
  end
end
