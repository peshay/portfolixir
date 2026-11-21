defmodule PortfolixirWeb.LiveMenu do
  @moduledoc """
  The menu's dashboard entries for the process that renders the shell
  (ADR-0022's amendment of 2026-11-21, point 1; ADR-0062 §3, §9; Sprint 31
  D7): the stored dashboards in their order, or, while none is stored, the
  templates (`Portfolixir.Dashboards.entries/0`, a read that writes
  nothing).

  `on_mount/4` reads them once per LiveView mount, the static render's and
  the connected one's alike, and keeps them in the process, as
  `PortfolixirWeb.PrivacyMode` keeps its mode, so `PortfolixirWeb.AppShell`
  draws them without a query per render and without an attribute on every
  page. A write that changes the list (a create, „Anpassen“, a copy from
  „Alle Widgets“) navigates to the dashboard it made, which mounts anew. A
  shell rendered outside a LiveView mount (a component rendered alone)
  offers the templates, as a fresh instance does; it reads nothing.
  """

  alias Portfolixir.Dashboards

  @key :portfolixir_menu_dashboards

  @doc "Reads the menu's dashboard entries for this LiveView's process."
  def on_mount(:default, _params, _session, socket) do
    put(Dashboards.entries())
    {:cont, socket}
  end

  @doc "Keeps `entries` as the menu's dashboard entries of this process."
  @spec put([Dashboards.entry()]) :: [Dashboards.entry()]
  def put(entries) when is_list(entries) do
    Process.put(@key, entries)
    entries
  end

  @doc "The menu's dashboard entries of this process; the templates when none were read."
  @spec entries() :: [Dashboards.entry()]
  def entries do
    case Process.get(@key) do
      entries when is_list(entries) -> entries
      nil -> Enum.map(Dashboards.templates(), &%{type: :template, template: &1})
    end
  end
end
