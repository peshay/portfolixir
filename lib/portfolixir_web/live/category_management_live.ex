defmodule PortfolixirWeb.CategoryManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Taxonomies
  alias Portfolixir.Catalog
  alias PortfolixirWeb.AppShell

  @taxonomy_form_defaults %{
    "name" => "",
    "description" => ""
  }

  @category_form_defaults %{
    "taxonomy_id" => "",
    "parent_id" => "",
    "name" => "",
    "description" => "",
    "color" => "",
    "sort_order" => ""
  }

  @category_assignment_form_defaults %{
    "security_id" => "",
    "category_id" => ""
  }

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:taxonomy_form, @taxonomy_form_defaults)
      |> assign(:category_form, @category_form_defaults)
      |> assign(:category_assignment_form, @category_assignment_form_defaults)
      |> assign(:taxonomy_error, nil)
      |> assign(:category_error, nil)
      |> assign(:category_assignment_error, nil)
      |> assign(:preset_success, nil)

    {:ok, load_taxonomy_state(socket)}
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/taxonomies">
      <header class="app-shell-page-header">
        <div>
          <p class="app-shell-page-kicker"><%= gettext("Classifications") %></p>
          <h1><%= gettext("Classifications") %></h1>
          <p>
            <%= gettext("Build user-defined grouping systems for asset allocation, regions, sectors and other portfolio views.") %>
          </p>
        </div>
      </header>

      <section id="classification-workbench-toolbar" class="app-shell-section-card">
        <div class="app-shell-section-header">
          <div>
            <h2 class="app-shell-section-title"><%= gettext("Classification workbench") %></h2>
            <p><%= gettext("Tree/details layout with explicit placeholder views.") %></p>
          </div>
          <div class="app-shell-form-actions" role="group" aria-label={gettext("View mode")}> 
            <button id="classification-view-list" type="button" class="app-shell-secondary" disabled>
              <%= gettext("List") %>
            </button>
            <button id="classification-view-tree" type="button" class="app-shell-secondary" disabled>
              <%= gettext("Tree") %>
            </button>
            <button id="classification-view-chart" type="button" class="app-shell-secondary" disabled>
              <%= gettext("Chart") %>
            </button>
            <button id="classification-view-sunburst" type="button" class="app-shell-secondary" disabled>
              <%= gettext("Sunburst") %>
            </button>
          </div>
        </div>
      </section>

      <div id="classification-workspace" class="app-shell-workspace-grid">
        <section
          id="classification-tree-region"
          class="app-shell-section-card"
          data-priority="primary"
        >
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Taxonomy tree") %></h2>
              <p><%= gettext("Each taxonomy is a classification system with its own category tree.") %></p>
            </div>
            <span class="app-shell-badge app-shell-badge--accent">
              <%= ngettext("%{count} total", "%{count} total", Enum.count(@taxonomies), count: Enum.count(@taxonomies)) %>
            </span>
          </div>

          <div class="app-shell-form-actions">
            <button
              id="portfolio-performance-presets"
              type="button"
              class="app-shell-secondary"
              phx-click="create_portfolio_performance_presets"
            >
              <%= gettext("Create Portfolio Performance presets") %>
            </button>
          </div>

          <%= if @preset_success do %>
            <p
              id="portfolio-performance-presets-success"
              class="app-shell-alert app-shell-alert--success"
              role="status"
              aria-live="polite"
            >
              <%= @preset_success %>
            </p>
          <% end %>

          <%= if @taxonomy_error do %>
            <p id="taxonomy-form-error" class="app-shell-alert app-shell-alert--error" role="alert">
              <%= @taxonomy_error %>
            </p>
          <% end %>

          <form id="taxonomy-form" class="app-shell-form-grid" phx-submit="create_taxonomy">
            <div class="app-shell-field app-shell-field--full">
              <label for="taxonomy-name"><%= gettext("Name") %></label>
              <input id="taxonomy-name" name="taxonomy[name]" value={@taxonomy_form["name"]} />
            </div>

            <div class="app-shell-field app-shell-field--full">
              <label for="taxonomy-description"><%= gettext("Description") %></label>
              <textarea id="taxonomy-description" name="taxonomy[description]"><%= @taxonomy_form["description"] %></textarea>
            </div>

            <div class="app-shell-form-actions">
              <button type="submit" class="app-shell-primary"><%= gettext("Create Taxonomy") %></button>
            </div>
          </form>

          <%= if Enum.empty?(@taxonomies) do %>
            <div
              id="no-taxonomies"
              class="app-shell-empty-state"
              role="status"
              aria-live="polite"
              aria-labelledby="no-taxonomies-heading"
              aria-describedby="no-taxonomies-description"
            >
              <h3 id="no-taxonomies-heading"><%= gettext("No taxonomies yet") %></h3>
              <p id="no-taxonomies-description">
                <%= gettext("Create a taxonomy before adding categories.") %>
              </p>
            </div>
          <% else %>
            <ul id="taxonomy-list" class="app-shell-list">
              <%= for taxonomy <- @taxonomies do %>
                <li class="app-shell-list-item">
                  <button
                    id={"taxonomy-#{taxonomy.id}"}
                    class="app-shell-secondary"
                    phx-click="select_taxonomy"
                    phx-value-id={taxonomy.id}
                    disabled={taxonomy.id == @selected_taxonomy_id}
                  >
                    <%= taxonomy.name %>
                  </button>
                  <p class="app-shell-muted"><%= taxonomy.description || gettext("No description") %></p>
                </li>
              <% end %>
            </ul>

            <div id="classification-tree" class="app-shell-section-card" data-role="tree">
              <h3 class="app-shell-section-title"><%= gettext("Category tree") %></h3>

              <%= if Enum.empty?(@selected_category_tree) do %>
                <p id="classification-tree-empty" class="app-shell-muted">
                  <%= gettext("No categories yet") %>
                </p>
              <% else %>
                <ul id="classification-tree-root" class="app-shell-list">
                  <%= for node <- @selected_category_tree do %>
                    <.tree_node node={node} />
                  <% end %>
                </ul>
              <% end %>
            </div>
          <% end %>
        </section>

        <section
          id="classification-details-region"
          class="app-shell-section-card"
          data-priority="secondary"
        >
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Selected classification details") %></h2>
              <p><%= gettext("Add and maintain the groups inside the selected taxonomy.") %></p>
            </div>
          </div>

          <%= if @selected_taxonomy_id do %>
            <%= if @category_error do %>
              <p id="category-form-error" class="app-shell-alert app-shell-alert--error" role="alert">
                <%= @category_error %>
              </p>
            <% end %>

            <form id="category-form" class="app-shell-form-grid" phx-submit="create_category">
              <input type="hidden" name="category[taxonomy_id]" value={@selected_taxonomy_id} />

              <div class="app-shell-field app-shell-field--full">
                <label for="category-name"><%= gettext("Name") %></label>
                <input id="category-name" name="category[name]" value={@category_form["name"]} />
              </div>

              <div class="app-shell-field app-shell-field--full">
                <label for="category-description"><%= gettext("Description") %></label>
                <textarea id="category-description" name="category[description]"><%= @category_form["description"] %></textarea>
              </div>

              <div class="app-shell-field">
                <label for="category-parent-id"><%= gettext("Parent (optional)") %></label>
                <select id="category-parent-id" name="category[parent_id]">
                  <option value=""><%= gettext("None") %></option>
                  <%= for category <- @selected_categories do %>
                    <option value={category.id}><%= category.name %></option>
                  <% end %>
                </select>
              </div>

              <div class="app-shell-field">
                <label for="category-color"><%= gettext("Color (optional)") %></label>
                <input id="category-color" name="category[color]" value={@category_form["color"]} />
              </div>

              <div class="app-shell-field">
                <label for="category-sort-order"><%= gettext("Sort order (optional)") %></label>
                <input
                  id="category-sort-order"
                  name="category[sort_order]"
                  type="number"
                  min="0"
                  value={@category_form["sort_order"]}
                />
              </div>

              <div class="app-shell-form-actions">
                <button type="submit" class="app-shell-primary"><%= gettext("Add Category") %></button>
              </div>
            </form>

            <%= if Enum.empty?(@selected_categories) do %>
              <div
                id="no-categories"
                class="app-shell-empty-state"
                role="status"
                aria-live="polite"
                aria-labelledby="no-categories-title"
                aria-describedby="no-categories-description"
              >
                <h3 id="no-categories-title"><%= gettext("No categories yet") %></h3>
                <p id="no-categories-description">
                  <%= gettext("Add the first category for this taxonomy.") %>
                </p>
              </div>
            <% else %>
              <section id="category-assignment-region" class="app-shell-section-card">
                <div class="app-shell-section-header">
                  <div>
                    <h3 class="app-shell-section-title"><%= gettext("Security assignments") %></h3>
                    <p><%= gettext("Assign a security to a classification category.") %></p>
                  </div>
                </div>

                <%= if @category_assignment_error do %>
                  <p id="category-assignment-error" class="app-shell-alert app-shell-alert--error" role="alert">
                    <%= @category_assignment_error %>
                  </p>
                <% end %>

                <form
                  id="category-assignment-form"
                  class="app-shell-form-grid"
                  phx-change="select_security_for_assignment"
                  phx-submit="assign_category_to_security"
                >
                  <div class="app-shell-field app-shell-field--full">
                    <label for="assignment-security-id"><%= gettext("Security") %></label>
                    <select id="assignment-security-id" name="assignment[security_id]">
                      <option value=""><%= gettext("Select security") %></option>
                      <%= for security <- @securities do %>
                        <option value={security.id} selected={to_string(security.id) == @category_assignment_form["security_id"]}>
                          <%= security.name %>
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <div class="app-shell-field app-shell-field--full">
                    <label for="assignment-category-id"><%= gettext("Category") %></label>
                    <select id="assignment-category-id" name="assignment[category_id]">
                      <option value=""><%= gettext("Select category") %></option>
                      <%= for category <- @selected_categories do %>
                        <option value={category.id} selected={to_string(category.id) == @category_assignment_form["category_id"]}>
                          <%= category.name %>
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <div class="app-shell-form-actions">
                    <button type="submit" class="app-shell-primary"><%= gettext("Assign category") %></button>
                  </div>
                </form>

                <%= if is_nil(@selected_security_id) do %>
                  <p id="security-assignments-empty" class="app-shell-muted"><%= gettext("Select a security to view assignments.") %></p>
                <% else %>
                  <ul id="security-assignment-list" class="app-shell-list">
                    <%= for category <- @selected_security_categories do %>
                      <li id={"security-assignment-#{@selected_security_id}-#{category.id}"} class="app-shell-list-item">
                        <strong><%= category.name %></strong>
                        <button
                          id={"remove-security-assignment-#{@selected_security_id}-#{category.id}"}
                          type="button"
                          class="app-shell-secondary"
                          phx-click="remove_category_assignment"
                          phx-value-security-id={@selected_security_id}
                          phx-value-category-id={category.id}
                        >
                          <%= gettext("Remove") %>
                        </button>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              </section>

              <ul id="category-list" class="app-shell-list">
                <%= for category <- @selected_categories do %>
                  <li id={"category-#{category.id}"} class="app-shell-list-item">
                    <strong><%= category.name %></strong>
                    <p class="app-shell-muted"><%= category.description || gettext("No description") %></p>

                    <form
                      id={"edit-category-form-#{category.id}"}
                      class="app-shell-form-grid"
                      phx-submit="update_category"
                      phx-value-id={category.id}
                    >
                      <div class="app-shell-field">
                        <label><%= gettext("Name") %></label>
                        <input name="category[name]" value={category.name} />
                      </div>

                      <div class="app-shell-field">
                        <label><%= gettext("Description") %></label>
                        <textarea name="category[description]"><%= category.description %></textarea>
                      </div>

                      <div class="app-shell-form-actions">
                        <button type="submit" class="app-shell-secondary"><%= gettext("Save") %></button>
                        <button
                          id={"delete-category-#{category.id}"}
                          class="app-shell-secondary"
                          type="button"
                          phx-click="delete_category"
                          phx-value-id={category.id}
                        >
                          <%= gettext("Delete") %>
                        </button>
                      </div>
                    </form>
                  </li>
                <% end %>
              </ul>
            <% end %>
          <% else %>
            <div
              id="no-taxonomy-selected"
              class="app-shell-empty-state"
              role="status"
              aria-live="polite"
              aria-labelledby="no-taxonomy-selected-title"
              aria-describedby="no-taxonomy-selected-description"
            >
              <h3 id="no-taxonomy-selected-title"><%= gettext("Create or select a taxonomy first") %></h3>
              <p id="no-taxonomy-selected-description">
                <%= gettext("Categories belong to one taxonomy, so choose the grouping system before adding them.") %>
              </p>
            </div>
          <% end %>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  def handle_event("select_taxonomy", %{"id" => taxonomy_id}, socket) do
    with {taxonomy_id, ""} <- Integer.parse(taxonomy_id) do
      {:noreply, load_taxonomy_state(socket, taxonomy_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("create_taxonomy", %{"taxonomy" => params}, socket) do
    case Taxonomies.create_taxonomy(sanitize_params(params)) do
      {:ok, taxonomy} ->
        socket =
          socket
          |> assign(:taxonomy_form, @taxonomy_form_defaults)
          |> assign(:taxonomy_error, nil)
          |> load_taxonomy_state(taxonomy.id)

        {:noreply, socket}

      {:error, %{} = changeset} ->
        {:noreply,
         socket
         |> assign(:taxonomy_form, sanitize_params(params))
         |> assign(:taxonomy_error, format_errors(changeset))}
    end
  end

  def handle_event("create_portfolio_performance_presets", _params, socket) do
    Taxonomies.ensure_portfolio_performance_presets!()

    {:noreply,
     socket
     |> assign(:preset_success, gettext("Portfolio Performance presets are available."))
     |> load_taxonomy_state(socket.assigns.selected_taxonomy_id)}
  end

  def handle_event("create_category", %{"category" => params}, socket) do
    selected_taxonomy_id = socket.assigns.selected_taxonomy_id

    prepared_params = prepare_category_params(params, selected_taxonomy_id)
    selected_id_for_form = selected_taxonomy_id || parsed_id(params["taxonomy_id"])

    case Taxonomies.create_category(prepared_params) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> assign(:category_form, @category_form_defaults)
         |> assign(:category_error, nil)
         |> load_taxonomy_state(selected_id_for_form)}

      {:error, %{} = changeset} ->
        {:noreply,
         socket
         |> assign(:category_form, preserve_category_form_values(params, selected_id_for_form))
         |> assign(:category_error, format_errors(changeset))}
    end
  end

  def handle_event("update_category", %{"id" => category_id, "category" => params}, socket) do
    with {category_id, ""} <- Integer.parse(category_id),
         category <- Taxonomies.get_category!(category_id),
         {:ok, _} <- Taxonomies.update_category(category, sanitize_params(params)) do
      {:noreply, load_taxonomy_state(socket, socket.assigns.selected_taxonomy_id)}
    else
      {:error, changeset} ->
        {:noreply, assign(socket, :category_error, format_errors(changeset))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_category", %{"id" => category_id}, socket) do
    with {category_id, ""} <- Integer.parse(category_id),
         category <- Taxonomies.get_category!(category_id),
         {:ok, _} <- Taxonomies.delete_category(category) do
      {:noreply, load_taxonomy_state(socket, socket.assigns.selected_taxonomy_id)}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_security_for_assignment", %{"assignment" => params}, socket) do
    selected_security_id = parsed_id(params["security_id"])

    {:noreply,
     socket
     |> assign(:category_assignment_form, sanitize_assignment_form(params))
     |> assign(:category_assignment_error, nil)
     |> load_taxonomy_state(socket.assigns.selected_taxonomy_id, selected_security_id)}
  end

  def handle_event("assign_category_to_security", %{"assignment" => params}, socket) do
    with {security_id, ""} <- Integer.parse(params["security_id"] || ""),
         {category_id, ""} <- Integer.parse(params["category_id"] || ""),
         {:ok, _} <- Catalog.assign_category_to_security(security_id, category_id) do
      {:noreply,
       socket
       |> assign(:category_assignment_form, %{
         "security_id" => to_string(security_id),
         "category_id" => ""
       })
       |> assign(:category_assignment_error, nil)
       |> load_taxonomy_state(socket.assigns.selected_taxonomy_id, security_id)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:category_assignment_form, sanitize_assignment_form(params))
         |> assign(:category_assignment_error, format_errors(changeset))}

      _ ->
        {:noreply,
         socket
         |> assign(:category_assignment_form, sanitize_assignment_form(params))
         |> assign(:category_assignment_error, gettext("Select both security and category."))}
    end
  end

  def handle_event(
        "remove_category_assignment",
        %{"security-id" => security_id, "category-id" => category_id},
        socket
      ) do
    with {security_id, ""} <- Integer.parse(security_id),
         {category_id, ""} <- Integer.parse(category_id),
         {:ok, _} <- Catalog.remove_category_assignment(security_id, category_id) do
      {:noreply,
       socket
       |> assign(:category_assignment_error, nil)
       |> load_taxonomy_state(socket.assigns.selected_taxonomy_id, security_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp load_taxonomy_state(socket, selected_taxonomy_id \\ nil, selected_security_id \\ nil) do
    taxonomies = Taxonomies.list_taxonomies()
    selected_taxonomy_id = selected_taxonomy_id || fallback_selected_taxonomy_id(taxonomies)
    securities = Catalog.list_securities(:active)

    categories =
      if selected_taxonomy_id do
        Taxonomies.list_categories(selected_taxonomy_id)
      else
        []
      end

    selected_security_id =
      selected_security_id || parsed_id(socket.assigns[:category_assignment_form]["security_id"])

    selected_security_categories =
      if selected_security_id do
        Catalog.list_security_categories(selected_security_id)
      else
        []
      end

    socket
    |> assign(:taxonomies, taxonomies)
    |> assign(:securities, securities)
    |> assign(:selected_taxonomy_id, selected_taxonomy_id)
    |> assign(:selected_security_id, selected_security_id)
    |> assign(:selected_security_categories, selected_security_categories)
    |> assign(:selected_categories, categories)
    |> assign(:selected_category_tree, build_category_tree(categories))
    |> assign(
      :category_form,
      Map.put(@category_form_defaults, "taxonomy_id", selected_taxonomy_id || "")
    )
  end

  attr(:node, :map, required: true)

  defp tree_node(assigns) do
    ~H"""
    <li id={"tree-node-#{@node.category.id}"} class="app-shell-list-item">
      <div>
        <strong><%= @node.category.name %></strong>
        <span class="app-shell-muted">
          (<%= gettext("assigned") %>: <%= @node.assigned_security_count %>)
        </span>
      </div>
      <p class="app-shell-muted"><%= @node.category.description || gettext("No description") %></p>

      <%= if @node.children != [] do %>
        <ul class="app-shell-list" data-depth="child">
          <%= for child <- @node.children do %>
            <.tree_node node={child} />
          <% end %>
        </ul>
      <% end %>
    </li>
    """
  end

  defp build_category_tree(categories) do
    children_by_parent = Enum.group_by(categories, & &1.parent_id)

    categories
    |> Enum.filter(&is_nil(&1.parent_id))
    |> Enum.map(&build_tree_node(&1, children_by_parent))
  end

  defp build_tree_node(category, children_by_parent) do
    children =
      children_by_parent
      |> Map.get(category.id, [])
      |> Enum.map(&build_tree_node(&1, children_by_parent))

    %{
      category: category,
      assigned_security_count: Enum.count(category.security_category_assignments || []),
      children: children
    }
  end

  defp fallback_selected_taxonomy_id([]), do: nil

  defp fallback_selected_taxonomy_id(taxonomies) do
    taxonomies |> Enum.min_by(& &1.inserted_at) |> Map.get(:id)
  end

  defp sanitize_params(params) when is_map(params) do
    params
    |> Map.new(fn {key, value} -> {key, value} end)
    |> maybe_remove_empty_string("description")
    |> maybe_remove_empty_string("parent_id")
    |> maybe_remove_empty_string("sort_order")
  end

  defp sanitize_params(_), do: %{}

  defp maybe_remove_empty_string(params, key) do
    case Map.get(params, key) do
      "" -> Map.put(params, key, nil)
      _ -> params
    end
  end

  defp prepare_category_params(params, taxonomy_id) do
    params
    |> sanitize_params()
    |> Map.put("taxonomy_id", taxonomy_id || params["taxonomy_id"])
  end

  defp parsed_id(nil), do: nil

  defp parsed_id(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp preserve_category_form_values(params, selected_taxonomy_id) do
    params
    |> sanitize_params()
    |> Map.put("taxonomy_id", selected_taxonomy_id || "")
    |> Map.put("parent_id", params["parent_id"] || "")
  end

  defp sanitize_assignment_form(params) do
    %{
      "security_id" => params["security_id"] || "",
      "category_id" => params["category_id"] || ""
    }
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
  end
end
