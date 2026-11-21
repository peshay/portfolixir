defmodule Portfolixir.Dashboards do
  @moduledoc """
  Dashboards composed from widgets (ADR-0062, FR-60).

  * **The registry** (`Portfolixir.Dashboards.Widgets`): every widget kind,
    in code, with its sizes, the read it draws, its period rule and its
    scope (§1).
  * **The templates** (`Portfolixir.Dashboards.Templates`): curated
    layouts in code, never stored and never edited; copied into a stored
    dashboard by `copy_template/3` (§3).
  * **The stored dashboards** (`Portfolixir.Dashboards.Dashboard`): a name,
    a position, a validated layout (`Portfolixir.Dashboards.Layout`) and a
    `lock_version`, at most `max_dashboards/0` of them (§2).

  A dashboard holds no figure: it is arrangement, not data, no part of the
  ledger and no input of any money read. Reads never write: a fresh
  instance stores nothing, and `entries/0` then offers the templates.
  """

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Repo

  @max_dashboards 50
  @max_id 9_223_372_036_854_775_807

  @typedoc """
  A menu entry: a stored dashboard, or a template offered while none is
  stored.
  """
  @type entry ::
          %{type: :dashboard, dashboard: Dashboard.t()}
          | %{type: :template, template: Templates.t()}

  # --- the registry and the templates ---------------------------------------

  @doc "Every registered widget kind (`Portfolixir.Dashboards.Widgets.kinds/0`)."
  @spec widgets() :: [Widgets.kind()]
  def widgets, do: Widgets.kinds()

  @doc "The widget kind under `key`, matched as a string, or `:error`."
  @spec fetch_widget(term()) :: {:ok, Widgets.kind()} | :error
  def fetch_widget(key), do: Widgets.fetch(key)

  @doc "The templates this release offers."
  @spec templates() :: [Templates.t()]
  def templates, do: Templates.templates()

  @doc "The template under `key`, matched as a string, or `:error`."
  @spec fetch_template(term()) :: {:ok, Templates.t()} | :error
  def fetch_template(key), do: Templates.fetch(key)

  @doc """
  Validates a layout without storing it (`Portfolixir.Dashboards.Layout.validate/1`):
  `{:ok, normalized}` or `{:error, refusal}` naming the first bad item.
  """
  @spec validate_layout(term()) :: {:ok, [Layout.item()]} | {:error, Layout.refusal()}
  def validate_layout(layout), do: Layout.validate(layout)

  @doc "The most dashboards an instance stores (ADR-0062 §2)."
  @spec max_dashboards() :: pos_integer()
  def max_dashboards, do: @max_dashboards

  @doc "The longest dashboard name, in characters."
  @spec name_max() :: pos_integer()
  def name_max, do: Dashboard.name_max()

  # --- reads ----------------------------------------------------------------

  @doc "The stored dashboards in the menu's order: by position, then id."
  @spec list_dashboards() :: [Dashboard.t()]
  def list_dashboards,
    do: Repo.all(from(d in Dashboard, order_by: [asc: d.position, asc: d.id]))

  @doc """
  The menu's dashboard entries, each marked: the stored dashboards in
  their order, or, while none is stored, the templates (ADR-0062 §3: the
  first entry of a fresh instance is „Überblick“, read-only). Writes
  nothing.
  """
  @spec entries() :: [entry()]
  def entries do
    case list_dashboards() do
      [] -> Enum.map(Templates.templates(), &%{type: :template, template: &1})
      stored -> Enum.map(stored, &%{type: :dashboard, dashboard: &1})
    end
  end

  @doc "The stored dashboard `id`, or `nil` (also for an id no row can carry)."
  @spec get_dashboard(term()) :: Dashboard.t() | nil
  def get_dashboard(id) when is_integer(id) and id >= 1 and id <= @max_id,
    do: Repo.get(Dashboard, id)

  def get_dashboard(_id), do: nil
end
