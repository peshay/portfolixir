defmodule PortfolixirWeb.Securities.RowContextMenu do
  @moduledoc """
  Stateless row context menu rendered into the securities list.

  The menu lists the per-security actions the user can run without leaving
  the master list. Click-away or `Escape` close it. CSS switches the layout
  between a floating popover on desktop and a bottom sheet on narrow
  viewports — the markup is identical.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.AppShell

  attr(:security, :map, required: true)
  attr(:has_transactions?, :boolean, default: false)

  def menu(assigns) do
    ~H"""
    <div
      class="row-context-menu"
      role="menu"
      aria-label={gettext("Security actions")}
      phx-click-away="close_row_menu"
      phx-window-keydown="close_row_menu"
      phx-key="Escape"
      id={"row-menu-#{@security.id}"}
      phx-hook="PositionedMenu"
      data-trigger={"row-kebab-#{@security.id}"}
    >
      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="edit"
        phx-value-id={@security.id}
      >
        <AppShell.icon name={:edit} />
        <span><%= gettext("Edit") %></span>
      </button>

      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="sync"
        phx-value-id={@security.id}
      >
        <AppShell.icon name={:refresh_cw} />
        <span><%= gettext("Sync prices") %></span>
      </button>

      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="open"
        phx-value-id={@security.id}
      >
        <AppShell.icon name={:chevron_right} />
        <span><%= gettext("Open detail") %></span>
      </button>

      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="copy_isin"
        phx-value-id={@security.id}
        disabled={is_nil(@security.isin) or @security.isin == ""}
      >
        <AppShell.icon name={:copy} />
        <span><%= gettext("Copy ISIN") %></span>
      </button>

      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="copy_ticker"
        phx-value-id={@security.id}
        disabled={is_nil(@security.ticker_symbol) or @security.ticker_symbol == ""}
      >
        <AppShell.icon name={:copy} />
        <span><%= gettext("Copy ticker") %></span>
      </button>

      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="update_logo"
        phx-value-id={@security.id}
      >
        <AppShell.icon name={:refresh_cw} />
        <span><%= gettext("Update logo") %></span>
      </button>

      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="manage_logo"
        phx-value-id={@security.id}
      >
        <AppShell.icon name={:image} />
        <span><%= gettext("Manage logo…") %></span>
      </button>

      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="retire"
        phx-value-id={@security.id}
      >
        <AppShell.icon name={:archive} />
        <span>
          <%= if @security.is_retired do %>
            <%= gettext("Reactivate") %>
          <% else %>
            <%= gettext("Retire") %>
          <% end %>
        </span>
      </button>

      <button
        type="button"
        class="row-context-menu__item row-context-menu__item--danger"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="delete"
        phx-value-id={@security.id}
        data-confirm={gettext("Delete this security? Its bookings block the deletion; its notes and logo do not survive it.")}
      >
        <AppShell.icon name={:trash} />
        <span><%= gettext("Delete") %></span>
      </button>
    </div>
    """
  end

  attr(:security, :map, required: true)

  def delete_blocked_dialog(assigns) do
    ~H"""
    <%!-- Native dialog (UX-DR9, issue 646): opened via showModal() by the
         ModalDialog hook; cancel (Esc) pushes the close event. --%>
    <dialog
      id="delete-blocked-dialog"
      class="modal confirm-delete-blocked"
      phx-hook="ModalDialog"
      data-close-event="close_delete_blocked"
      aria-labelledby="delete-blocked-title"
    >
        <header class="modal-head">
          <h2 id="delete-blocked-title"><%= gettext("Cannot delete") %></h2>
          <button
            type="button"
            class="icon-button"
            aria-label={gettext("Close")}
            phx-click="close_delete_blocked"
          >
            <AppShell.icon name={:x} />
          </button>
        </header>

        <div class="modal-body">
          <p>
            <%= gettext(
              "%{name} is referenced by existing transactions or quote history and cannot be deleted. Retire it instead to hide it from the active list while keeping the historical record intact.",
              name: @security.name
            ) %>
          </p>
        </div>

        <div class="modal-footer">
          <button type="button" class="button-ghost" phx-click="close_delete_blocked">
            <%= gettext("Cancel") %>
          </button>
          <button
            type="button"
            class="button-primary"
            phx-click="row_action"
            phx-value-action="retire"
            phx-value-id={@security.id}
          >
            <%= gettext("Retire instead") %>
          </button>
        </div>
    </dialog>
    """
  end
end
