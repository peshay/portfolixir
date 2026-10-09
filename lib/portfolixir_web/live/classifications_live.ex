defmodule PortfolixirWeb.ClassificationsLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CategoryResult
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.PolicyRuleReferences
  alias PortfolixirWeb.StoredText
  alias PortfolixirWeb.ViewSwitcher

  @zero Decimal.new("0")
  @hundred Decimal.new("100")

  @impl true
  def mount(_params, _session, socket) do
    # Built-in trees are seeded at startup (#529), not on this read path.
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
     |> assign(:results, nil)
     |> assign(:current_path, "/classifications")
     |> assign(:portfolio, Portfolios.first_portfolio())
     |> assign(:views, Buckets.list_views())
     |> assign(:soll_plan_id, nil)
     |> assign(:soll, nil)
     |> assign(:planned_view_ids, [])
     |> assign(:view_gone_notice, false)
     |> assign(:view_matches_nothing, false)
     |> assign(:soll_refused, nil)}
  end

  # The per-security holdings/valuation is loaded asynchronously, after the
  # socket connects (mirrors the Portfolio page): one ledger read plus the
  # shared quote/FX path, joined onto the tree in memory rather than queried
  # per node (issue #334). It is read in the screen's scope (#1091, pick J10
  # A): under a view, the view valuation's positions grouped by security, so
  # "Positions" and "Value" are about the view the result beside them reads;
  # under Everything, every portfolio's, as before. It starts with the tree,
  # where the scope and the selection are both known.
  defp start_holdings(socket) do
    if connected?(socket) do
      view_id = socket.assigns.active_view_id
      start_async(socket, :holdings, fn -> scoped_holdings(view_id) end)
    else
      socket
    end
  end

  defp scoped_holdings(nil),
    do: {:ok, %{holdings: Valuation.holdings_by_security(), matches_no_accounts: false}}

  defp scoped_holdings(view_id), do: Valuation.holdings_by_security_for_view(view_id)

  # Either read answering that the chosen view is gone degrades the screen
  # (`view_gone/1`); whichever answers first does, the other is dropped.
  @impl true
  def handle_async(read, {:ok, {:error, :view_not_found}}, socket)
      when read in [:holdings, :results],
      do: {:noreply, view_gone(socket)}

  def handle_async(:holdings, {:ok, {:ok, read}}, socket) do
    {:noreply,
     socket
     |> assign(holdings: read.holdings, view_matches_nothing: read.matches_no_accounts)
     |> reload()}
  end

  def handle_async(:holdings, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :error, gettext("Couldn't load current holdings."))}
  end

  # The per-category result (ADR-0041 slice one, #712) loads on its own, after
  # the tree is known: it is keyed by the selected classification and read in
  # the screen's scope. A failure leaves the tree fully usable and simply
  # omits the columns -- the result is an addition to this surface, not a
  # precondition for it.
  def handle_async(:results, {:ok, {:ok, result}}, socket) do
    {:noreply, assign(socket, :results, index_results(result))}
  end

  def handle_async(:results, _other, socket), do: {:noreply, socket}

  # The chosen view was deleted while the page read it (another tab, the
  # API): the screen degrades to Everything with Wealth's notice and reads
  # again, rather than rendering a read that failed. A stale answer of the
  # reads it replaces is dropped by `start_async/3`'s own bookkeeping.
  defp view_gone(socket) do
    socket
    |> assign(
      active_view: nil,
      active_view_id: nil,
      view_gone_notice: true,
      views: Buckets.list_views(),
      soll_plan_id: nil,
      holdings: nil,
      results: nil,
      view_matches_nothing: false
    )
    |> reload()
    |> load_soll()
    |> start_reads()
  end

  # The open tree's two reads, in the screen's scope; a tree that is gone
  # has nothing to read.
  defp start_reads(%{assigns: %{selected_id: classification_id}} = socket)
       when is_integer(classification_id),
       do: socket |> start_holdings() |> start_results(classification_id)

  defp start_reads(socket), do: socket

  @impl true
  def handle_params(params, uri, socket) do
    path = URI.parse(uri).path

    {:noreply,
     socket
     |> assign(:current_path, path)
     |> apply_action(socket.assigns.live_action, params)}
  end

  # The index owns the tree list (ADR-0022): the per-classification tree left
  # the sidebar, so this page is where every tree stays reachable.
  defp apply_action(socket, :index, _params) do
    assign(socket,
      selected_id: nil,
      tree: nil,
      tree_menu_id: nil,
      classifications: Classifications.list_classifications(),
      index_rows: index_rows(socket.assigns.portfolio)
    )
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, selected_id: nil, tree: nil)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    case LiveParam.id(id) do
      classification_id when is_integer(classification_id) ->
        # The screen's scope is the active view (`LiveViewScope`; #1091, pick
        # J10 A): the plan editor edits its plan, and the reads below are
        # made in it. The portfolio page's no-plan hint deep-links here with
        # the switcher's own `?view=`, so the editor opens on the right
        # `(view, classification)` plan (ADR-0020, #468).
        socket
        |> assign(:query, "")
        |> assign(:editing_id, nil)
        |> load_show(classification_id)
        |> load_soll()
        # Started here rather than in load_show/2: reload/1 also calls that, so
        # putting it there recomputed the roll-up on every holdings arrival and
        # every filter change. It depends on the SELECTION, which changes here,
        # and on the composition, which the tree's edits change
        # (`reload_composition/1`, #1110).
        |> start_reads()

      _ ->
        push_navigate(socket, to: "/classifications")
    end
  end

  # #808: one row per tree, built from the reads that already exist —
  # `list_trees/0` carries the categories and the assignments in one pass, and
  # the plan comes from the plan list the SOLL editor already reads. Nothing
  # is recomputed here; the row only says what those reads hold.
  defp index_rows(portfolio) do
    security_count = Catalog.count_securities()

    Enum.map(Classifications.list_trees(), fn tree ->
      assigned = tree.assignments |> Enum.map(& &1.security_id) |> Enum.uniq() |> length()

      %{
        classification: tree.classification,
        category_count: length(tree.categories),
        depth: tree_depth(tree.categories),
        assigned_count: assigned,
        security_count: security_count,
        unassigned_count: max(security_count - assigned, 0),
        plan: index_plan(portfolio, tree.classification.id)
      }
    end)
  end

  # The plan a tree carries, preferring the active one — `list_plans/2` orders
  # active before draft. Plans are portfolio-scoped and this page is not, so
  # it reads the same portfolio the SOLL editor does; with no portfolio there
  # is no plan to name.
  defp index_plan(nil, _classification_id), do: nil

  defp index_plan(portfolio, classification_id) do
    portfolio.id
    |> Targets.list_plans(classification_id: classification_id)
    |> List.first()
  end

  # How many levels the tree actually uses: a flat tree is 1, a tree with
  # children is 2, and so on. A pure fold over the categories the read
  # already loaded.
  defp tree_depth([]), do: 0

  defp tree_depth(categories) do
    parents = Map.new(categories, &{&1.id, &1.parent_id})

    categories
    |> Enum.map(&category_level(&1.id, parents, 1, Classifications.max_tree_depth()))
    |> Enum.max(fn -> 0 end)
  end

  # Bounded, because `parent_id` carries a foreign key and nothing else: a
  # category re-homed under its own descendant is accepted by the ordinary
  # write path, and an unbounded walk over one pins a scheduler on the only
  # page that could undo it. The same guard, and the same number, as
  # `Classifications`' root-path walk.
  defp category_level(_id, _parents, level, 0), do: level

  defp category_level(id, parents, level, depth_left) do
    case Map.get(parents, id) do
      nil -> level
      parent_id -> category_level(parent_id, parents, level + 1, depth_left - 1)
    end
  end

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
      page_title={ClassificationName.display(@tree.classification)}
      page_subtitle={gettext("Organise securities by dragging them between categories")}
    >
      <div
        id="classifications-workspace"
        phx-hook="ClassificationDnD"
        class="workspace-page classifications-detail"
        {workspace_attrs(@tree)}
      >
        <%!-- #1064 (pick J7 = A, board 07): the page's result is an inline
             result — a success a note, a refusal a problem, each with its
             word and glyph; a refusal naming rules keeps its links.
             Focusable (#945, the closing act of PR γ): a plan write's
             refusal is brought into view and focused, because "Save plan"
             sits far below it (`answer_plan_write/1`); a success is not. --%>
        <AppShell.inline_result
          id="classifications-result"
          class="inline-result--page"
          result={page_result(@error, @success)}
          focusable
        />

        <header class="detail-head">
          <h2 id="classification-heading" tabindex="-1">
            <%= ClassificationName.display(@tree.classification) %>
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

        <%!-- #1091 (pick J10 A; board ux-design-2026-10-04/10-category-results):
             the Wealth page's view switcher, unchanged, in a controls row, is
             the screen's one scope. Every figure of a category row, the plan
             editor and the basis line read the view it picks; a chip is a
             navigation through ViewScope, so the choice is the active view on
             Wealth too. Built-in trees, which have no editor, get it as well. --%>
        <div class="workspace-section workspace-section--controls">
          <ViewSwitcher.view_switcher
            current_path={@current_path}
            views={@views}
            active_view={@active_view}
            planned_view_ids={@planned_view_ids}
          />
        </div>

        <%!-- The picked view was deleted while the page read it: the screen
             degraded to Everything, as Wealth does. --%>
        <p :if={@view_gone_notice} class="hint" data-role="view-gone-notice" role="status">
          <%= gettext("The selected view no longer exists — showing Everything.") %>
        </p>

        <%!-- The view resolves to no account, so every figure below is a dash
             for a reason of definition, not of data: Wealth's hint, in its
             words (review round). --%>
        <p :if={@view_matches_nothing} class="hint" data-role="view-matches-nothing" role="status">
          <%= gettext(
            "This view matches no accounts — its included buckets are empty or no longer assigned. Edit the view under Views or tag accounts into its buckets."
          ) %>
        </p>

        <%= if @soll do %>
          <.soll_editor
            soll={@soll}
            scope_name={view_name(@active_view)}
            flat={@tree.flat}
            assigned={@tree.assigned_counts}
            refused={@soll_refused}
          />
        <% end %>

        <%= if @tree.assignable and @tree.flat != [] and @tree.unsorted != [] do %>
          <%!-- A finding is a data note, not an accent banner (UX-DR17); the
               remedy — the Unsorted list below — is the link inside it. --%>
          <div role="status">
            <AppShell.data_note severity={:attention} id="assignment-nudge" data-role="assignment-nudge">
              <%= ngettext(
                "%{count} security is in no category yet and does not count toward the target/actual allocation.",
                "%{count} securities are in no category yet and do not count toward the target/actual allocation.",
                length(@tree.unsorted)
              ) %>
              <a href="#unsorted"><%= gettext("Unsorted") %></a>
            </AppShell.data_note>
          </div>
        <% end %>

        <form id="tree-search-form" phx-change="filter_tree" class="tree-search" data-no-submit>
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

        <form id="current-only-form" phx-change="toggle_current_only" class="tree-toggle" data-no-submit>
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
            <button
              type="button"
              class="button-danger"
              data-unassign-selected
              data-confirm={gettext("Unassign the selected securities from this classification?")}
            >
              <%= gettext("Unassign") %>
            </button>
            <button type="button" data-clear-selection><%= gettext("Clear") %></button>
          </div>

        <% end %>

        <%!-- ADR-0041 §1: the basis is one line, stated once for the surface
              rather than repeated per row or left for the reader to assume —
              the short statement in the line, the full rule behind its ⓘ
              (UX-DR11, issue 805). It opens on the scope every figure under
              it reads (#1091, pick J10 A: "a scoped figure names its view"),
              then their currency (#1048, pick J10.2 A): the result's, never
              assumed. The sentence is one span, so the line's flex row
              wraps it as text, not between the view's name and the rest,
              and a no-break space holds each "·" to the word before it, so
              no line starts with one. --%>
        <div :if={@results} class="summary-basis tree-basis" data-role="category-result-basis">
          <span><%= StoredText.isolate(gettext("View %{name}", name: StoredText.slot(:name)),
              name: view_name(@active_view)
            ) %>&nbsp;· <%= gettext("in %{currency}", currency: @results.base_currency) %>&nbsp;· <%= gettext("Result: today's composition, not a period return") %></span>
          <details class="metric-tooltip metric-tooltip--inline" data-role="category-result-info">
            <summary aria-label={gettext("About the result")}>ⓘ</summary>
            <p role="tooltip">
              <%= gettext(
                "Cost and result cover the positions filed here today, in %{currency} — a statement about the current composition, not a period return. A position whose cost was not paid in %{currency} is left out of both and named above; “Value” still counts it when it has a value.",
                currency: @results.base_currency
              ) %>
            </p>
          </details>
        </div>
        <.excluded_note
          :if={@results}
          excluded={@results.excluded}
          currency={@results.base_currency}
          categories={@tree.flat}
          holdings={@holdings}
        />
        <%!-- #805 (review C8, variant A): the row figures stand in named,
             right-aligned columns under one head; an empty category prints
             "—", never a row of zeros. --%>
        <div class="tree-head" data-role="tree-head">
          <span class="tree-head__name"><%= gettext("Category") %></span>
          <span class="tree-head__num"><%= gettext("Positions") %></span>
          <span class="tree-head__num"><%= gettext("Value") %></span>
          <span class="tree-head__num"><%= gettext("Cost") %></span>
          <span class="tree-head__num"><%= gettext("Result") %></span>
          <span class="tree-head__actions" aria-hidden="true"></span>
        </div>
        <section class="tree">
          <%= for node <- @tree.nodes do %>
            <.category_node
              node={node}
              classification_id={@tree.classification.id}
              editable={@tree.editable}
              assignable={@tree.assignable}
              editing_id={@editing_id}
              filtering={@tree.filtering?}
              results={@results}
              view_scoped={not is_nil(@active_view)}
            />
          <% end %>
          <%= if @tree.nodes == [] and not @tree.filtering? do %>
            <p class="hint"><%= gettext("No categories yet.") %></p>
          <% end %>
          <%= if @tree.filtering? and @tree.nodes == [] and @tree.unsorted == [] do %>
            <p class="hint"><%= gettext("No securities match the search.") %></p>
          <% end %>
        </section>

        <details id="unsorted" class="cat-node unsorted-node" open={@tree.filtering?} {unsorted_attrs(@tree)}>
          <summary class="cat-summary">
            <span class="cat-name">
              <span class="cat-swatch is-empty" aria-hidden="true"></span>
              <span class="cat-name__text"><%= gettext("Unsorted") %></span>
              <%!-- The unsorted securities "current positions only" hides,
                   counted as a category counts them: under a view the ones
                   the view holds none of (review round), under Everything
                   the ones no longer held (the closing act of PR γ). --%>
              <span
                :if={@tree.unsorted_row.hidden > 0}
                class="cat-without-holdings"
                data-role="without-holdings"
                title={unsorted_hidden_title(not is_nil(@active_view))}
              >+<%= @tree.unsorted_row.hidden %> <%= hidden_label(not is_nil(@active_view)) %></span>
            </span>
            <span class="cat-positions" data-role="unsorted-positions">
              <%= length(@tree.unsorted_row.securities) %>
            </span>
            <span class="cat-value" data-role="unsorted-value">
              <.figure value={unsorted_total(@tree.unsorted_row.securities)} />
            </span>
            <span class="cat-invested" data-role="unsorted-invested"><.not_computable /></span>
            <span class="cat-result" data-role="unsorted-result"><.not_computable /></span>
            <span class="cat-actions" aria-hidden="true"></span>
          </summary>
          <div class="cat-body">
            <ul class="cat-securities">
              <%= for security <- @tree.unsorted_row.securities do %>
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
        <AppShell.inline_result
          id="classifications-result"
          class="inline-result--page"
          result={page_result(@error, nil)}
        />
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
        <%!-- #808 (review C11): the index is the door to a tree, so each row
             says what that tree holds — its size, its assignment state and
             whether it carries a plan. The "choose a tree" sentence is gone
             (issue 791) and the full-width button is a + in the heading. --%>
        <section class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Classifications") %></h2>
            <div class="section-head-controls">
              <.link
                navigate="/classifications/new"
                id="new-classification"
                class="icon-button"
                aria-label={gettext("New classification")}
                title={gettext("New classification")}
              >
                <AppShell.icon name={:plus} />
              </.link>
            </div>
          </header>

          <%!-- The shipped list-row anatomy of the Views page (issue 802,
               DESIGN.md → Components → bucket-list): name over its facts, the
               short figure right, the actions behind the kebab. No new
               component is invented for this index. --%>
          <p :if={@index_rows == []} class="empty-state" role="status">
            <%= gettext("No classification trees yet.") %>
          </p>
          <ul
            :if={@index_rows != []}
            id="classification-index"
            class="bucket-list"
            role="list"
            data-role="classification-index"
          >
            <li
              :for={row <- @index_rows}
              id={"classification-row-#{row.classification.id}"}
              class="bucket-list__item"
              data-role="classification-row"
            >
              <div class="bucket-list__main">
                <span class="bucket-list__name">
                  <.link navigate={"/classifications/#{row.classification.id}"}>
                    <%= ClassificationName.display(row.classification) %>
                  </.link>
                  <span :if={row.classification.built_in} class="badge"><%= gettext("Built-in") %></span>
                </span>
                <span class="bucket-list__rule" data-role="tree-categories">
                  <%= ngettext("%{count} category", "%{count} categories", row.category_count,
                    count: row.category_count
                  ) %>
                  <%= if row.depth > 1 do %>
                    · <%= ngettext("%{count} level", "%{count} levels", row.depth, count: row.depth) %>
                  <% end %>
                </span>
                <span class="bucket-list__usage">
                  <span data-role="tree-assigned">
                    <%= gettext("%{assigned} of %{total} securities assigned",
                      assigned: row.assigned_count,
                      total: row.security_count
                    ) %>
                  </span>
                  <%!-- The unassigned count is the state worth acting on, so
                       it reads as a word rather than as a third bare
                       number. --%>
                  <%!-- A plain badge: `badge--derived` carries issue 700's
                       "shown but never shown as stated" contract — the
                       visually-hidden "Derived:" qualifier and the ≈ marker —
                       and an unassigned count is a stated fact, not a derived
                       one. --%>
                  <span
                    :if={row.unassigned_count > 0}
                    class="badge badge-warning"
                    data-role="tree-unassigned"
                  >
                    <%= ngettext(
                      "%{count} unassigned",
                      "%{count} unassigned",
                      row.unassigned_count,
                      count: row.unassigned_count
                    ) %>
                  </span>
                </span>
                <span class="bucket-list__usage" data-role="tree-plan-name">
                  <%= if row.plan do %>
                    <%= gettext("Plan: %{name}", name: row.plan.name) %>
                  <% end %>
                </span>
              </div>

              <%!-- DESIGN.md → bucket-list.figures: the trailing slot is
                   `white-space: nowrap`, so a user-named plan clipped at
                   390 px and took the status word with it. The name lives in
                   `__main`, where it wraps; the slot keeps the short status
                   word it was built for. --%>
              <span class="bucket-list__figures" data-role="tree-plan">
                <%= if row.plan do %>
                  <%= plan_status_label(row.plan.status) %>
                <% else %>
                  <%= gettext("No plan") %>
                <% end %>
              </span>

              <AppShell.row_kebab
                id={"tree-kebab-#{row.classification.id}"}
                row={ClassificationName.display(row.classification)}
                open={@tree_menu_id == row.classification.id}
                phx-click="open_tree_menu"
                phx-value-id={row.classification.id}
              />
            </li>
          </ul>

          <% open_row = @tree_menu_id && Enum.find(@index_rows, &(&1.classification.id == @tree_menu_id)) %>
          <AppShell.row_menu
            :if={open_row}
            id={"tree-row-menu-#{open_row.classification.id}"}
            trigger={"tree-kebab-#{open_row.classification.id}"}
            label={gettext("Classification actions")}
          >
            <.link
              navigate={"/classifications/#{open_row.classification.id}"}
              id={"tree-open-#{open_row.classification.id}"}
              class="row-context-menu__item"
              role="menuitem"
            >
              <AppShell.icon name={:external_link} />
              <%= gettext("Open") %>
            </.link>
            <button
              :if={not open_row.classification.built_in}
              type="button"
              id={"tree-delete-#{open_row.classification.id}"}
              class="row-context-menu__item row-context-menu__item--danger"
              role="menuitem"
              phx-click="delete_classification_row"
              phx-value-id={open_row.classification.id}
              data-confirm={gettext("Delete this classification and all its categories?")}
            >
              <AppShell.icon name={:trash} />
              <%= gettext("Delete") %>
            </button>
          </AppShell.row_menu>
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
      data-security-id={@security.id}
      data-role="security-row"
    >
      <span class="row-name" title={@security.name}><%= @security.name %></span>
      <%= if @security.ticker_symbol not in [nil, ""] do %>
        <small class="row-ticker"><%= @security.ticker_symbol %></small>
      <% end %>
      <small class="row-ccy"><%= @security.currency_code %></small>
      <span
        :if={match?(%Decimal{}, @security.quantity) and Decimal.compare(@security.quantity, 0) == :lt}
        class="negative-holding-chip"
        data-role="negative-holding"
        title={
          gettext(
            "The derived holding quantity is negative — likely an unmodeled corporate action from an imported history. Repair the security's transaction history."
          )
        }
      >
        <%= gettext("negative quantity") %>
      </span>
      <span class="row-quantity" data-role="security-quantity">
        <%= Format.money(@security.quantity) %>
      </span>
      <span class="row-value" data-role="security-value">
        <%= Format.money(@security.market_value) %>
      </span>
    </li>
    """
  end

  # #1048 (pick J10.2 A; board ux-design-2026-10-04/10-category-results ②):
  # the members the roll-up leaves out of "Cost" and "Result" are named where
  # the totals are read -- one attention data note between the basis line and
  # the tree head, in a status region that is there whenever the result is,
  # so the note's arrival is announced (UX-DR25). It gives each member's
  # category, and the cost it was paid in its own currency (clause 2, never
  # converted) or its reason in words. It has no control, because there is
  # nothing to fix here (clause 3). A member is said to be in "Value" exactly
  # when the valuation that column reads gives it a value, whatever its reason
  # (UX-DR26): never of a member whose row prints "—". Past one member the
  # names sit in a disclosure as aligned lines, the trades facet's
  # unmatched-sells shape. The category names come from the tree on screen.
  # Nothing excluded, no note: UX-DR2 has no all-clear.
  attr(:excluded, :list, required: true)
  attr(:currency, :string, required: true)
  attr(:categories, :list, required: true)
  attr(:holdings, :map, default: nil)

  defp excluded_note(assigns) do
    assigns =
      assigns
      |> assign(
        :names,
        Map.new(assigns.categories, fn {category, _} -> {category.id, category.name} end)
      )
      |> assign(:count, length(assigns.excluded))
      |> assign(:paid_elsewhere, Enum.count(assigns.excluded, &paid_elsewhere?/1))
      |> assign(:valued, Enum.count(assigns.excluded, &valued?(&1, assigns.holdings)))
      |> assign(:single, single_member(assigns.excluded))

    ~H"""
    <div role="status" data-role="category-result-excluded-region">
      <AppShell.data_note
        :if={@excluded != []}
        severity={:attention}
        data-role="category-result-excluded"
      >
        <%= if @single do %>
          <%= single_excluded_lead(@single, @currency) %>
          <bdi><%= @single.security_name %></bdi><%= excluded_tail(@single, @names, @currency) %>
          <%= excluded_value_sentence(1, @valued) %>
        <% else %>
          <%= excluded_lead(@count, @paid_elsewhere, @currency) %>
          <%= excluded_value_sentence(@count, @valued) %>
          <details class="perf-table-disclosure" data-role="category-result-excluded-list">
            <summary class="disclosure-summary">
              <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
              <%= ngettext("The position", "The %{count} positions", @count) %>
            </summary>
            <ul class="excluded-list">
              <li :for={member <- @excluded}>
                <bdi><%= member.security_name %></bdi>
                <span><%= Map.get(@names, member.category_id) %></span>
                <.excluded_line_cost
                  member={member}
                  currency={@currency}
                  lead_says_why={@paid_elsewhere == @count}
                />
              </li>
            </ul>
          </details>
        <% end %>
      </AppShell.data_note>
    </div>
    """
  end

  defp single_member([member]), do: member
  defp single_member(_members), do: nil

  # A member out only because its cost was not paid in the result's currency
  # carries that cost; every other exclusion carries none.
  defp paid_elsewhere?(member), do: member.native_costs != []

  # In "Value" exactly when the valuation that column reads values it: the
  # screen's holdings map, keyed by security (nil until it has loaded).
  defp valued?(member, holdings),
    do: match?(%{market_value: %Decimal{}}, Map.get(holdings || %{}, member.security_id))

  defp single_excluded_lead(member, currency) do
    cond do
      Enum.any?(member.native_costs, &(&1.currency == currency)) ->
        gettext(
          "1 position is not included in “Cost” and “Result” because its cost was not paid in %{currency} alone:",
          currency: currency
        )

      paid_elsewhere?(member) ->
        gettext(
          "1 position is not included in “Cost” and “Result” because its cost was not paid in %{currency}:",
          currency: currency
        )

      true ->
        gettext("1 position is not included in “Cost” and “Result”:")
    end
  end

  # The single member's name is the caller's <bdi>; this is the rest of its
  # clause: the category it is filed under, then its cost or its reason.
  defp excluded_tail(member, names, currency) do
    category =
      case Map.get(names, member.category_id) do
        nil -> ""
        name -> " (#{name})"
      end

    "#{category}, #{cost_or_reason(member, currency)}."
  end

  # Past one member: the count, with the currency's reason when it is every
  # member's.
  defp excluded_lead(count, count, currency),
    do:
      ngettext(
        "%{count} position is not included in “Cost” and “Result” because its cost was not paid in %{currency}.",
        "%{count} positions are not included in “Cost” and “Result” because their cost was not paid in %{currency}.",
        count,
        currency: currency
      )

  defp excluded_lead(count, _paid_elsewhere, _currency),
    do:
      ngettext(
        "%{count} position is not included in “Cost” and “Result”.",
        "%{count} positions are not included in “Cost” and “Result”.",
        count
      )

  # Whether "Value" counts them: every one, some, or none of the members.
  defp excluded_value_sentence(_count, 0), do: nil

  defp excluded_value_sentence(count, count),
    do: ngettext("It is included in “Value”.", "They are included in “Value”.", count)

  defp excluded_value_sentence(_count, valued),
    do:
      ngettext(
        "%{count} of them is included in “Value”.",
        "%{count} of them are included in “Value”.",
        valued
      )

  # The native cost, one amount per currency, each in the currency it was
  # paid in -- never converted (UX-DR25 clause 2) -- in money's two
  # decimals. Otherwise the reason.
  defp cost_or_reason(%{native_costs: [_ | _] = costs}, _currency),
    do: gettext("cost %{amount}", amount: native_amounts(costs))

  defp cost_or_reason(member, currency), do: excluded_reason(member.reason, currency)

  attr(:member, :map, required: true)
  attr(:currency, :string, required: true)
  attr(:lead_says_why, :boolean, required: true)

  # A disclosure line's third cell. Under the lead that names the currency
  # for every member, the cost alone, one unbroken `num` cell; a reason in
  # words is a plain cell. Under the generic lead, whose members are out for
  # different reasons, a cost carries its reason too, as every other line
  # does (closing act, UAT): "not paid in EUR", or "not paid in EUR alone"
  # where EUR is among the costs, the one-member sentence's distinction.
  # That line is too long to stay unbroken at 390 px, where `.num`'s nowrap
  # pushed it past the note's edge (closing act's screenshots): only each
  # amount is a `num` span, and the rest of the line wraps.
  # A cost in two currencies is long without its reason too, so under the
  # currency's lead it wraps between its amounts the same way.
  defp excluded_line_cost(
         %{member: %{native_costs: [_ | _] = costs}, lead_says_why: lead_says_why} = assigns
       )
       when not lead_says_why or length(costs) > 1 do
    assigns =
      assign(
        assigns,
        :segments,
        line_cost_segments(costs, assigns.currency, not lead_says_why)
      )

    ~H"""
    <span><%= for segment <- @segments do %><%= case segment do %><% {:amount, amount} -> %><span class="num"><%= amount %></span><% text -> %><%= text %><% end %><% end %></span>
    """
  end

  defp excluded_line_cost(assigns) do
    ~H"""
    <span class={paid_elsewhere?(@member) && "num"}><%= cost_or_reason(@member, @currency) %></span>
    """
  end

  # A placeholder no translation can carry: the sentence is split on it, so
  # the amounts take its place as their own spans and nothing else of the
  # translation is read as markup.
  @amount_marker "\u0000"

  # The sentence's text around the amounts, with each amount as
  # `{:amount, text}` and " + " between them; the reason only when the lead
  # does not already give it.
  defp line_cost_segments(costs, currency, with_reason?) do
    sentence =
      cond do
        not with_reason? ->
          gettext("cost %{amount}", amount: @amount_marker)

        Enum.any?(costs, &(&1.currency == currency)) ->
          gettext("cost %{amount}, not paid in %{currency} alone",
            amount: @amount_marker,
            currency: currency
          )

        true ->
          gettext("cost %{amount}, not paid in %{currency}",
            amount: @amount_marker,
            currency: currency
          )
      end

    amounts = costs |> Enum.map(&{:amount, native_amount(&1)}) |> Enum.intersperse(" + ")

    sentence
    |> String.split(@amount_marker)
    |> Enum.intersperse(:amounts)
    |> Enum.flat_map(fn
      :amounts -> amounts
      "" -> []
      text -> [text]
    end)
  end

  defp native_amounts(costs), do: Enum.map_join(costs, " + ", &native_amount/1)

  defp native_amount(cost), do: "#{Format.money(cost.amount)} #{cost.currency}"

  # Every reason the roll-up names (ADR-0033's `undecomposed_reason`, and the
  # roll-up's own `no_usable_price`), in words.
  defp excluded_reason(reason, _currency) when reason in [:no_usable_price, :no_price],
    do: gettext("no usable price")

  defp excluded_reason(:missing_native_cost, _currency),
    do: gettext("no cost derivable from its bookings")

  # Relative to the portfolio's base currency (ADR-0033), which need not be
  # the result's.
  defp excluded_reason(:missing_base_cost, _currency),
    do: gettext("no cost derivable in its portfolio's base currency")

  defp excluded_reason(:missing_fx, _currency), do: gettext("no stored exchange rate")

  defp category_node(assigns) do
    ~H"""
    <details class="cat-node" open={@filtering} {category_attrs(@assignable, @classification_id, @node.category.id)}>
      <summary class="cat-summary">
        <span class="cat-name">
          <span class="cat-swatch" style={swatch(@node.category.color)} aria-hidden="true"></span>
          <%!-- A clipped name stays recoverable: the ellipsis is CSS, the
               full name is the title (issue 805 fix round). --%>
          <span class="cat-name__text" title={@node.category.name}><%= @node.category.name %></span>
          <%= if @node.category.description not in [nil, ""] do %>
            <small class="cat-description-inline"><%= @node.category.description %></small>
          <% end %>
          <%!-- The hidden-positions count is a suffix of the name (#805),
               not a seventh figure in the row. Under a view it counts the
               members the view holds none of -- held outside it or nowhere --
               as "not in the view" (#1091, pick J10 A). --%>
          <%= if hidden_count(@node) > 0 do %>
            <span
              class="cat-without-holdings"
              data-role="without-holdings"
              title={hidden_title(@view_scoped)}
            >+<%= hidden_count(@node) %> <%= hidden_label(@view_scoped) %></span>
          <% end %>
        </span>
        <span
          class="cat-positions"
          data-role="category-positions"
          title={gettext("Visible positions in this category and its sub-categories")}
        ><%= total_count(@node) %></span>
        <span class="cat-value" data-role="category-value" title={gettext("EUR value of the visible positions")}>
          <.figure value={visible_value(@node)} />
        </span>
        <%!-- Per-category result (ADR-0041 slice one, #712). A dash until the
              async load lands and for a category with nothing invested: a
              category with no cost has no result to state, and a zero would
              claim it is flat. --%>
        <%= if result = stated_result(@results, @node.category.id) do %>
          <span
            class="cat-invested"
            data-role="category-invested"
            title={gettext("What the positions filed here cost, in EUR")}
          >
            <%= Format.money(result.invested) %>
          </span>
          <span
            class={["cat-result", result_tone(result.result_abs)]}
            data-role="category-result"
            title={
              gettext(
                "Current value minus cost, over the positions filed here today. Money-weighted: the sum of results divided by the sum invested."
              )
            }
          >
            <b><%= Format.signed_decimal(result.result_abs, 2) %></b>
            <small><%= result_percent(result.result_pct) %></small>
            <%!-- ADR-0041 §4: a partial sum never presents itself as complete. --%>
            <span
              :if={result.covered_count < result.member_count}
              class="cat-result-partial"
              data-role="category-result-partial"
              title={
                gettext(
                  "Some positions here are left out of both sides of the sum, rather than counted as zero, because no result in %{currency} is derivable for them.",
                  currency: @results.base_currency
                )
              }
            ><%= result.covered_count %>/<%= result.member_count %></span>
          </span>
        <% else %>
          <span class="cat-invested" data-role="category-invested"><.not_computable /></span>
          <span class="cat-result" data-role="category-result"><.not_computable /></span>
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
          <%!-- E25 S7, G20; pick G12.2 = B: marked where it is renamed. --%>
          <AppShell.invisible_text_note subject={:name} texts={[@node.category.name]}>
            <%= gettext("Typed in anew, it is clean.") %>
          </AppShell.invisible_text_note>
        <% end %>
        <%= if @editing_id == @node.category.id and not @editable do %>
          <form id={"recolor-form-#{@node.category.id}"} phx-change="recolor_category" class="cat-edit-form">
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
            results={@results}
            view_scoped={@view_scoped}
          />
        <% end %>
      </div>
    </details>
    """
  end

  # The view-bound SOLL plan editor (ADR-0020, issue #467). It edits the plan
  # of the view the screen reads -- the view switcher's (#1091, pick J10 A;
  # its own select is gone) -- and defines, edits, copies or clears that
  # `(view, classification)` plan's per-category target weights plus its
  # cash target, with a live Σ badge and per-parent consistency hints. Its
  # head states the scope it edits as text. Weights are entered and shown as
  # percentages; the context stores fractions in [0, 1].
  attr(:soll, :map, required: true)
  attr(:scope_name, :string, required: true)
  attr(:flat, :list, required: true)
  attr(:assigned, :map, required: true)

  # The id of the input the last save's refusal names (#945; the closing act
  # of PR γ), or nil: that input is marked invalid and described by the
  # page's problem note.
  attr(:refused, :string, default: nil)

  defp soll_editor(assigns) do
    ~H"""
    <section id="soll-editor" class="workspace-section soll-editor">
      <header class="soll-editor__head">
        <h2 id="soll-editor-heading" tabindex="-1"><%= gettext("Target plan") %></h2>
        <span class="soll-editor__scope" data-role="soll-editor-scope">
          <%= StoredText.isolate(gettext("for view %{name}", name: StoredText.slot(:name)),
            name: @scope_name
          ) %>
        </span>
      </header>

      <%!-- Plan versions (ADR-0027): pick the version to edit, duplicate the
           current one into a draft, activate a draft. Only the active plan
           steers the Wealth page; drafts are edited silently beside it. --%>
      <%= if length(@soll.plans) > 0 do %>
        <div class="soll-plan-versions">
          <%= if length(@soll.plans) > 1 do %>
            <form id="soll-plan-picker-form" phx-change="select_soll_plan" class="soll-plan-picker" data-no-submit>
              <label class="soll-view-picker__label" for="soll-plan-select">
                <%= gettext("Plan version:") %>
              </label>
              <select id="soll-plan-select" name="soll_plan">
                <%= for plan <- @soll.plans do %>
                  <option value={plan.id} selected={@soll.plan && @soll.plan.id == plan.id}>
                    <%= plan.name %> · <%= plan_status_label(plan.status) %>
                  </option>
                <% end %>
              </select>
            </form>
          <% else %>
            <span class="muted" data-role="soll-plan-name">
              <%= @soll.plan && @soll.plan.name %>
            </span>
          <% end %>
          <button type="button" class="button" phx-click="duplicate_soll_plan">
            <%= gettext("Duplicate plan") %>
          </button>
          <%= if @soll.plan do %>
            <%!-- #873: the one disclosure marker (#854), never the browser's
                 triangle; the accent colour stays, because Rename opens an
                 action, as "Positions (n)" beside it does. --%>
            <details class="plan-rename">
              <summary class="disclosure-summary">
                <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
                <%= gettext("Rename") %>
              </summary>
              <form phx-submit="rename_soll_plan">
                <label class="sr-only" for="plan-rename-input"><%= gettext("New plan name") %></label>
                <input
                  id="plan-rename-input"
                  type="text"
                  name="plan_name"
                  value={@soll.plan.name}
                  maxlength="120"
                  required
                />
                <button type="submit" class="button"><%= gettext("Save name") %></button>
              </form>
            </details>
          <% end %>
          <%= if @soll.editing_version? do %>
            <button type="button" class="button-primary" phx-click="activate_soll_plan">
              <%= gettext("Activate this plan") %>
            </button>
            <span class="hint" data-role="soll-version-hint">
              <%= version_hint(@soll.plan.status) %>
            </span>
          <% end %>
        </div>
      <% end %>

      <%= if @soll.exists do %>
        <%!-- #945 (board 08.5): the plan inputs carry `step="any"` and no
             `min` or `max`. The browser's own range and step checks would
             block the submit with its generic message, so the store's
             refusal, which names the row, would never be read; the store
             decides (0–100 %, four decimal places in percent). --%>
        <form id="soll-plan-form" phx-change="soll_sum" phx-submit="save_soll_plan">
          <div class="data-table-wrapper">
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
                      <%!-- #481 (pick F2-A): the category's positions, in the
                           same form — one save, one live Σ. --%>
                      <button
                        :if={Map.get(@soll.members, category.id, []) != []}
                        type="button"
                        id={"soll-positions-toggle-#{category.id}"}
                        class="disclosure-button soll-positions-toggle"
                        phx-click="toggle_soll_positions"
                        phx-value-id={category.id}
                        aria-expanded={to_string(MapSet.member?(@soll.expanded, category.id))}
                        aria-controls={"soll-positions-#{category.id}"}
                      >
                        <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
                        <%= ngettext(
                          "Position (%{count})",
                          "Positions (%{count})",
                          length(Map.get(@soll.members, category.id, []))
                        ) %>
                      </button>
                      <span
                        :if={position_sum(@soll, category.id)}
                        class="hint soll-row__follows"
                        data-role="soll-position-hint"
                      >
                        <%= gettext("Sum of the position targets — the category follows it") %>
                      </span>
                    </th>
                    <td class="num">
                      <%= case position_sum(@soll, category.id) do %>
                        <% nil -> %>
                          <label class="sr-only" for={"soll-weight-#{category.id}"}>
                            <%= gettext("Target weight for %{name}", name: category.name) %>
                          </label>
                          <input
                            type="number"
                            id={"soll-weight-#{category.id}"}
                            name={"weights[#{category.id}]"}
                            value={Map.get(@soll.weights, category.id, "")}
                            step="any"
                            inputmode="decimal"
                            {refused_attrs(@refused, "soll-weight-#{category.id}")}
                          />
                        <% sum -> %>
                          <%!-- ADR-0030 §2: once a position carries a target
                               the category IS the sum of its positions — shown,
                               not entered. --%>
                          <output
                            id={"soll-position-sum-#{category.id}"}
                            class="soll-position-sum"
                            aria-label={gettext("Σ positions for %{name}", name: category.name)}
                          ><%= format_sum(sum) %></output>
                      <% end %>
                    </td>
                  </tr>
                  <tr
                    :for={member <- Map.get(@soll.members, category.id, [])}
                    class="soll-row soll-row--position"
                    data-category={category.id}
                    hidden={not MapSet.member?(@soll.expanded, category.id)}
                  >
                    <th scope="row" class="soll-row__name soll-row__name--position">
                      <span aria-hidden="true"><%= indent(depth + 1) %></span><%= member.name %>
                    </th>
                    <td class="num">
                      <label class="sr-only" for={"soll-position-#{category.id}-#{member.id}"}>
                        <%= gettext("Position target for %{name}", name: member.name) %>
                      </label>
                      <input
                        type="number"
                        id={"soll-position-#{category.id}-#{member.id}"}
                        name={"positions[#{category.id}][#{member.id}]"}
                        value={@soll.position_weights |> Map.get(category.id, %{}) |> Map.get(member.id, "")}
                        step="any"
                        inputmode="decimal"
                        {refused_attrs(@refused, "soll-position-#{category.id}-#{member.id}")}
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
                      step="any"
                      inputmode="decimal"
                      disabled={@soll.editing_version?}
                      aria-invalid={@refused == "soll-cash-target" && "true"}
                      aria-describedby={cash_describedby(@soll, @refused)}
                    />
                    <span
                      :if={@soll.editing_version?}
                      class="hint"
                      id="soll-cash-lock-hint"
                      data-role="soll-cash-lock-hint"
                    >
                      <%= gettext("Follows the active plan until this version is activated") %>
                    </span>
                  </td>
                </tr>
              </tbody>
              <%!-- #969, pick H8.4 = A (board 08-dialogs-copy; ADR-0040 §3,
                   DESIGN.md D3): ✓ only at exactly 100 %, ✗ and the warning
                   colour only above it; under 100 % the Σ carries no mark and
                   the gap is the last row, muted, arithmetic, not an input. --%>
              <tfoot>
                <tr class={["soll-row", "soll-row--sum", @soll.mismatch? && "is-target-mismatch"]}>
                  <th scope="row"><%= gettext("Σ") %></th>
                  <td class="num" data-role="soll-sum">
                    <%= @soll.sum %>%
                    <span :if={@soll.complete?} class="soll-ok" aria-hidden="true">✓</span>
                    <span :if={@soll.mismatch?} class="soll-bad" aria-hidden="true">✗</span>
                  </td>
                </tr>
                <tr :if={@soll.remainder} class="soll-row soll-row--remainder">
                  <th scope="row"><%= gettext("Not allocated") %></th>
                  <td class="num" data-role="soll-remainder"><%= @soll.remainder %>%</td>
                </tr>
              </tfoot>
            </table>
          </div>

          <div class="soll-editor__actions">
            <button type="submit" class="button-primary"><%= gettext("Save plan") %></button>
            <button
              type="button"
              class="button-danger"
              phx-click="delete_soll_plan"
              data-confirm={gettext("Delete this view's plan? The Wealth page falls back to actual-only for it.")}
            >
              <%= gettext("Delete plan") %>
            </button>
          </div>
        </form>

        <%= if @soll.copy_sources != [] do %>
          <form id="soll-copy-form" phx-change="copy_soll_plan" class="soll-copy" data-no-submit>
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
            <%= gettext("No plan for this view.") %>
          </p>
          <div class="soll-editor__actions">
            <button type="button" class="button-primary" phx-click="create_soll_plan">
              <%= gettext("Create plan") %>
            </button>
          </div>
          <%= if @soll.copy_sources != [] do %>
            <form id="soll-copy-form-empty" phx-change="copy_soll_plan" class="soll-copy" data-no-submit>
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
  # The result's dismiss (#1064): the slot empties until the next action.
  # The focus may have sat on the slot (a refusal takes it), so it goes back
  # where the operator was editing: the input the refusal named, else the
  # plan editor's heading, else the tree's own (cascade layer 2 of the PR γ
  # closing act; the component-wide case, a dismiss on any page, is issue
  # 1166).
  def handle_event("dismiss_result", _params, socket) do
    target = dismiss_focus(socket.assigns)

    socket =
      socket
      |> assign(error: nil, success: nil, soll_refused: nil)
      |> focus_into_view(target)

    {:noreply, socket}
  end

  def handle_event("create_classification", %{"classification" => params}, socket) do
    case Classifications.create_classification(Actor.owner_ui(), LiveParam.map(params)) do
      {:ok, classification} ->
        {:noreply, push_navigate(socket, to: "/classifications/#{classification.id}")}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event("create_category", %{"category" => params}, socket) do
    case Classifications.create_category(Actor.owner_ui(), LiveParam.map(params)) do
      {:ok, _category} ->
        {:noreply, socket |> success(gettext("Category created")) |> reload_composition()}

      {:error, reason} ->
        {:noreply, failure(socket, error_message(reason))}
    end
  end

  def handle_event("edit_category", %{"id" => id}, socket) do
    case LiveParam.fetch_id(id) do
      {:ok, category_id} -> {:noreply, assign(socket, :editing_id, category_id)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_category", _params, socket) do
    {:noreply, assign(socket, :editing_id, nil)}
  end

  def handle_event("update_category", %{"category" => %{"id" => id} = params}, socket) do
    with {:ok, category_id} <- LiveParam.fetch_id(id),
         category when not is_nil(category) <- Classifications.get_category(category_id),
         {:ok, updated} <- Classifications.update_category(Actor.owner_ui(), category, params) do
      {:noreply,
       socket
       |> assign(:editing_id, nil)
       |> success(gettext("Category updated"))
       |> reload_after_update(category, updated)}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("recolor_category", %{"category_id" => id, "color" => color}, socket) do
    with {:ok, category_id} <- LiveParam.fetch_id(id),
         category when not is_nil(category) <- Classifications.get_category(category_id),
         {:ok, _} <- Classifications.recolor_category(Actor.owner_ui(), category, color) do
      {:noreply, reload(socket)}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    with {:ok, category_id} <- LiveParam.fetch_id(id),
         category when not is_nil(category) <- Classifications.get_category(category_id),
         {:ok, _} <- Classifications.delete_category(Actor.owner_ui(), category) do
      {:noreply, socket |> success(gettext("Category deleted")) |> reload_composition()}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      _ -> {:noreply, socket}
    end
  end

  # #808: the index row's kebab. Delete goes through the same context call the
  # detail head uses; only the id travels differently, because the index has
  # no selected tree.
  def handle_event("open_tree_menu", %{"id" => id_str}, socket) do
    case LiveParam.id(id_str) do
      nil -> {:noreply, socket}
      id -> {:noreply, assign(socket, :tree_menu_id, id)}
    end
  end

  def handle_event("close_row_menu", _params, socket) do
    {:noreply, assign(socket, :tree_menu_id, nil)}
  end

  def handle_event("delete_classification_row", %{"id" => id_str}, socket) do
    with {:ok, id} <- LiveParam.fetch_id(id_str),
         classification when not is_nil(classification) <- Classifications.get_classification(id),
         {:ok, _} <- Classifications.delete_classification(Actor.owner_ui(), classification) do
      {:noreply, push_navigate(socket, to: "/classifications")}
    else
      {:error, reason} ->
        {:noreply, socket |> assign(:tree_menu_id, nil) |> failure(error_message(reason))}

      _ ->
        {:noreply, assign(socket, :tree_menu_id, nil)}
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

  # -- plan versions (ADR-0027) ----------------------------------------------

  # Another version's inputs carry no refusal: the mark goes with the
  # refusal it described (cascade layer 2 of the PR γ closing act).
  def handle_event("select_soll_plan", %{"soll_plan" => value}, socket) do
    case LiveParam.id(value) do
      nil ->
        {:noreply, socket}

      plan_id ->
        {:noreply, socket |> assign(soll_plan_id: plan_id, soll_refused: nil) |> load_soll()}
    end
  end

  def handle_event("duplicate_soll_plan", _params, socket) do
    with %{plan: %{id: plan_id}} <- socket.assigns.soll,
         {:ok, copy} <- Targets.duplicate_plan(Actor.owner_ui(), plan_id) do
      {:noreply,
       socket
       |> assign(:soll_plan_id, copy.id)
       |> success(gettext("Plan duplicated as draft"))
       |> load_soll()}
    else
      _ -> {:noreply, failure(socket, gettext("Could not duplicate the plan"))}
    end
  end

  def handle_event("activate_soll_plan", _params, socket) do
    with %{plan: %{id: plan_id}} <- socket.assigns.soll,
         {:ok, activated} <- Targets.activate_plan(Actor.owner_ui(), plan_id) do
      {:noreply,
       socket
       |> assign(:soll_plan_id, activated.id)
       |> success(gettext("Plan activated"))
       |> load_soll()}
    else
      _ -> {:noreply, failure(socket, gettext("Could not activate the plan"))}
    end
  end

  def handle_event("rename_soll_plan", %{"plan_name" => name}, socket) when is_binary(name) do
    with %{plan: %{id: plan_id}} <- socket.assigns.soll,
         {:ok, renamed} <- Targets.rename_plan(Actor.owner_ui(), plan_id, String.trim(name)) do
      {:noreply,
       socket
       |> assign(:soll_plan_id, renamed.id)
       |> success(gettext("Plan renamed"))
       |> load_soll()}
    else
      _ -> {:noreply, failure(socket, gettext("Could not rename the plan"))}
    end
  end

  # The three plan writes name the active view; each checks first that it
  # still exists (`unless_view_gone/3`), and each refusal is brought into
  # view (`answer_plan_write/1`).
  def handle_event("create_soll_plan", _params, socket),
    do:
      socket
      |> unless_view_gone(:create, fn -> create_soll_plan(socket) end)
      |> answer_plan_write()

  # Live Σ: recompute the running total (categories + cash) from the form as the
  # maintainer types, without persisting anything.
  def handle_event("soll_sum", params, %{assigns: %{soll: %{} = soll}} = socket) do
    {:noreply, assign(socket, :soll, recompute_soll_sum(soll, params))}
  end

  def handle_event("save_soll_plan", params, socket),
    do:
      socket
      |> unless_view_gone(:save, fn -> save_soll_plan(socket, params) end)
      |> answer_plan_write()

  # #481: a category's position rows open and close in place; closed rows
  # stay in the form (hidden), so closing never reads as clearing.
  def handle_event("toggle_soll_positions", %{"id" => id}, socket) do
    with {:ok, category_id} <- LiveParam.fetch_id(id),
         %{expanded: expanded} = soll <- socket.assigns.soll do
      expanded =
        if MapSet.member?(expanded, category_id),
          do: MapSet.delete(expanded, category_id),
          else: MapSet.put(expanded, category_id)

      {:noreply, assign(socket, :soll, %{soll | expanded: expanded})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_soll_plan", _params, socket),
    do:
      socket
      |> unless_view_gone(:delete, fn -> delete_soll_plan(socket) end)
      |> answer_plan_write()

  # Prefill the editor from another view's plan for the same classification,
  # without persisting until the maintainer saves.
  def handle_event("copy_soll_plan", %{"copy_from" => ""}, socket), do: {:noreply, socket}

  # Only an open editor has a plan to prefill (E25 S4, F17). The copied
  # weights carry no refusal, so the mark goes (cascade layer 2).
  def handle_event("copy_soll_plan", %{"copy_from" => value}, %{assigns: %{soll: %{}}} = socket) do
    {:noreply,
     assign(socket,
       soll: copy_soll_from(socket.assigns, parse_soll_view(value)),
       soll_refused: nil
     )}
  end

  def handle_event("filter_tree", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, LiveParam.string(query) || "") |> reload()}
  end

  def handle_event("toggle_current_only", params, socket) do
    current_only? = params["current_only"] == "true"
    {:noreply, socket |> assign(:current_only, current_only?) |> reload()}
  end

  def handle_event("assign_security", params, socket) do
    with {:ok, security_id} <- LiveParam.fetch_id(params["security_id"]),
         {:ok, classification_id} <- LiveParam.fetch_id(params["classification_id"]),
         {:ok, category_id} <- LiveParam.fetch_id(params["category_id"]),
         {:ok, _assignment} <-
           Classifications.assign_security(
             Actor.owner_ui(),
             security_id,
             classification_id,
             category_id
           ) do
      {:noreply, reload_composition(socket)}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("unassign", params, socket) do
    with {:ok, security_id} <- LiveParam.fetch_id(params["security_id"]),
         {:ok, classification_id} <- LiveParam.fetch_id(params["classification_id"]) do
      {:ok, _} =
        Classifications.unassign_security(Actor.owner_ui(), security_id, classification_id)

      {:noreply, reload_composition(socket)}
    else
      :error -> {:noreply, socket}
    end
  end

  def handle_event("assign_securities", params, socket) do
    with {:ok, ids} <- coerce_ids(params["security_ids"]),
         {:ok, classification_id} <- LiveParam.fetch_id(params["classification_id"]),
         {:ok, category_id} <- LiveParam.fetch_id(params["category_id"]) do
      do_assign(socket, ids, classification_id, category_id)
    else
      :error -> {:noreply, socket}
    end
  end

  def handle_event("unassign_many", params, socket) do
    with {:ok, ids} <- coerce_ids(params["security_ids"]),
         {:ok, classification_id} <- LiveParam.fetch_id(params["classification_id"]) do
      do_unassign(socket, ids, classification_id)
    else
      :error -> {:noreply, socket}
    end
  end

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # A plan write names the active view. One deleted since the page loaded
  # (another tab, the API) is noticed before the write: the screen degrades
  # to Everything with Wealth's notice, and nothing is written -- not to the
  # gone view, and not to the Everything plan the screen falls back to
  # (#1091, review round). The write answers as a problem that says so (the
  # closing act of PR γ): the typed weights give way to Everything's plan,
  # and the notice alone did not say they were not saved.
  defp unless_view_gone(%{assigns: %{active_view_id: nil}}, _write_kind, write), do: write.()

  defp unless_view_gone(socket, write_kind, write) do
    if Buckets.get_view(socket.assigns.active_view_id) do
      write.()
    else
      gone = view_gone_answer(write_kind, view_name(socket.assigns.active_view))
      {:noreply, socket |> view_gone() |> failure(gone)}
    end
  end

  defp view_gone_answer(:create, name) do
    StoredText.isolate(
      gettext("The view “%{name}” was deleted meanwhile; no plan was created.",
        name: StoredText.slot(:name)
      ),
      name: name
    )
  end

  defp view_gone_answer(:save, name) do
    StoredText.isolate(
      gettext("The view “%{name}” was deleted meanwhile; nothing was saved.",
        name: StoredText.slot(:name)
      ),
      name: name
    )
  end

  defp view_gone_answer(:delete, name) do
    StoredText.isolate(
      gettext("The view “%{name}” was deleted meanwhile; nothing was deleted.",
        name: StoredText.slot(:name)
      ),
      name: name
    )
  end

  # A plan write's refusal lands in the page's result slot at the top, far
  # above "Save plan" and "Delete plan" (#945; the closing act of PR γ, the
  # design critic's #1): the page brings the slot into view below the sticky
  # top bar and moves the focus to it, as Securities does for a row action
  # whose security went meanwhile (#920). A success does not (cascade layer
  # 2): its note shows in the slot's status region, which announces it, and
  # the page stays where the operator is.
  defp answer_plan_write({:noreply, %{assigns: %{error: nil}}} = reply), do: reply

  defp answer_plan_write({:noreply, socket}),
    do: {:noreply, focus_into_view(socket, "classifications-result")}

  defp create_soll_plan(socket) do
    with %{id: portfolio_id} <- socket.assigns.portfolio,
         classification_id when is_integer(classification_id) <- socket.assigns.selected_id,
         {:ok, _plan} <-
           Targets.ensure_plan(Actor.owner_ui(), portfolio_id, classification_id,
             view: socket.assigns.active_view_id
           ) do
      {:noreply, socket |> success(gettext("Plan created")) |> load_soll()}
    else
      _ -> {:noreply, failure(socket, gettext("Could not create the plan"))}
    end
  end

  defp save_soll_plan(socket, params) do
    with %{id: portfolio_id} <- socket.assigns.portfolio,
         classification_id when is_integer(classification_id) <- socket.assigns.selected_id,
         {:ok, entries} <- parse_weight_entries(params["weights"]),
         {:ok, position_entries} <- parse_position_entries(params["positions"]),
         {:ok, cash_opts} <- soll_cash_opts(socket, params),
         {:ok, _} <-
           Targets.edit_plan(
             Actor.owner_ui(),
             portfolio_id,
             classification_id,
             changed_positions(socket.assigns.soll, position_entries) ++
               follow_positions(entries, position_entries),
             soll_scope(socket) ++
               soll_clears(socket.assigns.soll, params["positions"], entries, position_entries) ++
               cash_opts
           ) do
      {:noreply, socket |> success(gettext("Plan saved")) |> load_soll()}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> failure(soll_error(socket.assigns, reason))
         |> assign(:soll_refused, refused_input(reason))}

      _ ->
        {:noreply, failure(socket, gettext("Could not save the plan"))}
    end
  end

  defp delete_soll_plan(socket) do
    with %{id: portfolio_id} <- socket.assigns.portfolio,
         classification_id when is_integer(classification_id) <- socket.assigns.selected_id do
      # A non-active version deletes just that version (ADR-0027); the active
      # plan keeps the ADR-0020 scope semantics (Wealth page → actual-only).
      case socket.assigns.soll do
        %{editing_version?: true, plan: %{id: plan_id}} ->
          # Already deleted elsewhere (other tab, API, MCP) is not an error —
          # the version is gone either way (review finding).
          case Targets.delete_plan_version(Actor.owner_ui(), plan_id) do
            {:ok, _} -> :ok
            {:error, :not_found} -> :ok
          end

        _ ->
          Targets.delete_plan(Actor.owner_ui(), portfolio_id, classification_id,
            view: socket.assigns.active_view_id
          )
      end

      {:noreply,
       socket |> assign(:soll_plan_id, nil) |> success(gettext("Plan deleted")) |> load_soll()}
    else
      _ -> {:noreply, socket}
    end
  end

  # Writes into the picked plan version when one is loaded; with no plan yet
  # (e.g. saving a copy-prefilled empty scope) the view-addressed write creates
  # the scope's active plan on first save, as before ADR-0027.
  defp soll_scope(socket) do
    case socket.assigns.soll do
      %{plan: %{id: plan_id}} -> [plan: plan_id, view: socket.assigns.active_view_id]
      _ -> [view: socket.assigns.active_view_id]
    end
  end

  # The cash target belongs to the ACTIVE steering (the portfolio-wide cash
  # plan of the view scope, ADR-0020) — editing a draft version leaves it
  # untouched; the input is disabled there (ADR-0027 v1). It is written in the
  # same transaction as the plan (`Targets.edit_plan/5`).
  defp soll_cash_opts(socket, params) do
    case socket.assigns.soll do
      %{editing_version?: true} ->
        {:ok, []}

      _ ->
        with {:ok, cash_weight} <- parse_percent_fraction(params["cash_target"]) do
          {:ok, [cash: cash_weight]}
        end
    end
  end

  # -- move / reclassify dispatch -------------------------------------------

  # Asset-class tree: a "move" edits each security's asset_class field; other
  # trees write the stored assignment.
  defp do_assign(%{assigns: %{tree: %{reclassify: true}}} = socket, ids, _cid, category_id) do
    case Classifications.reclassify_securities(ids, category_id) do
      {:ok, count} -> {:noreply, socket |> success(moved_message(count)) |> reload_composition()}
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
    end
  end

  defp do_assign(socket, ids, classification_id, category_id) do
    case Classifications.assign_securities(Actor.owner_ui(), ids, classification_id, category_id) do
      {:ok, count} -> {:noreply, socket |> success(moved_message(count)) |> reload_composition()}
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
    end
  end

  # Asset-class tree: "unassign" resets each security's asset_class to automatic.
  defp do_unassign(%{assigns: %{tree: %{reclassify: true}}} = socket, ids, _classification_id) do
    {:ok, count} = Classifications.reset_asset_class(ids)
    {:noreply, socket |> success(unassigned_message(count)) |> reload_composition()}
  end

  defp do_unassign(socket, ids, classification_id) do
    {:ok, count} = Classifications.unassign_securities(Actor.owner_ui(), ids, classification_id)
    {:noreply, socket |> success(unassigned_message(count)) |> reload_composition()}
  end

  # -- data loading ---------------------------------------------------------

  defp reload(%{assigns: %{selected_id: nil}} = socket), do: socket
  defp reload(socket), do: load_show(socket, socket.assigns.selected_id)

  # #1110 (ADR-0041 §1): the category result is a statement about the
  # current composition, so an edit that changes the tree computes it again
  # -- a create (the result lists every category), a delete, an assignment,
  # a move. `reload/1` alone rebuilds the rows from the result already
  # computed, which is right for a filter change (the search, the
  # current-positions toggle) and for a rename or a recolour: none of them
  # changes what is filed where.
  defp reload_composition(socket), do: socket |> reload() |> restart_results()

  defp restart_results(%{assigns: %{selected_id: classification_id}} = socket)
       when is_integer(classification_id),
       do: start_results(socket, classification_id)

  defp restart_results(socket), do: socket

  # A category update moves it when its parent changed (the context takes a
  # `parent_id`, validated against the tree); otherwise it renamed it.
  defp reload_after_update(socket, %{parent_id: parent_id}, %{parent_id: parent_id}),
    do: reload(socket)

  defp reload_after_update(socket, _before, _after), do: reload_composition(socket)

  # -- SOLL plan loading -----------------------------------------------------

  # The editor and the switcher's plan dots, after anything that can change
  # which plans exist; one read of the tree's plans serves both.
  defp load_soll(socket) do
    plan_views = plan_views(socket.assigns)

    socket
    |> assign(:planned_view_ids, planned_view_ids(plan_views, socket.assigns.views))
    |> assign_soll(plan_views)
  end

  defp plan_views(%{portfolio: %{id: portfolio_id}, selected_id: classification_id})
       when is_integer(classification_id),
       do: Targets.plan_views(portfolio_id, classification_id)

  defp plan_views(_assigns), do: %{}

  # Which chips carry the plan dot (#1091, review round): the views, and
  # Everything (`nil`), in which this tree has a plan -- the plan the editor
  # below shows, active or draft. A portfolio-wide cash target alone is no
  # plan of this tree. Wealth's dots keep the allocation engine's own
  # definition.
  defp planned_view_ids(plan_views, views),
    do: Enum.filter([nil | Enum.map(views, & &1.id)], &Map.has_key?(plan_views, &1))

  # The plan editor only makes sense for an editable (custom) tree that has a
  # portfolio behind it; built-in trees and the no-portfolio case carry no
  # editor (`soll: nil`). It edits the active view's plan (#1091).
  defp assign_soll(%{assigns: %{portfolio: nil}} = socket, _plan_views),
    do: assign(socket, :soll, nil)

  defp assign_soll(%{assigns: %{tree: nil}} = socket, _plan_views),
    do: assign(socket, :soll, nil)

  defp assign_soll(%{assigns: %{tree: %{editable: false}}} = socket, _plan_views),
    do: assign(socket, :soll, nil)

  defp assign_soll(socket, plan_views) do
    %{portfolio: portfolio, selected_id: classification_id, active_view_id: view_id} =
      socket.assigns

    assign(
      socket,
      :soll,
      build_soll(portfolio.id, classification_id, view_id, socket.assigns, plan_views)
    )
  end

  defp build_soll(portfolio_id, classification_id, view_id, assigns, plan_views) do
    # Plan versions (ADR-0027): the editor follows the scope's active plan by
    # default; a picked version (soll_plan_id) is edited via plan-addressed
    # reads/writes while the active plan keeps steering the SOLL surface.
    plans = Targets.list_plans(portfolio_id, classification_id: classification_id, view: view_id)
    active = Enum.find(plans, &(&1.status == "active"))

    # With no active plan (e.g. the active version was deleted while drafts
    # survive) fall back to the first version, so a lone draft stays reachable,
    # editable and activatable instead of stranding (review finding).
    selected =
      case assigns[:soll_plan_id] do
        nil -> active || List.first(plans)
        plan_id -> Enum.find(plans, &(&1.id == plan_id)) || active || List.first(plans)
      end

    editing_version? = selected != nil and selected.status != "active"
    exists? = selected != nil

    weights =
      if exists? do
        portfolio_id
        |> Targets.list_targets(classification_id: classification_id, plan: selected.id)
        |> Map.new(&{&1.category_id, fraction_to_percent(&1.target_weight)})
      else
        %{}
      end

    # The cash target shown (and counted into Σ) is ALWAYS the view scope's
    # active steering value — matching the hint that cash stays with the
    # active plan while a version is edited. A draft's own copied cash column
    # stays inert in v1 (Steve UAT finding: Σ must not call a complete plan
    # broken just because a version is selected).
    cash_target =
      portfolio_id
      |> Targets.get_cash_target(view: view_id)
      |> fraction_to_percent_or_nil()

    # Position targets (ADR-0030, #481 rescoped, pick F2-A): the securities
    # each category offers as position rows, and the stored position weights
    # of the edited plan. A stored row whose security moved elsewhere (stale)
    # still shows under the category it was filed in — it keeps counting
    # there, so it must stay editable there.
    stored_positions =
      if exists?,
        do:
          Targets.list_position_targets(portfolio_id,
            classification_id: classification_id,
            plan: selected.id
          ),
        else: []

    position_weights =
      Enum.reduce(stored_positions, %{}, fn row, acc ->
        put_in_nested(
          acc,
          row.category_id,
          row.security_id,
          fraction_to_percent(row.target_weight)
        )
      end)

    soll = %{
      view_id: view_id,
      plans: plans,
      plan: selected,
      editing_version?: editing_version?,
      exists: exists?,
      weights: weights,
      members: position_members(classification_id, stored_positions),
      position_weights: position_weights,
      stored_positions: MapSet.new(stored_positions, &{&1.category_id, &1.security_id}),
      stale_positions:
        for(
          row <- stored_positions,
          row.stale,
          into: %{},
          do: {{row.category_id, row.security_id}, row.target_weight}
        ),
      expanded: position_weights |> Map.keys() |> MapSet.new(),
      cash_target: cash_target,
      top_level_ids: top_level_ids(assigns.tree.flat),
      children_by_parent: children_by_parent(assigns.tree.flat),
      copy_sources: copy_sources(view_id, assigns.views, plan_views)
    }

    soll
    |> put_child_sums()
    |> put_sum()
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
  # per-parent children sums without touching the database (#874: the same
  # computation as on load, so the hints never vanish until the save).
  defp recompute_soll_sum(soll, params) do
    soll
    |> Map.put(:weights, parse_percent_map(params["weights"]))
    |> Map.put(:position_weights, parse_position_map(params["positions"]))
    |> Map.put(:cash_target, parse_percent_string(params["cash_target"]))
    |> put_child_sums()
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

    # The source's position targets come along (closing act): a plan that
    # steers by positions is not copied by its category rows alone.
    positions =
      Targets.list_position_targets(portfolio.id,
        classification_id: classification_id,
        view: source_view_id
      )

    position_weights =
      Enum.reduce(positions, %{}, fn row, acc ->
        put_in_nested(
          acc,
          row.category_id,
          row.security_id,
          fraction_to_percent(row.target_weight)
        )
      end)

    # Copying prefills the form (and reveals it from the empty state) without
    # persisting; the maintainer still has to Save to write the plan.
    assigns.soll
    |> Map.put(:exists, true)
    |> Map.put(:weights, weights)
    |> Map.put(:position_weights, position_weights)
    |> Map.put(:members, position_members(classification_id, positions))
    |> Map.put(:expanded, position_weights |> Map.keys() |> MapSet.new())
    |> Map.put(:cash_target, cash)
    |> put_child_sums()
    |> put_sum()
  end

  # Other views (Everything + named) that carry an active plan for this
  # classification -- the plan a copy reads -- as `{label, value}` pairs for
  # the copy-from picker, the current view excluded; read from the same
  # `Targets.plan_views/2` the dots read. The no-view scope is "Everything",
  # the switcher's word, never "Gesamt" (#1091, pick J10 A).
  defp copy_sources(current_view_id, views, plan_views) do
    candidates = [{gettext("Everything"), nil} | Enum.map(views, &{&1.name, &1.id})]

    candidates
    |> Enum.reject(fn {_label, id} -> id == current_view_id end)
    |> Enum.filter(fn {_label, id} -> Map.get(plan_views, id) == true end)
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
      |> Map.put(:weights, steering_weights(soll))
      |> effective_top_level_sum(top_level_ids, children_by_parent)
      |> Decimal.add(to_decimal(soll.cash_target))

    soll
    |> Map.put(:sum, format_sum(sum))
    |> Map.put(:complete?, Decimal.equal?(sum, @hundred))
    |> Map.put(:mismatch?, Decimal.gt?(sum, @hundred))
    |> Map.put(:remainder, remainder(sum))
  end

  # ADR-0040 §1, §3: what a plan under 100 % leaves unallocated, 100 − Σ
  # with the cash target counted like `Allocation`'s top-level sum; nothing
  # at or above 100 %, so no row reads "0 %" (#969, pick H8.4 = A).
  defp remainder(sum) do
    if Decimal.lt?(sum, @hundred), do: format_sum(Decimal.sub(@hundred, sum))
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

  # ADR-0030 §2: a category with any position target steers by the sum of its
  # positions, whatever its own row says; the rest steer by their own weight.
  defp steering_weights(soll) do
    soll
    |> Map.get(:position_weights, %{})
    |> Enum.reduce(soll.weights, fn {category_id, _positions}, acc ->
      case position_sum(soll, category_id) do
        nil -> acc
        sum -> Map.put(acc, category_id, sum)
      end
    end)
  end

  # The sum of a category's position targets (percent), or nil when none of
  # its positions carries one — an empty input is no target, not zero.
  defp position_sum(soll, category_id) do
    case soll |> Map.get(:position_weights, %{}) |> Map.get(category_id, %{}) |> Map.values() do
      [] -> nil
      values -> Enum.reduce(values, @zero, &Decimal.add(to_decimal(&1), &2))
    end
  end

  # The securities a category offers as position rows: those assigned to it in
  # this classification, plus any security a stored position row files there.
  defp position_members(classification_id, stored_positions) do
    assigned =
      case Classifications.security_category_map(classification_id) do
        {:ok, map} ->
          Enum.map(map, fn {security_id, category_id} -> {category_id, security_id} end)

        {:error, _} ->
          []
      end

    pairs = Enum.uniq(assigned ++ Enum.map(stored_positions, &{&1.category_id, &1.security_id}))
    ids = pairs |> Enum.map(&elem(&1, 1)) |> MapSet.new()

    names =
      Catalog.list_securities()
      |> Enum.filter(&MapSet.member?(ids, &1.id))
      |> Map.new(&{&1.id, &1.name})

    pairs
    |> Enum.filter(fn {_category_id, security_id} -> Map.has_key?(names, security_id) end)
    |> Enum.group_by(&elem(&1, 0), fn {_category_id, security_id} ->
      %{id: security_id, name: Map.fetch!(names, security_id)}
    end)
    |> Map.new(fn {category_id, members} -> {category_id, Enum.sort_by(members, & &1.name)} end)
  end

  defp put_in_nested(map, outer, inner, value),
    do: Map.update(map, outer, %{inner => value}, &Map.put(&1, inner, value))

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

  # The per-parent "children Σ" hint (#467), keyed by parent id: the sum of
  # each parent's direct children, only where at least one child carries a
  # weight (advisory, display-only). A child counts with the weight it steers
  # by — a child that follows its position targets with their sum (ADR-0030
  # §2), as the Σ row counts it. One computation on load and on every change
  # (#874); the tree shape travels in `children_by_parent`.
  defp put_child_sums(soll) do
    weights = steering_weights(soll)

    sums =
      soll
      |> Map.get(:children_by_parent, %{})
      |> Enum.reduce(%{}, fn {parent_id, child_ids}, acc ->
        case sum_child_weights(child_ids, weights) do
          nil -> acc
          sum -> Map.put(acc, parent_id, sum)
        end
      end)

    Map.put(soll, :child_sums, sums)
  end

  defp sum_child_weights(child_ids, weights) do
    Enum.reduce(child_ids, nil, fn id, acc ->
      case Map.get(weights, id) do
        nil -> acc
        value -> Decimal.add(acc || @zero, to_decimal(value))
      end
    end)
  end

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

  # The category result in the screen's scope (#1091, pick J10 A), from the
  # function the API serves that scope with: under a view
  # `CategoryResult.for_view/3` (`GET /api/v1/views/:view_id/category-results`),
  # under Everything `for_all_portfolios/2` (`GET /api/v1/category-results`),
  # so the screen and the agent's read cannot disagree.
  defp start_results(socket, classification_id) do
    if connected?(socket) do
      view_id = socket.assigns.active_view_id
      start_async(socket, :results, fn -> scoped_result(view_id, classification_id) end)
    else
      socket
    end
  end

  defp scoped_result(nil, classification_id),
    do: CategoryResult.for_all_portfolios(classification_id)

  defp scoped_result(view_id, classification_id),
    do: CategoryResult.for_view(view_id, classification_id)

  # The scope's name in the screen's sentences: the view's, or the
  # switcher's "Everything".
  defp view_name(nil), do: gettext("Everything")
  defp view_name(%{name: name}), do: name

  # The hidden-members suffix: under a view, the members the view holds none
  # of (#1091); under Everything, the ones no longer held (#334).
  defp hidden_label(true), do: gettext("not in the view")
  defp hidden_label(false), do: gettext("without holdings")

  defp hidden_title(true),
    do: gettext("Assigned securities with no position in this view, hidden by the filter")

  defp hidden_title(false),
    do: gettext("Assigned securities no longer held, hidden by the filter")

  # Unsorted's own (cascade layer 2): its securities are unassigned, and
  # under Everything some were never held, so the categories' "Assigned
  # securities no longer held" was wrong twice.
  defp unsorted_hidden_title(true),
    do: gettext("Unassigned securities with no position in this view, hidden by the filter")

  defp unsorted_hidden_title(false),
    do: gettext("Unassigned securities without holdings, hidden by the filter")

  # The roll-up's currency and its excluded members stay with it (#1048):
  # the basis line names the one, the note the other.
  defp index_results(result) do
    %{
      basis: result.basis,
      base_currency: result.base_currency,
      excluded: result.excluded_members,
      by_category: Map.new(result.categories, &{&1.category_id, &1})
    }
  end

  # The result cell's sign colour, decided on the amount as displayed
  # (`Format.displayed_sign/2`, U2's rule; the closing act of PR γ): a result
  # that reads 0.00 is unsigned and `is-flat`, never in the gain colour.
  defp result_tone(result_abs) do
    case Format.displayed_sign(result_abs, 2) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      :zero -> "is-flat"
      nil -> nil
    end
  end

  # The row's result cell (#805): the result only where something is
  # invested — a category with no cost has no result to state.
  defp stated_result(results, category_id) do
    case category_result(results, category_id) do
      %{invested: invested} = result ->
        if Decimal.gt?(invested, Decimal.new("0")), do: result, else: nil

      nil ->
        nil
    end
  end

  # The result's percent in the house form, the sign and "%" glued on
  # ("+13,7%"), as U2 and U3 made it on the Trades surfaces (the closing act
  # of PR γ; DESIGN.md's γ n12).
  defp result_percent(pct), do: Format.signed_percent(pct) <> "%"

  # The Unsorted row's value: the visible unsorted positions, or nil.
  defp unsorted_total([]), do: nil

  defp unsorted_total(securities) do
    if Enum.all?(securities, &match?(%Decimal{}, &1.market_value)) do
      Enum.reduce(securities, @zero, &Decimal.add(&2, &1.market_value))
    end
  end

  # A row's money figure, or the value slot's not-computable dash. A count is
  # always computable, so "Positions" prints its number, 0 included (the
  # closing act of PR γ; it printed "—" since #805).
  attr(:value, :any, required: true)

  defp figure(%{value: %Decimal{}} = assigns), do: ~H"<%= Format.money(@value) %>"
  defp figure(assigns), do: ~H"<.not_computable />"

  # The value slot's not-computable dash (UX-DR20, DESIGN.md's
  # `value-slot.not-computable`): muted and at weight 400, never at the
  # figures' weight, so a stable "no figure" does not read as one
  # (`.cat-summary .cat-na`).
  defp not_computable(assigns), do: ~H|<span class="cat-na">—</span>|

  defp category_result(nil, _category_id), do: nil

  defp category_result(%{by_category: by_category}, category_id),
    do: Map.get(by_category, category_id)

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

    # Unsorted shows and counts the unsorted securities the scope holds, and
    # counts the rest beside its name, as a category does, in every scope:
    # under a view the ones it holds none of (#1091, review round), under
    # Everything the ones no longer held (the closing act of PR γ, where
    # Everything listed every unsorted security whatever the toggle and read
    # differently from a view that includes every account).
    unsorted_row = split_members(unsorted, hide_sold?)

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
      unsorted_row: unsorted_row,
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
  # A total is only a total when every row carries the figure: while the
  # holdings are still loading every market value is nil, and afterwards a
  # position the app cannot price is still nil. Either way the sum is a dash,
  # never a silently smaller number presented as the category's value (the
  # same rule the securities detail's sum_known/2 states).
  defp visible_value(node) do
    rows = node_securities(node)

    if rows != [] and Enum.all?(rows, &match?(%Decimal{}, &1.market_value)) do
      Enum.reduce(rows, @zero, &Decimal.add(&2, &1.market_value))
    end
  end

  defp node_securities(node),
    do: node.securities ++ Enum.flat_map(node.children, &node_securities/1)

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

  defp coerce_ids(values) when is_list(values), do: {:ok, LiveParam.ids(values)}
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
    own = soll |> steering_weights() |> Map.get(category_id)
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
      with {:ok, category_id} <- LiveParam.fetch_id(key),
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

  # `positions[category_id][security_id]` → position entries (ADR-0030); a blank
  # input is no position target and yields no entry.
  defp parse_position_entries(positions) when is_map(positions) do
    Enum.reduce_while(positions, {:ok, []}, fn {category_key, by_security}, {:ok, acc} ->
      case position_entries_for(category_key, by_security) do
        {:ok, entries} -> {:cont, {:ok, entries ++ acc}}
        error -> {:halt, error}
      end
    end)
  end

  defp parse_position_entries(_positions), do: {:ok, []}

  defp position_entries_for(category_key, by_security) when is_map(by_security) do
    with {:ok, category_id} <- LiveParam.fetch_id(category_key) do
      Enum.reduce_while(by_security, {:ok, []}, fn {security_key, value}, {:ok, acc} ->
        with {:ok, security_id} <- LiveParam.fetch_id(security_key),
             {:ok, fraction} <- parse_percent_fraction(value) do
          entry = %{category_id: category_id, security_id: security_id, target_weight: fraction}
          {:cont, {:ok, if(fraction, do: [entry | acc], else: acc)}}
        else
          _ -> {:halt, {:error, :invalid_weight}}
        end
      end)
    else
      _ -> {:error, :invalid_weight}
    end
  end

  defp position_entries_for(_category_key, _by_security), do: {:error, :invalid_weight}

  # "The category follows it" (board 02, ADR-0030 §2): a category whose
  # positions carry targets gets its own row set to their sum, so the stored
  # category weight never disagrees with what steers — the conflict the Wealth
  # page reports is resolved by saving here, not by a second field to keep in
  # step. Any submitted weight for such a category is superseded.
  defp follow_positions(entries, []), do: entries

  defp follow_positions(entries, position_entries) do
    sums =
      Enum.reduce(position_entries, %{}, fn entry, acc ->
        Map.update(
          acc,
          entry.category_id,
          entry.target_weight,
          &Decimal.add(&1, entry.target_weight)
        )
      end)

    entries
    |> Enum.reject(&Map.has_key?(sums, &1.category_id))
    |> Kernel.++(Enum.map(sums, fn {id, sum} -> %{category_id: id, target_weight: sum} end))
  end

  # The stored position rows whose input came back empty are deleted — an empty
  # field means "no position target", never zero (#481). Only a row the form
  # actually carried is touched: a submit without the position inputs clears
  # nothing. A category whose stored positions this save clears completely,
  # with no weight typed for it and no new position, loses the row that only
  # followed their sum (closing-act fix round): the steering goes back to the
  # category, which then has no target, as the editor shows.
  defp soll_clears(soll, positions, entries, position_entries) when is_map(positions) do
    case soll do
      %{plan: %{id: _}, stored_positions: stored} ->
        cleared = Enum.filter(stored, fn {c, s} -> blank_position?(positions, c, s) end)
        kept = MapSet.difference(stored, MapSet.new(cleared))

        typed =
          MapSet.new(entries ++ position_entries, & &1.category_id)
          |> MapSet.union(MapSet.new(kept, &elem(&1, 0)))

        categories =
          cleared |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.reject(&(&1 in typed))

        [clear_positions: cleared, clear_categories: categories]

      _no_plan ->
        []
    end
  end

  defp soll_clears(_soll, _positions, _entries, _position_entries), do: []

  # A stale position row (its security re-filed outside the category since)
  # keeps counting where it was filed (ADR-0030), so the editor still shows it
  # — but the write path refuses to file a security under a category it no
  # longer sits in. Sent back unchanged, the row is left as it is instead of
  # blocking every save; a changed value still goes to the write and is
  # refused with the reason.
  defp changed_positions(soll, position_entries) do
    stale = Map.get(soll, :stale_positions, %{})

    Enum.reject(position_entries, fn entry ->
      case Map.get(stale, {entry.category_id, entry.security_id}) do
        nil -> false
        stored -> Decimal.equal?(stored, entry.target_weight)
      end
    end)
  end

  defp blank_position?(positions, category_id, security_id) do
    case positions |> Map.get(to_string(category_id)) do
      %{} = by_security ->
        by_security
        |> Map.fetch(to_string(security_id))
        |> case do
          {:ok, value} when is_binary(value) -> String.trim(value) == ""
          _absent -> false
        end

      _absent ->
        false
    end
  end

  # A percentage string ("60", "12.5", "" ) → a `Decimal` fraction in [0, 1], or
  # `nil` for blank. Returns `{:error, :invalid_weight}` for non-numbers.
  # Status-aware banner for a selected non-active version (Steve UAT: an
  # archived plan is not a draft).
  defp version_hint("archived"),
    do: gettext("Archived — the Wealth page follows the active plan; activate to reuse it.")

  defp version_hint(_status),
    do:
      gettext(
        "Draft — the Wealth page keeps following the active plan until this one is activated."
      )

  defp plan_status_label("active"), do: gettext("active")
  defp plan_status_label("draft"), do: gettext("draft")
  defp plan_status_label(_status), do: gettext("archived")

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
      case {LiveParam.fetch_id(key), parse_percent_string(value)} do
        {{:ok, id}, %Decimal{} = decimal} -> Map.put(acc, id, decimal)
        _ -> acc
      end
    end)
  end

  defp parse_percent_map(_weights), do: %{}

  # `positions[category_id][security_id]` → `%{category_id => %{security_id =>
  # Decimal}}`, blanks dropped: an empty position input is no target.
  defp parse_position_map(positions) when is_map(positions) do
    Enum.reduce(positions, %{}, fn {category_key, by_security}, acc ->
      with {:ok, category_id} <- LiveParam.fetch_id(category_key),
           parsed when parsed != %{} <- parse_percent_map(by_security) do
        Map.put(acc, category_id, parsed)
      else
        _ -> acc
      end
    end)
  end

  defp parse_position_map(_positions), do: %{}

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
  # an uncaught `ArgumentError`. The shared finite-decimal rule treats any
  # non-finite result as invalid, so a crafted form payload can never crash the
  # editor — it surfaces as a normal "invalid weight" instead.
  defp parse_decimal(value), do: BoundedDecimal.parse(value)

  # A stored fraction in [0, 1] → its percentage as a plain display string
  # ("0.6" → "60", "0.125" → "12.5"), trimming trailing zeros. A weight stored
  # before the scale bound (E25 S4, G14) shows at the places a plan holds, so
  # the form's untouched rows save as shown instead of being refused.
  defp fraction_to_percent(%Decimal{} = fraction) do
    fraction
    |> BoundedDecimal.round_to_scale(Target.weight_scale())
    |> Decimal.mult(@hundred)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp fraction_to_percent_or_nil(nil), do: nil
  defp fraction_to_percent_or_nil(%Decimal{} = fraction), do: fraction_to_percent(fraction)

  # Format a running sum (already a percentage Decimal) for display, trimming
  # trailing zeros so "100.0" reads "100", in the page's number format: a
  # German page reads "95,5", as the Allocation basis line does (UAT-8).
  defp format_sum(%Decimal{} = sum), do: PortfolixirWeb.Format.exact(sum)

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(nil), do: @zero

  defp to_decimal(value) when is_binary(value) do
    case parse_decimal(value) do
      {:ok, decimal} -> decimal
      :error -> @zero
    end
  end

  # "total" or a view id string → the view id (nil for Gesamt) used by the
  # Targets context. Never builds an atom from input; a value no view id can
  # be (#868) reads as Gesamt.
  defp parse_soll_view(value), do: LiveParam.id(value)

  defp view_param(nil), do: "total"
  defp view_param(id) when is_integer(id), do: Integer.to_string(id)

  defp success(socket, message),
    do: assign(socket, success: message, error: nil, soll_refused: nil)

  defp failure(socket, message),
    do: assign(socket, error: message, success: nil, soll_refused: nil)

  # #1064 (J7 = A): the page's one result, in the data note's severities. A
  # refusal that names rules renders through `PolicyRuleReferences`, so each
  # rule's name stays a link (#871).
  defp page_result(error, _success) when not is_nil(error) do
    assigns = %{error: error}
    {:problem, ~H"<PolicyRuleReferences.message message={@error} />"}
  end

  defp page_result(nil, success) when not is_nil(success), do: {:note, success}
  defp page_result(nil, nil), do: nil

  defp error_message(:builtin_locked), do: gettext("Built-in classifications cannot be edited")
  defp error_message(:category_mismatch), do: gettext("That category belongs to another tree")
  defp error_message(:not_found), do: gettext("Not found")
  defp error_message(:category_not_found), do: gettext("Category not found")
  defp error_message(:not_reclassifiable), do: gettext("This tree cannot be reassigned")
  defp error_message({:policy_rules, rules}), do: PolicyRuleReferences.refusal(rules)
  defp error_message(%Ecto.Changeset{} = changeset), do: changeset_error(changeset)
  defp error_message(_other), do: gettext("Something went wrong")

  # A plan save refused by the write path, in the operator's terms (closing
  # act): the securities and categories by name, a weight as the percentage
  # the form takes — the changeset's own bound is a fraction.
  defp soll_error(assigns, {:security_category_mismatch, security_id, category_id}) do
    gettext("%{security} no longer sits under %{category} — clear its position target there",
      security: soll_member_name(assigns, security_id),
      category: category_name(assigns, category_id)
    )
  end

  defp soll_error(assigns, {:duplicate_position, security_id}) do
    gettext("%{security} already carries a position target under another category",
      security: soll_member_name(assigns, security_id)
    )
  end

  defp soll_error(assigns, %Ecto.Changeset{errors: errors} = changeset) do
    cond do
      # E25 S4 (G14): a weight refused for its precision says so, in the
      # percent the form speaks (six places of a fraction are four of a
      # percentage), instead of naming the 0-100 % range.
      scale_error?(errors) ->
        soll_row_error(assigns, changeset, :scale)

      Keyword.has_key?(errors, :target_weight) or Keyword.has_key?(errors, :cash_target_weight) ->
        soll_row_error(assigns, changeset, :range)

      true ->
        changeset_error(changeset)
    end
  end

  defp soll_error(_assigns, reason), do: error_message(reason)

  # #945 (board 08.5): the refused row first, in the editor's own names,
  # then the rule — the row read off the refused changeset: the plan's cash
  # target, a position under its category, or a category. Stored names sit
  # in <bdi> (H8.8).
  defp soll_row_error(assigns, %Ecto.Changeset{errors: errors} = changeset, rule) do
    category_id = Ecto.Changeset.get_field(changeset, :category_id)
    security_id = Ecto.Changeset.get_field(changeset, :security_id)

    cond do
      Keyword.has_key?(errors, :cash_target_weight) ->
        cash_target_error(rule)

      is_integer(category_id) and is_integer(security_id) ->
        StoredText.isolate(position_target_error(rule),
          security: soll_member_name(assigns, security_id),
          category: category_name(assigns, category_id)
        )

      is_integer(category_id) ->
        StoredText.isolate(category_target_error(rule),
          category: category_name(assigns, category_id)
        )

      rule == :scale ->
        gettext("A target carries at most four decimal places in percent")

      true ->
        gettext("A target must lie between 0 and 100 %")
    end
  end

  defp cash_target_error(:scale),
    do: gettext("Cash target: at most four decimal places in percent")

  defp cash_target_error(:range), do: gettext("Cash target: must lie between 0 and 100 %")

  defp position_target_error(:scale) do
    gettext(
      "Position target of “%{security}” under “%{category}”: at most four decimal places in percent",
      security: StoredText.slot(:security),
      category: StoredText.slot(:category)
    )
  end

  defp position_target_error(:range) do
    gettext("Position target of “%{security}” under “%{category}”: must lie between 0 and 100 %",
      security: StoredText.slot(:security),
      category: StoredText.slot(:category)
    )
  end

  defp category_target_error(:scale) do
    gettext("Target of “%{category}”: at most four decimal places in percent",
      category: StoredText.slot(:category)
    )
  end

  defp category_target_error(:range) do
    gettext("Target of “%{category}”: must lie between 0 and 100 %",
      category: StoredText.slot(:category)
    )
  end

  defp scale_error?(errors) do
    Enum.any?(errors, fn {field, {_message, keys}} ->
      field in [:target_weight, :cash_target_weight] and keys[:validation] == :decimal_scale
    end)
  end

  # The input a save's refusal names (#945; the closing act of PR γ), read
  # off the refusal as `soll_error/2` reads its row: the cash target, a
  # position under its category, or a category. A refusal that names no
  # input marks none.
  defp refused_input({:security_category_mismatch, security_id, category_id}),
    do: "soll-position-#{category_id}-#{security_id}"

  defp refused_input(%Ecto.Changeset{errors: errors} = changeset) do
    category_id = Ecto.Changeset.get_field(changeset, :category_id)
    security_id = Ecto.Changeset.get_field(changeset, :security_id)

    cond do
      Keyword.has_key?(errors, :cash_target_weight) ->
        "soll-cash-target"

      not Keyword.has_key?(errors, :target_weight) ->
        nil

      is_integer(category_id) and is_integer(security_id) ->
        "soll-position-#{category_id}-#{security_id}"

      is_integer(category_id) ->
        "soll-weight-#{category_id}"

      true ->
        nil
    end
  end

  defp refused_input(_reason), do: nil

  # Where a dismiss puts the focus back (`dismiss_result`).
  defp dismiss_focus(%{soll_refused: input}) when is_binary(input), do: input
  defp dismiss_focus(%{soll: %{}}), do: "soll-editor-heading"
  defp dismiss_focus(%{tree: %{}}), do: "classification-heading"
  defp dismiss_focus(_assigns), do: nil

  defp focus_into_view(socket, nil), do: socket
  defp focus_into_view(socket, id), do: push_event(socket, "focus-into-view", %{id: id})

  # The refused input is marked invalid and described by the page's problem
  # region, which holds the refusal naming it.
  defp refused_attrs(id, id),
    do: %{"aria-invalid" => "true", "aria-describedby" => "classifications-result-alert"}

  defp refused_attrs(_refused, _id), do: %{}

  # The cash input is described by its lock hint while a draft is edited (a
  # draft's save sends no cash target, so it is never the refused one), else
  # by a refusal that names it.
  defp cash_describedby(%{editing_version?: true}, _refused), do: "soll-cash-lock-hint"
  defp cash_describedby(_soll, "soll-cash-target"), do: "classifications-result-alert"
  defp cash_describedby(_soll, _refused), do: nil

  defp soll_member_name(assigns, security_id) do
    assigns.soll.members
    |> Map.values()
    |> List.flatten()
    |> Enum.find_value(to_string(security_id), &(&1.id == security_id && &1.name))
  end

  defp category_name(assigns, category_id) do
    Enum.find_value(assigns.tree.flat, to_string(category_id), fn {category, _depth} ->
      category.id == category_id && category.name
    end)
  end

  # A changeset's errors in the page's language (closing act): the messages
  # run through the `errors` domain with their values bound, never the raw
  # English with an unfilled placeholder.
  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, error} -> "#{field_label(field)} #{translate_error(error)}" end)
    |> Enum.join(", ")
  end

  defp field_label(:name), do: gettext("Name")
  defp field_label(field), do: Phoenix.Naming.humanize(field)

  defp translate_error({message, opts}) do
    bindings = Map.new(opts, fn {key, value} -> {key, to_string(value)} end)

    case opts[:count] do
      nil ->
        Gettext.dgettext(PortfolixirWeb.Gettext, "errors", message, bindings)

      count ->
        Gettext.dngettext(PortfolixirWeb.Gettext, "errors", message, message, count, bindings)
    end
  end
end
