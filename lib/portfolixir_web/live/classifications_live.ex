defmodule PortfolixirWeb.ClassificationsLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  @zero Decimal.new("0")
  @hundred Decimal.new("100")

  @impl true
  def mount(_params, _session, socket) do
    Classifications.ensure_builtins()

    {:ok,
     socket
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> assign(:selected_id, nil)
     |> assign(:tree, nil)
     |> assign(:query, "")
     |> assign(:editing_id, nil)
     |> assign(:current_only, true)
     |> assign(:holdings, nil)
     |> assign(:current_path, "/classifications")
     |> assign(:portfolio, Portfolios.first_portfolio())
     |> assign(:views, Buckets.list_views())
     |> assign(:soll_view_id, nil)
     |> assign(:soll, nil)
     |> start_holdings()}
  end

  # The per-security holdings/valuation is loaded once, asynchronously, after
  # the socket connects (mirrors the Portfolio page): one ledger read plus the
  # shared quote/FX path, joined onto the tree in memory rather than queried
  # per node (issue #334).
  defp start_holdings(socket) do
    if connected?(socket) do
      start_async(socket, :holdings, fn -> Valuation.holdings_by_security() end)
    else
      socket
    end
  end

  @impl true
  def handle_async(:holdings, {:ok, holdings}, socket) do
    {:noreply, socket |> assign(:holdings, holdings) |> reload()}
  end

  def handle_async(:holdings, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :error, gettext("Couldn't load current holdings."))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    path = URI.parse(uri).path

    {:noreply,
     socket
     |> assign(:current_path, path)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, selected_id: nil, tree: nil)
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, selected_id: nil, tree: nil)
  end

  defp apply_action(socket, :show, %{"id" => id} = params) do
    case Integer.parse(id) do
      {classification_id, ""} ->
        # The portfolio page's no-plan hint deep-links here with `?soll_view=`
        # so the editor opens on the right `(view, classification)` plan
        # (ADR-0020, #468). Without the param the editor defaults to Gesamt.
        socket
        |> assign(:query, "")
        |> assign(:editing_id, nil)
        |> assign(:soll_view_id, soll_view_from_params(params))
        |> load_show(classification_id)
        |> load_soll()

      _ ->
        push_navigate(socket, to: "/classifications")
    end
  end

  # Reads the deep-link's `soll_view` param: missing → Gesamt (nil); otherwise
  # "total"/an integer id via the shared, atom-safe parser.
  defp soll_view_from_params(%{"soll_view" => value}), do: parse_soll_view(value)
  defp soll_view_from_params(_params), do: nil

  @impl true
  def render(%{live_action: :show, tree: nil} = assigns) do
    ~H"""
    <AppShell.shell current_path={@current_path} page_title={gettext("Classifications")}>
      <div class="workspace-page">
        <p class="alert-error" role="alert"><%= gettext("Classification not found") %></p>
      </div>
    </AppShell.shell>
    """
  end

  def render(%{live_action: :show} = assigns) do
    ~H"""
    <AppShell.shell
      current_path={@current_path}
      page_title={@tree.classification.name}
      page_subtitle={gettext("Organise securities by dragging them between categories")}
    >
      <div
        id="classifications-workspace"
        phx-hook="ClassificationDnD"
        class="workspace-page classifications-detail"
        {workspace_attrs(@tree)}
      >
        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <header class="detail-head">
          <h2>
            <%= @tree.classification.name %>
            <%= if @tree.classification.built_in do %>
              <span class="badge"><%= gettext("Built-in") %></span>
            <% end %>
          </h2>
          <%= if @tree.editable do %>
            <button
              type="button"
              class="button-danger"
              phx-click="delete_classification"
              data-confirm={gettext("Delete this classification and all its categories?")}
            >
              <%= gettext("Delete classification") %>
            </button>
          <% end %>
        </header>

        <%= if @soll do %>
          <.soll_editor
            soll={@soll}
            views={@views}
            flat={@tree.flat}
            assigned={@tree.assigned_counts}
          />
        <% end %>

        <%= if @tree.assignable and @tree.flat != [] and @tree.unsorted != [] do %>
          <p class="alert-info" role="status" data-role="assignment-nudge">
            <%= ngettext(
              "%{count} security isn't in any category yet — drag it from Unsorted below into a category so it counts toward the target/actual allocation.",
              "%{count} securities aren't in any category yet — drag them from Unsorted below into categories so they count toward the target/actual allocation.",
              length(@tree.unsorted)
            ) %>
          </p>
        <% end %>

        <form phx-change="filter_tree" class="tree-search" onsubmit="return false">
          <input
            id="tree-search-input"
            type="search"
            name="query"
            value={@query}
            phx-debounce="150"
            autocomplete="off"
            placeholder={gettext("Search securities in this tree…")}
          />
        </form>

        <form phx-change="toggle_current_only" class="tree-toggle" onsubmit="return false">
          <input type="hidden" name="current_only" value="false" />
          <label class="current-only-label">
            <input
              type="checkbox"
              name="current_only"
              value="true"
              checked={@tree.current_only}
              data-role="current-only-toggle"
            />
            <span><%= gettext("Current positions only") %></span>
          </label>
        </form>

        <%= if @tree.editable do %>
          <form phx-submit="create_category" class="inline-form category-form">
            <input type="hidden" name="category[classification_id]" value={@tree.classification.id} />
            <label>
              <span><%= gettext("New category") %></span>
              <input name="category[name]" required />
            </label>
            <label>
              <span><%= gettext("Parent") %></span>
              <select name="category[parent_id]">
                <option value=""><%= gettext("— Top level —") %></option>
                <%= for {category, depth} <- @tree.flat do %>
                  <option value={category.id}><%= indent(depth) %><%= category.name %></option>
                <% end %>
              </select>
            </label>
            <label>
              <span><%= gettext("Color") %></span>
              <input type="color" name="category[color]" value="#7c3aed" />
            </label>
            <label class="category-form__description">
              <span><%= gettext("Description") %> <small>(<%= gettext("optional") %>)</small></span>
              <input name="category[description]" />
            </label>
            <button type="submit"><%= gettext("Add") %></button>
          </form>
        <% end %>

        <%= if @tree.assignable do %>
          <div class="select-toolbar" data-select-toolbar hidden>
            <span class="select-count">
              <strong data-selected-count>0</strong> <%= gettext("selected") %>
            </span>
            <label class="select-move">
              <span class="sr-only"><%= gettext("Target category") %></span>
              <select data-move-target>
                <%= for {category, depth} <- @tree.flat do %>
                  <option value={category.id}><%= indent(depth) %><%= category.name %></option>
                <% end %>
              </select>
            </label>
            <button type="button" class="button" data-move-selected>
              <%= gettext("Move to category") %>
            </button>
            <button type="button" class="button-danger" data-unassign-selected>
              <%= gettext("Unassign") %>
            </button>
            <button type="button" data-clear-selection><%= gettext("Clear") %></button>
          </div>

          <p class="hint multiselect-hint">
            <%= gettext("Tip: click rows to select several, then drag or use the toolbar to move them together.") %>
          </p>
        <% end %>

        <section class="tree">
          <%= for node <- @tree.nodes do %>
            <.category_node
              node={node}
              classification_id={@tree.classification.id}
              editable={@tree.editable}
              assignable={@tree.assignable}
              editing_id={@editing_id}
              filtering={@tree.filtering?}
            />
          <% end %>
          <%= if @tree.nodes == [] and not @tree.filtering? do %>
            <p class="hint"><%= gettext("No categories yet.") %></p>
          <% end %>
          <%= if @tree.filtering? and @tree.nodes == [] and @tree.unsorted == [] do %>
            <p class="hint"><%= gettext("No securities match your search.") %></p>
          <% end %>
        </section>

        <details class="cat-node unsorted-node" open={@tree.filtering?} {unsorted_attrs(@tree)}>
          <summary class="cat-summary">
            <span class="cat-swatch is-empty" aria-hidden="true"></span>
            <span class="cat-name"><%= gettext("Unsorted") %></span>
            <span class="cat-count"><%= length(@tree.unsorted) %></span>
          </summary>
          <div class="cat-body">
            <ul class="cat-securities">
              <%= for security <- @tree.unsorted do %>
                <.security_row security={security} assignable={@tree.assignable} />
              <% end %>
              <%= if @tree.unsorted == [] do %>
                <li class="hint"><%= gettext("Everything is sorted.") %></li>
              <% end %>
            </ul>
          </div>
        </details>
      </div>
    </AppShell.shell>
    """
  end

  def render(%{live_action: :new} = assigns) do
    ~H"""
    <AppShell.shell current_path={@current_path} page_title={gettext("New classification")}>
      <div class="workspace-page">
        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <section class="workspace-section">
          <h2><%= gettext("Create classification") %></h2>
          <form id="classification-form" phx-submit="create_classification" class="inline-form">
            <label>
              <span><%= gettext("Name") %></span>
              <input name="classification[name]" required autofocus />
            </label>
            <button type="submit"><%= gettext("Create classification") %></button>
          </form>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell current_path={@current_path} page_title={gettext("Classifications")}>
      <div class="workspace-page">
        <section class="workspace-section empty-state">
          <h2><%= gettext("Classifications") %></h2>
          <p><%= gettext("Pick a classification on the left, or create a new one.") %></p>
          <.link navigate="/classifications/new" class="button">
            <%= gettext("New classification") %>
          </.link>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  # One assigned/unsorted security row, with its current quantity and EUR market
  # value joined in (issue #334). Shared by the category and Unsorted lists so
  # the markup lives in one place (SonarCloud copy-paste, issue #368).
  defp security_row(assigns) do
    ~H"""
    <li
      class={["dnd-row", @assignable && "is-draggable"]}
      draggable={if @assignable, do: "true", else: nil}
      data-drag-security={if @assignable, do: @security.id, else: nil}
      data-role="security-row"
    >
      <span class="row-name" title={@security.name}><%= @security.name %></span>
      <%= if @security.ticker_symbol not in [nil, ""] do %>
        <small class="row-ticker"><%= @security.ticker_symbol %></small>
      <% end %>
      <small class="row-ccy"><%= @security.currency_code %></small>
      <span class="row-quantity" data-role="security-quantity">
        <%= Format.money(@security.quantity) %>
      </span>
      <span class="row-value" data-role="security-value">
        <%= Format.money(@security.market_value) %>
      </span>
    </li>
    """
  end

  defp category_node(assigns) do
    ~H"""
    <details class="cat-node" open={@filtering} {category_attrs(@assignable, @classification_id, @node.category.id)}>
      <summary class="cat-summary">
        <span class="cat-swatch" style={swatch(@node.category.color)} aria-hidden="true"></span>
        <span class="cat-name">
          <%= @node.category.name %>
          <%= if @node.category.description not in [nil, ""] do %>
            <small class="cat-description-inline"><%= @node.category.description %></small>
          <% end %>
        </span>
        <span class="cat-count" title={gettext("Securities in this category and its sub-categories")}><%= total_count(@node) %></span>
        <span
          class="cat-positions"
          data-role="category-positions"
          title={gettext("Visible positions in this category and its sub-categories")}
        ><%= total_count(@node) %></span>
        <span class="cat-value" data-role="category-value" title={gettext("EUR value of the visible positions")}>
          <%= Format.money(visible_value(@node)) %>
        </span>
        <%= if hidden_count(@node) > 0 do %>
          <span
            class="cat-without-holdings"
            data-role="without-holdings"
            title={gettext("Assigned securities you no longer hold, hidden by the filter")}
          >+<%= hidden_count(@node) %> <%= gettext("without holdings") %></span>
        <% end %>
        <span class="cat-actions" data-no-toggle>
          <button
            type="button"
            class="icon-mini"
            phx-click="edit_category"
            phx-value-id={@node.category.id}
            aria-label={gettext("Edit category")}
            title={gettext("Edit category")}
          >✎</button>
          <%= if @editable do %>
            <button
              type="button"
              class="icon-mini"
              phx-click="delete_category"
              phx-value-id={@node.category.id}
              data-confirm={gettext("Delete this category?")}
              aria-label={gettext("Delete category")}
              title={gettext("Delete category")}
            >×</button>
          <% end %>
        </span>
      </summary>
      <div class="cat-body">
        <%= if @editing_id == @node.category.id and @editable do %>
          <form phx-submit="update_category" class="cat-edit-form">
            <input type="hidden" name="category[id]" value={@node.category.id} />
            <input
              name="category[name]"
              value={@node.category.name}
              aria-label={gettext("Name")}
              required
            />
            <input
              name="category[description]"
              value={@node.category.description}
              placeholder={gettext("Description")}
            />
            <input
              type="color"
              name="category[color]"
              value={@node.category.color || "#cccccc"}
              class="color-mini"
              aria-label={gettext("Color")}
            />
            <button type="submit" class="button"><%= gettext("Save") %></button>
            <button type="button" phx-click="cancel_edit_category"><%= gettext("Cancel") %></button>
          </form>
        <% end %>
        <%= if @editing_id == @node.category.id and not @editable do %>
          <form phx-change="recolor_category" class="cat-edit-form">
            <input type="hidden" name="category_id" value={@node.category.id} />
            <label class="recolor-label">
              <span><%= gettext("Color") %></span>
              <input
                type="color"
                name="color"
                value={@node.category.color || "#cccccc"}
                class="color-mini"
              />
            </label>
            <button type="button" phx-click="cancel_edit_category"><%= gettext("Done") %></button>
          </form>
        <% end %>
        <ul class="cat-securities">
          <%= for security <- @node.securities do %>
            <.security_row security={security} assignable={@assignable} />
          <% end %>
        </ul>
        <%= for child <- @node.children do %>
          <.category_node
            node={child}
            classification_id={@classification_id}
            editable={@editable}
            assignable={@assignable}
            editing_id={@editing_id}
            filtering={@filtering}
          />
        <% end %>
      </div>
    </details>
    """
  end

  # The view-bound SOLL plan editor (ADR-0020, issue #467). It lets the
  # maintainer pick a view (Gesamt by default), then define, edit, copy or clear
  # that `(view, classification)` plan's per-category target weights plus its
  # cash target, with a live Σ badge and per-parent consistency hints. Weights
  # are entered and shown as percentages; the context stores fractions in [0, 1].
  attr(:soll, :map, required: true)
  attr(:views, :list, required: true)
  attr(:flat, :list, required: true)
  attr(:assigned, :map, required: true)

  defp soll_editor(assigns) do
    ~H"""
    <section id="soll-editor" class="workspace-section soll-editor">
      <header class="soll-editor__head">
        <h2><%= gettext("Target plan") %></h2>
        <form phx-change="select_soll_view" class="soll-view-picker" onsubmit="return false">
          <label class="soll-view-picker__label" for="soll-view-select">
            <%= gettext("Target plan for view:") %>
          </label>
          <select id="soll-view-select" name="soll_view">
            <option value="total" selected={is_nil(@soll.view_id)}>
              <%= gettext("Gesamt (total)") %>
            </option>
            <%= for view <- @views do %>
              <option value={view.id} selected={@soll.view_id == view.id}>
                <%= view.name %>
              </option>
            <% end %>
          </select>
        </form>
      </header>

      <%= if @soll.exists do %>
        <form id="soll-plan-form" phx-change="soll_sum" phx-submit="save_soll_plan">
          <table class="soll-table">
            <thead>
              <tr>
                <th scope="col"><%= gettext("Category") %></th>
                <th scope="col" class="num"><%= gettext("Target %") %></th>
              </tr>
            </thead>
            <tbody>
              <%= for {category, depth} <- @flat do %>
                <tr class={["soll-row", child_mismatch_class(@soll, category.id)]}>
                  <th scope="row" class="soll-row__name">
                    <span aria-hidden="true"><%= indent(depth) %></span><%= category.name %>
                    <span
                      :if={child_hint(@soll, category.id)}
                      class={[
                        "hint",
                        "target-consistency",
                        child_mismatch_class(@soll, category.id)
                      ]}
                      data-role="soll-child-hint"
                    >
                      <%= gettext("children Σ") %> <%= child_hint(@soll, category.id) %>%
                    </span>
                    <span
                      :if={empty_target?(@soll, @assigned, category.id)}
                      class="hint target-consistency is-mismatch"
                      data-role="empty-category-warning"
                    >
                      <%= gettext("no assigned positions") %>
                    </span>
                  </th>
                  <td class="num">
                    <label class="sr-only" for={"soll-weight-#{category.id}"}>
                      <%= gettext("Target weight for %{name}", name: category.name) %>
                    </label>
                    <input
                      type="number"
                      id={"soll-weight-#{category.id}"}
                      name={"weights[#{category.id}]"}
                      value={Map.get(@soll.weights, category.id, "")}
                      min="0"
                      max="100"
                      step="0.1"
                      inputmode="decimal"
                    />
                  </td>
                </tr>
              <% end %>
              <tr class="soll-row soll-row--cash">
                <th scope="row" class="soll-row__name"><%= gettext("Cash") %></th>
                <td class="num">
                  <label class="sr-only" for="soll-cash-target"><%= gettext("Cash target") %></label>
                  <input
                    type="number"
                    id="soll-cash-target"
                    name="cash_target"
                    value={@soll.cash_target || ""}
                    min="0"
                    max="100"
                    step="0.1"
                    inputmode="decimal"
                  />
                </td>
              </tr>
            </tbody>
            <tfoot>
              <tr class={["soll-row", "soll-row--sum", @soll.mismatch? && "is-target-mismatch"]}>
                <th scope="row"><%= gettext("Σ") %></th>
                <td class="num" data-role="soll-sum">
                  <%= @soll.sum %>%
                  <span :if={not @soll.mismatch?} class="soll-ok" aria-hidden="true">✓</span>
                  <span :if={@soll.mismatch?} class="soll-bad" aria-hidden="true">✗</span>
                </td>
              </tr>
            </tfoot>
          </table>

          <div class="soll-editor__actions">
            <button type="submit" class="button-primary"><%= gettext("Save plan") %></button>
            <button
              type="button"
              class="button-danger"
              phx-click="delete_soll_plan"
              data-confirm={gettext("Delete this view's plan? The portfolio page falls back to actual-only for it.")}
            >
              <%= gettext("Delete plan") %>
            </button>
          </div>
        </form>

        <%= if @soll.copy_sources != [] do %>
          <form phx-change="copy_soll_plan" class="soll-copy" onsubmit="return false">
            <label class="soll-copy__label" for="soll-copy-from">
              <%= gettext("Copy from another view…") %>
            </label>
            <select id="soll-copy-from" name="copy_from">
              <option value=""><%= gettext("— Choose a view —") %></option>
              <%= for {label, value} <- @soll.copy_sources do %>
                <option value={value}><%= label %></option>
              <% end %>
            </select>
          </form>
        <% end %>
      <% else %>
        <div class="soll-empty" data-role="soll-empty">
          <p class="hint">
            <%= gettext("No plan for this view yet. Create one, or copy another view's plan for this classification.") %>
          </p>
          <div class="soll-editor__actions">
            <button type="button" class="button-primary" phx-click="create_soll_plan">
              <%= gettext("Create plan") %>
            </button>
          </div>
          <%= if @soll.copy_sources != [] do %>
            <form phx-change="copy_soll_plan" class="soll-copy" onsubmit="return false">
              <label class="soll-copy__label" for="soll-copy-from-empty">
                <%= gettext("Copy from another view…") %>
              </label>
              <select id="soll-copy-from-empty" name="copy_from">
                <option value=""><%= gettext("— Choose a view —") %></option>
                <%= for {label, value} <- @soll.copy_sources do %>
                  <option value={value}><%= label %></option>
                <% end %>
              </select>
            </form>
          <% end %>
        </div>
      <% end %>
    </section>
    """
  end

  @impl true
  def handle_event("create_classification", %{"classification" => params}, socket) do
    case Classifications.create_classification(Actor.owner_ui(), params) do
      {:ok, classification} ->
        {:noreply, push_navigate(socket, to: "/classifications/#{classification.id}")}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event("create_category", %{"category" => params}, socket) do
    case Classifications.create_category(Actor.owner_ui(), params) do
      {:ok, _category} ->
        {:noreply, socket |> success(gettext("Category created")) |> reload()}

      {:error, reason} ->
        {:noreply, failure(socket, error_message(reason))}
    end
  end

  def handle_event("edit_category", %{"id" => id}, socket) do
    case coerce_id(id) do
      {:ok, category_id} -> {:noreply, assign(socket, :editing_id, category_id)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_category", _params, socket) do
    {:noreply, assign(socket, :editing_id, nil)}
  end

  def handle_event("update_category", %{"category" => %{"id" => id} = params}, socket) do
    with {:ok, category_id} <- coerce_id(id),
         category when not is_nil(category) <- Classifications.get_category(category_id),
         {:ok, _} <- Classifications.update_category(Actor.owner_ui(), category, params) do
      {:noreply,
       socket
       |> assign(:editing_id, nil)
       |> success(gettext("Category updated"))
       |> reload()}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("recolor_category", %{"category_id" => id, "color" => color}, socket) do
    with {:ok, category_id} <- coerce_id(id),
         category when not is_nil(category) <- Classifications.get_category(category_id),
         {:ok, _} <- Classifications.recolor_category(Actor.owner_ui(), category, color) do
      {:noreply, reload(socket)}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    with {:ok, category_id} <- coerce_id(id),
         category when not is_nil(category) <- Classifications.get_category(category_id),
         {:ok, _} <- Classifications.delete_category(Actor.owner_ui(), category) do
      {:noreply, socket |> success(gettext("Category deleted")) |> reload()}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_classification", _params, socket) do
    with id when not is_nil(id) <- socket.assigns.selected_id,
         classification when not is_nil(classification) <- Classifications.get_classification(id),
         {:ok, _} <- Classifications.delete_classification(Actor.owner_ui(), classification) do
      {:noreply, push_navigate(socket, to: "/classifications")}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      _ -> {:noreply, socket}
    end
  end

  # -- SOLL plan events ------------------------------------------------------

  def handle_event("select_soll_view", %{"soll_view" => value}, socket) do
    {:noreply, socket |> assign(:soll_view_id, parse_soll_view(value)) |> load_soll()}
  end

  def handle_event("create_soll_plan", _params, socket) do
    with %{id: portfolio_id} <- socket.assigns.portfolio,
         classification_id when is_integer(classification_id) <- socket.assigns.selected_id,
         {:ok, _plan} <-
           Targets.ensure_plan(portfolio_id, classification_id, view: socket.assigns.soll_view_id) do
      {:noreply, socket |> success(gettext("Plan created")) |> load_soll()}
    else
      _ -> {:noreply, failure(socket, gettext("Could not create the plan"))}
    end
  end

  # Live Σ: recompute the running total (categories + cash) from the form as the
  # maintainer types, without persisting anything.
  def handle_event("soll_sum", params, socket) do
    {:noreply, assign(socket, :soll, recompute_soll_sum(socket.assigns.soll, params))}
  end

  def handle_event("save_soll_plan", params, socket) do
    with %{id: portfolio_id} <- socket.assigns.portfolio,
         classification_id when is_integer(classification_id) <- socket.assigns.selected_id,
         {:ok, entries} <- parse_weight_entries(params["weights"]),
         {:ok, cash_weight} <- parse_percent_fraction(params["cash_target"]),
         {:ok, _} <-
           Targets.set_targets(portfolio_id, classification_id, entries,
             view: socket.assigns.soll_view_id
           ),
         :ok <-
           Targets.set_cash_target(portfolio_id, cash_weight, view: socket.assigns.soll_view_id) do
      {:noreply, socket |> success(gettext("Plan saved")) |> load_soll()}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}

      {:error, reason} ->
        {:noreply, failure(socket, error_message(reason))}

      _ ->
        {:noreply, failure(socket, gettext("Could not save the plan"))}
    end
  end

  def handle_event("delete_soll_plan", _params, socket) do
    with %{id: portfolio_id} <- socket.assigns.portfolio,
         classification_id when is_integer(classification_id) <- socket.assigns.selected_id do
      Targets.delete_plan(portfolio_id, classification_id, view: socket.assigns.soll_view_id)
      {:noreply, socket |> success(gettext("Plan deleted")) |> load_soll()}
    else
      _ -> {:noreply, socket}
    end
  end

  # Prefill the editor from another view's plan for the same classification,
  # without persisting until the maintainer saves.
  def handle_event("copy_soll_plan", %{"copy_from" => ""}, socket), do: {:noreply, socket}

  def handle_event("copy_soll_plan", %{"copy_from" => value}, socket) do
    {:noreply, assign(socket, :soll, copy_soll_from(socket.assigns, parse_soll_view(value)))}
  end

  def handle_event("filter_tree", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> reload()}
  end

  def handle_event("toggle_current_only", params, socket) do
    current_only? = params["current_only"] == "true"
    {:noreply, socket |> assign(:current_only, current_only?) |> reload()}
  end

  def handle_event("assign_security", params, socket) do
    with {:ok, security_id} <- coerce_id(params["security_id"]),
         {:ok, classification_id} <- coerce_id(params["classification_id"]),
         {:ok, category_id} <- coerce_id(params["category_id"]),
         {:ok, _assignment} <-
           Classifications.assign_security(
             Actor.owner_ui(),
             security_id,
             classification_id,
             category_id
           ) do
      {:noreply, reload(socket)}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("unassign", params, socket) do
    with {:ok, security_id} <- coerce_id(params["security_id"]),
         {:ok, classification_id} <- coerce_id(params["classification_id"]) do
      {:ok, _} =
        Classifications.unassign_security(Actor.owner_ui(), security_id, classification_id)

      {:noreply, reload(socket)}
    else
      :error -> {:noreply, socket}
    end
  end

  def handle_event("assign_securities", params, socket) do
    with {:ok, ids} <- coerce_ids(params["security_ids"]),
         {:ok, classification_id} <- coerce_id(params["classification_id"]),
         {:ok, category_id} <- coerce_id(params["category_id"]) do
      do_assign(socket, ids, classification_id, category_id)
    else
      :error -> {:noreply, socket}
    end
  end

  def handle_event("unassign_many", params, socket) do
    with {:ok, ids} <- coerce_ids(params["security_ids"]),
         {:ok, classification_id} <- coerce_id(params["classification_id"]) do
      do_unassign(socket, ids, classification_id)
    else
      :error -> {:noreply, socket}
    end
  end

  # -- move / reclassify dispatch -------------------------------------------

  # Asset-class tree: a "move" edits each security's asset_class field; other
  # trees write the stored assignment.
  defp do_assign(%{assigns: %{tree: %{reclassify: true}}} = socket, ids, _cid, category_id) do
    case Classifications.reclassify_securities(ids, category_id) do
      {:ok, count} -> {:noreply, socket |> success(moved_message(count)) |> reload()}
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
    end
  end

  defp do_assign(socket, ids, classification_id, category_id) do
    case Classifications.assign_securities(Actor.owner_ui(), ids, classification_id, category_id) do
      {:ok, count} -> {:noreply, socket |> success(moved_message(count)) |> reload()}
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
    end
  end

  # Asset-class tree: "unassign" resets each security's asset_class to automatic.
  defp do_unassign(%{assigns: %{tree: %{reclassify: true}}} = socket, ids, _classification_id) do
    {:ok, count} = Classifications.reset_asset_class(ids)
    {:noreply, socket |> success(unassigned_message(count)) |> reload()}
  end

  defp do_unassign(socket, ids, classification_id) do
    {:ok, count} = Classifications.unassign_securities(Actor.owner_ui(), ids, classification_id)
    {:noreply, socket |> success(unassigned_message(count)) |> reload()}
  end

  # -- data loading ---------------------------------------------------------

  defp reload(%{assigns: %{selected_id: nil}} = socket), do: socket
  defp reload(socket), do: load_show(socket, socket.assigns.selected_id)

  # -- SOLL plan loading -----------------------------------------------------

  # The plan editor only makes sense for an editable (custom) tree that has a
  # portfolio behind it; built-in trees and the no-portfolio case carry no
  # editor (`soll: nil`).
  defp load_soll(%{assigns: %{portfolio: nil}} = socket), do: assign(socket, :soll, nil)
  defp load_soll(%{assigns: %{tree: nil}} = socket), do: assign(socket, :soll, nil)

  defp load_soll(%{assigns: %{tree: %{editable: false}}} = socket),
    do: assign(socket, :soll, nil)

  defp load_soll(socket) do
    %{portfolio: portfolio, selected_id: classification_id, soll_view_id: view_id} =
      socket.assigns

    assign(socket, :soll, build_soll(portfolio.id, classification_id, view_id, socket.assigns))
  end

  defp build_soll(portfolio_id, classification_id, view_id, assigns) do
    exists? = Targets.plan_exists?(portfolio_id, classification_id, view: view_id)

    weights =
      if exists? do
        portfolio_id
        |> Targets.list_targets(classification_id: classification_id, view: view_id)
        |> Map.new(&{&1.category_id, fraction_to_percent(&1.target_weight)})
      else
        %{}
      end

    cash_target =
      portfolio_id
      |> Targets.get_cash_target(view: view_id)
      |> fraction_to_percent_or_nil()

    soll = %{
      view_id: view_id,
      exists: exists?,
      weights: weights,
      cash_target: cash_target,
      top_level_ids: top_level_ids(assigns.tree.flat),
      children_by_parent: children_by_parent(assigns.tree.flat),
      child_sums: child_sums(assigns.tree.flat, weights),
      copy_sources: copy_sources(portfolio_id, classification_id, view_id, assigns.views)
    }

    put_sum(soll)
  end

  # The integer ids of the top-level categories (those without a parent). The
  # running Σ counts only these, mirroring the allocation engine's
  # `top_level_target_sum`, so a hierarchical plan is not double-counted when a
  # parent's weight already covers its children (#467).
  defp top_level_ids(flat) do
    for {category, _depth} <- flat, is_nil(category.parent_id), into: MapSet.new() do
      category.id
    end
  end

  # The parent→children id structure (`%{parent_id => [child_id, ...]}`, integers)
  # used to roll a blank parent's Σ up from its children's effective weights.
  # Only real parents (non-nil parent_id rows grouped by their parent) appear.
  defp children_by_parent(flat) do
    flat
    |> Enum.reject(fn {category, _depth} -> is_nil(category.parent_id) end)
    |> Enum.group_by(
      fn {category, _depth} -> category.parent_id end,
      fn {category, _depth} -> category.id end
    )
  end

  # Live Σ from the in-flight form values: recompute the running total and the
  # per-parent children sums without touching the database.
  defp recompute_soll_sum(soll, params) do
    weights = parse_percent_map(params["weights"])
    cash = parse_percent_string(params["cash_target"])

    soll
    |> Map.put(:weights, weights)
    |> Map.put(:cash_target, cash)
    |> Map.put(:child_sums, child_sums_from_decimals(weights))
    |> put_sum()
  end

  # Prefill from a source view's plan (for the same classification) without
  # persisting; the editor shows the source values for the target view.
  defp copy_soll_from(assigns, source_view_id) do
    %{portfolio: portfolio, selected_id: classification_id} = assigns

    weights =
      portfolio.id
      |> Targets.list_targets(classification_id: classification_id, view: source_view_id)
      |> Map.new(&{&1.category_id, fraction_to_percent(&1.target_weight)})

    cash =
      portfolio.id
      |> Targets.get_cash_target(view: source_view_id)
      |> fraction_to_percent_or_nil()

    # Copying prefills the form (and reveals it from the empty state) without
    # persisting; the maintainer still has to Save to write the plan.
    assigns.soll
    |> Map.put(:exists, true)
    |> Map.put(:weights, weights)
    |> Map.put(:cash_target, cash)
    |> Map.put(:child_sums, child_sums(assigns.tree.flat, weights))
    |> put_sum()
  end

  # Other views (Gesamt + named) that carry a plan for this classification, as
  # `{label, value}` pairs for the copy-from picker — the current view excluded.
  defp copy_sources(portfolio_id, classification_id, current_view_id, views) do
    candidates = [{gettext("Gesamt (total)"), nil} | Enum.map(views, &{&1.name, &1.id})]

    candidates
    |> Enum.reject(fn {_label, id} -> id == current_view_id end)
    |> Enum.filter(fn {_label, id} ->
      Targets.plan_exists?(portfolio_id, classification_id, view: id)
    end)
    |> Enum.map(fn {label, id} -> {label, view_param(id)} end)
  end

  # Running total: the TOP-LEVEL categories' EFFECTIVE weights plus the cash
  # percentage. A category's effective weight is its own explicit weight when set
  # (children are not added on top — that stays the per-parent hint only), else
  # the rolled-up sum of its children's effective weights so sub-category-only
  # plans still count (#467). Decimal math throughout so the 100% comparison is
  # exact. `top_level_ids`/`children_by_parent` are always populated by
  # `build_soll/4`; the fallback keeps a malformed map from crashing.
  defp put_sum(soll) do
    top_level_ids = Map.get(soll, :top_level_ids)
    children_by_parent = Map.get(soll, :children_by_parent)

    sum =
      soll
      |> effective_top_level_sum(top_level_ids, children_by_parent)
      |> Decimal.add(to_decimal(soll.cash_target))

    soll
    |> Map.put(:sum, format_sum(sum))
    |> Map.put(:mismatch?, not Decimal.equal?(sum, @hundred))
  end

  defp effective_top_level_sum(soll, %MapSet{} = top_level_ids, children_by_parent)
       when is_map(children_by_parent) do
    Enum.reduce(top_level_ids, @zero, fn id, acc ->
      Decimal.add(acc, effective_weight(id, soll.weights, children_by_parent))
    end)
  end

  # Fallback when the tree shape is absent (malformed soll): sum every weight, as
  # the pre-#467 editor did, so the badge degrades gracefully instead of crashing.
  defp effective_top_level_sum(soll, _ids, _children) do
    Enum.reduce(soll.weights, @zero, fn {_id, value}, acc ->
      Decimal.add(acc, to_decimal(value))
    end)
  end

  # A category's effective weight: its explicit weight when set, else the summed
  # effective weights of its children (recursive roll-up), else zero.
  defp effective_weight(id, weights, children_by_parent) do
    case Map.get(weights, id) do
      nil ->
        children_by_parent
        |> Map.get(id, [])
        |> Enum.reduce(@zero, fn child_id, acc ->
          Decimal.add(acc, effective_weight(child_id, weights, children_by_parent))
        end)

      value ->
        to_decimal(value)
    end
  end

  # Sum of each parent's direct children's percentages, keyed by parent id, only
  # where at least one child carries a weight (advisory hint, display-only).
  defp child_sums(flat, weights) do
    flat
    |> Enum.group_by(fn {category, _depth} -> category.parent_id end)
    |> Enum.reduce(%{}, fn {parent_id, children}, acc ->
      case sum_child_weights(children, weights) do
        nil -> acc
        sum -> Map.put(acc, parent_id, sum)
      end
    end)
  end

  defp sum_child_weights(children, weights) do
    Enum.reduce(children, nil, fn {category, _depth}, acc ->
      case Map.get(weights, category.id) do
        nil -> acc
        value -> Decimal.add(acc || @zero, to_decimal(value))
      end
    end)
  end

  # Children sums during live typing: weights here are already parsed Decimals,
  # but we lack the tree shape, so we only flag the top-level (parent nil) row.
  # The full per-parent hints come back on the next server load.
  defp child_sums_from_decimals(_weights), do: %{}

  defp load_show(socket, classification_id) do
    tree = Enum.find(Classifications.list_trees(), &(&1.classification.id == classification_id))

    if tree do
      view =
        build_view(tree, socket.assigns.query, socket.assigns.holdings,
          current_only: socket.assigns.current_only
        )

      assign(socket, selected_id: classification_id, tree: view)
    else
      assign(socket, selected_id: nil, tree: nil)
    end
  end

  defp build_view(tree, query, holdings, opts) do
    needle = query |> to_string() |> String.trim() |> String.downcase()
    current_only? = Keyword.fetch!(opts, :current_only)
    # An active search always reveals matching securities so results stay
    # visible, even ones the "current positions only" toggle would normally hide.
    hide_sold? = current_only? and needle == ""
    securities = Catalog.list_securities()
    securities_by_id = Map.new(securities, &{&1.id, &1})

    decorate = fn security ->
      decorate_security(security, holdings)
    end

    by_category =
      tree.assignments
      |> Enum.group_by(& &1.category_id, & &1.security_id)
      |> Map.new(fn {category_id, ids} ->
        members =
          ids
          |> Enum.map(&Map.get(securities_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(&matches?(&1, needle))
          |> Enum.map(decorate)
          |> Enum.sort_by(& &1.name)

        {category_id, split_members(members, hide_sold?)}
      end)

    assigned_ids = MapSet.new(tree.assignments, & &1.security_id)

    unsorted =
      securities
      |> Enum.reject(&MapSet.member?(assigned_ids, &1.id))
      |> Enum.filter(&matches?(&1, needle))
      |> Enum.map(decorate)
      |> Enum.sort_by(& &1.name)

    grouped = Enum.group_by(tree.categories, & &1.parent_id)
    nodes = build_nodes(grouped, nil, by_category)

    # The built-in "asset class" tree is derived from each security's asset_class
    # field; we still let users drag securities between its categories, which
    # edits that field. Other built-in trees (currency) stay read-only.
    reclassify? = tree.classification.key == "asset_class"

    %{
      classification: tree.classification,
      editable: not tree.classification.built_in,
      assignable: not tree.classification.built_in or reclassify?,
      reclassify: reclassify?,
      nodes: if(needle == "", do: nodes, else: prune_nodes(nodes)),
      flat: flatten(tree.categories),
      assigned_counts: assigned_counts(nodes),
      unsorted: unsorted,
      query: query,
      filtering?: needle != "",
      current_only: current_only?
    }
  end

  # Splits a category's decorated, matching securities into the ones to show and
  # a count of the zero-holding ones hidden by the "current positions only"
  # toggle. With the toggle off everything is visible and nothing is hidden.
  defp split_members(members, false), do: %{securities: members, hidden: 0}

  defp split_members(members, true) do
    {held, sold} = Enum.split_with(members, & &1.held?)
    %{securities: held, hidden: length(sold)}
  end

  # Joins the global per-security holdings/valuation onto a plain row map. Before
  # the async load completes (`holdings == nil`) quantity/value are unknown and
  # the row is treated as held so nothing is hidden prematurely.
  defp decorate_security(security, nil) do
    row(security, quantity: nil, market_value: nil, held?: true)
  end

  defp decorate_security(security, holdings) do
    case Map.get(holdings, security.id) do
      %{quantity: quantity, market_value: market_value} ->
        row(security, quantity: quantity, market_value: market_value, held?: true)

      nil ->
        row(security, quantity: @zero, market_value: nil, held?: false)
    end
  end

  defp row(security, fields) do
    %{
      id: security.id,
      name: security.name,
      ticker_symbol: security.ticker_symbol,
      currency_code: security.currency_code,
      quantity: Keyword.fetch!(fields, :quantity),
      market_value: Keyword.fetch!(fields, :market_value),
      held?: Keyword.fetch!(fields, :held?)
    }
  end

  defp matches?(_security, ""), do: true

  defp matches?(security, needle) do
    [security.name, security.ticker_symbol, security.isin]
    |> Enum.any?(fn value ->
      is_binary(value) and String.contains?(String.downcase(value), needle)
    end)
  end

  # When filtering, drop category branches that contain no matching securities.
  defp prune_nodes(nodes) do
    nodes
    |> Enum.map(fn node -> %{node | children: prune_nodes(node.children)} end)
    |> Enum.filter(fn node -> node.securities != [] or node.children != [] end)
  end

  defp build_nodes(grouped, parent_id, by_category) do
    grouped
    |> Map.get(parent_id, [])
    |> Enum.map(fn category ->
      %{securities: securities, hidden: hidden} =
        Map.get(by_category, category.id, %{securities: [], hidden: 0})

      %{
        category: category,
        securities: securities,
        hidden: hidden,
        children: build_nodes(grouped, category.id, by_category)
      }
    end)
  end

  # Securities directly in this node plus everything in its sub-categories.
  defp total_count(node) do
    length(node.securities) + Enum.sum(Enum.map(node.children, &total_count/1))
  end

  # category_id -> number of securities assigned to it and its sub-categories
  # (held or sold). Used by the target editor to warn when a target weight is
  # set on a category that has nothing assigned, so it can never be reached
  # (#501). Built from the unpruned node tree so search filtering can't skew it.
  defp assigned_counts(nodes) do
    Enum.reduce(nodes, %{}, fn node, acc ->
      acc
      |> Map.merge(assigned_counts(node.children))
      |> Map.put(node.category.id, assigned_total(node))
    end)
  end

  defp assigned_total(node) do
    length(node.securities) + node.hidden +
      Enum.sum(Enum.map(node.children, &assigned_total/1))
  end

  # Zero-holding securities hidden in this node and every sub-category, so the
  # "+N without holdings" counter never silently drops a branch's legacy
  # positions (issue #334).
  defp hidden_count(node) do
    node.hidden + Enum.sum(Enum.map(node.children, &hidden_count/1))
  end

  # EUR value of the VISIBLE securities directly in this node and below; an
  # unvalued holding contributes nothing rather than distorting the total.
  defp visible_value(node) do
    direct =
      Enum.reduce(node.securities, @zero, fn security, acc ->
        case security.market_value do
          %Decimal{} = value -> Decimal.add(acc, value)
          _ -> acc
        end
      end)

    Enum.reduce(node.children, direct, fn child, acc ->
      Decimal.add(acc, visible_value(child))
    end)
  end

  # Flat, depth-tagged list of categories for the parent <select>.
  defp flatten(categories) do
    grouped = Enum.group_by(categories, & &1.parent_id)
    flatten_level(grouped, nil, 0)
  end

  defp flatten_level(grouped, parent_id, depth) do
    grouped
    |> Map.get(parent_id, [])
    |> Enum.flat_map(fn category ->
      [{category, depth} | flatten_level(grouped, category.id, depth + 1)]
    end)
  end

  # -- view helpers ---------------------------------------------------------

  defp category_attrs(false, _classification_id, _category_id), do: []

  defp category_attrs(true, classification_id, category_id) do
    [
      {"data-dropzone", ""},
      {"data-drop-kind", "category"},
      {"data-classification", classification_id},
      {"data-category", category_id}
    ]
  end

  defp unsorted_attrs(%{assignable: true, classification: %{id: id}}) do
    [
      {"data-dropzone", ""},
      {"data-drop-kind", "unassign"},
      {"data-classification", id}
    ]
  end

  defp unsorted_attrs(_tree), do: []

  defp workspace_attrs(%{assignable: true, classification: %{id: id}}),
    do: [{"data-classification", id}]

  defp workspace_attrs(_tree), do: []

  defp moved_message(count) do
    ngettext("Moved %{count} security", "Moved %{count} securities", count)
  end

  defp unassigned_message(count) do
    ngettext("Unassigned %{count} security", "Unassigned %{count} securities", count)
  end

  defp indent(0), do: ""
  defp indent(depth), do: String.duplicate("— ", depth)

  defp swatch(nil), do: nil
  defp swatch(color), do: "background:#{color}"

  defp coerce_id(value) when is_integer(value), do: {:ok, value}

  defp coerce_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp coerce_id(_value), do: :error

  defp coerce_ids(values) when is_list(values) do
    ids =
      Enum.flat_map(values, fn value ->
        case coerce_id(value) do
          {:ok, id} -> [id]
          :error -> []
        end
      end)

    {:ok, ids}
  end

  defp coerce_ids(_values), do: :error

  # -- SOLL render helpers ---------------------------------------------------

  # The children-Σ hint string for one parent (a percentage), or nil when no
  # direct child carries a weight.
  defp child_hint(soll, parent_id) do
    case Map.get(soll.child_sums, parent_id) do
      nil -> nil
      sum -> format_sum(sum)
    end
  end

  # True when a category carries a positive target weight but has no securities
  # assigned to it or its sub-categories — a target it can never reach (#501).
  defp empty_target?(soll, assigned, category_id) do
    case Map.get(soll.weights, category_id) do
      nil -> false
      weight -> Decimal.compare(weight, @zero) == :gt and Map.get(assigned, category_id, 0) == 0
    end
  end

  # Flags a parent row whose children's percentages do not sum to its own
  # percentage (advisory; never blocks saving). Reuses the portfolio page's
  # `is-target-mismatch` styling.
  defp child_mismatch_class(soll, category_id) do
    own = Map.get(soll.weights, category_id)
    sum = Map.get(soll.child_sums, category_id)

    if not is_nil(own) and not is_nil(sum) and not Decimal.equal?(to_decimal(own), sum) do
      "is-target-mismatch"
    end
  end

  # -- SOLL parsing / conversion ---------------------------------------------

  # Parse the weights map into context entries `%{category_id, target_weight}`,
  # converting each percentage to a fraction in [0, 1]. Blank inputs are skipped.
  # An unparseable value fails the whole save.
  defp parse_weight_entries(nil), do: {:ok, []}

  defp parse_weight_entries(weights) when is_map(weights) do
    Enum.reduce_while(weights, {:ok, []}, fn {key, value}, {:ok, acc} ->
      with {:ok, category_id} <- coerce_id(key),
           {:ok, fraction} <- parse_percent_fraction(value) do
        case fraction do
          nil -> {:cont, {:ok, acc}}
          _ -> {:cont, {:ok, [%{category_id: category_id, target_weight: fraction} | acc]}}
        end
      else
        _ -> {:halt, {:error, :invalid_weight}}
      end
    end)
  end

  defp parse_weight_entries(_weights), do: {:ok, []}

  # A percentage string ("60", "12.5", "" ) → a `Decimal` fraction in [0, 1], or
  # `nil` for blank. Returns `{:error, :invalid_weight}` for non-numbers.
  defp parse_percent_fraction(nil), do: {:ok, nil}
  defp parse_percent_fraction(""), do: {:ok, nil}

  defp parse_percent_fraction(value) when is_binary(value) do
    case parse_decimal(String.trim(value)) do
      {:ok, decimal} -> {:ok, Decimal.div(decimal, @hundred)}
      :error -> {:error, :invalid_weight}
    end
  end

  defp parse_percent_fraction(_value), do: {:error, :invalid_weight}

  # The live-Σ counterparts: lenient parsers that treat anything unparseable as
  # zero/absent so typing never crashes the form.
  defp parse_percent_map(nil), do: %{}

  defp parse_percent_map(weights) when is_map(weights) do
    Enum.reduce(weights, %{}, fn {key, value}, acc ->
      case {coerce_id(key), parse_percent_string(value)} do
        {{:ok, id}, %Decimal{} = decimal} -> Map.put(acc, id, decimal)
        _ -> acc
      end
    end)
  end

  defp parse_percent_map(_weights), do: %{}

  defp parse_percent_string(nil), do: nil
  defp parse_percent_string(""), do: nil

  defp parse_percent_string(value) when is_binary(value) do
    case parse_decimal(String.trim(value)) do
      {:ok, decimal} -> decimal
      :error -> nil
    end
  end

  defp parse_percent_string(_value), do: nil

  defp parse_decimal(""), do: :error

  # `Decimal.parse/1` also accepts the IEEE special values ("NaN", "Inf",
  # "Infinity", any case/sign), which the `:decimal` Ecto cast then rejects with
  # an uncaught `ArgumentError`. Treat any non-finite result as invalid here so a
  # crafted form payload can never crash the editor — it surfaces as a normal
  # "invalid weight" instead.
  defp parse_decimal(value) do
    case Decimal.parse(value) do
      {%Decimal{} = decimal, ""} ->
        if Decimal.nan?(decimal) or Decimal.inf?(decimal), do: :error, else: {:ok, decimal}

      _ ->
        :error
    end
  end

  # A stored fraction in [0, 1] → its percentage as a plain display string
  # ("0.6" → "60", "0.125" → "12.5"), trimming trailing zeros.
  defp fraction_to_percent(%Decimal{} = fraction) do
    fraction |> Decimal.mult(@hundred) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  defp fraction_to_percent_or_nil(nil), do: nil
  defp fraction_to_percent_or_nil(%Decimal{} = fraction), do: fraction_to_percent(fraction)

  # Format a running sum (already a percentage Decimal) for display, trimming
  # trailing zeros so "100.0" reads "100".
  defp format_sum(%Decimal{} = sum) do
    sum |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(nil), do: @zero

  defp to_decimal(value) when is_binary(value) do
    case parse_decimal(value) do
      {:ok, decimal} -> decimal
      :error -> @zero
    end
  end

  # "total" or a view id string → the view id (nil for Gesamt) used by the
  # Targets context. Never builds an atom from input.
  defp parse_soll_view("total"), do: nil
  defp parse_soll_view(nil), do: nil

  defp parse_soll_view(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp view_param(nil), do: "total"
  defp view_param(id) when is_integer(id), do: Integer.to_string(id)

  defp success(socket, message), do: assign(socket, success: message, error: nil)
  defp failure(socket, message), do: assign(socket, error: message, success: nil)

  defp error_message(:builtin_locked), do: gettext("Built-in classifications cannot be edited")
  defp error_message(:category_mismatch), do: gettext("That category belongs to another tree")
  defp error_message(:not_found), do: gettext("Not found")
  defp error_message(:category_not_found), do: gettext("Category not found")
  defp error_message(:not_reclassifiable), do: gettext("This tree cannot be reassigned")
  defp error_message(%Ecto.Changeset{} = changeset), do: changeset_error(changeset)
  defp error_message(_other), do: gettext("Something went wrong")

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
