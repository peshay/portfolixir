defmodule PortfolixirWeb.WidgetsLive do
  @moduledoc """
  „Alle Widgets“, the catalogue as a page under „Entdecken“ (ADR-0062 §1;
  ADR-0022's amendment of 2026-11-21; Sprint 31 D7; planning board
  `ux-design-2026-11-21-sprint31/01` ②), at `/widgets`.

  * **The registry's kinds**, by group in the registry's order, each with
    its title, its sizes as chips and „hinzufügen ›“. The page lists
    `Portfolixir.Dashboards.widgets/0` and nothing else as addable.
  * **The kinds each later pass brings**, dashed, with „kommt mit dem
    Umbau seines Screens“ (`later_kinds/0`): a static list of this page,
    **not registered kinds**. They have no add, and a layout naming one is
    refused by the layout's validation as an unknown kind, so the
    catalogue promises them without letting them be stored.
  * **„hinzufügen ›“** opens the choice of dashboard: the stored ones in
    the menu's order, read when the dialog opens. Choosing one adds the
    kind at its first size at the first free place of that dashboard's
    grid (`Portfolixir.Dashboards.Layout.first_free/2`) through the
    journaled replace with the lock_version the dialog read
    (`Dashboards.replace_dashboard/3`, ADR-0062 §2): a dashboard changed
    since answers stale, nothing is written, and the dialog shows the
    dashboards as now stored. On a fresh instance, where none is stored,
    the dialog offers to copy „Überblick“ with the widget (one journaled
    create) and links „Neues Dashboard“.
  * **„Suchen …“** keeps the kinds whose title holds the text.
  """
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.StoredText

  # Board ②'s dashed cards: what each later screen's pass brings, with the
  # sizes the board draws, read on Apple's families as a stored layout is
  # (Sprint 32 E4: W → M, M → L, L → XL). Keys name them on this page only;
  # none is a registered kind (`widget_catalogue_test.exs` holds that).
  @later [
    %{key: "contribution", group: "performance", sizes: ~w(L XL)},
    %{key: "allocation", group: "allocation", sizes: ~w(L)},
    %{key: "key_figures", group: "risk", sizes: ~w(S L)},
    %{key: "concentration", group: "risk", sizes: ~w(S)},
    %{key: "asset_class_limits", group: "risk", sizes: ~w(L)},
    %{key: "predictions", group: "analyses", sizes: ~w(S L)},
    %{key: "income", group: "income_tax", sizes: ~w(M L)},
    %{key: "fees_and_taxes", group: "income_tax", sizes: ~w(L)},
    %{key: "tax_allowance", group: "income_tax", sizes: ~w(S)}
  ]

  # The registry's groups, then the one only later kinds fill.
  @later_groups ~w(income_tax)

  @doc "The kinds the later passes bring, drawn dashed; no registered kind."
  @spec later_kinds() :: [%{key: String.t(), group: String.t(), sizes: [String.t()]}]
  def later_kinds, do: @later

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, query: "", adding: nil, added: nil)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) when is_binary(query),
    do: {:noreply, assign(socket, :query, String.slice(query, 0, 100))}

  # „hinzufügen ›“: the choice of dashboard, the stored ones as they are
  # now (the lock_version the add will name). A key that is no kind opens
  # nothing.
  def handle_event("choose", %{"kind" => key}, socket) when is_binary(key) do
    case Dashboards.fetch_widget(key) do
      {:ok, kind} ->
        {:noreply,
         assign(socket,
           adding: %{kind: kind, dashboards: Dashboards.list_dashboards(), note: nil},
           added: nil
         )}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("add", %{"id" => raw}, %{assigns: %{adding: %{} = adding}} = socket) do
    case Enum.find(adding.dashboards, &(&1.id == LiveParam.id(raw))) do
      nil -> {:noreply, socket}
      dashboard -> {:noreply, add(socket, adding, dashboard)}
    end
  end

  # A fresh instance: „Überblick“ copied with the widget at its first free
  # place, as one create, and opened.
  def handle_event("add_to_template", _params, %{assigns: %{adding: %{dashboards: []}}} = socket) do
    adding = socket.assigns.adding
    template = hd(Dashboards.templates())

    with {:ok, item} <- placed(adding.kind, template.layout),
         {:ok, dashboard} <-
           Dashboards.create_dashboard(Actor.owner_ui(), %{
             "name" => Templates.title(template.key),
             "layout" => template.layout ++ [item]
           }) do
      {:noreply, push_navigate(socket, to: "/dashboards/#{dashboard.id}")}
    else
      {:error, reason} ->
        {:noreply, assign(socket, :adding, %{adding | note: {:refused, reason, nil}})}
    end
  end

  def handle_event("cancel_add", _params, socket), do: {:noreply, assign(socket, :adding, nil)}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp add(socket, adding, dashboard) do
    with {:ok, item} <- placed(adding.kind, dashboard.layout),
         {:ok, stored} <-
           Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
             "name" => dashboard.name,
             "layout" => dashboard.layout ++ [item],
             "lock_version" => dashboard.lock_version
           }) do
      assign(socket,
        adding: nil,
        added: %{kind: adding.kind.key, id: stored.id, name: Dashboards.display_name(stored)}
      )
    else
      {:error, :stale, _stored} ->
        assign(socket, :adding, reread(adding, {:stale, Dashboards.display_name(dashboard)}))

      {:error, :not_found} ->
        assign(socket, :adding, reread(adding, {:gone, Dashboards.display_name(dashboard)}))

      {:error, reason} ->
        assign(socket, :adding, %{
          adding
          | note: {:refused, reason, Dashboards.display_name(dashboard)}
        })
    end
  end

  defp reread(adding, note), do: %{adding | dashboards: Dashboards.list_dashboards(), note: note}

  # The kind at its first grid size, at the first free place of `layout`.
  defp placed(kind, layout) do
    size = Enum.find(kind.sizes, &match?({:ok, _}, Widgets.dimensions(&1)))

    with {:ok, place} <- Layout.first_free(layout, size) do
      {:ok, Map.merge(%{"kind" => kind.key, "size" => size, "settings" => %{}}, place)}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :groups, groups(assigns.query))

    ~H"""
    <AppShell.shell page_address={@page_address}
      current_path="/widgets"
      page_title={gettext("All widgets")}
      page_subtitle={gettext("Every widget a dashboard can hold, by topic")}
    >
      <div id="widgets-workspace" class="workspace-page widget-catalogue-page">
        <section class="workspace-section workspace-section--controls widget-catalogue__bar">
          <form id="widget-search" phx-change="search" phx-submit="search" role="search">
            <input
              type="search"
              name="q"
              value={@query}
              class="widget-catalogue__search"
              placeholder={gettext("Search …")}
              aria-label={gettext("Search widgets")}
              autocomplete="off"
            />
          </form>
          <div id="widget-added-status" role="status"><AppShell.data_note
              :if={@added}
              severity={:note}
              data-role="widget-added"
            ><%= StoredText.isolate(
                gettext("%{widget} was added to %{name}.",
                  widget: Widgets.title(@added.kind),
                  name: StoredText.slot(:name)
                ),
                name: @added.name
              ) %> <.link navigate={"/dashboards/#{@added.id}"}><%= gettext("Open it") %></.link></AppShell.data_note></div>
        </section>

        <p :if={@groups == []} class="hint" data-role="widget-search-none">
          <%= gettext("No widget's name holds this text.") %>
        </p>

        <section
          :for={group <- @groups}
          class="workspace-section widget-group"
          data-role="widget-group"
          data-group={group.key}
          aria-labelledby={"widget-group-#{group.key}"}
        >
          <h2 id={"widget-group-#{group.key}"} class="widget-group__title"><%= group.title %></h2>
          <ul class="widget-catalogue" role="list">
            <li
              :for={kind <- group.kinds}
              class="widget-card"
              data-role="widget-card"
              data-widget-kind={kind.key}
            >
              <h3 class="widget-card__title"><%= kind.title %></h3>
              <.sizes sizes={kind.sizes} />
              <button
                type="button"
                class="widget-card__add"
                data-role="add-widget"
                phx-click="choose"
                phx-value-kind={kind.key}
                aria-label={gettext("Add %{widget} to a dashboard", widget: kind.title)}
              >
                <%= gettext("add ›") %>
              </button>
            </li>
            <li
              :for={kind <- group.later}
              class="widget-card widget-card--later"
              data-later-kind={kind.key}
            >
              <h3 class="widget-card__title"><%= kind.title %></h3>
              <.sizes sizes={kind.sizes} />
              <p class="widget-card__later"><%= gettext("comes with its screen's rework") %></p>
            </li>
          </ul>
        </section>

        <.add_dialog :if={@adding} adding={@adding} />
      </div>
    </AppShell.shell>
    """
  end

  attr(:sizes, :list, required: true)

  defp sizes(assigns) do
    ~H"""
    <ul class="widget-card__sizes" aria-label={gettext("Sizes")} role="list">
      <li :for={size <- @sizes} class="widget-size" data-role="widget-size"><%= Widget.size_label(size) %></li>
    </ul>
    """
  end

  attr(:adding, :map, required: true)

  # The choice of dashboard (board ②: „hinzufügen öffnet die Wahl des
  # Dashboards“), a native dialog on the ModalDialog hook.
  defp add_dialog(assigns) do
    assigns = assign(assigns, :title, Widgets.title(assigns.adding.kind.key))

    ~H"""
    <dialog
      id="widget-add-dialog"
      class="modal widget-add-dialog"
      phx-hook="ModalDialog"
      data-close-event="cancel_add"
      aria-labelledby="widget-add-title"
    >
      <header class="modal-head">
        <h2 id="widget-add-title"><%= gettext("Add %{widget}", widget: @title) %></h2>
        <button type="button" class="icon-button" aria-label={gettext("Close")} phx-click="cancel_add">
          <AppShell.icon name={:x} />
        </button>
      </header>
      <div class="modal-body">
        <div role="status"><.add_note :if={@adding.note} note={@adding.note} /></div>
        <%= if @adding.dashboards == [] do %>
          <p data-role="widget-add-none">
            <%= gettext(
              "No dashboard is stored yet. Copy the template %{template} with this widget, or start a new dashboard.",
              template: Templates.title(hd(Dashboards.templates()).key)
            ) %>
          </p>
          <div class="widget-add-dialog__choices">
            <button type="button" class="button-primary" data-role="add-to-template" phx-click="add_to_template">
              <%= gettext("Copy %{template} with this widget",
                template: Templates.title(hd(Dashboards.templates()).key)
              ) %>
            </button>
            <.link navigate="/dashboards/new" class="button-ghost"><%= gettext("New dashboard") %></.link>
          </div>
        <% else %>
          <p class="hint">
            <%= gettext("It is placed at the first free place; arrange it on the dashboard.") %>
          </p>
          <ul class="widget-add-dialog__list" role="list">
            <li :for={dashboard <- @adding.dashboards}>
              <button
                type="button"
                class="widget-add-dialog__choice"
                data-role="add-to"
                phx-click="add"
                phx-value-id={dashboard.id}
              ><bdi><%= Dashboards.display_name(dashboard) %></bdi></button>
            </li>
          </ul>
        <% end %>
      </div>
    </dialog>
    """
  end

  attr(:note, :any, required: true)

  defp add_note(%{note: {:stale, name}} = assigns) do
    assigns = assign(assigns, :name, name)

    ~H"""
    <AppShell.data_note severity={:attention} data-role="widget-add-stale"><%= StoredText.isolate(
        gettext(
          "%{name} was changed elsewhere since this list was read, so nothing was added. The list shows the dashboards as stored now; choose again.",
          name: StoredText.slot(:name)
        ),
        name: @name
      ) %></AppShell.data_note>
    """
  end

  defp add_note(%{note: {:gone, name}} = assigns) do
    assigns = assign(assigns, :name, name)

    ~H"""
    <AppShell.data_note severity={:attention} data-role="widget-add-stale"><%= StoredText.isolate(
        gettext("%{name} no longer exists, so nothing was added.", name: StoredText.slot(:name)),
        name: @name
      ) %></AppShell.data_note>
    """
  end

  defp add_note(%{note: {:refused, reason, name}} = assigns) do
    assigns = assign(assigns, :message, refusal(reason, name))

    ~H"""
    <AppShell.data_note severity={:problem} data-role="widget-add-refused"><%= @message %></AppShell.data_note>
    """
  end

  defp refusal(:too_many_items, name),
    do:
      StoredText.isolate(
        gettext("%{name} already holds %{max} widgets, the most a dashboard takes.",
          name: StoredText.slot(:name),
          max: Layout.max_items()
        ),
        name: name
      )

  defp refusal(:no_room, name),
    do:
      StoredText.isolate(
        gettext("%{name} has no free place left on its grid.", name: StoredText.slot(:name)),
        name: name
      )

  defp refusal(:too_many_dashboards, _name),
    do: gettext("Fifty dashboards are stored, the most an instance keeps.")

  defp refusal(_reason, _name), do: gettext("Couldn't add the widget.")

  # --- the catalogue ---------------------------------------------------------

  # The groups to draw: the registry's, then the later ones, each with its
  # kinds and its later kinds whose title holds `query`; a group left
  # empty is not drawn.
  defp groups(query) do
    needle = query |> String.trim() |> String.downcase()
    match? = fn title -> needle == "" or String.contains?(String.downcase(title), needle) end

    (Widgets.groups() ++ @later_groups)
    |> Enum.map(fn group ->
      %{
        key: group,
        title: group_title(group),
        kinds:
          for(
            kind <- Dashboards.widgets(),
            kind.group == group,
            title = Widgets.title(kind.key),
            match?.(title),
            do: %{key: kind.key, title: title, sizes: kind.sizes}
          ),
        later:
          for(
            kind <- @later,
            kind.group == group,
            title = later_title(kind.key),
            match?.(title),
            do: Map.put(kind, :title, title)
          )
      }
    end)
    |> Enum.reject(&(&1.kinds == [] and &1.later == []))
  end

  defp group_title("income_tax"), do: pgettext("widget group", "Income and tax")
  defp group_title(group), do: Widgets.group_title(group)

  defp later_title("contribution"), do: pgettext("widget kind", "Contribution by position")
  defp later_title("allocation"), do: pgettext("widget kind", "Allocation")
  defp later_title("key_figures"), do: pgettext("widget kind", "Key figures")
  defp later_title("concentration"), do: pgettext("widget kind", "Concentration")
  defp later_title("asset_class_limits"), do: pgettext("widget kind", "Asset class limits")
  defp later_title("predictions"), do: pgettext("widget kind", "Predictions")
  defp later_title("income"), do: pgettext("widget kind", "Income")
  defp later_title("fees_and_taxes"), do: pgettext("widget kind", "Fees and taxes")
  defp later_title("tax_allowance"), do: pgettext("widget kind", "Tax allowance")
end
