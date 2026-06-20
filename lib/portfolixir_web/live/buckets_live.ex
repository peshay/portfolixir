defmodule PortfolixirWeb.BucketsLive do
  @moduledoc """
  Buckets & Views management (issue #446).

  One workspace for the tag-based wealth-scoping model (ADR-0018):

  - **Buckets** — overlapping tags. Create, rename, delete.
  - **Views** — global include/exclude filters over buckets. Create, rename,
    delete, and edit each view's `include_all` toggle plus its include/exclude
    bucket sets via the unified checkbox picker (a modal).
  - **Assignment** — set the default bucket set on each depot and each cash
    account, so freshly-recorded positions inherit a sensible scope.

  Every write goes through the `Portfolixir.Buckets` context with the interactive
  owner actor (`Portfolixir.Actor.owner_ui/0`); the web layer never touches the
  Repo. Per-position overrides live on the security holdings surface, where the
  concrete `{depot, security}` rows are, and are reached through progressive
  disclosure there.
  """

  use PortfolixirWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> assign(:editing_bucket_id, nil)
     |> assign(:editing_view_id, nil)
     |> assign(:bucket_picker_view, nil)
     |> load_state()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/buckets"
      page_title={gettext("Buckets & views")}
      page_subtitle={gettext("Tag holdings and scope your analytics")}
    >
      <div id="buckets-workspace" class="workspace-page">
        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <div class="hint" data-role="how-it-works">
          <p>
            <strong><%= gettext("How it works — two steps:") %></strong>
            <%= gettext(
              "1. Create buckets — tags you put on depots, cash accounts and positions. 2. Create a view — a saved include/exclude filter over buckets. A view is what appears in the view switcher on the Portfolio page, so you need both."
            ) %>
          </p>
          <p data-role="overlap-hint">
            <%= gettext(
              "Buckets are overlapping tags, not a partition: a holding can carry several buckets at once. Per-bucket figures may overlap and must never be read as a sum."
            ) %>
          </p>
        </div>

        <section id="buckets-section" class="workspace-section">
          <h2><%= gettext("1. Buckets") %></h2>
          <p class="section-hint">
            <%= gettext("Tags you assign to depots, cash accounts and individual positions.") %>
          </p>
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

          <ul id="bucket-list" class="bucket-list">
            <%= for bucket <- @buckets do %>
              <li id={"bucket-#{bucket.id}"} class="bucket-list__item">
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
                  <span class="bucket-list__actions">
                    <button
                      type="button"
                      class="icon-mini"
                      phx-click="edit_bucket"
                      phx-value-id={bucket.id}
                      aria-label={gettext("Rename bucket")}
                      title={gettext("Rename bucket")}
                    >✎</button>
                    <button
                      type="button"
                      class="icon-mini"
                      phx-click="delete_bucket"
                      phx-value-id={bucket.id}
                      data-confirm={gettext("Delete this bucket? It is removed from every assignment and view.")}
                      aria-label={gettext("Delete bucket")}
                      title={gettext("Delete bucket")}
                    >×</button>
                  </span>
                <% end %>
              </li>
            <% end %>
            <%= if @buckets == [] do %>
              <li class="hint"><%= gettext("No buckets yet.") %></li>
            <% end %>
          </ul>
        </section>

        <section id="views-section" class="workspace-section">
          <h2><%= gettext("2. Views") %></h2>
          <p class="section-hint">
            <%= gettext("Saved include/exclude filters over buckets. A view is what you pick in the view switcher on the Portfolio page.") %>
          </p>
          <p class="hint">
            <%= gettext("A view includes some buckets and excludes others. Exclude always wins.") %>
          </p>
          <form id="view-form" phx-submit="create_view" class="inline-form">
            <label>
              <span><%= gettext("New view") %></span>
              <input name="view[name]" required autocomplete="off" />
            </label>
            <button type="submit"><%= gettext("Add view") %></button>
          </form>

          <ul id="view-list" class="bucket-list">
            <%= for view <- @views_full do %>
              <li id={"view-#{view.id}"} class="bucket-list__item">
                <%= if @editing_view_id == view.id do %>
                  <form phx-submit="rename_view" class="inline-form bucket-edit-form">
                    <input type="hidden" name="view_id" value={view.id} />
                    <input
                      name="view[name]"
                      value={view.name}
                      aria-label={gettext("View name")}
                      required
                    />
                    <button type="submit" class="button"><%= gettext("Save") %></button>
                    <button type="button" phx-click="cancel_edit_view">
                      <%= gettext("Cancel") %>
                    </button>
                  </form>
                <% else %>
                  <span class="bucket-list__name"><%= view.name %></span>
                  <span class="bucket-list__actions">
                    <button
                      type="button"
                      class="icon-mini"
                      phx-click="edit_view_buckets"
                      phx-value-id={view.id}
                      aria-label={gettext("Edit view buckets")}
                      title={gettext("Edit view buckets")}
                    >⚙</button>
                    <button
                      type="button"
                      class="icon-mini"
                      phx-click="edit_view"
                      phx-value-id={view.id}
                      aria-label={gettext("Rename view")}
                      title={gettext("Rename view")}
                    >✎</button>
                    <button
                      type="button"
                      class="icon-mini"
                      phx-click="delete_view"
                      phx-value-id={view.id}
                      data-confirm={gettext("Delete this view?")}
                      aria-label={gettext("Delete view")}
                      title={gettext("Delete view")}
                    >×</button>
                  </span>
                <% end %>
              </li>
            <% end %>
            <%= if @views_full == [] do %>
              <li class="hint"><%= gettext("No views yet.") %></li>
            <% end %>
          </ul>
        </section>

        <section id="assignment-section" class="workspace-section">
          <h2><%= gettext("Default bucket assignment") %></h2>
          <%= if @portfolio do %>
            <p class="hint">
              <%= gettext("Set the default buckets a depot's positions and a cash account inherit.") %>
            </p>

            <div class="grid">
              <article class="panel">
                <h3><%= gettext("Depots") %></h3>
                <ul id="depot-assignment-list" class="assignment-list">
                  <%= for depot <- @depots do %>
                    <li id={"depot-assignment-#{depot.id}"} class="assignment-list__item">
                      <details>
                        <summary>
                          <span class="assignment-list__name"><%= depot.name %></span>
                          <span class="assignment-list__chips">
                            <%= chip_summary(depot.bucket_ids, @buckets) %>
                          </span>
                        </summary>
                        <form phx-submit="set_depot_buckets" class="bucket-checklist">
                          <input type="hidden" name="depot_id" value={depot.id} />
                          <.bucket_checklist
                            buckets={@buckets}
                            field="bucket_ids[]"
                            checked={depot.bucket_ids}
                            id_prefix={"depot-#{depot.id}"}
                          />
                          <button type="submit" class="button"><%= gettext("Save defaults") %></button>
                        </form>
                      </details>
                    </li>
                  <% end %>
                  <%= if @depots == [] do %>
                    <li class="hint"><%= gettext("No depots yet.") %></li>
                  <% end %>
                </ul>
              </article>

              <article class="panel">
                <h3><%= gettext("Cash accounts") %></h3>
                <ul id="cash-assignment-list" class="assignment-list">
                  <%= for cash <- @cash_accounts do %>
                    <li id={"cash-assignment-#{cash.id}"} class="assignment-list__item">
                      <details>
                        <summary>
                          <span class="assignment-list__name"><%= cash.name %></span>
                          <span class="assignment-list__chips">
                            <%= chip_summary(cash.bucket_ids, @buckets) %>
                          </span>
                        </summary>
                        <form phx-submit="set_cash_buckets" class="bucket-checklist">
                          <input type="hidden" name="cash_id" value={cash.id} />
                          <.bucket_checklist
                            buckets={@buckets}
                            field="bucket_ids[]"
                            checked={cash.bucket_ids}
                            id_prefix={"cash-#{cash.id}"}
                          />
                          <button type="submit" class="button"><%= gettext("Save buckets") %></button>
                        </form>
                      </details>
                    </li>
                  <% end %>
                  <%= if @cash_accounts == [] do %>
                    <li class="hint"><%= gettext("No cash accounts yet.") %></li>
                  <% end %>
                </ul>
              </article>
            </div>
          <% else %>
            <p class="hint">
              <%= gettext("Create a portfolio with a depot and a cash account to assign buckets.") %>
            </p>
          <% end %>
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
    </AppShell.shell>
    """
  end

  # -- components --------------------------------------------------------------

  attr(:buckets, :list, required: true)
  attr(:field, :string, required: true)
  attr(:checked, :list, required: true)
  attr(:id_prefix, :string, required: true)
  attr(:disabled, :boolean, default: false)

  defp bucket_checklist(assigns) do
    ~H"""
    <fieldset class="bucket-fieldset">
      <%= if @buckets == [] do %>
        <p class="hint"><%= gettext("Create a bucket first.") %></p>
      <% end %>
      <%= for bucket <- @buckets do %>
        <label class="bucket-checkbox" for={"#{@id_prefix}-#{bucket.id}"}>
          <input
            type="checkbox"
            id={"#{@id_prefix}-#{bucket.id}"}
            name={@field}
            value={bucket.id}
            checked={bucket.id in @checked}
            disabled={@disabled}
          />
          <span>
            <span
              :if={bucket.color}
              class="cat-swatch"
              style={"background:#{bucket.color}"}
              aria-hidden="true"
            >
            </span>
            <%= bucket.name %>
          </span>
        </label>
      <% end %>
    </fieldset>
    """
  end

  attr(:view, :any, required: true)
  attr(:buckets, :list, required: true)
  attr(:include_all, :boolean, required: true)
  attr(:include, :list, required: true)
  attr(:exclude, :list, required: true)

  defp view_bucket_modal(assigns) do
    ~H"""
    <div
      id="view-bucket-modal"
      class="modal-backdrop"
      phx-window-keydown={JS.push("close_bucket_picker")}
      phx-key="Escape"
    >
      <div
        class="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="view-bucket-modal-title"
        tabindex="-1"
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
      </div>
    </div>
    """
  end

  # -- bucket events ----------------------------------------------------------

  @impl true
  def handle_event("create_bucket", %{"bucket" => params}, socket) do
    case Buckets.create_bucket(Actor.owner_ui(), normalize_color(params)) do
      {:ok, _bucket} ->
        {:noreply, socket |> success(gettext("Bucket created")) |> load_state()}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event("edit_bucket", %{"id" => id}, socket) do
    case coerce_id(id) do
      {:ok, bucket_id} -> {:noreply, assign(socket, :editing_bucket_id, bucket_id)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_bucket", _params, socket) do
    {:noreply, assign(socket, :editing_bucket_id, nil)}
  end

  def handle_event("rename_bucket", %{"bucket_id" => id, "bucket" => params}, socket) do
    with {:ok, bucket_id} <- coerce_id(id),
         bucket when not is_nil(bucket) <- Buckets.get_bucket(bucket_id),
         {:ok, _} <- Buckets.update_bucket(Actor.owner_ui(), bucket, normalize_color(params)) do
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
    with {:ok, bucket_id} <- coerce_id(id),
         bucket when not is_nil(bucket) <- Buckets.get_bucket(bucket_id),
         {:ok, _} <- Buckets.delete_bucket(Actor.owner_ui(), bucket) do
      {:noreply, socket |> success(gettext("Bucket deleted")) |> load_state()}
    else
      _ -> {:noreply, socket}
    end
  end

  # -- view events ------------------------------------------------------------

  def handle_event("create_view", %{"view" => params}, socket) do
    case Buckets.create_view(Actor.owner_ui(), params) do
      {:ok, _view} ->
        {:noreply, socket |> success(gettext("View created")) |> load_state()}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event("edit_view", %{"id" => id}, socket) do
    case coerce_id(id) do
      {:ok, view_id} -> {:noreply, assign(socket, :editing_view_id, view_id)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_view", _params, socket) do
    {:noreply, assign(socket, :editing_view_id, nil)}
  end

  def handle_event("rename_view", %{"view_id" => id, "view" => params}, socket) do
    with {:ok, view_id} <- coerce_id(id),
         view when not is_nil(view) <- Buckets.get_view(view_id),
         {:ok, _} <- Buckets.update_view(Actor.owner_ui(), view, params) do
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
    with {:ok, view_id} <- coerce_id(id),
         view when not is_nil(view) <- Buckets.get_view(view_id),
         {:ok, _} <- Buckets.delete_view(Actor.owner_ui(), view) do
      {:noreply, socket |> success(gettext("View deleted")) |> load_state()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_view_buckets", %{"id" => id}, socket) do
    with {:ok, view_id} <- coerce_id(id),
         view when not is_nil(view) <- Buckets.get_view(view_id) do
      filter = Buckets.view_filter(view_id)
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
     |> assign(:picker_include, coerce_id_list(params["include"]))
     |> assign(:picker_exclude, coerce_id_list(params["exclude"]))}
  end

  def handle_event("save_view_buckets", params, socket) do
    with {:ok, view_id} <- coerce_id(params["view_id"]),
         view when not is_nil(view) <- Buckets.get_view(view_id),
         include_all? <- params["include_all"] == "true",
         include <- coerce_id_list(params["include"]),
         exclude <- coerce_id_list(params["exclude"]),
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

  # -- assignment events ------------------------------------------------------

  def handle_event("set_depot_buckets", params, socket) do
    with {:ok, depot_id} <- coerce_id(params["depot_id"]),
         depot when not is_nil(depot) <- Portfolios.get_securities_account(depot_id),
         true <- owned_depot?(socket, depot),
         :ok <-
           Buckets.set_depot_default_buckets(
             Actor.owner_ui(),
             depot,
             coerce_id_list(params["bucket_ids"])
           ) do
      {:noreply, socket |> success(gettext("Depot defaults saved")) |> load_state()}
    else
      {:error, :bucket_ids} ->
        {:noreply,
         failure(socket, gettext("That bucket no longer exists. Refresh and try again."))}

      _ ->
        {:noreply, failure(socket, gettext("Could not save depot defaults"))}
    end
  end

  def handle_event("set_cash_buckets", params, socket) do
    with {:ok, cash_id} <- coerce_id(params["cash_id"]),
         cash when not is_nil(cash) <- Portfolios.get_cash_account(cash_id),
         true <- owned_cash?(socket, cash),
         :ok <-
           Buckets.set_cash_account_buckets(
             Actor.owner_ui(),
             cash,
             coerce_id_list(params["bucket_ids"])
           ) do
      {:noreply, socket |> success(gettext("Cash account buckets saved")) |> load_state()}
    else
      {:error, :bucket_ids} ->
        {:noreply,
         failure(socket, gettext("That bucket no longer exists. Refresh and try again."))}

      _ ->
        {:noreply, failure(socket, gettext("Could not save cash account buckets"))}
    end
  end

  # -- data loading -----------------------------------------------------------

  defp load_state(socket) do
    portfolio = Portfolios.first_portfolio()
    buckets = Buckets.list_buckets()

    depots =
      if portfolio do
        portfolio.id
        |> Portfolios.list_securities_accounts_for_portfolio()
        |> Enum.map(&Map.put(&1, :bucket_ids, Buckets.depot_default_bucket_ids(&1.id)))
      else
        []
      end

    cash_accounts =
      if portfolio do
        portfolio.id
        |> Portfolios.list_cash_accounts_for_portfolio()
        |> Enum.map(&Map.put(&1, :bucket_ids, Buckets.cash_account_bucket_ids(&1.id)))
      else
        []
      end

    assign(socket,
      portfolio: portfolio,
      buckets: buckets,
      views_full: Buckets.list_views(),
      depots: depots,
      cash_accounts: cash_accounts
    )
  end

  defp owned_depot?(%{assigns: %{portfolio: %{id: pid}}}, depot), do: depot.portfolio_id == pid
  defp owned_depot?(_socket, _depot), do: false

  defp owned_cash?(%{assigns: %{portfolio: %{id: pid}}}, cash), do: cash.portfolio_id == pid
  defp owned_cash?(_socket, _cash), do: false

  # -- helpers ----------------------------------------------------------------

  defp chip_summary([], _buckets), do: gettext("no default buckets")

  defp chip_summary(bucket_ids, buckets) do
    names =
      buckets
      |> Enum.filter(&(&1.id in bucket_ids))
      |> Enum.map_join(", ", & &1.name)

    if names == "", do: gettext("no default buckets"), else: names
  end

  # An empty color picker submits "" — drop it so the bucket keeps no color.
  defp normalize_color(%{"color" => ""} = params), do: Map.delete(params, "color")
  defp normalize_color(params), do: params

  defp coerce_id(value) when is_integer(value), do: {:ok, value}

  defp coerce_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp coerce_id(_value), do: :error

  defp coerce_id_list(nil), do: []

  defp coerce_id_list(values) when is_list(values) do
    Enum.flat_map(values, fn value ->
      case coerce_id(value) do
        {:ok, id} -> [id]
        :error -> []
      end
    end)
  end

  defp coerce_id_list(_values), do: []

  defp success(socket, message), do: assign(socket, success: message, error: nil)
  defp failure(socket, message), do: assign(socket, error: message, success: nil)

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
