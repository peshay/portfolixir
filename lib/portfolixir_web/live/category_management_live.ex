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

    {:ok, load_taxonomy_state(socket)}
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/taxonomies">
      <h1>Category Management</h1>

      <section id="taxonomy-management">
        <h2>Taxonomies</h2>

        <%= if @taxonomy_error do %>
          <p id="taxonomy-form-error"><%= @taxonomy_error %></p>
        <% end %>

        <form id="taxonomy-form" phx-submit="create_taxonomy">
          <label for="taxonomy-name">Name</label>
          <input id="taxonomy-name" name="taxonomy[name]" value={@taxonomy_form["name"]} />
          <label for="taxonomy-description">Description</label>
          <textarea id="taxonomy-description" name="taxonomy[description]"><%= @taxonomy_form["description"] %></textarea>
          <button type="submit">Create Taxonomy</button>
        </form>

        <%= if Enum.empty?(@taxonomies) do %>
          <p id="no-taxonomies">No taxonomies yet.</p>
        <% else %>
          <ul id="taxonomy-list">
            <%= for taxonomy <- @taxonomies do %>
              <li>
                <button
                  id={"taxonomy-#{taxonomy.id}"}
                  phx-click="select_taxonomy"
                  phx-value-id={taxonomy.id}
                  disabled={taxonomy.id == @selected_taxonomy_id}
                >
                  <%= taxonomy.name %> - <%= taxonomy.description || "No description" %>
                </button>
              </li>
            <% end %>
          </ul>
        <% end %>
      </section>

      <section id="category-management">
        <h2>Categories</h2>

        <%= if @selected_taxonomy_id do %>
          <%= if @category_error do %>
            <p id="category-form-error"><%= @category_error %></p>
          <% end %>

          <form id="category-form" phx-submit="create_category">
            <input type="hidden" name="category[taxonomy_id]" value={@selected_taxonomy_id} />

            <label for="category-name">Name</label>
            <input id="category-name" name="category[name]" value={@category_form["name"]} />

            <label for="category-description">Description</label>
            <textarea id="category-description" name="category[description]"><%= @category_form["description"] %></textarea>

            <label for="category-parent-id">Parent (optional)</label>
            <select id="category-parent-id" name="category[parent_id]">
              <option value="">None</option>
              <%= for category <- @selected_categories do %>
                <option value={category.id}><%= category.name %></option>
              <% end %>
            </select>

            <label for="category-color">Color (optional)</label>
            <input id="category-color" name="category[color]" value={@category_form["color"]} />

            <label for="category-sort-order">Sort order (optional)</label>
            <input
              id="category-sort-order"
              name="category[sort_order]"
              type="number"
              min="0"
              value={@category_form["sort_order"]}
            />

            <button type="submit">Add Category</button>
          </form>

          <%= if Enum.empty?(@selected_categories) do %>
            <p id="no-categories">No categories yet.</p>
          <% else %>
            <ul id="category-list">
              <%= for category <- @selected_categories do %>
                <li id={"category-#{category.id}"}>
                  <strong><%= category.name %></strong>
                  <p><%= category.description || "No description" %></p>

                  <form
                    id={"edit-category-form-#{category.id}"}
                    phx-submit="update_category"
                    phx-value-id={category.id}
                  >
                    <label>Name</label>
                    <input name="category[name]" value={category.name} />

                    <label>Description</label>
                    <textarea name="category[description]"><%= category.description %></textarea>

                    <button type="submit">Save</button>
                  </form>

                  <button
                    id={"delete-category-#{category.id}"}
                    phx-click="delete_category"
                    phx-value-id={category.id}
                  >
                    Delete
                  </button>
                </li>
              <% end %>
            </ul>
          <% end %>
        <% else %>
          <p id="no-taxonomy-selected">Create or select a taxonomy first.</p>
        <% end %>
      </section>
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
    |> maybe_remove_empty_string("color")
    |> normalize_parent_id()
    |> normalize_sort_order()
  end

  defp sanitize_params(_params), do: %{}

  defp preserve_category_form_values(params, selected_taxonomy_id) do
    %{
      "taxonomy_id" => selected_taxonomy_id || "",
      "parent_id" => Map.get(params, "parent_id", ""),
      "name" => Map.get(params, "name", ""),
      "description" => Map.get(params, "description", ""),
      "color" => Map.get(params, "color", ""),
      "sort_order" => Map.get(params, "sort_order", "")
    }
  end

  defp prepare_category_params(params, selected_taxonomy_id) do
    params =
      params
      |> sanitize_params()
      |> Map.put("taxonomy_id", selected_taxonomy_id)

    params
  end

  defp maybe_remove_empty_string(params, key) do
    case Map.get(params, key) do
      "" -> Map.put(params, key, nil)
      _ -> params
    end
  end

  defp normalize_parent_id(params) do
    Map.put(params, "parent_id", normalize_optional_integer(Map.get(params, "parent_id")))
  end

  defp normalize_sort_order(params) do
    Map.put(params, "sort_order", normalize_optional_integer(Map.get(params, "sort_order")))
  end

  defp normalize_optional_integer(value) when value in ["", nil], do: nil

  defp normalize_optional_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_optional_integer(value) when is_integer(value), do: value
  defp normalize_optional_integer(value), do: value

  defp parsed_id(nil), do: nil
  defp parsed_id(value) when is_integer(value), do: value

  defp parsed_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} ->
      "#{field} #{message}"
    end)
  end
end
