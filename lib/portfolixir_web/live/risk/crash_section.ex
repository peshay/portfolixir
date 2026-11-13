defmodule PortfolixirWeb.Risk.CrashSection do
  @moduledoc """
  The **Crashes** section on Wealth's Risk tab (Sprint 29 C6; FR-54, #1421;
  ADR-0058 §9 and its amendment's F1 to F4; board
  `ux-design-2026-11-12-sprint29/01-crash-section`, and board 02 ④ for the
  crash benchmark's inline choice; plan D-5 P1 to P9 and Q2).

  Top to bottom:

    * one bar of labelled controls (DESIGN.md, "Labelled controls start on
      one edge", the shared `PortfolixirWeb.ControlBar.bar/1` of issue
      1435): **Fenster**, a select of every window newest first
      (P2), then **Liste** (Verlierer · Gewinner · Erholer) and
      **Wertpapiere** (Im Depot · Ganzer Katalog);
    * the window line: its name, its kind, its dates, the crash benchmark's
      fall in its own currency, its recovery, and „Im Depot ansehen“ —
      Holdings with the window as a custom range, or one line why not when
      the window ends before the view's first booking (F4);
    * the list: eight entries as `Portfolixir.Crashes.rankings/3` answers
      them, each a bar against the crash benchmark's dashed line, its
      figure, the difference in points and, for the rebounders, the days to
      the pre-crash close; the basis line; the unanswered counted;
    * the windows behind a disclosure: the rule and the crash benchmark
      with „Ändern“ (board 02 ④, Q2), every window with its kind, the names
      without a window, and the forms that name, draw, edit and delete.

  **The screen answers as the API does** (plan D-1, item 7): every list is
  `Crashes.rankings/3` over `view:<id>` (the page's view, P3) or
  `catalogue`, the call `GET /api/v1/crashes/:key/rankings` makes. With no
  view chosen (Everything), „Im Depot“ asks for `held`, the securities held
  today in any depot (the closing act, #1421).

  **The choice is kept in the address** (P4): `crash` (the window's key),
  `crash_list` and `crash_universe`; without one the section opens on the
  newest window, the losers and „Im Depot“.

  **The privacy mode changes nothing here:** the section holds percentages,
  dates and day counts only, each formatted by a `plain_*` or percent form
  (`PortfolixirWeb.PrivacyMode`).

  **No verdict** (ADR-0058 §8): the lists compare prices; nothing says what
  to buy.
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Crashes
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Settings
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.BenchmarkChoices
  alias PortfolixirWeb.ControlBar
  alias PortfolixirWeb.FieldLabel
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveEventGuard
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.SecurityNames

  @lists ~w(losers winners rebounders)
  @universes ~w(depot catalogue)
  @param_keys ~w(crash crash_list crash_universe)
  @hundred Decimal.new(100)
  @steps [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> LiveEventGuard.attach()
     |> assign(form: nil, errors: [], posted: %{}, show_unanswered: false, loaded_for: nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      assign(socket, Map.take(assigns, [:id, :params, :view_id, :base_currency]))

    key = {socket.assigns.params, socket.assigns.view_id}

    if socket.assigns.loaded_for == key do
      {:ok, socket}
    else
      {:ok, socket |> assign(:loaded_for, key) |> load()}
    end
  end

  # -- the read ---------------------------------------------------------------

  defp load(socket) do
    listing = Crashes.list_windows()
    windows = ordered(listing)
    view_id = socket.assigns.view_id
    params = socket.assigns.params

    window = chosen_window(windows, params["crash"])
    list = if params["crash_list"] in @lists, do: params["crash_list"], else: "losers"

    universe =
      if params["crash_universe"] in @universes, do: params["crash_universe"], else: "depot"

    socket
    |> assign(
      listing: listing,
      windows: windows,
      window: window,
      list: list,
      universe: universe,
      first_date: first_date(view_id, socket.assigns.base_currency)
    )
    |> rank()
  end

  defp rank(%{assigns: %{window: nil}} = socket), do: assign(socket, :ranking, nil)

  defp rank(socket) do
    %{window: window, list: list, universe: universe, view_id: view_id} = socket.assigns
    api_universe = api_universe(universe, view_id)

    ranking =
      case Crashes.rankings(window.key, api_universe,
             list: list,
             include_unanswered: socket.assigns.show_unanswered
           ) do
        {:ok, payload} -> twin_ids(payload)
        {:error, _refusal} -> nil
      end

    assign(socket, :ranking, ranking)
  end

  # UAT-13's rule: a row whose name another row shows for another security
  # carries the identifier that tells it apart (its ISIN, else its number).
  defp twin_ids(%{entries: entries} = payload) do
    entries =
      entries
      |> Enum.map(&Map.merge(&1, %{security_id: &1.security.id, isin: &1.security.isin}))
      |> SecurityNames.put_twin_ids(& &1.security.name)

    %{payload | entries: entries}
  end

  # „Im Depot“ is the page's view's holdings today, or with no view chosen
  # the holdings today in any depot; the API's universe either way.
  defp api_universe("catalogue", _view_id), do: "catalogue"
  defp api_universe("depot", nil), do: "held"
  defp api_universe("depot", view_id), do: "view:#{view_id}"

  # Every window, newest first (P4): by start, a detected one before a
  # manual one of the same day, then by key.
  defp ordered(listing) do
    Enum.sort(listing.detected ++ listing.manual, fn a, b ->
      case Date.compare(a.start, b.start) do
        :gt -> true
        :lt -> false
        :eq -> {a.kind, a.key} <= {b.kind, b.key}
      end
    end)
  end

  defp chosen_window([], _key), do: nil

  defp chosen_window([newest | _] = windows, key) do
    Enum.find(windows, newest, &(&1.key == key))
  end

  # The day Holdings' analysis starts for the view (`first_date`, the check
  # its range makes, F4); nil without any booking.
  defp first_date(view_id, base_currency) do
    opts = if base_currency, do: [base_currency: base_currency], else: []

    case Performance.view_analysis(view_id, opts) do
      %{first_date: first} -> first
      _none -> nil
    end
  end

  # -- the events -------------------------------------------------------------

  @impl true
  def handle_event("crash_window", %{"crash" => key}, socket) when is_binary(key) do
    {:noreply, push_patch(socket, to: path(socket.assigns, %{"crash" => key}))}
  end

  def handle_event("crash_choose_benchmark", _params, socket),
    do: {:noreply, open_form(socket, :benchmark)}

  def handle_event("crash_add_window", _params, socket),
    do: {:noreply, open_form(socket, :manual_new)}

  def handle_event("crash_name_open", %{"key" => key}, socket) when is_binary(key),
    do: {:noreply, open_form(socket, {:name, key})}

  def handle_event("crash_manual_edit", %{"key" => key}, socket) when is_binary(key),
    do: {:noreply, open_form(socket, {:manual, key})}

  def handle_event("crash_from_name_open", %{"key" => key}, socket) when is_binary(key),
    do: {:noreply, open_form(socket, {:from_name, key})}

  def handle_event("crash_cancel", _params, socket),
    do: {:noreply, assign(socket, form: nil, errors: [], posted: %{})}

  def handle_event("crash_toggle_unanswered", _params, socket) do
    {:noreply, socket |> assign(:show_unanswered, not socket.assigns.show_unanswered) |> rank()}
  end

  def handle_event("crash_save_benchmark", %{"crash_benchmark" => raw}, socket)
      when raw != "" do
    with {:ok, id} <- LiveParam.fetch_id(raw),
         {:ok, _security} <- Settings.set_crash_benchmark(Actor.owner_ui(), id) do
      {:noreply, socket |> assign(form: nil, errors: []) |> load()}
    else
      _refused ->
        {:noreply,
         assign(socket, :errors, [gettext("This security cannot be the crash benchmark.")])}
    end
  end

  # Board 02 ④ A: with none chosen the select opens on a disabled
  # „— choose —“, which a browser does not send; saving it unchanged is
  # refused in the form and writes nothing.
  def handle_event("crash_save_benchmark", _params, socket),
    do: {:noreply, assign(socket, :errors, [gettext("Choose a security first.")])}

  def handle_event("crash_window_save", %{"window" => attrs}, socket) when is_map(attrs) do
    save(socket.assigns.form, texts(attrs), socket)
  end

  def handle_event("crash_from_name_save", %{"window" => attrs}, socket) when is_map(attrs) do
    with {:from_name, key} <- socket.assigns.form do
      attrs = attrs |> texts() |> Map.take(["name", "trough"])

      case Crashes.manual_window_from_name(Actor.owner_ui(), key, attrs) do
        {:ok, window} -> {:noreply, written(socket, "m:#{window.id}")}
        {:error, refusal} -> {:noreply, refused(socket, refusal, attrs)}
      end
    else
      _no_form -> {:noreply, socket}
    end
  end

  def handle_event("crash_unname", %{"key" => key}, socket) when is_binary(key) do
    _result = Crashes.unname_window(Actor.owner_ui(), key)
    {:noreply, socket |> assign(form: nil, errors: []) |> load()}
  end

  def handle_event("crash_manual_delete", %{"key" => key}, socket) when is_binary(key) do
    _result = Crashes.delete_manual_window(Actor.owner_ui(), key)
    {:noreply, socket |> assign(form: nil, errors: []) |> load()}
  end

  # An event this section does not know, or a payload it cannot read,
  # changes nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # A form's fields as text: a value no input sends (a list, a map) is
  # dropped, so the write refuses it as missing, never crashes on it.
  defp texts(attrs) do
    for {field, value} <- attrs,
        is_binary(field) and is_binary(value),
        into: %{},
        do: {field, value}
  end

  defp open_form(socket, form), do: assign(socket, form: form, errors: [], posted: %{})

  defp save({:name, key}, attrs, socket) do
    attrs = Map.take(attrs, ["name"])

    case Crashes.name_window(Actor.owner_ui(), key, attrs) do
      {:ok, _name} -> {:noreply, written(socket, nil)}
      {:error, refusal} -> {:noreply, refused(socket, refusal, attrs)}
    end
  end

  defp save(:manual_new, attrs, socket) do
    attrs = Map.take(attrs, ["name", "start", "trough"])

    case Crashes.create_manual_window(Actor.owner_ui(), attrs) do
      {:ok, window} -> {:noreply, written(socket, "m:#{window.id}")}
      {:error, refusal} -> {:noreply, refused(socket, refusal, attrs)}
    end
  end

  defp save({:manual, key}, attrs, socket) do
    attrs = Map.take(attrs, ["name", "start", "trough"])

    case Crashes.update_manual_window(Actor.owner_ui(), key, attrs) do
      {:ok, _window} -> {:noreply, written(socket, nil)}
      {:error, refusal} -> {:noreply, refused(socket, refusal, attrs)}
    end
  end

  defp save(_form, _attrs, socket), do: {:noreply, socket}

  # A write landed: the form closes and the section reads again; a new
  # window is chosen in the address.
  defp written(socket, nil),
    do: socket |> assign(form: nil, errors: [], posted: %{}) |> load()

  defp written(socket, key) do
    socket
    |> assign(form: nil, errors: [], posted: %{})
    |> load()
    |> push_patch(to: path(socket.assigns, %{"crash" => key}))
  end

  # A window gone (deleted, or no longer detected) or a name that has a
  # window again: the section is read again before the message says so.
  defp refused(socket, refusal, attrs) when refusal in [:not_found, :name_has_window],
    do: socket |> load() |> assign(errors: refusal_messages(refusal), posted: attrs)

  defp refused(socket, refusal, attrs),
    do: assign(socket, errors: refusal_messages(refusal), posted: attrs)

  defp refusal_messages(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&FieldLabel.translate_error/1)
    |> Enum.map(fn {field, messages} -> "#{field_label(field)}: #{Enum.join(messages, ", ")}" end)
  end

  defp refusal_messages(:name_has_window),
    do: [gettext("This name has a window again: it is read there.")]

  defp refusal_messages(_refusal),
    do: [gettext("This window no longer exists: the section was read again.")]

  defp field_label(:name), do: gettext("Name")
  defp field_label(:start), do: pgettext("crash", "High")
  defp field_label(:trough), do: pgettext("crash", "Low")
  defp field_label(other), do: FieldLabel.label(other)

  # The page's address with the section's choice: the page's own pairs
  # first (the view), then the window, the list and the universe.
  defp path(assigns, changes) do
    kept =
      assigns.params
      |> Enum.reject(fn {key, _value} -> key in @param_keys end)
      |> Enum.sort()

    choice =
      Map.merge(
        %{
          "crash" => assigns.window && assigns.window.key,
          "crash_list" => assigns.list,
          "crash_universe" => assigns.universe
        },
        changes
      )

    pairs = kept ++ for key <- @param_keys, choice[key], do: {key, choice[key]}
    "/risk?" <> URI.encode_query(pairs)
  end

  # -- the render -------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        benchmark: assigns.listing.benchmark,
        reason: assigns.listing.reason,
        today: Clock.today()
      )

    ~H"""
    <section class="workspace-section crash-section" id="risk-crashes" aria-labelledby="risk-crashes-title">
      <header class="section-head">
        <div class="section-title">
          <h2 id="risk-crashes-title"><%= gettext("Crashes") %></h2>
          <AppShell.section_info>
            <:line><%= gettext("A window opens once the crash benchmark closes 10 % or more below its high; it starts on the last day at the high and ends on the lowest close before the recovery, the earliest of equal lows.") %></:line>
            <:line><%= gettext("Detected in the benchmark's currency, listed in EUR at each close's exchange rate; splits adjusted.") %></:line>
            <:line><%= gettext("The price on a day: the last close on or before it, at most 7 days old. Without a price or an exchange rate no answer, never a zero.") %></:line>
            <:line><%= gettext("Rebounders: from the own low between high and low to three calendar months after the low; days to the pre-crash close in calendar days.") %></:line>
            <:line><%= gettext("Ties by figure, then name, then ISIN. Benchmarks are in no list.") %></:line>
            <:line><%= gettext("No verdict: the lists compare prices, they do not say what to buy.") %></:line>
          </AppShell.section_info>
        </div>
      </header>

      <AppShell.data_note :if={@reason} severity={:note} data-role="crash-no-benchmark">
        <%= reason_text(@reason) %>
        <button
          type="button"
          class="link-button"
          data-role="crash-choose-benchmark"
          phx-click="crash_choose_benchmark"
          phx-target={@myself}
        >
          <%= gettext("Choose crash benchmark") %>
        </button>
      </AppShell.data_note>

      <%= if @windows == [] do %>
        <p class="empty-state" data-role="crash-empty">
          <%= gettext("No window yet.") %>
          <button
            type="button"
            class="link-button"
            data-role="crash-add-window"
            phx-click="crash_add_window"
            phx-target={@myself}
          >
            <%= gettext("Add window") %>
          </button>
        </p>
      <% else %>
        <.bar
          myself={@myself}
          windows={@windows}
          window={@window}
          list={@list}
          universe={@universe}
          paths={%{
            lists: Map.new(lists(), fn {list, _label} -> {list, path(assigns, %{"crash_list" => list})} end),
            universes: Map.new(universes(), fn {universe, _label} -> {universe, path(assigns, %{"crash_universe" => universe})} end)
          }}
        />

        <.window_line
          window={@window}
          benchmark={@benchmark}
          ranking={@ranking}
          list={@list}
          first_date={@first_date}
          today={@today}
        />
        <p :if={Map.get(@window, :provisional, false)} class="hint crash-provisional" data-role="crash-ongoing-hint">
          <%= gettext("The window is ongoing: while %{benchmark} closes lower, the low and the lists move with it.",
            benchmark: @benchmark && @benchmark.name
          ) %>
        </p>

        <.list_table :if={@ranking} ranking={@ranking} list={@list} universe={@universe} />
        <p :if={is_nil(@ranking)} class="empty-state" data-role="crash-no-list">
          <%= gettext("This list cannot be read for this view.") %>
        </p>
        <.unanswered :if={@ranking} ranking={@ranking} show={@show_unanswered} myself={@myself} />
      <% end %>

      <.windows
        :if={@windows != [] or @listing.unmatched_names != [] or @form != nil}
        myself={@myself}
        listing={@listing}
        windows={@windows}
        benchmark={@benchmark}
        form={@form}
        errors={@errors}
        posted={@posted}
      />
    </section>
    """
  end

  defp reason_text("no_crash_benchmark"),
    do:
      gettext("No crash benchmark chosen: the rule detects no windows, manual ones still apply.")

  defp reason_text(_unavailable),
    do:
      gettext(
        "The crash benchmark is no longer available: the rule detects no windows, manual ones still apply."
      )

  defp lists,
    do: [
      {"losers", pgettext("crash list", "Losers")},
      {"winners", pgettext("crash list", "Winners")},
      {"rebounders", pgettext("crash list", "Rebounders")}
    ]

  defp universes,
    do: [
      {"depot", pgettext("crash universe", "In depot")},
      {"catalogue", pgettext("crash universe", "Whole catalogue")}
    ]

  # The bar of labelled controls (DESIGN.md, "Labelled controls start on
  # one edge"): the window's select first (P2), then the list and the
  # universe, on the shared `PortfolixirWeb.ControlBar.bar/1` (issue 1435):
  # one line while it fits, the label column from 900 px of the bar, labels
  # above at 330 px. The fold is the Lane L walk's measure: with the
  # window's select at its 19.5rem cap the line wraps up to an 877 px bar
  # (German), and the bar is 924 px at a 1200 px window, one line there.
  defp bar(assigns) do
    ~H"""
    <ControlBar.bar class="crash-bar" fold={900} data-role="crash-bar">
      <:group
        label={pgettext("crash", "Window")}
        for="crash-window"
        form={[id: "crash-window-form", "phx-change": "crash_window", "phx-target": @myself]}
      >
        <select id="crash-window" name="crash">
          <option :for={window <- @windows} value={window.key} selected={window.key == @window.key}>
            <%= option_label(window) %>
          </option>
        </select>
      </:group>
      <:group label={pgettext("crash", "List")} label_id="crash-list-label">
        <div class="segmented-control" data-role="crash-list" role="group" aria-labelledby="crash-list-label">
          <.link
            :for={{list, label} <- lists()}
            patch={@paths.lists[list]}
            class={["segmented-control__option", @list == list && "is-active"]}
            data-list={list}
            aria-current={if @list == list, do: "true"}
          >
            <%= label %>
          </.link>
        </div>
      </:group>
      <:group label={gettext("Securities")} label_id="crash-universe-label">
        <div class="segmented-control" data-role="crash-universe" role="group" aria-labelledby="crash-universe-label">
          <%= for {universe, label} <- universes() do %>
            <.link
              patch={@paths.universes[universe]}
              class={["segmented-control__option", @universe == universe && "is-active"]}
              data-universe={universe}
              aria-current={if @universe == universe, do: "true"}
            >
              <%= label %>
            </.link>
          <% end %>
        </div>
      </:group>
    </ControlBar.bar>
    """
  end

  defp option_label(window) do
    name = window.name || gettext("Unnamed")

    text =
      if Map.get(window, :provisional, false) do
        gettext("%{name} · since %{date} · ongoing", name: name, date: Format.date(window.start))
      else
        "#{name} · #{Format.date(window.start)}–#{Format.date(window.trough)}"
      end

    if window.kind == "manual",
      do: text <> " · " <> pgettext("crash kind", "manual"),
      else: text
  end

  # The window line: name, kind, dates, the benchmark's fall in its own
  # currency, the recovery, and „Im Depot ansehen“ or why not (F4).
  defp window_line(assigns) do
    assigns =
      assign(assigns,
        provisional: Map.get(assigns.window, :provisional, false),
        link: holdings_link(assigns.window, assigns.first_date, assigns.today)
      )

    ~H"""
    <p class="crash-window" data-role="crash-window">
      <b :if={@window.name}><%= @window.name %></b>
      <b :if={is_nil(@window.name)}><i><%= gettext("Unnamed") %></i></b>
      <.kind_badge kind={@window.kind} />
      <span>
        <%= pgettext("crash", "High") %> <b><%= Format.date(@window.start) %></b>
        →
        <%= if @provisional, do: pgettext("crash", "low so far"), else: pgettext("crash line", "low") %>
        <b><%= Format.date(@window.trough) %></b>
        <span :if={@provisional} class="badge badge-warning"><%= pgettext("crash", "provisional") %></span>
      </span>
      <span :if={@window.kind == "detected" and @benchmark}>
        <%= @benchmark.name %>
        <b class={sign_class(@window.decline)}><%= Format.signed_percent(@window.decline) %> %</b>
        <%= gettext("in %{currency}", currency: @benchmark.currency_code) %>
      </span>
      <span :if={@window.kind == "detected"}>
        <%= if @provisional,
          do: pgettext("crash", "ongoing"),
          else: gettext("recovered on %{date}", date: Format.date(@window.recovered_on)) %>
      </span>
      <span :if={@list == "rebounders" and @ranking}>
        <%= gettext("Recovery measured to") %> <b><%= Format.date(@ranking.measured_to) %></b>
        <%= if @ranking.provisional do %>
          <span class="badge badge-warning"><%= pgettext("crash", "provisional") %></span>
          <%= if @ranking.completes_on do %>
            · <%= gettext("complete on %{date}", date: Format.date(@ranking.completes_on)) %>
          <% end %>
        <% else %>
          <%= gettext("(low + 3 months)") %>
        <% end %>
      </span>
      <%= case @link do %>
        <% {:link, href} -> %>
          <.link navigate={href} class="crash-window__link" data-role="crash-holdings-link">
            <%= gettext("View in holdings →") %>
          </.link>
        <% {:none, nil} -> %>
          <span class="crash-window__nolink" data-role="crash-holdings-none">
            <%= gettext("The view has no booking yet.") %>
          </span>
        <% {:none, first} -> %>
          <span class="crash-window__nolink" data-role="crash-holdings-none">
            <%= gettext("The view begins on %{date}: there was no depot in this window.",
              date: Format.date(first)
            ) %>
          </span>
      <% end %>
    </p>
    """
  end

  # Holdings with the window as a custom range: from its high to its low,
  # or to today while it is ongoing. A window that ends before the view's
  # first booking would open on Holdings' one-year fallback, so it links
  # nothing and says why (F4), as Holdings' own range check decides.
  defp holdings_link(window, first_date, today) do
    to = if Map.get(window, :provisional, false), do: today, else: window.trough

    cond do
      is_nil(first_date) ->
        {:none, nil}

      Date.compare(to, first_date) == :lt ->
        {:none, first_date}

      true ->
        {:link,
         "/portfolio?" <>
           URI.encode_query(from: Date.to_iso8601(window.start), to: Date.to_iso8601(to))}
    end
  end

  attr(:kind, :string, required: true)

  defp kind_badge(assigns) do
    ~H"""
    <span :if={@kind == "manual"} class="badge crash-badge--manual"><%= pgettext("crash kind", "manual") %></span>
    <span :if={@kind != "manual"} class="badge badge--neutral"><%= pgettext("crash kind", "detected") %></span>
    """
  end

  # The list: rank, name (with „im Depot“ in the catalogue), the bar
  # against the benchmark's dashed line, the figure, the points and, for
  # the rebounders, the days back. At a phone's width each row is two
  # lines (P5), by the stylesheet alone.
  defp list_table(assigns) do
    reference = assigns.ranking.reference && assigns.ranking.reference.return
    values = Enum.map(assigns.ranking.entries, & &1.return)
    scale = scale(if(reference, do: [reference | values], else: values))

    assigns =
      assign(assigns,
        reference: reference,
        scale: scale,
        rebound?: assigns.list == "rebounders",
        catalogue?: assigns.universe == "catalogue",
        benchmark_name: assigns.ranking.benchmark && assigns.ranking.benchmark.name
      )

    ~H"""
    <%= if @ranking.entries == [] do %>
      <p class="empty-state" data-role="crash-list-empty"><%= gettext("No security with an answer.") %></p>
    <% else %>
      <div class="data-table-wrapper">
        <table class={["data-table crash-table", @rebound? && "is-rebound"]} data-list={@list}>
          <thead>
            <tr>
              <th class="crash-rank">#</th>
              <th class="crash-name"><%= gettext("Security") %></th>
              <th class="crash-plot">
                <%= if @rebound?,
                  do: gettext("Rise from own low, EUR"),
                  else: gettext("Price return high → low, EUR") %>
              </th>
              <th class="num crash-fig">%</th>
              <th :if={@reference} class="num crash-pp">
                <%= gettext("vs. %{benchmark}", benchmark: @benchmark_name) %>
              </th>
              <th :if={@rebound?} class="num crash-days"><%= gettext("Days to pre-crash close") %></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={entry <- @ranking.entries}
              data-rank={entry.rank}
              data-security-id={entry.security.id}
              data-return={Decimal.to_string(entry.return)}
            >
              <td class="crash-rank"><%= entry.rank %></td>
              <td class="crash-name">
                <%= entry.security.name %><SecurityNames.twin_id tag={entry.twin_id} /><span
                  :if={@catalogue? and entry.held}
                  class="badge badge--neutral"
                  data-role="crash-held"
                ><%= pgettext("crash", "in depot") %></span>
              </td>
              <td class="crash-plot" aria-hidden="true">
                <div class="crash-track">
                  <span class="crash-track__zero" style={"left:#{position(@scale, Decimal.new(0))}%"}></span>
                  <span class={["crash-track__bar", Decimal.gt?(entry.return, 0) && "is-up"]} style={bar_style(@scale, entry.return)}></span>
                  <span :if={@reference} class="crash-track__ref" style={"left:#{position(@scale, @reference)}%"}></span>
                </div>
              </td>
              <td class={["num crash-fig", sign_class(entry.return)]} data-role="crash-figure">
                <%= Format.signed_percent(entry.return) %> %
              </td>
              <td :if={@reference} class="num crash-pp">
                <%= gettext("%{value} pp", value: Format.plain_signed_decimal(entry.vs_benchmark_pp, 1)) %>
              </td>
              <td :if={@rebound?} class={["num crash-days", entry.not_yet && "crash-notyet"]} data-role="crash-days">
                <span class="crash-days__label"><%= gettext("Days to pre-crash close") %>:</span>
                <%= if entry.not_yet, do: gettext("not yet"), else: entry.days_back %>
              </td>
            </tr>
          </tbody>
          <tfoot aria-hidden="true">
            <tr>
              <td class="crash-rank"></td>
              <td class="crash-name"></td>
              <td class="crash-plot">
                <div class="crash-axis">
                  <span :for={tick <- ticks(@scale)} style={"left:#{position(@scale, tick)}%"}>
                    <%= tick_label(tick) %> %
                  </span>
                </div>
              </td>
              <td class="crash-fig"></td>
              <td :if={@reference} class="crash-pp"></td>
              <td :if={@rebound?} class="crash-days"></td>
            </tr>
          </tfoot>
        </table>
      </div>
    <% end %>
    <p class="summary-basis crash-basis" data-role="crash-basis">
      <%= basis_text(@ranking, @list) %>
    </p>
    """
  end

  defp basis_text(ranking, list) do
    figure =
      cond do
        list != "rebounders" ->
          gettext("Basis: EUR price return from the window's high to its low")

        ranking.provisional ->
          gettext(
            "Basis: EUR rise from each security's own low to the last close (%{date}), not to the end of the span",
            date: Format.date(ranking.measured_to)
          )

        true ->
          gettext("Basis: EUR rise from each security's own low to the end of the recovery span")
      end

    reference =
      case {ranking.reference, ranking.benchmark} do
        {%{return: return}, %{name: name}} when list == "rebounders" ->
          gettext("dashed: %{benchmark} (%{return} %)",
            benchmark: name,
            return: Format.signed_percent(return)
          )

        {%{return: return}, %{name: name}} ->
          gettext("dashed: %{benchmark} over the same days (%{return} %)",
            benchmark: name,
            return: Format.signed_percent(return)
          )

        {nil, %{name: name}} ->
          gettext("no comparison: %{benchmark} has no price or rate for these days",
            benchmark: name
          )

        {nil, nil} ->
          gettext("no comparison: no crash benchmark chosen")
      end

    Enum.join(
      [figure, reference, gettext("only securities the catalogue still holds.")],
      " · "
    )
  end

  # The answered and the unanswered, counted per reason, never a zero.
  defp unanswered(assigns) do
    counts = assigns.ranking.unanswered
    missing = counts |> Map.values() |> Enum.sum()

    assigns =
      assign(assigns,
        shown: length(assigns.ranking.entries),
        total: assigns.ranking.answered + missing,
        missing: missing,
        parts:
          [
            {counts.no_close_at_start, &no_start_text/1},
            {counts.no_close_at_end, &no_end_text/1},
            {counts.no_fx_rate, &no_rate_text/1}
          ]
          |> Enum.reject(fn {count, _text} -> count == 0 end)
          |> Enum.map(fn {count, text} -> text.(count) end)
      )

    ~H"""
    <p class="crash-unanswered" data-role="crash-unanswered">
      <%= ngettext(
        "%{shown} of %{count} security with an answer shown",
        "%{shown} of %{count} securities with an answer shown",
        @total,
        shown: @shown
      ) %><%= if @missing > 0 do %> · <%= ngettext(
          "%{count} without an answer: %{reasons}",
          "%{count} without an answer: %{reasons}",
          @missing,
          reasons: Enum.join(@parts, ", ")
        ) %>
        <button type="button" class="link-button" phx-click="crash_toggle_unanswered" phx-target={@myself}>
          <%= if @show, do: gettext("hide"), else: gettext("show") %>
        </button>
      <% end %>
    </p>
    <ul :if={@show and Map.get(@ranking, :unanswered_entries, []) != []} class="crash-unanswered-list" data-role="crash-unanswered-list">
      <li :for={item <- @ranking.unanswered_entries}>
        <%= item.security.name %> · <%= reason_label(item.reason) %>
      </li>
    </ul>
    """
  end

  defp no_start_text(count),
    do:
      ngettext(
        "%{count} without a close at the window's start",
        "%{count} without a close at the window's start",
        count
      )

  defp no_end_text(count),
    do:
      ngettext(
        "%{count} without a close at its end",
        "%{count} without a close at its end",
        count
      )

  defp no_rate_text(count),
    do: ngettext("%{count} without an exchange rate", "%{count} without an exchange rate", count)

  defp reason_label("no_close_at_start"), do: gettext("no close at the window's start")
  defp reason_label("no_close_at_end"), do: gettext("no close at its end")
  defp reason_label(_no_fx_rate), do: gettext("no exchange rate")

  # The windows behind the disclosure: the rule and the crash benchmark
  # (board 02 ④), every window with its kind, the names without a window,
  # and the forms.
  defp windows(assigns) do
    listing = assigns.listing

    assigns =
      assign(assigns,
        detected_count: length(listing.detected),
        manual_count: length(listing.manual),
        unmatched: listing.unmatched_names,
        open?: assigns.form != nil
      )

    ~H"""
    <details class="perf-table-disclosure crash-windows" id="crash-windows" phx-hook="DisclosureState" open={@open?}>
      <summary class="disclosure-summary">
        <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
        <%= summary_text(@detected_count, @manual_count, length(@unmatched)) %>
      </summary>
      <div class="crash-windows__body">
        <p class="crash-rule" data-role="crash-rule">
          <%= if @benchmark do %>
            <span>
              <%= gettext("Rule: high → low from 10 % in the crash benchmark's close · crash benchmark") %>
              <b><%= @benchmark.name %></b> (<%= @benchmark.currency_code %>)
            </span>
            <button
              type="button"
              class="link-button"
              data-role="crash-change-benchmark"
              phx-click="crash_choose_benchmark"
              phx-target={@myself}
            >
              <%= pgettext("crash", "Change") %>
            </button>
          <% else %>
            <span><%= gettext("No crash benchmark chosen.") %></span>
            <button
              type="button"
              class="link-button"
              phx-click="crash_choose_benchmark"
              phx-target={@myself}
            >
              <%= gettext("Choose crash benchmark") %>
            </button>
          <% end %>
          <button
            type="button"
            class="button-secondary crash-rule__add"
            data-role="crash-add-window"
            phx-click="crash_add_window"
            phx-target={@myself}
          >
            <AppShell.icon name={:plus} size={12} /><%= gettext("Add window") %>
          </button>
        </p>

        <.benchmark_form :if={@form == :benchmark} myself={@myself} benchmark={@benchmark} errors={@errors} />
        <.window_form
          :if={match?({:name, _}, @form) or match?({:manual, _}, @form) or @form == :manual_new}
          myself={@myself}
          form={@form}
          windows={@windows}
          errors={@errors}
          posted={@posted}
        />

        <div :if={@windows != []} class="data-table-wrapper">
          <table class="data-table crash-windows-table" id="crash-windows-table">
            <thead>
              <tr>
                <th><%= gettext("Name") %></th>
                <th><%= pgettext("crash", "High") %></th>
                <th><%= pgettext("crash", "Low") %></th>
                <th class="num"><%= gettext("Decline") %></th>
                <th><%= gettext("Recovered") %></th>
                <th class="num"><%= gettext("Gap, days") %></th>
                <th><%= gettext("Kind") %></th>
                <th><span class="sr-only"><%= gettext("Actions") %></span></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={window <- @windows}
                data-key={window.key}
                class={Map.get(window, :provisional, false) && "is-ongoing"}
              >
                <td class={is_nil(window.name) && "crash-unnamed"}><%= window.name || gettext("unnamed") %></td>
                <td><%= Format.date(window.start) %></td>
                <td>
                  <%= Format.date(window.trough) %>
                  <span :if={Map.get(window, :provisional, false)} class="badge badge-warning"><%= pgettext("crash", "provisional") %></span>
                </td>
                <%= if window.kind == "detected" do %>
                  <td class={["num", sign_class(window.decline)]}><%= Format.signed_percent(window.decline) %> %</td>
                  <td>
                    <%= if window.provisional,
                      do: pgettext("crash", "ongoing"),
                      else: Format.date(window.recovered_on) %>
                  </td>
                  <td class="num"><%= window.max_gap_days %></td>
                <% else %>
                  <td class="num muted">—</td>
                  <td class="muted">—</td>
                  <td class="num muted">—</td>
                <% end %>
                <td><.kind_badge kind={window.kind} /></td>
                <td class="crash-actions">
                  <%= if window.kind == "detected" do %>
                    <button
                      type="button"
                      class="link-button"
                      data-role="crash-name-open"
                      phx-click="crash_name_open"
                      phx-value-key={window.key}
                      phx-target={@myself}
                    >
                      <%= if window.name, do: gettext("Rename"), else: pgettext("crash action", "Name") %>
                    </button>
                    <button
                      :if={window.name}
                      type="button"
                      class="link-button"
                      data-role="crash-unname"
                      phx-click="crash_unname"
                      phx-value-key={window.key}
                      phx-target={@myself}
                      data-confirm={gettext("Delete the name „%{name}“?", name: window.name)}
                    >
                      <%= gettext("Delete name") %>
                    </button>
                  <% else %>
                    <button
                      type="button"
                      class="link-button"
                      data-role="crash-manual-edit"
                      phx-click="crash_manual_edit"
                      phx-value-key={window.key}
                      phx-target={@myself}
                    >
                      <%= gettext("Edit") %>
                    </button>
                    <button
                      type="button"
                      class="link-button"
                      data-role="crash-manual-delete"
                      phx-click="crash_manual_delete"
                      phx-value-key={window.key}
                      phx-target={@myself}
                      data-confirm={gettext("Delete the manual window „%{name}“?", name: window.name)}
                    >
                      <%= gettext("Delete") %>
                    </button>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@unmatched != []} class="crash-unmatched" id="crash-unmatched">
          <h3><%= ngettext(
            "Name without a window (%{count})",
            "Names without a window (%{count})",
            length(@unmatched)
          ) %></h3>
          <p class="hint">
            <%= gettext("The closes have changed: no detected window starts on these days any more. A name is never attached to another window by a guess.") %>
          </p>
          <div class="data-table-wrapper">
            <table class="data-table crash-windows-table">
              <thead>
                <tr>
                  <th><%= gettext("Name") %></th>
                  <th><%= gettext("Given for") %></th>
                  <th><%= pgettext("crash", "High") %></th>
                  <th><span class="sr-only"><%= gettext("Actions") %></span></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={name <- @unmatched} data-key={name.key}>
                  <td><%= name.name %></td>
                  <td>
                    <%= name.benchmark_name || gettext("a removed security") %>
                    <span :if={not name.for_current_benchmark} class="muted">
                      · <%= gettext("returns when it is the crash benchmark again") %>
                    </span>
                  </td>
                  <td><%= Format.date(name.start) %></td>
                  <td class="crash-actions">
                    <button
                      type="button"
                      class="link-button"
                      data-role="crash-from-name-open"
                      phx-click="crash_from_name_open"
                      phx-value-key={name.key}
                      phx-target={@myself}
                    >
                      <%= gettext("Make a manual window …") %>
                    </button>
                    <button
                      type="button"
                      class="link-button"
                      data-role="crash-unname"
                      phx-click="crash_unname"
                      phx-value-key={name.key}
                      phx-target={@myself}
                      data-confirm={gettext("Delete the name „%{name}“?", name: name.name)}
                    >
                      <%= gettext("Delete") %>
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <.from_name_form
            :if={match?({:from_name, _}, @form)}
            myself={@myself}
            name={Enum.find(@unmatched, &({:from_name, &1.key} == @form))}
            errors={@errors}
            posted={@posted}
          />
        </div>
      </div>
    </details>
    """
  end

  defp summary_text(detected, manual, unmatched) do
    parts =
      [
        detected > 0 && ngettext("%{count} detected", "%{count} detected", detected),
        manual > 0 && ngettext("%{count} manual", "%{count} manual", manual),
        unmatched > 0 &&
          ngettext("%{count} name without a window", "%{count} names without a window", unmatched)
      ]
      |> Enum.filter(& &1)

    Enum.join([gettext("Crash windows") | parts], " · ")
  end

  # Board 02 ④ (Q2): the crash benchmark chosen in place, from the
  # pickers' groups („Benchmarks“, „Im Bestand“, and „Weitere“ for a chosen
  # one neither offers), written through the API's own path, journaled.
  defp benchmark_form(assigns) do
    chosen = if assigns.benchmark, do: [assigns.benchmark], else: []
    assigns = assign(assigns, groups: BenchmarkChoices.groups(chosen))

    ~H"""
    <form id="crash-benchmark-form" class="crash-benchmark-form" phx-submit="crash_save_benchmark" phx-target={@myself}>
      <label for="crash-benchmark"><%= gettext("Crash benchmark") %></label>
      <select id="crash-benchmark" name="crash_benchmark">
        <option :if={is_nil(@benchmark)} value="" disabled selected><%= gettext("— choose —") %></option>
        <optgroup :for={group <- @groups} label={group.label} data-group={group.key}>
          <option
            :for={security <- group.securities}
            value={security.id}
            selected={@benchmark && @benchmark.id == security.id}
          >
            <%= BenchmarkChoices.label(group, security) %>
          </option>
        </optgroup>
      </select>
      <div class="crash-benchmark-form__actions">
        <button type="submit" class="button-primary"><%= gettext("Save") %></button>
        <button type="button" class="button-ghost" phx-click="crash_cancel" phx-target={@myself}>
          <%= gettext("Cancel") %>
        </button>
      </div>
      <ul :if={@errors != []} class="crash-form__errors" role="alert">
        <li :for={error <- @errors}><%= error %></li>
      </ul>
      <p class="hint">
        <%= gettext("Applies to this page and every agent: all read the same windows. The change is in the audit journal.") %>
      </p>
      <p :if={@benchmark} class="hint">
        <%= gettext("Names stay with the former benchmark and return when it is chosen again.") %>
      </p>
    </form>
    """
  end

  # Naming a detected window, or drawing or editing a manual one (§3, §4).
  defp window_form(assigns) do
    window =
      case assigns.form do
        {_kind, key} -> Enum.find(assigns.windows, &(&1.key == key))
        :manual_new -> nil
      end

    assigns =
      assign(assigns,
        name_only?: match?({:name, _}, assigns.form),
        value: fn field, stored -> Map.get(assigns.posted, field, stored) end,
        window: window
      )

    ~H"""
    <form id="crash-window-edit-form" class="crash-edit-form" phx-submit="crash_window_save" phx-target={@myself}>
      <label>
        <%= gettext("Name") %>
        <input type="text" name="window[name]" value={@value.("name", @window && @window.name)} required />
      </label>
      <%= unless @name_only? do %>
        <label>
          <%= pgettext("crash", "High") %>
          <input
            type="text"
            name="window[start]"
            placeholder="YYYY-MM-DD"
            pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
            maxlength="10"
            value={@value.("start", @window && Date.to_iso8601(@window.start))}
            required
          />
        </label>
        <label>
          <%= pgettext("crash", "Low") %>
          <input
            type="text"
            name="window[trough]"
            placeholder="YYYY-MM-DD"
            pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
            maxlength="10"
            value={@value.("trough", @window && Date.to_iso8601(@window.trough))}
            required
          />
        </label>
      <% end %>
      <button type="submit" class="button-primary"><%= gettext("Save") %></button>
      <button type="button" class="button-ghost" phx-click="crash_cancel" phx-target={@myself}>
        <%= gettext("Cancel") %>
      </button>
      <ul :if={@errors != []} class="crash-form__errors" role="alert">
        <li :for={error <- @errors}><%= error %></li>
      </ul>
      <p :if={not @name_only?} class="hint">
        <%= gettext("A manual window's dates are chosen by hand, and it reads „manual“ wherever it is read.") %>
      </p>
    </form>
    """
  end

  # F1: a name keeps only its high; the low is asked for, never guessed.
  defp from_name_form(%{name: nil} = assigns), do: ~H""

  defp from_name_form(assigns) do
    assigns =
      assign(assigns, value: fn field, stored -> Map.get(assigns.posted, field, stored) end)

    ~H"""
    <form id="crash-from-name-form" class="crash-edit-form" phx-submit="crash_from_name_save" phx-target={@myself}>
      <label>
        <%= gettext("Name") %>
        <input type="text" name="window[name]" value={@value.("name", @name.name)} required />
      </label>
      <label>
        <%= pgettext("crash", "High") %>
        <input type="text" value={Date.to_iso8601(@name.start)} readonly />
      </label>
      <label>
        <%= pgettext("crash", "Low") %>
        <input
          type="text"
          name="window[trough]"
          placeholder="YYYY-MM-DD"
          pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
          maxlength="10"
          value={@value.("trough", nil)}
          aria-invalid={if @errors != [], do: "true"}
          required
        />
      </label>
      <button type="submit" class="button-primary"><%= gettext("Create") %></button>
      <button type="button" class="button-ghost" phx-click="crash_cancel" phx-target={@myself}>
        <%= gettext("Cancel") %>
      </button>
      <ul :if={@errors != []} class="crash-form__errors" role="alert">
        <li :for={error <- @errors}><%= error %></li>
      </ul>
      <p class="hint">
        <%= gettext("A name keeps only the day of its high: the low is entered here. The window is then „manual“, and the name without a window goes.") %>
      </p>
    </form>
    """
  end

  # -- the bars' scale --------------------------------------------------------

  # The axis in whole percent, rounded outward to a step that gives at most
  # four intervals, zero always inside. Display arithmetic only.
  defp scale(values) do
    percents = Enum.map(values, &Decimal.mult(&1, @hundred))
    lo = Enum.reduce(percents, Decimal.new(0), &Decimal.min/2)
    hi = Enum.reduce(percents, Decimal.new(0), &Decimal.max/2)
    span = Decimal.sub(hi, lo)

    step =
      Enum.find(@steps, List.last(@steps), fn step ->
        Decimal.compare(Decimal.mult(step, 4), span) != :lt
      end)

    lo_tick = round_to(lo, step, :floor)
    hi_tick = round_to(hi, step, :ceiling)

    hi_tick = if Decimal.eq?(lo_tick, hi_tick), do: Decimal.add(hi_tick, step), else: hi_tick
    %{lo: lo_tick, hi: hi_tick, step: step}
  end

  defp round_to(value, step, mode) do
    value |> Decimal.div(step) |> Decimal.round(0, mode) |> Decimal.mult(step)
  end

  # A fraction's place on the track, in percent of its width.
  defp position(%{lo: lo, hi: hi}, fraction) do
    fraction
    |> Decimal.mult(@hundred)
    |> Decimal.sub(lo)
    |> Decimal.div(Decimal.sub(hi, lo))
    |> Decimal.mult(@hundred)
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  defp bar_style(scale, value) do
    zero = Decimal.new(0)
    from = position(scale, Decimal.min(value, zero))
    to = position(scale, Decimal.max(value, zero))
    width = Decimal.sub(Decimal.new(to), Decimal.new(from)) |> Decimal.to_string(:normal)
    "left:#{from}%;width:#{width}%"
  end

  # The ticks as fractions, one per step from the low end to the high one.
  defp ticks(%{lo: lo, hi: hi, step: step}) do
    count = hi |> Decimal.sub(lo) |> Decimal.div(step) |> Decimal.to_integer()

    for index <- 0..count do
      lo |> Decimal.add(Decimal.mult(step, index)) |> Decimal.div(@hundred)
    end
  end

  defp tick_label(tick), do: Format.plain_signed_decimal(Decimal.mult(tick, @hundred), 0)

  defp sign_class(value) do
    case Format.displayed_percent_sign(value) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      _zero -> nil
    end
  end
end
