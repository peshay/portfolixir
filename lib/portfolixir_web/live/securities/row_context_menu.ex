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
  alias PortfolixirWeb.PolicyRuleReferences
  alias PortfolixirWeb.ReferenceCounts
  alias PortfolixirWeb.StoredText

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

      <%!-- ADR-0046 §1 (#572): the benchmark flag — a reference series the
           Wealth page compares against; never offered for booking. --%>
      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="benchmark"
        phx-value-id={@security.id}
      >
        <AppShell.icon name={:compass} />
        <span>
          <%= if @security.is_benchmark do %>
            <%= gettext("Unmark benchmark") %>
          <% else %>
            <%= gettext("Mark as benchmark") %>
          <% end %>
        </span>
      </button>

      <%!-- ADR-0050 §9 (board 03, G3-A): merge a duplicate into another
           security. Not danger-coloured: it opens a preview, and only the
           preview's confirm writes. --%>
      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        data-role="menu-merge"
        phx-click="row_action"
        phx-value-action="merge"
        phx-value-id={@security.id}
      >
        <AppShell.icon name={:merge} />
        <span><%= gettext("Merge into…") %></span>
      </button>

      <button
        type="button"
        class="row-context-menu__item row-context-menu__item--danger"
        role="menuitem"
        phx-click="row_action"
        phx-value-action="delete"
        phx-value-id={@security.id}
        data-confirm={
          gettext(
            "Delete this security? Bookings, quotes, events, research entries and policy rules block the deletion. Removed with it: its classifications, position targets, bucket assignments and former ISINs, each recorded in the journal, and its logo."
          )
        }
      >
        <AppShell.icon name={:trash} />
        <span><%= gettext("Delete") %></span>
      </button>
    </div>
    """
  end

  attr(:security, :map, required: true)
  # ADR-0049 §8: the policy rules that read the security, when they are what
  # blocks the delete; empty for a booking or a quote. References
  # (`PortfolixirWeb.PolicyRuleReferences`), so each name links to Risk in the
  # view the rule applies in (#871, G6-A).
  attr(:rules, :list, default: [])
  # ADR-0050 §9 (board 03, second entry): where bookings or quotes block the
  # delete and a merge could carry them, "Merge into…" is the way out beside
  # "Retire instead"; where a rule or a research entry holds the security,
  # a merge would be refused as well, and the dialog stays as it is.
  attr(:merge?, :boolean, default: false)
  # #918, pick H8.2 = A (board 08-dialogs-copy): what blocks the delete,
  # counted per referencing table from the refusal ({:referenced, counts});
  # nil when the refusal carried no count.
  attr(:counts, :map, default: nil)

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
          <%= cond do %>
            <% @rules == [] and is_map(@counts) and map_size(@counts) > 0 -> %>
              <p><%= blocked_by(@security, @counts) %></p>
              <p class="muted"><%= blocked_remedy(@counts, @merge?) %></p>
            <% @rules == [] -> %>
              <p>
                <%= StoredText.isolate(
                  gettext(
                    "“%{name}” has bookings, quotes, events or research entries and cannot be deleted. Retiring hides the security from the active list; everything is kept.",
                    name: StoredText.slot(:name)
                  ),
                  name: @security.name
                ) %>
              </p>
            <% true -> %>
              <p>
                <%= StoredText.isolate(
                  gettext("%{name} is read by policy rules:", name: StoredText.slot(:name)),
                  name: @security.name
                ) %>
              </p>
            <ul>
              <li :for={reference <- @rules}><PolicyRuleReferences.rule reference={reference} /></li>
            </ul>
            <p class="muted">
              <%= gettext(
                "A rule that has been in force keeps its subject as part of its history. Retiring the security hides it from the active list and keeps both."
              ) %>
            </p>
          <% end %>
        </div>

        <div class="modal-footer">
          <button type="button" class="button-ghost" phx-click="close_delete_blocked">
            <%= gettext("Cancel") %>
          </button>
          <button
            :if={@merge?}
            type="button"
            class="button-ghost"
            data-role="delete-blocked-merge"
            phx-click="row_action"
            phx-value-action="merge"
            phx-value-id={@security.id}
          >
            <%= gettext("Merge into…") %>
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

  # #918, pick H8.2 = A: "“Nordwind Industrie AG” still has 12 bookings,
  # 840 quotes and 3 research entries." — the refusal's own counts, the
  # accounts page's "still has" (`blocked_sentence/1`) as the precedent.
  defp blocked_by(security, counts) do
    StoredText.isolate(
      gettext("“%{name}” still has %{references}.",
        name: StoredText.slot(:name),
        references: counts |> ReferenceCounts.parts() |> ReferenceCounts.and_list()
      ),
      name: security.name
    )
  end

  # The reason for the way out (`Delete.remedy/2`): research entries never
  # go and no merge carries them, so retire; a rule version neither; what a
  # merge carries — bookings, quotes, events — offers the merge first.
  defp blocked_remedy(%{"security_notes" => n}, _merge?) when n > 0 do
    gettext(
      "Research entries are never removed, and no merge carries them. Retiring hides the security from the active list; everything is kept."
    )
  end

  defp blocked_remedy(_counts, true) do
    gettext(
      "If it is a duplicate, “Merge into…” moves its bookings, quotes and events into the other security. Retiring hides it from the active list; everything is kept."
    )
  end

  defp blocked_remedy(_counts, false) do
    gettext(
      "A rule version keeps the security as part of its rule's history, and no merge carries it. Retiring hides the security from the active list; everything is kept."
    )
  end
end
