defmodule PortfolixirWeb.ClassificationsLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias PortfolixirWeb.AppShell

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
     |> assign(:current_path, "/classifications")}
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

  defp apply_action(socket, :show, %{"id" => id}) do
    case Integer.parse(id) do
      {classification_id, ""} ->
        socket
        |> assign(:query, "")
        |> assign(:editing_id, nil)
        |> load_show(classification_id)
      _ -> push_navigate(socket, to: "/classifications")
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
        <% end %>

        <%= if @tree.editable do %>
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
              editing_id={@editing_id}
            />
          <% end %>
          <%= if @tree.nodes == [] and not @tree.filtering? do %>
            <p class="hint"><%= gettext("No categories yet.") %></p>
          <% end %>
          <%= if @tree.filtering? and @tree.nodes == [] and @tree.unsorted == [] do %>
            <p class="hint"><%= gettext("No securities match your search.") %></p>
          <% end %>
        </section>

        <details class="cat-node unsorted-node" open {unsorted_attrs(@tree)}>
          <summary class="cat-summary">
            <span class="cat-swatch is-empty" aria-hidden="true"></span>
            <span class="cat-name"><%= gettext("Unsorted") %></span>
            <span class="cat-count"><%= length(@tree.unsorted) %></span>
          </summary>
          <div class="cat-body">
            <ul class="cat-securities">
              <%= for security <- @tree.unsorted do %>
                <li
                  class={["dnd-row", @tree.editable && "is-draggable"]}
                  draggable={if @tree.editable, do: "true", else: nil}
                  data-drag-security={if @tree.editable, do: security.id, else: nil}
                >
                  <span class="row-name"><%= security.name %></span>
                  <small class="row-ccy"><%= security.currency_code %></small>
                </li>
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

  defp category_node(assigns) do
    ~H"""
    <details class="cat-node" open {category_attrs(@editable, @classification_id, @node.category.id)}>
      <summary class="cat-summary">
        <span class="cat-swatch" style={swatch(@node.category.color)} aria-hidden="true"></span>
        <span class="cat-name">
          <%= @node.category.name %>
          <%= if @node.category.description not in [nil, ""] do %>
            <small class="cat-description-inline"><%= @node.category.description %></small>
          <% end %>
        </span>
        <span class="cat-count"><%= length(@node.securities) %></span>
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
            <li
              class={["dnd-row", @editable && "is-draggable"]}
              draggable={if @editable, do: "true", else: nil}
              data-drag-security={if @editable, do: security.id, else: nil}
            >
              <span class="row-name"><%= security.name %></span>
              <small class="row-ccy"><%= security.currency_code %></small>
            </li>
          <% end %>
        </ul>
        <%= for child <- @node.children do %>
          <.category_node
            node={child}
            classification_id={@classification_id}
            editable={@editable}
            editing_id={@editing_id}
          />
        <% end %>
      </div>
    </details>
    """
  end

  @impl true
  def handle_event("create_classification", %{"classification" => params}, socket) do
    case Classifications.create_classification(params) do
      {:ok, classification} ->
        {:noreply, push_navigate(socket, to: "/classifications/#{classification.id}")}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event("create_category", %{"category" => params}, socket) do
    case Classifications.create_category(params) do
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
         {:ok, _} <- Classifications.update_category(category, params) do
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
         {:ok, _} <- Classifications.recolor_category(category, color) do
      {:noreply, reload(socket)}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    with {:ok, category_id} <- coerce_id(id),
         category when not is_nil(category) <- Classifications.get_category(category_id),
         {:ok, _} <- Classifications.delete_category(category) do
      {:noreply, socket |> success(gettext("Category deleted")) |> reload()}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_classification", _params, socket) do
    with id when not is_nil(id) <- socket.assigns.selected_id,
         classification when not is_nil(classification) <- Classifications.get_classification(id),
         {:ok, _} <- Classifications.delete_classification(classification) do
      {:noreply, push_navigate(socket, to: "/classifications")}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("filter_tree", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> reload()}
  end

  def handle_event("assign_security", params, socket) do
    with {:ok, security_id} <- coerce_id(params["security_id"]),
         {:ok, classification_id} <- coerce_id(params["classification_id"]),
         {:ok, category_id} <- coerce_id(params["category_id"]),
         {:ok, _assignment} <-
           Classifications.assign_security(security_id, classification_id, category_id) do
      {:noreply, reload(socket)}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("unassign", params, socket) do
    with {:ok, security_id} <- coerce_id(params["security_id"]),
         {:ok, classification_id} <- coerce_id(params["classification_id"]) do
      {:ok, _} = Classifications.unassign_security(security_id, classification_id)
      {:noreply, reload(socket)}
    else
      :error -> {:noreply, socket}
    end
  end

  def handle_event("assign_securities", params, socket) do
    with {:ok, ids} <- coerce_ids(params["security_ids"]),
         {:ok, classification_id} <- coerce_id(params["classification_id"]),
         {:ok, category_id} <- coerce_id(params["category_id"]),
         {:ok, count} <- Classifications.assign_securities(ids, classification_id, category_id) do
      {:noreply, socket |> success(moved_message(count)) |> reload()}
    else
      {:error, reason} -> {:noreply, failure(socket, error_message(reason))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("unassign_many", params, socket) do
    with {:ok, ids} <- coerce_ids(params["security_ids"]),
         {:ok, classification_id} <- coerce_id(params["classification_id"]) do
      {:ok, count} = Classifications.unassign_securities(ids, classification_id)
      {:noreply, socket |> success(unassigned_message(count)) |> reload()}
    else
      :error -> {:noreply, socket}
    end
  end

  # -- data loading ---------------------------------------------------------

  defp reload(%{assigns: %{selected_id: nil}} = socket), do: socket
  defp reload(socket), do: load_show(socket, socket.assigns.selected_id)

  defp load_show(socket, classification_id) do
    tree = Enum.find(Classifications.list_trees(), &(&1.classification.id == classification_id))

    if tree do
      assign(socket, selected_id: classification_id, tree: build_view(tree, socket.assigns.query))
    else
      assign(socket, selected_id: nil, tree: nil)
    end
  end

  defp build_view(tree, query) do
    needle = query |> to_string() |> String.trim() |> String.downcase()
    securities = Catalog.list_securities()
    securities_by_id = Map.new(securities, &{&1.id, &1})

    by_category =
      tree.assignments
      |> Enum.group_by(& &1.category_id, & &1.security_id)
      |> Map.new(fn {category_id, ids} ->
        members =
          ids
          |> Enum.map(&Map.get(securities_by_id, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(&matches?(&1, needle))
          |> Enum.sort_by(& &1.name)

        {category_id, members}
      end)

    assigned_ids = MapSet.new(tree.assignments, & &1.security_id)

    unsorted =
      securities
      |> Enum.reject(&MapSet.member?(assigned_ids, &1.id))
      |> Enum.filter(&matches?(&1, needle))
      |> Enum.sort_by(& &1.name)

    grouped = Enum.group_by(tree.categories, & &1.parent_id)
    nodes = build_nodes(grouped, nil, by_category)

    %{
      classification: tree.classification,
      editable: not tree.classification.built_in,
      nodes: if(needle == "", do: nodes, else: prune_nodes(nodes)),
      flat: flatten(tree.categories),
      unsorted: unsorted,
      query: query,
      filtering?: needle != ""
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
      %{
        category: category,
        securities: Map.get(by_category, category.id, []),
        children: build_nodes(grouped, category.id, by_category)
      }
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

  defp unsorted_attrs(%{editable: false}), do: []

  defp unsorted_attrs(%{editable: true, classification: %{id: id}}) do
    [
      {"data-dropzone", ""},
      {"data-drop-kind", "unassign"},
      {"data-classification", id}
    ]
  end

  defp workspace_attrs(%{editable: true, classification: %{id: id}}),
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
