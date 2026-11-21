defmodule PortfolixirWeb.NewDashboardLive do
  @moduledoc """
  „Neues Dashboard“ (ADR-0062 §2, §3; ADR-0022's amendment of 2026-11-21;
  Sprint 31 D7; planning board `ux-design-2026-11-21-sprint31/01` ③), at
  `/dashboards/new`, the last entry of the menu's „Dashboards“ group.

  A name and one of two starts: **„Leer beginnen“**, an empty layout, or
  **„Aus Vorlage“**, a copy of the template „Überblick“ (the only template
  this release offers; the others come with their widgets, ADR-0062 §3).
  „Anlegen“ stores it under the UI's actor as one journaled create
  (`Dashboards.create_dashboard/2`, `Dashboards.copy_template/3`) and opens
  it. An empty dashboard says so and links „Alle Widgets“ until the edit
  mode opens the catalogue itself (D6). A refused name is said at the
  field; the 51st dashboard is refused with the reason.
  """
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Templates
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.FieldLabel

  @starts ~w(empty template)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, name: "", start: "empty", name_error: nil, refused: nil)}
  end

  @impl true
  def handle_event("create", %{"dashboard" => params}, socket) when is_map(params) do
    name = if is_binary(params["name"]), do: params["name"], else: ""
    start = if params["start"] in @starts, do: params["start"], else: "empty"
    socket = assign(socket, name: name, start: start, name_error: nil, refused: nil)

    case create(start, name) do
      {:ok, dashboard} ->
        {:noreply, push_navigate(socket, to: "/dashboards/#{dashboard.id}")}

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

  defp create("template", name),
    do: Dashboards.copy_template(Actor.owner_ui(), template().key, %{"name" => name})

  defp create(_empty, name),
    do: Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name, "layout" => []})

  defp template, do: hd(Dashboards.templates())

  # The name's refusals, in the page's language; any other field's (none
  # a name and an empty layout or a template's can raise) as the page's.
  defp name_error(changeset) do
    case Keyword.get_values(changeset.errors, :name) do
      [] -> FieldLabel.changeset_message(changeset)
      errors -> Enum.map_join(errors, ", ", &FieldLabel.translate_error/1)
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :template_title, Templates.title(template().key))

    ~H"""
    <AppShell.shell page_address={@page_address}
      current_path="/dashboards/new"
      page_title={gettext("New dashboard")}
      page_subtitle={gettext("Start empty or from a template")}
    >
      <div id="new-dashboard-workspace" class="workspace-page">
        <section class="workspace-section new-dashboard">
          <div role="status"><AppShell.data_note
              :if={@refused}
              severity={:problem}
              data-role="new-dashboard-refused"
            ><%= @refused %></AppShell.data_note></div>
          <form id="new-dashboard-form" class="new-dashboard__form" phx-submit="create">
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
            <fieldset class="new-dashboard__starts">
              <legend class="visually-hidden"><%= gettext("Start") %></legend>
              <label class="new-dashboard__start">
                <input type="radio" name="dashboard[start]" value="empty" checked={@start == "empty"} />
                <span class="new-dashboard__start-title"><%= gettext("Start empty") %></span>
                <span class="new-dashboard__start-sub">
                  <%= gettext("an empty dashboard; add widgets from All widgets") %>
                </span>
              </label>
              <label class="new-dashboard__start">
                <input
                  type="radio"
                  name="dashboard[start]"
                  value="template"
                  checked={@start == "template"}
                />
                <span class="new-dashboard__start-title"><%= gettext("From a template") %></span>
                <span class="new-dashboard__start-sub">
                  <%= gettext("%{template} · more templates come with their widgets",
                    template: @template_title
                  ) %>
                </span>
              </label>
            </fieldset>
            <div>
              <button type="submit" class="button-primary"><%= gettext("Create") %></button>
            </div>
          </form>
        </section>
      </div>
    </AppShell.shell>
    """
  end
end
