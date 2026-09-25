defmodule PortfolixirWeb.BucketsLive do
  @moduledoc """
  Views management (issue #446; renamed from "Buckets & views" per ADR-0024
  modification 6 — the sidebar entry is about views, while bucket CRUD is
  additionally reachable from the chips on the Accounts & depots rows).

  One workspace for the tag-based wealth-scoping model (ADR-0018), read-first
  since issue 802 (UX-DR1: the list is the surface, `+` opens the form):

  - **Views** — global include/exclude filters over buckets. Each row says
    what the view does (its rule as chips) and what it covers (the scoped
    total, positions and accounts); the built-in "Everything" row is marked
    as the default. Create, rename, delete, and edit each view's
    `include_all` toggle plus its include/exclude bucket sets via the unified
    checkbox picker (a modal).
  - **Buckets** — overlapping tags. Each row carries its colour and where it
    is used: the accounts it is the default on, the positions inheriting it,
    the positions tagged directly. Create, rename, delete.

  Default buckets are set on the account row of Accounts & depots (ADR-0024:
  buckets are attributes of account rows); the buckets section's basis line
  points there. Per-position overrides live on the security holdings surface.
  Every write goes through the `Portfolixir.Buckets` context with the
  interactive owner actor (`Portfolixir.Actor.owner_ui/0`); the web layer
  never touches the Repo.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.PricingContext
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.Settings
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.PolicyRuleReferences

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> assign(:editing_bucket_id, nil)
     |> assign(:editing_view_id, nil)
     |> assign(:bucket_picker_view, nil)
     |> assign(:view_form_open?, false)
     |> assign(:bucket_form_open?, false)
     |> assign(:row_menu, nil)
     |> load_state()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/buckets"
      page_title={gettext("Views")}
      page_subtitle={gettext("Saved filters that scope the analytics, built from bucket tags")}
    >
      <div id="buckets-workspace" class="workspace-page">
        <%= if @error do %>
          <p class="alert-error" role="alert"><PolicyRuleReferences.message message={@error} /></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <section id="views-section" class="workspace-section">
          <header class="section-head">
            <h2>
              <%= gettext("Views") %>
              <%!-- The two-step explanation behind the heading's ⓘ (UX-DR11
                   triage of the former how-it-works block, issue 802). --%>
              <details class="metric-tooltip metric-tooltip--inline" data-role="views-info">
                <summary aria-label={gettext("About views")}>ⓘ</summary>
                <p role="tooltip">
                  <%= gettext(
                    "Two steps: 1. Create buckets — tags on depots, cash accounts and positions. 2. Create a view — a saved include/exclude filter over buckets; exclude always wins. A view is what the view switcher on the Wealth page offers, so both are needed."
                  ) %>
                </p>
              </details>
            </h2>
            <div class="section-head-controls">
              <p class="summary-basis" data-role="views-basis">
                <%= gettext("Saved include/exclude filters over buckets · applied in the view switcher on Wealth") %>
              </p>
              <button
                type="button"
                class="button-primary"
                phx-click="toggle_form"
                phx-value-form="view"
                aria-expanded={to_string(@view_form_open?)}
                aria-controls="view-form-panel"
              >
                + <%= gettext("View") %>
              </button>
            </div>
          </header>

          <div id="view-form-panel" class="disclosure-panel" hidden={not @view_form_open?}>
            <form id="view-form" phx-submit="create_view" class="inline-form">
              <label>
                <span><%= gettext("New view") %></span>
                <input name="view[name]" required autocomplete="off" />
              </label>
              <button type="submit"><%= gettext("Add view") %></button>
            </form>
          </div>

          <ul id="view-list" class="bucket-list" role="list">
            <%!-- The built-in scope as a row of its own: what "no view" covers. --%>
            <li id="view-everything" class="bucket-list__item" data-role="view-row">
              <div class="bucket-list__main">
                <span class="bucket-list__name">
                  <%= gettext("Everything") %>
                  <span :if={is_nil(@default_view_id)} class="badge" data-role="view-default">
                    <%= gettext("Default") %>
                  </span>
                </span>
                <span class="bucket-list__rule" data-role="view-rule">
                  <%= gettext("All depots, cash accounts and positions · no filters") %>
                </span>
              </div>
              <.view_figures figures={@everything} />
            </li>

            <%= for row <- @view_rows do %>
              <li
                id={"view-#{row.id}"}
                class={["bucket-list__item", @editing_view_id == row.id && "is-editing"]}
                data-role="view-row"
              >
                <%= if @editing_view_id == row.id do %>
                  <form phx-submit="rename_view" class="inline-form bucket-edit-form">
                    <input type="hidden" name="view_id" value={row.id} />
                    <input
                      name="view[name]"
                      value={row.name}
                      aria-label={gettext("View name")}
                      required
                    />
                    <button type="submit" class="button"><%= gettext("Save") %></button>
                    <button type="button" phx-click="cancel_edit_view">
                      <%= gettext("Cancel") %>
                    </button>
                  </form>
                <% else %>
                  <div class="bucket-list__main">
                    <span class="bucket-list__name">
                      <%= row.name %>
                      <span :if={@default_view_id == row.id} class="badge" data-role="view-default">
                        <%= gettext("Default") %>
                      </span>
                      <%!-- Matches-nothing hint (fix round): the view's resolution
                           matches zero accounts, so every figure under it is a
                           silent 0 — say so where the view is edited. --%>
                      <span
                        :if={row.matches_nothing?}
                        class="hint"
                        data-role="view-matches-nothing"
                      >
                        <%= gettext("matches no accounts") %>
                      </span>
                    </span>
                    <span class="bucket-list__rule" data-role="view-rule">
                      <.view_rule rule={row.rule} />
                    </span>
                  </div>
                  <.view_figures figures={row.figures} />
                  <AppShell.row_kebab
                    id={"view-kebab-#{row.id}"}
                    row={row.name}
                    open={@row_menu == {:view, row.id}}
                    phx-click="open_row_menu"
                    phx-value-kind="view"
                    phx-value-id={row.id}
                  />
                <% end %>
              </li>
            <% end %>
          </ul>
          <p :if={@view_rows == []} class="hint"><%= gettext("No views yet.") %></p>
        </section>

        <section id="buckets-section" class="workspace-section">
          <header class="section-head">
            <h2>
              <%= gettext("Buckets") %>
              <details class="metric-tooltip metric-tooltip--inline" data-role="buckets-info">
                <summary aria-label={gettext("About buckets")}>ⓘ</summary>
                <p role="tooltip" data-role="overlap-hint">
                  <%= gettext(
                    "Buckets are overlapping tags, not a partition: a holding can carry several buckets at once. Per-bucket figures may overlap and must never be read as a sum."
                  ) %>
                </p>
              </details>
            </h2>
            <div class="section-head-controls">
              <p class="summary-basis" data-role="buckets-basis">
                <%= gettext("Overlapping tags on depots, cash accounts and positions · per-bucket figures are not a sum") %>
              </p>
              <button
                type="button"
                class="button-ghost"
                phx-click="toggle_form"
                phx-value-form="bucket"
                aria-expanded={to_string(@bucket_form_open?)}
                aria-controls="bucket-form-panel"
              >
                + <%= gettext("Bucket") %>
              </button>
            </div>
          </header>

          <div id="bucket-form-panel" class="disclosure-panel" hidden={not @bucket_form_open?}>
            <form id="bucket-form" phx-submit="create_bucket" class="inline-form">
              <label>
                <span><%= gettext("New bucket") %></span>
                <input name="bucket[name]" required autocomplete="off" />
              </label>
              <label>
                <span><%= gettext("Color") %> <small>(<%= gettext("optional") %>)</small></span>
                <input type="color" name="bucket[color]" value="#7c3aed" />
              </label>
              <button type="submit"><%= gettext("Add bucket") %></button>
            </form>
          </div>

          <ul id="bucket-list" class="bucket-list" role="list">
            <%= for bucket <- @buckets do %>
              <li
                id={"bucket-#{bucket.id}"}
                class={["bucket-list__item", @editing_bucket_id == bucket.id && "is-editing"]}
                data-role="bucket-row"
              >
                <%= if @editing_bucket_id == bucket.id do %>
                  <form phx-submit="rename_bucket" class="inline-form bucket-edit-form">
                    <input type="hidden" name="bucket_id" value={bucket.id} />
                    <input
                      name="bucket[name]"
                      value={bucket.name}
                      aria-label={gettext("Bucket name")}
                      required
                    />
                    <input
                      type="color"
                      name="bucket[color]"
                      value={bucket.color || "#7c3aed"}
                      class="color-mini"
                      aria-label={gettext("Color")}
                    />
                    <button type="submit" class="button"><%= gettext("Save") %></button>
                    <button type="button" phx-click="cancel_edit_bucket">
                      <%= gettext("Cancel") %>
                    </button>
                  </form>
                <% else %>
                  <div class="bucket-list__main">
                    <span class="bucket-list__name">
                      <span
                        :if={bucket.color}
                        class="cat-swatch"
                        style={"background:#{bucket.color}"}
                        aria-hidden="true"
                      >
                      </span>
                      <%= bucket.name %>
                    </span>
                    <span class="bucket-list__usage" data-role="bucket-usage">
                      <.bucket_usage usage={Map.fetch!(@bucket_usage, bucket.id)} />
                    </span>
                  </div>
                  <AppShell.row_kebab
                    id={"bucket-kebab-#{bucket.id}"}
                    row={bucket.name}
                    open={@row_menu == {:bucket, bucket.id}}
                    phx-click="open_row_menu"
                    phx-value-kind="bucket"
                    phx-value-id={bucket.id}
                  />
                <% end %>
              </li>
            <% end %>
          </ul>
          <p :if={@buckets == []} class="hint"><%= gettext("No buckets yet.") %></p>

          <%!-- The former assignment section is the usage line above; the
               edit path is the account row (ADR-0024), named here. --%>
          <p class="summary-basis" data-role="assignment-basis">
            <%= gettext("Default buckets are set on the account row →") %>
            <.link navigate="/portfolios"><%= gettext("Accounts & depots") %></.link>.
            <span :if={@unassigned_accounts != []}>
              <%= ngettext(
                "%{names} has no default bucket.",
                "%{names} have no default bucket.",
                length(@unassigned_accounts),
                names: Enum.join(@unassigned_accounts, ", ")
              ) %>
            </span>
          </p>
        </section>

        <%= if @bucket_picker_view do %>
          <.view_bucket_modal
            view={@bucket_picker_view}
            buckets={@buckets}
            include_all={@picker_include_all}
            include={@picker_include}
            exclude={@picker_exclude}
          />
        <% end %>
      </div>

      <.row_menu :if={@row_menu} menu={@row_menu} />
    </AppShell.shell>
    """
  end

  # -- components --------------------------------------------------------------

  # What a view covers: the scoped total, positions and accounts (one
  # valuation per view, sub-second — the figures the Wealth page shows under
  # that view). `nil` when the view vanished between the list and the read.
  attr(:figures, :any, required: true)

  defp view_figures(%{figures: nil} = assigns) do
    ~H"""
    <span class="bucket-list__figures" data-role="view-figures">—</span>
    """
  end

  defp view_figures(assigns) do
    ~H"""
    <span class="bucket-list__figures" data-role="view-figures">
      <strong><%= Format.money(@figures.total) %> <%= @figures.currency %></strong>
      · <%= ngettext("%{count} position", "%{count} positions", @figures.positions) %>
      · <%= ngettext("%{count} account", "%{count} accounts", @figures.accounts) %>
    </span>
    """
  end

  # The rule as chips: "Everything" or "Only <buckets>", then "except <buckets>".
  attr(:rule, :map, required: true)

  defp view_rule(assigns) do
    ~H"""
    <%= if @rule.include == :all do %>
      <%= if @rule.exclude == [] do %>
        <%= gettext("All depots, cash accounts and positions · no filters") %>
      <% else %>
        <%= gettext("Everything") %>
      <% end %>
    <% else %>
      <%= gettext("Only") %>
      <span :for={name <- @rule.include} class="badge"><%= name %></span>
      <span :if={@rule.include == []} class="hint"><%= gettext("nothing included") %></span>
    <% end %>
    <%= if @rule.exclude != [] do %>
      · <%= gettext("except") %>
      <span :for={name <- @rule.exclude} class="badge"><%= name %></span>
    <% end %>
    """
  end

  # Where a bucket is used: the accounts it is the default on with the
  # positions inheriting it, the positions tagged directly, or "unused".
  attr(:usage, :map, required: true)

  defp bucket_usage(assigns) do
    ~H"""
    <%= if @usage.default_on == [] and @usage.direct == [] do %>
      <%= gettext("unused") %>
    <% else %>
      <%= if @usage.default_on != [] do %>
        <%= gettext("Default on") %>
        <strong><%= Enum.join(@usage.default_on, ", ") %></strong>
        <%= if @usage.inherits > 0 do %>
          · <%= ngettext("%{count} position inherits", "%{count} positions inherit", @usage.inherits) %>
        <% end %>
      <% end %>
      <%= if @usage.direct != [] do %>
        <%= if @usage.default_on != [], do: "·" %>
        <%= ngettext("%{count} position directly:", "%{count} positions directly:", length(@usage.direct)) %>
        <strong><%= Enum.join(@usage.direct, ", ") %></strong>
      <% end %>
      <%= if @usage.default_on == [] do %>
        · <%= gettext("no default") %>
      <% end %>
    <% end %>
    """
  end

  attr(:view, :any, required: true)
  attr(:buckets, :list, required: true)
  attr(:include_all, :boolean, required: true)
  attr(:include, :list, required: true)
  attr(:exclude, :list, required: true)

  defp view_bucket_modal(assigns) do
    ~H"""
    <%!-- Native dialog (UX-DR9, issue 646): opened via showModal() by the
         ModalDialog hook; cancel (Esc) pushes the close event. --%>
    <dialog
      id="view-bucket-modal"
      class="modal"
      phx-hook="ModalDialog"
      data-close-event="close_bucket_picker"
      aria-labelledby="view-bucket-modal-title"
    >
      <header class="modal-head">
        <h2 id="view-bucket-modal-title">
          <%= gettext("Buckets for %{name}", name: @view.name) %>
        </h2>
        <button
          type="button"
          class="icon-button"
          aria-label={gettext("Close")}
          phx-click="close_bucket_picker"
          autofocus
        >
          <AppShell.icon name={:x} />
        </button>
      </header>

      <div class="modal-body">
        <form id="view-bucket-form" phx-submit="save_view_buckets" phx-change="toggle_include_all">
          <input type="hidden" name="view_id" value={@view.id} />

          <label class="bucket-checkbox">
            <input type="hidden" name="include_all" value="false" />
            <input type="checkbox" name="include_all" value="true" checked={@include_all} />
            <span><%= gettext("Include all buckets") %></span>
          </label>

          <%= if not @include_all do %>
            <fieldset class="bucket-fieldset">
              <legend><%= gettext("Include buckets") %></legend>
              <%= for bucket <- @buckets do %>
                <label class="bucket-checkbox" for={"view-include-#{bucket.id}"}>
                  <input
                    type="checkbox"
                    id={"view-include-#{bucket.id}"}
                    name="include[]"
                    value={bucket.id}
                    checked={bucket.id in @include}
                  />
                  <span><%= bucket.name %></span>
                </label>
              <% end %>
            </fieldset>
          <% end %>

          <fieldset class="bucket-fieldset">
            <legend><%= gettext("Exclude buckets") %> <small><%= gettext("(exclude wins)") %></small></legend>
            <%= for bucket <- @buckets do %>
              <label class="bucket-checkbox" for={"view-exclude-#{bucket.id}"}>
                <input
                  type="checkbox"
                  id={"view-exclude-#{bucket.id}"}
                  name="exclude[]"
                  value={bucket.id}
                  checked={bucket.id in @exclude}
                />
                <span><%= bucket.name %></span>
              </label>
            <% end %>
          </fieldset>

          <div class="modal-footer">
            <button type="button" phx-click="close_bucket_picker"><%= gettext("Cancel") %></button>
            <button type="submit" class="button-primary"><%= gettext("Save view") %></button>
          </div>
        </form>
      </div>
    </dialog>
    """
  end

  # The row menu (Part 4 rule 11 of the 2026-09-12 review): a view's bucket
  # editing, rename and delete; a bucket's rename and delete.
  attr(:menu, :any, required: true)

  defp row_menu(%{menu: {:view, id}} = assigns) do
    assigns = assign(assigns, :id, id)

    ~H"""
    <AppShell.row_menu
      id={"view-row-menu-#{@id}"}
      trigger={"view-kebab-#{@id}"}
      label={gettext("View actions")}
    >
      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="edit_view_buckets"
        phx-value-id={@id}
      >
        <AppShell.icon name={:filter} />
        <span><%= gettext("Edit buckets") %></span>
      </button>
      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="edit_view"
        phx-value-id={@id}
      >
        <AppShell.icon name={:edit} />
        <span><%= gettext("Rename") %></span>
      </button>
      <button
        type="button"
        class="row-context-menu__item row-context-menu__item--danger"
        role="menuitem"
        phx-click="delete_view"
        phx-value-id={@id}
        data-confirm={gettext("Delete this view?")}
      >
        <AppShell.icon name={:trash} />
        <span><%= gettext("Delete") %></span>
      </button>
    </AppShell.row_menu>
    """
  end

  defp row_menu(%{menu: {:bucket, id}} = assigns) do
    assigns = assign(assigns, :id, id)

    ~H"""
    <AppShell.row_menu
      id={"bucket-row-menu-#{@id}"}
      trigger={"bucket-kebab-#{@id}"}
      label={gettext("Bucket actions")}
    >
      <button
        type="button"
        class="row-context-menu__item"
        role="menuitem"
        phx-click="edit_bucket"
        phx-value-id={@id}
      >
        <AppShell.icon name={:edit} />
        <span><%= gettext("Rename") %></span>
      </button>
      <button
        type="button"
        class="row-context-menu__item row-context-menu__item--danger"
        role="menuitem"
        phx-click="delete_bucket"
        phx-value-id={@id}
        data-confirm={
          gettext(
            "Delete this bucket? It is removed from every assignment and view. A position whose only specific bucket is this one stays at “no buckets (excluded)” and does not inherit from its depot."
          )
        }
      >
        <AppShell.icon name={:trash} />
        <span><%= gettext("Delete") %></span>
      </button>
    </AppShell.row_menu>
    """
  end

  # -- disclosure and row-menu events -------------------------------------------

  @impl true
  def handle_event("toggle_form", %{"form" => "view"}, socket) do
    {:noreply, assign(socket, :view_form_open?, not socket.assigns.view_form_open?)}
  end

  def handle_event("toggle_form", %{"form" => "bucket"}, socket) do
    {:noreply, assign(socket, :bucket_form_open?, not socket.assigns.bucket_form_open?)}
  end

  def handle_event("open_row_menu", %{"kind" => kind, "id" => id}, socket) do
    menu =
      case {kind, LiveParam.fetch_id(id)} do
        {"view", {:ok, view_id}} ->
          if Enum.any?(socket.assigns.view_rows, &(&1.id == view_id)), do: {:view, view_id}

        {"bucket", {:ok, bucket_id}} ->
          if Enum.any?(socket.assigns.buckets, &(&1.id == bucket_id)), do: {:bucket, bucket_id}

        _other ->
          nil
      end

    {:noreply, assign(socket, :row_menu, menu)}
  end

  def handle_event("close_row_menu", _params, socket) do
    {:noreply, assign(socket, :row_menu, nil)}
  end

  # -- bucket events ----------------------------------------------------------

  def handle_event("create_bucket", %{"bucket" => params}, socket) do
    case Buckets.create_bucket(Actor.owner_ui(), normalize_color(LiveParam.map(params))) do
      {:ok, _bucket} ->
        {:noreply,
         socket
         |> assign(:bucket_form_open?, false)
         |> success(gettext("Bucket created"))
         |> load_state()}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event("edit_bucket", %{"id" => id}, socket) do
    case LiveParam.fetch_id(id) do
      {:ok, bucket_id} -> {:noreply, assign(socket, editing_bucket_id: bucket_id, row_menu: nil)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_bucket", _params, socket) do
    {:noreply, assign(socket, :editing_bucket_id, nil)}
  end

  def handle_event("rename_bucket", %{"bucket_id" => id, "bucket" => params}, socket) do
    with {:ok, bucket_id} <- LiveParam.fetch_id(id),
         bucket when not is_nil(bucket) <- Buckets.get_bucket(bucket_id),
         {:ok, _} <-
           Buckets.update_bucket(Actor.owner_ui(), bucket, normalize_color(LiveParam.map(params))) do
      {:noreply,
       socket
       |> assign(:editing_bucket_id, nil)
       |> success(gettext("Bucket updated"))
       |> load_state()}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_bucket", %{"id" => id}, socket) do
    socket = assign(socket, :row_menu, nil)

    with {:ok, bucket_id} <- LiveParam.fetch_id(id),
         {:ok, bucket} <- bucket_to_delete(bucket_id),
         {:ok, _} <- Buckets.delete_bucket(Actor.owner_ui(), bucket) do
      {:noreply, socket |> success(gettext("Bucket deleted")) |> load_state()}
    else
      # E25 S6 review round (G19): a delete that does not happen says why.
      {:error, :not_found} ->
        {:noreply,
         socket
         |> failure(gettext("That bucket no longer exists. Refresh and try again."))
         |> load_state()}

      {:error, _reason} ->
        {:noreply,
         failure(socket, gettext("The bucket could not be deleted. Nothing was changed."))}

      _unreadable_id ->
        {:noreply, socket}
    end
  end

  # -- view events ------------------------------------------------------------

  def handle_event("create_view", %{"view" => params}, socket) do
    case Buckets.create_view(Actor.owner_ui(), LiveParam.map(params)) do
      {:ok, _view} ->
        {:noreply,
         socket
         |> assign(:view_form_open?, false)
         |> success(gettext("View created"))
         |> load_state()}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event("edit_view", %{"id" => id}, socket) do
    case LiveParam.fetch_id(id) do
      {:ok, view_id} -> {:noreply, assign(socket, editing_view_id: view_id, row_menu: nil)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_view", _params, socket) do
    {:noreply, assign(socket, :editing_view_id, nil)}
  end

  def handle_event("rename_view", %{"view_id" => id, "view" => params}, socket) do
    with {:ok, view_id} <- LiveParam.fetch_id(id),
         view when not is_nil(view) <- Buckets.get_view(view_id),
         {:ok, _} <- Buckets.update_view(Actor.owner_ui(), view, LiveParam.map(params)) do
      {:noreply,
       socket
       |> assign(:editing_view_id, nil)
       |> success(gettext("View updated"))
       |> load_state()}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_view", %{"id" => id}, socket) do
    socket = assign(socket, :row_menu, nil)

    with {:ok, view_id} <- LiveParam.fetch_id(id),
         view when not is_nil(view) <- Buckets.get_view(view_id),
         {:ok, _} <- Buckets.delete_view(Actor.owner_ui(), view) do
      {:noreply, socket |> success(gettext("View deleted")) |> load_state()}
    else
      # ADR-0049 §8: a view a rule reads is refused by name, where the delete
      # used to fail with no message at all (board 06-rule-reference-409);
      # each name links to Risk in the view the rule applies in (#871, G6-A).
      {:error, {:policy_rules, rules}} ->
        {:noreply, failure(socket, PolicyRuleReferences.refusal(rules))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_view_buckets", %{"id" => id}, socket) do
    socket = assign(socket, :row_menu, nil)

    with {:ok, view_id} <- LiveParam.fetch_id(id),
         view when not is_nil(view) <- Buckets.get_view(view_id),
         {:ok, filter} <- Buckets.view_filter(view_id) do
      include = if filter.include == :all, do: [], else: filter.include

      {:noreply,
       socket
       |> assign(:bucket_picker_view, view)
       |> assign(:picker_include_all, view.include_all)
       |> assign(:picker_include, include)
       |> assign(:picker_exclude, filter.exclude)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_bucket_picker", _params, socket) do
    {:noreply, assign(socket, :bucket_picker_view, nil)}
  end

  # Live preview of the include-all toggle inside the modal, so the include
  # checklist appears/disappears as the user flips it before saving.
  def handle_event("toggle_include_all", params, socket) do
    include_all? = params["include_all"] == "true"

    {:noreply,
     socket
     |> assign(:picker_include_all, include_all?)
     |> assign(:picker_include, LiveParam.ids(params["include"]))
     |> assign(:picker_exclude, LiveParam.ids(params["exclude"]))}
  end

  def handle_event("save_view_buckets", params, socket) do
    with {:ok, view_id} <- LiveParam.fetch_id(params["view_id"]),
         view when not is_nil(view) <- Buckets.get_view(view_id),
         include_all? <- params["include_all"] == "true",
         include <- LiveParam.ids(params["include"]),
         exclude <- LiveParam.ids(params["exclude"]),
         {:ok, _} <- Buckets.update_view(Actor.owner_ui(), view, %{include_all: include_all?}),
         :ok <-
           Buckets.set_view_buckets(
             Actor.owner_ui(),
             view,
             if(include_all?, do: [], else: include),
             exclude
           ) do
      {:noreply,
       socket
       |> assign(:bucket_picker_view, nil)
       |> success(gettext("View buckets saved"))
       |> load_state()}
    else
      {:error, :bucket_ids} ->
        {:noreply,
         failure(socket, gettext("That bucket no longer exists. Refresh and try again."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}

      _ ->
        {:noreply, socket}
    end
  end

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # -- data loading -----------------------------------------------------------

  # ADR-0024: every depot and cash account is managed here, regardless of the
  # internal portfolio compatibility record it happens to be bound to. The
  # rows' figures are the view-scoped valuations the Wealth page shows under
  # each view (one pricing pass shared across them, ADR-0035); the usage lines
  # are composed from the instance-wide assignment maps the scope resolution
  # itself reads.
  defp load_state(socket) do
    buckets = Buckets.list_buckets()
    views_full = Buckets.list_views()
    depots = Portfolios.list_securities_accounts()
    cash_accounts = Portfolios.list_cash_accounts()
    assignments = Buckets.global_assignments()
    context = PricingContext.for_all_portfolios()
    everything = Valuation.for_view(nil, pricing_context: context)

    assign(socket,
      buckets: buckets,
      views_full: views_full,
      view_rows: Enum.map(views_full, &view_row(&1, buckets, context)),
      everything: figures(everything),
      default_view_id: Settings.default_view_id(),
      bucket_usage:
        bucket_usage(buckets, assignments, depots, cash_accounts, everything.positions),
      unassigned_accounts: unassigned_accounts(assignments, depots, cash_accounts)
    )
  end

  defp view_row(view, buckets, context) do
    rule =
      case Buckets.view_filter(view.id) do
        {:ok, filter} ->
          %{
            include: bucket_names(filter.include, buckets),
            exclude: bucket_names(filter.exclude, buckets)
          }

        {:error, :view_not_found} ->
          %{include: :all, exclude: []}
      end

    figures =
      case Valuation.for_view(view.id, pricing_context: context) do
        {:error, :view_not_found} -> nil
        valuation -> figures(valuation)
      end

    # Matches-nothing (fix round): a view whose resolution matches zero
    # accounts shows silent zeros everywhere — say so where it is edited.
    matches_nothing? =
      case Buckets.load_global_scope(view.id) do
        {:error, :view_not_found} -> false
        scope -> not Buckets.scope_matches_any_account?(scope)
      end

    %{
      id: view.id,
      name: view.name,
      rule: rule,
      figures: figures,
      matches_nothing?: matches_nothing?
    }
  end

  defp bucket_names(:all, _buckets), do: :all

  defp bucket_names(ids, buckets) do
    buckets |> Enum.filter(&(&1.id in ids)) |> Enum.map(& &1.name)
  end

  defp figures(valuation) do
    depot_ids = valuation.positions |> Enum.map(& &1.securities_account_id) |> Enum.uniq()

    %{
      total: valuation.total_with_cash,
      currency: valuation.base_currency,
      positions: length(valuation.positions),
      accounts: length(depot_ids) + length(valuation.cash_balances)
    }
  end

  defp bucket_usage(buckets, assignments, depots, cash_accounts, positions) do
    depot_names = Map.new(depots, &{&1.id, &1.name})
    cash_names = Map.new(cash_accounts, &{&1.id, &1.name})

    Map.new(buckets, fn bucket ->
      default_depots =
        for {id, ids} <- assignments.depot_defaults,
            bucket.id in ids,
            name = depot_names[id],
            do: name

      default_cash =
        for {id, ids} <- assignments.cash, bucket.id in ids, name = cash_names[id], do: name

      {inherits, direct} =
        Enum.reduce(positions, {0, []}, fn position, {inherits, direct} ->
          key = {position.securities_account_id, position.security_id}

          case Map.get(assignments.overrides, key, :inherit) do
            {:explicit, ids} ->
              if bucket.id in ids,
                do: {inherits, [position.security_name || gettext("Unsorted") | direct]},
                else: {inherits, direct}

            :explicit_empty ->
              {inherits, direct}

            :inherit ->
              defaults = Map.get(assignments.depot_defaults, position.securities_account_id, [])
              if bucket.id in defaults, do: {inherits + 1, direct}, else: {inherits, direct}
          end
        end)

      {bucket.id,
       %{
         default_on: Enum.sort(default_depots) ++ Enum.sort(default_cash),
         inherits: inherits,
         direct: direct |> Enum.reverse() |> Enum.sort()
       }}
    end)
  end

  # The accounts without any default bucket, named on the basis line so the
  # remaining assignment work is visible where the edit path is linked.
  defp unassigned_accounts(assignments, depots, cash_accounts) do
    depot_names =
      for depot <- depots, Map.get(assignments.depot_defaults, depot.id, []) == [], do: depot.name

    cash_names =
      for cash <- cash_accounts, Map.get(assignments.cash, cash.id, []) == [], do: cash.name

    Enum.sort(depot_names ++ cash_names)
  end

  # -- helpers ----------------------------------------------------------------

  # An empty color picker submits "" — drop it so the bucket keeps no color.
  defp normalize_color(%{"color" => ""} = params), do: Map.delete(params, "color")
  defp normalize_color(params), do: params

  defp success(socket, message), do: assign(socket, success: message, error: nil)
  defp failure(socket, message), do: assign(socket, error: message, success: nil)

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end

  defp bucket_to_delete(bucket_id) do
    case Buckets.get_bucket(bucket_id) do
      nil -> {:error, :not_found}
      bucket -> {:ok, bucket}
    end
  end
end
