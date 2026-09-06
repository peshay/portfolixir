defmodule PortfolixirWeb.Securities.LogoOverrideDialog do
  @moduledoc """
  Stateless dialog for managing a single security's logo: set a manual logo
  from an image URL, remove it (lock "no logo"), or trigger automatic
  re-discovery. Submits to the parent LiveView's events.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog
  alias PortfolixirWeb.AppShell

  attr(:security, :map, required: true)

  def dialog(assigns) do
    assigns = assign(assigns, :status, Catalog.logo_status(assigns.security))

    ~H"""
    <%!-- Native dialog (UX-DR9, issue 646): opened via showModal() by the
         ModalDialog hook; cancel (Esc) pushes the close event. --%>
    <dialog
      id="logo-override-dialog"
      class="modal logo-override"
      phx-hook="ModalDialog"
      data-close-event="close_logo_dialog"
      aria-labelledby="logo-override-title"
    >
        <header class="modal-head">
          <h2 id="logo-override-title"><%= gettext("Manage logo") %></h2>
          <button
            type="button"
            class="icon-button"
            aria-label={gettext("Close")}
            phx-click="close_logo_dialog"
          >
            <AppShell.icon name={:x} />
          </button>
        </header>

        <div class="modal-body">
          <p class="detail-pane-sub"><%= @security.name %></p>

          <p>
            <%= cond do %>
              <% @status.locked and @status.has_logo -> %>
                <%= gettext("A manual logo is set (discovery will not overwrite it).") %>
              <% @status.locked -> %>
                <%= gettext("This security is set to have no logo.") %>
              <% @status.has_logo -> %>
                <%= gettext("Current logo source: %{source}", source: @status.source || "—") %>
              <% true -> %>
                <%= gettext("No logo found yet.") %>
            <% end %>
          </p>

          <form phx-submit="save_logo_url" class="logo-override__form">
            <label for="logo-override-url"><%= gettext("Image URL") %></label>
            <input
              type="url"
              id="logo-override-url"
              name="logo[url]"
              placeholder="https://…"
              value={if @status.source == "manual", do: @status.path, else: ""}
            />
            <button type="submit" class="button-primary"><%= gettext("Save URL") %></button>
          </form>
        </div>

        <div class="modal-footer">
          <button
            type="button"
            class="button-ghost"
            phx-click="row_action"
            phx-value-action="update_logo"
            phx-value-id={@security.id}
          >
            <%= gettext("Search again") %>
          </button>
          <button
            type="button"
            class="button-ghost"
            phx-click="remove_logo_override"
            phx-value-id={@security.id}
            disabled={not @status.has_logo and @status.locked}
            data-confirm={gettext("Remove the logo and keep the security without one?")}
          >
            <%= gettext("Remove logo") %>
          </button>
        </div>
    </dialog>
    """
  end
end
