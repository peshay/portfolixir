defmodule PortfolixirWeb.Dashboard.Widgets.Rebounders do
  @moduledoc """
  The widget „Erholer nach Crashes“ `rebounders` (I61; Sprint 32 S5;
  planning board `ux-design-2026-11-25-sprint32/11` ⑤; D-15): the
  rebounders' lists of the last three crash windows side by side, over the
  scope's holdings („Im Depot“: the widget's view, else every depot) or
  the whole catalogue, the switch „Im Depot · Katalog“ the one „Crashes im
  Vergleich“ keeps.

  Each list is `GET /api/v1/crashes/:key/rankings?list=rebounders` for its
  window (`Portfolixir.Crashes.rankings/3`, ADR-0058 §6, level (b)): each
  security's rise from its own low in the window to the trough plus three
  calendar months, in EUR, highest first. The last three windows are the
  three newest by start whose fall has ended (a running window has no
  rebound yet); a list still inside its three months says so.

  **No score across crashes** (D-15; ADR-0058 §8): a name in more than one
  list is marked „mehrfach“ by its name only — the widget adds, averages
  and ranks nothing across the windows. Survivorship is named in its ⓘ:
  only what is in the catalogue today is in a list.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Crashes
  alias Portfolixir.Crashes.Rankings
  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format

  @windows 3
  # The rows each list shows: L three, XL five (board 11 ⑤ draws four).
  @shown %{"L" => 3, "XL" => 5}
  @limit 5

  # -- the read -----------------------------------------------------------------

  @doc """
  The universe a rebounders' list reads for the switch `universe`
  (`"held"` or `"catalogue"`) and the widget's scope: „Im Depot“ is the
  scope's view (`"view:<id>"`) where it has one, else every depot
  (`"held"`).
  """
  @spec universe(String.t(), integer() | nil) :: String.t()
  def universe("held", view_id) when is_integer(view_id), do: "view:#{view_id}"
  def universe("catalogue", _view_id), do: "catalogue"
  def universe(_held, _view_id), do: "held"

  @doc """
  The widget's read over `universe`: the crash benchmark and the last
  three ended windows, newest first, each with its rebounders' list
  (`%{key, name, start, trough, provisional, completes_on, entries}`, each
  entry `%{security_id, name, return, days_back, not_yet}`), and `repeated`,
  the names that stand in more than one list. `%{state: :no_benchmark}`
  when no crash benchmark is chosen.
  """
  @spec read(String.t()) :: map()
  def read(universe) do
    listing = Crashes.list_windows()

    case listing.benchmark do
      nil ->
        %{state: :no_benchmark}

      benchmark ->
        {:ok, request} = Rankings.request(universe, list: "rebounders", limit: @limit)

        lists =
          (listing.detected ++ listing.manual)
          |> Enum.reject(&Map.get(&1, :provisional, false))
          |> Enum.sort_by(& &1.start, {:desc, Date})
          |> Enum.take(@windows)
          |> Enum.map(&list(&1, benchmark, listing.reason, request))

        %{
          state: :ok,
          universe: universe,
          benchmark: %{id: benchmark.id, name: benchmark.name},
          lists: lists,
          repeated: repeated(lists)
        }
    end
  end

  defp list(window, benchmark, reason, request) do
    {entries, provisional, completes_on} =
      case Rankings.rank(window, benchmark, reason, request) do
        {:ok, payload} ->
          {Enum.map(payload.entries, &entry/1), payload.provisional, payload.completes_on}

        {:error, _refusal} ->
          {[], false, nil}
      end

    %{
      key: window.key,
      name: window.name,
      start: window.start,
      trough: window.trough,
      provisional: provisional,
      completes_on: completes_on,
      entries: entries
    }
  end

  defp entry(entry) do
    %{
      security_id: entry.security.id,
      name: entry.security.name,
      return: entry.return,
      days_back: entry.days_back,
      not_yet: Map.get(entry, :not_yet, false)
    }
  end

  # The names in more than one list: by name only, nothing added up.
  defp repeated(lists) do
    lists
    |> Enum.flat_map(fn list -> list.entries |> Enum.map(& &1.name) |> Enum.uniq() end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> MapSet.new(fn {name, _count} -> name end)
  end

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:universe, :string, required: true, doc: "the switch: held or catalogue")
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")

  @doc "The widget „Erholer nach Crashes“ with its switch and its compact form."
  def widget(assigns) do
    ready = match?(%{state: :ok}, assigns.card)
    shown = Map.get(@shown, assigns.item.size, 3)

    assigns =
      assign(assigns,
        ready: ready,
        lists:
          if(ready,
            do: Enum.map(assigns.card.lists, &%{&1 | entries: Enum.take(&1.entries, shown)}),
            else: []
          ),
        repeated: if(ready, do: assigns.card.repeated, else: MapSet.new())
      )

    ~H"""
    <Widget.frame
      id={"dashboard-rebounders" <> @item.uid}
      item={@item}
      title={Widgets.title("rebounders")}
      scope_label={gettext("Rise from the own low up to three months after · only what is in the catalogue today · no forecast")}
      full_href="/risk"
      full_label={gettext("All windows →")}
      full_role="rebounders-all-windows"
    >
      <:info>
        <%= gettext("Each list: the rise of every security from its own lowest close within the window to the window's trough plus three calendar months, in EUR at each close's stored rate, highest first. The last three windows whose fall has ended, newest first; a list still inside its three months is measured to today and says so.") %>
      </:info>
      <:info>
        <%= gettext("“several” marks a name that stands in more than one list, by its name only: nothing is added up or ranked across the crashes. Survivorship: a security that failed and was removed is in no list, so the lists read better than the market did.") %>
      </:info>
      <:controls>
        <div class="segmented-control widget-switch" role="group" aria-label={gettext("Securities")} data-role="rebounders-universe">
          <button
            :for={universe <- ~w(held catalogue)}
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
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="rebounders-skeleton"></p>
        <p :if={@card == :error} class="hint" data-role="rebounders-failed">
          <%= gettext("Couldn't load the crash windows.") %>
        </p>
        <p :if={match?(%{state: :no_benchmark}, @card)} class="hint" data-role="rebounders-empty">
          <%= gettext("No crash benchmark chosen: the windows are detected on its closes.") %>
        </p>
        <p :if={@ready and @lists == []} class="hint" data-role="rebounders-empty">
          <%= gettext("No ended crash window in the benchmark's closes.") %>
        </p>
      </:shared>
      <div :if={@lists != []} class="widget-rebounders" data-role="rebounders-lists">
        <section :for={list <- @lists} class="widget-rebounders__list" data-role="rebounders-list" data-key={list.key}>
          <h3 class="widget-rebounders__window"><%= gettext("After “%{window}”", window: list.name || gettext("unnamed")) %></h3>
          <p :if={list.provisional} class="hint" data-role="rebounders-provisional">
            <%= gettext("measured to today, complete on %{date}", date: Format.date(list.completes_on)) %>
          </p>
          <ol class="widget-rebounders__rows">
            <li :for={entry <- list.entries} data-role="rebounder" data-security-id={entry.security_id}>
              <bdi class="widget-rebounders__name"><%= entry.name %></bdi>
              <span :if={MapSet.member?(@repeated, entry.name)} class="widget-rebounders__repeated" data-role="rebounder-repeated"><%= gettext("several") %></span>
              <span class={["num", sign_class(entry.return)]} data-role="rebounder-return"><%= percent(entry.return) %></span>
            </li>
          </ol>
          <p :if={list.entries == []} class="hint"><%= gettext("No security answered.") %></p>
        </section>
      </div>
      <:compact>
        <%= for list <- @lists, entry <- list.entries do %>
          <Widget.row href="/risk" data-compact-role="rebounder" data-key={list.key} data-security-id={entry.security_id}>
            <:name><%= entry.name %></:name>
            <:sub>
              <%= gettext("After “%{window}”", window: list.name || gettext("unnamed")) %>
              <span :if={MapSet.member?(@repeated, entry.name)}> · <%= gettext("several") %></span>
            </:sub>
            <:figure><span class={sign_class(entry.return)}><%= percent(entry.return) %></span></:figure>
          </Widget.row>
        <% end %>
      </:compact>
    </Widget.frame>
    """
  end

  defp universe_label("held"), do: pgettext("crash universe", "In depot")
  defp universe_label("catalogue"), do: pgettext("crash universe", "Catalogue")

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
