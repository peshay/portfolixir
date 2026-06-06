defmodule PortfolixirWeb.ClassificationsLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias PortfolixirWeb.AppShell

  @new_classification %{"name" => ""}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:classification_form, @new_classification)
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> load_state()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/classifications"
      page_title={gettext("Classifications")}
      page_subtitle={gettext("Organise securities into built-in and custom trees")}
    >
      <div id="classifications-workspace" phx-hook="ClassificationDnD" class="workspace-page">
        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <section class="workspace-section">
          <h2><%= gettext("Create classification") %></h2>
          <form id="classification-form" phx-submit="create_classification" class="inline-form">
            <label>
              <span><%= gettext("Name") %></span>
              <input name="classification[name]" value={@classification_form["name"]} required />
            </label>
            <button type="submit"><%= gettext("Create classification") %></button>
          </form>
        </section>

        <div class="classification-grid">
          <%= for tree <- @trees do %>
            <article class="classification-tree">
              <header class="classification-head">
                <h3><%= tree.classification.name %></h3>
                <%= if tree.classification.built_in do %>
                  <span class="badge"><%= gettext("Built-in") %></span>
                <% end %>
              </header>

              <%= unless tree.classification.built_in do %>
                <form phx-submit="create_category" class="inline-form category-form">
                  <input type="hidden" name="category[classification_id]" value={tree.classification.id} />
                  <input name="category[name]" placeholder={gettext("New category")} required />
                  <input type="color" name="category[color]" value="#7c3aed" aria-label={gettext("Color")} />
                  <button type="submit"><%= gettext("Add") %></button>
                </form>
              <% end %>

              <div class="category-list">
                <%= for view <- tree.categories do %>
                  <div class={category_class(tree)} {drop_attrs(tree, view.category)}>
                    <div class="category-head">
                      <span class="cat-swatch" style={swatch(view.category.color)} aria-hidden="true"></span>
                      <span class="cat-name"><%= view.category.name %></span>
                      <span class="cat-count"><%= length(view.securities) %></span>
                    </div>
                    <ul class="cat-securities">
                      <%= for security <- view.securities do %>
                        <li class="dnd-chip is-member">
                          <span><%= security.name %></span>
                          <%= unless tree.classification.built_in do %>
                            <button
                              type="button"
                              class="chip-remove"
                              phx-click="unassign"
                              phx-value-security_id={security.id}
                              phx-value-classification_id={tree.classification.id}
                              aria-label={gettext("Remove")}
                            >×</button>
                          <% end %>
                        </li>
                      <% end %>
                    </ul>
                  </div>
                <% end %>
              </div>
            </article>
          <% end %>
        </div>

        <section class="workspace-section securities-palette">
          <h2><%= gettext("Securities") %></h2>
          <p class="hint"><%= gettext("Drag a security into a custom category.") %></p>
          <ul class="palette-list">
            <%= for security <- @securities do %>
              <li class="dnd-chip" draggable="true" data-drag-security={security.id}>
                <span><%= security.name %></span>
                <small><%= security.currency_code %></small>
              </li>
            <% end %>
          </ul>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  @impl true
  def handle_event("create_classification", %{"classification" => params}, socket) do
    case Classifications.create_classification(params) do
      {:ok, _classification} ->
        {:noreply,
         socket
         |> assign(:classification_form, @new_classification)
         |> success(gettext("Classification created"))
         |> load_state()}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event("create_category", %{"category" => params}, socket) do
    case Classifications.create_category(params) do
      {:ok, _category} ->
        {:noreply, socket |> success(gettext("Category created")) |> load_state()}

      {:error, reason} ->
        {:noreply, failure(socket, error_message(reason))}
    end
  end

  def handle_event("assign_security", params, socket) do
    with {:ok, security_id} <- coerce_id(params["security_id"]),
         {:ok, classification_id} <- coerce_id(params["classification_id"]),
         {:ok, category_id} <- coerce_id(params["category_id"]),
         {:ok, _assignment} <-
           Classifications.assign_security(security_id, classification_id, category_id) do
      {:noreply, load_state(socket)}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("unassign", params, socket) do
    with {:ok, security_id} <- coerce_id(params["security_id"]),
         {:ok, classification_id} <- coerce_id(params["classification_id"]) do
      {:ok, _} = Classifications.unassign_security(security_id, classification_id)
      {:noreply, load_state(socket)}
    else
      :error -> {:noreply, socket}
    end
  end

  defp load_state(socket) do
    securities = Catalog.list_securities()
    securities_by_id = Map.new(securities, &{&1.id, &1})

    trees = Enum.map(Classifications.list_trees(), &build_tree_view(&1, securities_by_id))

    assign(socket, securities: securities, trees: trees)
  end

  defp build_tree_view(tree, securities_by_id) do
    by_category =
      tree.assignments
      |> Enum.group_by(& &1.category_id, & &1.security_id)

    categories =
      Enum.map(tree.categories, fn category ->
        members =
          by_category
          |> Map.get(category.id, [])
          |> Enum.map(&Map.get(securities_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1.name)

        %{category: category, securities: members}
      end)

    %{classification: tree.classification, categories: categories}
  end

  defp drop_attrs(%{classification: %{built_in: true}}, _category), do: []

  defp drop_attrs(%{classification: classification}, category) do
    [
      {"data-drop-category", category.id},
      {"data-drop-classification", classification.id}
    ]
  end

  defp category_class(%{classification: %{built_in: true}}), do: "dnd-dropzone is-builtin"
  defp category_class(_tree), do: "dnd-dropzone"

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

  defp success(socket, message), do: assign(socket, success: message, error: nil)
  defp failure(socket, message), do: assign(socket, error: message, success: nil)

  defp error_message(:builtin_locked), do: gettext("Built-in classifications cannot be edited")
  defp error_message(:category_mismatch), do: gettext("That category belongs to another tree")
  defp error_message(:not_found), do: gettext("Not found")
  defp error_message(:category_not_found), do: gettext("Category not found")
  defp error_message(%Ecto.Changeset{} = changeset), do: changeset_error(changeset)
  defp error_message(_other), do: gettext("Something went wrong")

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
