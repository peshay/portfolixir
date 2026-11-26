defmodule PortfolixirWeb.NewDashboardLive do
  @moduledoc """
  „Neues Dashboard“: the gallery (ADR-0062 §2, §3 and its amendment of
  2026-11-25, point 5; I61; Sprint 32 S4; planning board
  `ux-design-2026-11-25-sprint32/03` ①, ②), at `/dashboards/new`, the
  last entry of the menu's „Dashboards“ group.

  The gallery shows **„Leer beginnen“**, then the **starters** (today's
  screens as dashboards), then the **themes**; each template card draws its
  grid in miniature (one cell per widget at its place), its widget count
  and its widgets' names. Only templates whose kinds are all built are
  shown (`Portfolixir.Dashboards.Templates.offered/1`).

  A card opens a dialog: the name, suggested from the template's title and
  never one a dashboard already holds („… (2)“,
  `Portfolixir.Dashboards.suggested_name/1`), and, for a template that asks
  for one, the scope — the dashboard's own view, or none to follow the
  bar's (`view_id`, the amendment's point 4), preselected where a view is
  named as the template suggests (`Templates.suggested_scope/1`: „Krypto“
  for „Krypto Lover“, board 03 ②; the S32 closing act). **„Anlegen“** stores it under
  the UI's actor as one journaled create (`Dashboards.create_dashboard/2`,
  `Dashboards.copy_template/3`) and opens it: „Leer beginnen“ in the edit
  mode with the catalogue open (Sprint 31 closing act), a copy as it
  reads. A refused name is said at the field; the 51st dashboard is
  refused with the reason.
  """
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.FieldLabel
  alias PortfolixirWeb.LiveParam

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       templates: Dashboards.templates(),
       picked: nil,
       name: "",
       view_id: nil,
       name_error: nil,
       refused: nil
     )}
  end

  # --- the gallery and its dialog -------------------------------------------

  @impl true
  def handle_event("pick", %{"template" => ""}, socket),
    do: {:noreply, open(socket, :empty, "")}

  def handle_event("pick", %{"template" => key}, socket) when is_binary(key) do
    case Enum.find(socket.assigns.templates, &(&1.key == key)) do
      nil -> {:noreply, socket}
      template -> {:noreply, open(socket, template, Templates.title(template.key))}
    end
  end

  def handle_event("cancel_pick", _params, socket),
    do: {:noreply, assign(socket, picked: nil, name_error: nil, refused: nil)}

  def handle_event("create", %{"dashboard" => params}, %{assigns: %{picked: picked}} = socket)
      when is_map(params) and not is_nil(picked) do
    name = if is_binary(params["name"]), do: params["name"], else: ""
    view_id = view_id(picked, params["view_id"], socket.assigns.views)
    socket = assign(socket, name: name, view_id: view_id, name_error: nil, refused: nil)

    case create(picked, name, view_id) do
      {:ok, dashboard} ->
        # „Leer beginnen“ opens the edit mode with the catalogue (board 01
        # ③'s caption; Sprint 31 closing act).
        to =
          if picked == :empty,
            do: "/dashboards/#{dashboard.id}?edit=catalogue",
            else: "/dashboards/#{dashboard.id}"

        {:noreply, push_navigate(socket, to: to)}

      {:error, :too_many_dashboards} ->
        {:noreply,
         assign(
           socket,
           :refused,
           gettext("Fifty dashboards are stored, the most an instance keeps.")
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :name_error, name_error(changeset))}

      {:error, _refusal} ->
        {:noreply, assign(socket, :refused, gettext("Couldn't create the dashboard."))}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp open(socket, picked, title) do
    assign(socket,
      picked: picked,
      name: if(title == "", do: "", else: Dashboards.suggested_name(title)),
      view_id: preselected(picked, socket.assigns.views),
      name_error: nil,
      refused: nil
    )
  end

  # The view the dialog preselects for a template that asks for a scope
  # (board 03 ②, „Krypto ▾“; the S32 closing act): the first view whose
  # name is the template's suggested scope, in the page's language or its
  # English source, any case; else none, so the dashboard follows the
  # bar's view.
  defp preselected(%{asks_scope: true, key: key}, views) do
    case Templates.suggested_scope(key) do
      nil ->
        nil

      names ->
        wanted = Enum.map(names, &String.downcase/1)

        Enum.find_value(views, fn view ->
          if String.downcase(String.trim(view.name)) in wanted, do: view.id
        end)
    end
  end

  defp preselected(_picked, _views), do: nil

  # The scope a template that asks for one takes: a view the page lists,
  # else none (the dashboard follows the bar's).
  defp view_id(%{asks_scope: true}, raw, views) do
    with id when is_integer(id) <- LiveParam.id(raw),
         %{} <- Enum.find(views, &(&1.id == id)) do
      id
    else
      _none -> nil
    end
  end

  defp view_id(_picked, _raw, _views), do: nil

  defp create(:empty, name, _view_id),
    do: Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name, "layout" => []})

  defp create(template, name, view_id) do
    attrs = if view_id, do: %{"name" => name, "view_id" => view_id}, else: %{"name" => name}
    Dashboards.copy_template(Actor.owner_ui(), template.key, attrs)
  end

  # The name's refusals, in the page's language; any other field's as the
  # page's.
  defp name_error(changeset) do
    case Keyword.get_values(changeset.errors, :name) do
      [] -> FieldLabel.changeset_message(changeset)
      errors -> Enum.map_join(errors, ", ", &FieldLabel.translate_error/1)
    end
  end

  # --- the page ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        starters: Enum.filter(assigns.templates, &(Templates.group(&1) == "starter")),
        themes: Enum.filter(assigns.templates, &(Templates.group(&1) == "theme"))
      )

    ~H"""
    <AppShell.shell page_address={@page_address}
      current_path="/dashboards/new"
      page_title={gettext("New dashboard")}
      page_subtitle={gettext("Start empty or from a template")}
    >
      <div id="new-dashboard-workspace" class="workspace-page">
        <section class="workspace-section dashboard-gallery" aria-label={gettext("Templates")}>
          <button
            type="button"
            class="gallery-card gallery-card--empty"
            phx-click="pick"
            phx-value-template=""
            data-role="gallery-empty"
          >
            <span aria-hidden="true">+</span> <%= gettext("Start empty") %>
          </button>
          <h2 class="gallery-group"><%= gettext("Like today's pages · the starter dashboards") %></h2>
          <ul class="gallery-cards" data-role="gallery-starters">
            <li :for={template <- @starters}><.card template={template} /></li>
          </ul>
          <h2 :if={@themes != []} class="gallery-group"><%= gettext("Themes") %></h2>
          <ul :if={@themes != []} class="gallery-cards" data-role="gallery-themes">
            <li :for={template <- @themes}><.card template={template} /></li>
          </ul>
        </section>
      </div>
      <.create_dialog
        :if={@picked}
        picked={@picked}
        name={@name}
        view_id={@view_id}
        views={@views}
        name_error={@name_error}
        refused={@refused}
      />
    </AppShell.shell>
    """
  end

  attr(:template, :map, required: true)

  # One template's card (board 03 ①): its grid in miniature, its title, its
  # line, its widget count and its widgets' names.
  defp card(assigns) do
    assigns =
      assign(assigns,
        title: Templates.title(assigns.template.key),
        cells: Enum.flat_map(assigns.template.layout, &cell/1),
        names:
          assigns.template.layout
          |> Enum.map(&Widgets.title(&1["kind"]))
          |> Enum.uniq()
          |> Enum.join(", ")
      )

    ~H"""
    <button
      type="button"
      class="gallery-card"
      phx-click="pick"
      phx-value-template={@template.key}
      data-template={@template.key}
    >
      <span class="gallery-card__grid" aria-hidden="true">
        <span
          :for={cell <- @cells}
          class="gallery-card__cell"
          data-role="gallery-cell"
          style={"--cell-col: #{cell.col}; --cell-row: #{cell.row}; --cell-w: #{cell.w}; --cell-h: #{cell.h};"}
        ></span>
      </span>
      <strong class="gallery-card__title"><%= @title %></strong>
      <span class="gallery-card__sub"><%= Templates.subtitle(@template.key) %></span>
      <span class="gallery-card__widgets">
        <%= ngettext("%{count} widget", "%{count} widgets", length(@template.layout)) %> · <%= @names %>
      </span>
    </button>
    """
  end

  defp cell(%{"size" => size, "col" => col, "row" => row}) do
    case Widgets.dimensions(size) do
      {:ok, {w, h}} -> [%{col: col, row: row, w: w, h: h}]
      :error -> []
    end
  end

  attr(:picked, :any, required: true)
  attr(:name, :string, required: true)
  attr(:view_id, :any, required: true)
  attr(:views, :list, required: true)
  attr(:name_error, :string, default: nil)
  attr(:refused, :string, default: nil)

  # The dialog after the click (board 03 ②): the name and, for a template
  # that asks for one, the scope; „Abbrechen“ and „Anlegen“.
  defp create_dialog(assigns) do
    assigns =
      assign(assigns,
        heading: heading(assigns.picked),
        asks_scope: match?(%{asks_scope: true}, assigns.picked)
      )

    ~H"""
    <dialog
      id="new-dashboard-dialog"
      class="modal new-dashboard-dialog"
      phx-hook="ModalDialog"
      data-close-event="cancel_pick"
      aria-labelledby="new-dashboard-dialog-title"
    >
      <header class="modal-head">
        <h2 id="new-dashboard-dialog-title"><%= @heading %></h2>
        <button type="button" class="icon-button" aria-label={gettext("Close")} phx-click="cancel_pick">
          <AppShell.icon name={:x} />
        </button>
      </header>
      <form id="new-dashboard-form" class="new-dashboard__form" phx-submit="create">
        <div class="modal-body">
          <div role="status"><AppShell.data_note
              :if={@refused}
              severity={:problem}
              data-role="new-dashboard-refused"
            ><%= @refused %></AppShell.data_note></div>
          <label class="new-dashboard__name">
            <span><%= gettext("Name") %></span>
            <input
              type="text"
              name="dashboard[name]"
              value={@name}
              autocomplete="off"
              aria-invalid={@name_error && "true"}
              aria-describedby={@name_error && "new-dashboard-name-error"}
              autofocus
            />
          </label>
          <p :if={@name_error} id="new-dashboard-name-error" class="field-error" role="alert">
            <%= @name_error %>
          </p>
          <label :if={@asks_scope} class="new-dashboard__name">
            <span><%= gettext("View") %></span>
            <select name="dashboard[view_id]" data-role="new-dashboard-scope">
              <option value="" selected={is_nil(@view_id)}><%= gettext("None: follows the bar's view") %></option>
              <option :for={view <- @views} value={view.id} selected={view.id == @view_id}><%= view.name %></option>
            </select>
          </label>
          <p :if={@asks_scope} class="hint" data-role="new-dashboard-scope-hint">
            <%= gettext("The view holds for every widget of this dashboard that takes one; a single widget can still name its own in its ⋯ menu. Without one the dashboard follows the view in the bar.") %>
          </p>
        </div>
        <div class="modal-footer">
          <button
            type="button"
            class="button-ghost"
            phx-click="cancel_pick"
            data-role="new-dashboard-cancel"
          >
            <%= gettext("Cancel") %>
          </button>
          <button type="submit" class="button-primary"><%= gettext("Create") %></button>
        </div>
      </form>
    </dialog>
    """
  end

  defp heading(:empty), do: gettext("Empty dashboard")

  defp heading(template),
    do: gettext("Dashboard from “%{template}”", template: Templates.title(template.key))
end
