defmodule PortfolixirWeb.Dashboard.Widgets.Crashes do
  @moduledoc """
  The widget „Crashes im Vergleich“ `crashes` (ADR-0062 §12; ADR-0058;
  planning board `ux-design-2026-11-21-sprint31/01` ① and idea board
  `ux-design-2026-11-21-idea-i56/03`; Wealth › Risk › Crashes; Sprint 31
  D4).

  Its figures are the crash reads the Risk tab and the agent make:
  `Portfolixir.Crashes.list_windows/0` (`GET /api/v1/crashes`) for the
  windows, newest first as the Risk tab orders them, and for each window
  the losers' list `Portfolixir.Crashes.Rankings` derives
  (`GET /api/v1/crashes/:key/rankings?list=losers&universe=…`) over the
  universe the switch „Im Depot · Katalog“ picks: `held`, the securities
  held today in any depot, or `catalogue`. Per window the table draws
  the window's name and dates, the crash benchmark's return over it (the
  list's `reference.return`) and the list's first entry, the lowest
  return in the universe, with its name. At M five windows, at L eight.

  **A departure from the board:** board ① draws „Depot heute“ and „Tage“
  per window; no read answers either (a depot's return over a window is no
  route's figure, and a window carries its dates, not a day count), so the
  widget shows the lowest return in the chosen universe and the dates,
  which the rankings route answers, rather than a figure of its own.

  No verdict (ADR-0058 §8): the table compares prices and names no action.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Crashes
  alias Portfolixir.Crashes.Rankings
  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format

  @universes ~w(held catalogue)
  @max_windows 8

  @doc "The universes the switch offers, „Im Depot“ first."
  @spec universes() :: [String.t()]
  def universes, do: @universes

  @doc "The universe a value names: one of `universes/0`, else `held`."
  @spec universe(term()) :: String.t()
  def universe(value) when value in @universes, do: value
  def universe(_value), do: "held"

  # -- the read -----------------------------------------------------------------

  @doc """
  The widget's read, in the page's background task, for `universe`: the
  crash benchmark, and the newest windows (at most eight), each with the
  benchmark's return over it and the lowest entry of its losers' list.
  `%{state: :no_benchmark}` when no crash benchmark is chosen.
  """
  @spec read(String.t()) :: map()
  def read(universe) do
    listing = Crashes.list_windows()

    case listing.benchmark do
      nil ->
        %{state: :no_benchmark, universe: universe}

      benchmark ->
        {:ok, request} = Rankings.request(universe, list: "losers", limit: 1)

        windows =
          listing
          |> ordered()
          |> Enum.take(@max_windows)
          |> Enum.map(&row(&1, benchmark, listing.reason, request))

        %{
          state: :ok,
          universe: universe,
          benchmark: %{id: benchmark.id, name: benchmark.name},
          windows: windows
        }
    end
  end

  defp row(window, benchmark, reason, request) do
    {reference, lowest} =
      case Rankings.rank(window, benchmark, reason, request) do
        {:ok, payload} -> {payload.reference, List.first(payload.entries)}
        {:error, _refusal} -> {nil, nil}
      end

    %{
      key: window.key,
      name: window.name,
      kind: window.kind,
      start: window.start,
      trough: window.trough,
      provisional: Map.get(window, :provisional, false),
      benchmark_return: reference && reference.return,
      lowest:
        lowest &&
          %{
            security_id: lowest.security.id,
            name: lowest.security.name,
            return: lowest.return
          }
    }
  end

  # Every window, newest first, as the Risk tab orders them: by start, a
  # detected one before a manual one of the same day, then by key.
  defp ordered(listing) do
    Enum.sort(listing.detected ++ listing.manual, fn a, b ->
      case Date.compare(a.start, b.start) do
        :gt -> true
        :lt -> false
        :eq -> {a.kind, a.key} <= {b.kind, b.key}
      end
    end)
  end

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:universe, :string, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")

  @doc "The widget „Crashes im Vergleich“ with its switch and its compact form."
  def widget(assigns) do
    assigns =
      assigns
      |> assign(:uid, assigns.item.uid)
      |> assign(:ready, match?(%{state: :ok}, assigns.card))
      |> assign(:shown, if(assigns.item.size == "L", do: 8, else: 5))

    assigns =
      assign(
        assigns,
        :windows,
        if(assigns.ready, do: Enum.take(assigns.card.windows, assigns.shown), else: [])
      )

    ~H"""
    <Widget.frame
      id={"dashboard-crashes" <> @uid}
      item={@item}
      title={Widgets.title("crashes")}
      scope_label={if @ready, do: gettext("Benchmark %{name} · prices, no verdict", name: @card.benchmark.name)}
      full_href="/risk"
      full_label={gettext("All windows →")}
      full_role="crashes-all-windows"
    >
      <:info>
        <%= gettext("A window opens when the crash benchmark's close falls 10% or more below its last high and closes when it is back at that high; detected from the stored closes at every read, never stored.") %>
      </:info>
      <:info>
        <%= gettext("Benchmark: its return from the window's high to its low. Lowest: the lowest return over the same days among the securities held today in any depot, or in the whole catalogue; each in its own currency, in the closes' current display basis.") %>
      </:info>
      <:controls>
        <div class="segmented-control widget-switch" role="group" aria-label={gettext("Securities")} data-role="crashes-universe">
          <button
            :for={universe <- universes()}
            type="button"
            class={["segmented-control__option", universe == @universe && "is-active"]}
            phx-click="crash_universe"
            phx-value-universe={universe}
            aria-pressed={to_string(universe == @universe)}
            data-universe={universe}
          ><%= universe_label(universe) %></button>
        </div>
      </:controls>
      <:shared>
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="crashes-skeleton"></p>
        <p :if={@card == :error} class="hint" data-role="crashes-failed">
          <%= gettext("Couldn't load the crash windows.") %>
        </p>
        <p :if={match?(%{state: :no_benchmark}, @card)} class="hint" data-role="crashes-empty">
          <%= gettext("No crash benchmark chosen: the windows are detected on its closes.") %>
        </p>
        <p :if={@ready and @windows == []} class="hint" data-role="crashes-empty">
          <%= gettext("No crash window in the benchmark's closes.") %>
        </p>
      </:shared>
      <table :if={@windows != []} class="data-table widget-crash-table" data-role="crashes-table">
        <thead>
          <tr>
            <th scope="col"><%= gettext("Window") %></th>
            <th scope="col" class="num"><%= gettext("Benchmark") %></th>
            <th scope="col"><%= lowest_label(@universe) %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={window <- @windows} data-role="crash-window" data-key={window.key}>
            <th scope="row">
              <span class={is_nil(window.name) && "crash-unnamed"}><%= window.name || gettext("unnamed") %></span>
              <small class="widget-crash-table__dates"><%= dates(window) %></small>
            </th>
            <td class={["num", sign_class(window.benchmark_return)]} data-role="crash-benchmark"><%= percent(window.benchmark_return) %></td>
            <td data-role="crash-lowest">
              <%= if window.lowest do %>
                <bdi><%= window.lowest.name %></bdi>
                <span class={["num", sign_class(window.lowest.return)]} data-role="crash-lowest-return"><%= percent(window.lowest.return) %></span>
              <% else %>
                <span class="muted">—</span>
              <% end %>
            </td>
          </tr>
        </tbody>
      </table>
      <:compact>
        <Widget.row
          :for={window <- @windows}
          href="/risk"
          data-compact-role="crash-window"
          data-key={window.key}
        >
          <:name><%= window.name || gettext("unnamed") %></:name>
          <:sub><%= dates(window) %></:sub>
          <:figure><span class={sign_class(window.benchmark_return)}><%= percent(window.benchmark_return) %></span></:figure>
          <:figure_sub :if={window.lowest}><%= lowest_short(@universe) %> <%= percent(window.lowest.return) %></:figure_sub>
        </Widget.row>
      </:compact>
    </Widget.frame>
    """
  end

  defp universe_label("held"), do: pgettext("crash universe", "In depot")
  defp universe_label("catalogue"), do: pgettext("crash universe", "Catalogue")

  defp lowest_label("held"), do: gettext("Lowest in the depot")
  defp lowest_label("catalogue"), do: gettext("Lowest in the catalogue")

  defp lowest_short("held"), do: gettext("depot")
  defp lowest_short("catalogue"), do: gettext("catalogue")

  defp dates(%{provisional: true} = window),
    do:
      gettext("%{start} → %{low}, ongoing",
        start: Format.date(window.start),
        low: Format.date(window.trough)
      )

  defp dates(window),
    do:
      gettext("%{start} → %{low}",
        start: Format.date(window.start),
        low: Format.date(window.trough)
      )

  # One percent format across the dashboard, as the other widgets write it
  # (Sprint 31 closing act, DS5).
  defp percent(%Decimal{} = value), do: Format.signed_percent(value) <> "%"
  defp percent(_none), do: "—"

  defp sign_class(value) do
    case Format.displayed_percent_sign(value) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      :zero -> "is-flat"
      nil -> nil
    end
  end
end
