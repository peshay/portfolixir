defmodule PortfolixirWeb.CategoryManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Taxonomies
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

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:taxonomy_form, @taxonomy_form_defaults)
      |> assign(:category_form, @category_form_defaults)
      |> assign(:taxonomy_error, nil)
      |> assign(:category_error, nil)
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

      <div id="classification-workspace" class="app-shell-workspace-grid">
        <section
          id="taxonomy-management"
          class="app-shell-section-card"
          data-priority="primary"
        >
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Taxonomies") %></h2>
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
            <div id="no-taxonomies" class="app-shell-empty-state">
              <h3><%= gettext("No taxonomies yet") %></h3>
              <p><%= gettext("Create a taxonomy before adding categories.") %></p>
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
          <% end %>
        </section>

        <section
          id="category-management"
          class="app-shell-section-card"
          data-priority="secondary"
        >
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Categories") %></h2>
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
              <div id="no-categories" class="app-shell-empty-state">
                <h3><%= gettext("No categories yet") %></h3>
                <p><%= gettext("Add the first category for this taxonomy.") %></p>
              </div>
            <% else %>
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
            <div id="no-taxonomy-selected" class="app-shell-empty-state">
              <h3><%= gettext("Create or select a taxonomy first") %></h3>
              <p><%= gettext("Categories belong to one taxonomy, so choose the grouping system before adding them.") %></p>
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

  defp load_taxonomy_state(socket, selected_taxonomy_id \\ nil) do
    taxonomies = Taxonomies.list_taxonomies()
    selected_taxonomy_id = selected_taxonomy_id || fallback_selected_taxonomy_id(taxonomies)

    categories =
      if selected_taxonomy_id do
        Taxonomies.list_categories(selected_taxonomy_id)
      else
        []
      end

    socket
    |> assign(:taxonomies, taxonomies)
    |> assign(:selected_taxonomy_id, selected_taxonomy_id)
    |> assign(:selected_categories, categories)
    |> assign(
      :category_form,
      Map.put(@category_form_defaults, "taxonomy_id", selected_taxonomy_id || "")
    )
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

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
  end
end
