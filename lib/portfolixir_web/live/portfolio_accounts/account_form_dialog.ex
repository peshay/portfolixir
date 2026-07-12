defmodule PortfolixirWeb.PortfolioAccounts.AccountFormDialog do
  @moduledoc """
  Modal dialog for creating a depot with its linked cash account — or a cash
  account alone — in one flow (#491, ADR-0024).

  No portfolio decision appears anywhere: the internal compatibility binding
  resolves to `Portfolixir.Portfolios.default_portfolio/1`. Optional initial
  bucket tags (existing buckets plus one inline-created tag) become the
  starting membership of every record the dialog creates, written through the
  journaled `Portfolixir.Buckets` context.
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @empty_form %{
    "depot_name" => "",
    "cash_account_id" => "",
    "cash_name" => "",
    "currency_code" => "EUR",
    "bucket_ids" => [],
    "new_tag" => ""
  }

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:step, :choose)
     |> assign(:mode, nil)
     |> assign(:form, @empty_form)
     |> assign(:errors, %{})
     |> assign(:bucket_error, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="modal-backdrop"
      phx-window-keydown={JS.push("close", target: @myself)}
      phx-key="Escape"
    >
      <div class="modal" role="dialog" aria-modal="true" aria-labelledby={"#{@id}-title"}>
        <header class="modal-head">
          <h2 id={"#{@id}-title"}><%= dialog_title(@step, @mode) %></h2>
          <button
            type="button"
            class="icon-button"
            aria-label={gettext("Close")}
            phx-click="close"
            phx-target={@myself}
          >
            <AppShell.icon name={:x} />
          </button>
        </header>

        <div class="modal-body">
          <%= case @step do %>
            <% :choose -> %>
              <%= render_choose(assigns) %>
            <% :form -> %>
              <%= render_form(assigns) %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp render_choose(assigns) do
    ~H"""
    <div class="dialog-choose" role="group" aria-label={gettext("What to create")}>
      <button
        type="button"
        class="choose-card"
        phx-click="choose_mode"
        phx-value-mode="depot"
        phx-target={@myself}
      >
        <span class="choose-title"><%= gettext("Depot with cash account") %></span>
        <span class="choose-sub">
          <%= gettext("A depot for security positions plus the cash account it settles against.") %>
        </span>
      </button>

      <button
        type="button"
        class="choose-card"
        phx-click="choose_mode"
        phx-value-mode="cash"
        phx-target={@myself}
      >
        <span class="choose-title"><%= gettext("Cash account only") %></span>
        <span class="choose-sub">
          <%= gettext("A standalone account for cash balances, e.g. a giro or call-money account.") %>
        </span>
      </button>
    </div>
    """
  end

  defp render_form(assigns) do
    ~H"""
    <form id="account-dialog-form" phx-change="form_change" phx-submit="save" phx-target={@myself}>
      <%= if @bucket_error do %>
        <p class="alert-error" role="alert"><%= @bucket_error %></p>
      <% end %>

      <div class="form-grid">
        <%= if @mode == "depot" do %>
          <.text_field
            name="depot_name"
            label={gettext("Depot name")}
            value={@form["depot_name"]}
            required={true}
            errors={@errors}
          />
          <label>
            <span><%= gettext("Cash account") %></span>
            <select name="account[cash_account_id]">
              <option value="" selected={@form["cash_account_id"] == ""}>
                <%= gettext("Create a new cash account") %>
              </option>
              <option
                :for={cash <- @cash_accounts}
                value={cash.id}
                selected={@form["cash_account_id"] == to_string(cash.id)}
              >
                <%= cash.name %> (<%= cash.currency_code %>)
              </option>
            </select>
          </label>
        <% end %>

        <%= if new_cash?(@mode, @form) do %>
          <.text_field
            name="cash_name"
            label={gettext("Cash account name")}
            value={@form["cash_name"]}
            required={true}
            errors={@errors}
          />
          <.text_field
            name="currency_code"
            label={gettext("Currency")}
            value={@form["currency_code"]}
            required={true}
            maxlength="3"
            errors={@errors}
          />
        <% end %>
      </div>

      <fieldset class="bucket-fieldset">
        <legend><%= gettext("Initial buckets (optional)") %></legend>
        <p :if={@buckets != []} class="hint">
          <%= gettext("The new records start out tagged with these buckets.") %>
        </p>
        <label :for={bucket <- @buckets} class="bucket-checkbox">
          <input
            type="checkbox"
            name="account[bucket_ids][]"
            value={bucket.id}
            checked={to_string(bucket.id) in @form["bucket_ids"]}
          />
          <span>
            <%= bucket.name %>
            <small :if={bucket.dimension == "scope"}>(<%= gettext("scope") %>)</small>
          </span>
        </label>
        <label>
          <span><%= gettext("New tag (optional)") %></span>
          <input
            name="account[new_tag]"
            value={@form["new_tag"]}
            autocomplete="off"
            placeholder={gettext("e.g. Household")}
          />
        </label>
      </fieldset>

      <div class="modal-footer">
        <button type="button" class="button-ghost" phx-click="back" phx-target={@myself}>
          <%= gettext("Back") %>
        </button>
        <button type="submit" class="button-primary"><%= submit_label(@mode) %></button>
      </div>
    </form>
    """
  end

  attr(:name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, default: "")
  attr(:required, :boolean, default: false)
  attr(:maxlength, :any, default: nil)
  attr(:errors, :map, default: %{})

  defp text_field(assigns) do
    ~H"""
    <label>
      <span><%= @label %></span>
      <input
        type="text"
        name={"account[" <> @name <> "]"}
        value={@value || ""}
        required={@required}
        maxlength={@maxlength}
      />
      <%= if msg = @errors[@name] do %>
        <span class="field-error"><%= msg %></span>
      <% end %>
    </label>
    """
  end

  defp dialog_title(:choose, _mode), do: gettext("Add depot & account")
  defp dialog_title(:form, "depot"), do: gettext("New depot with cash account")
  defp dialog_title(:form, _cash), do: gettext("New cash account")

  defp submit_label("depot"), do: gettext("Create depot & account")
  defp submit_label(_cash), do: gettext("Create cash account")

  defp new_cash?("cash", _form), do: true
  defp new_cash?("depot", form), do: form["cash_account_id"] in [nil, ""]
  defp new_cash?(_mode, _form), do: false

  # -- events ---------------------------------------------------------------

  @impl true
  def handle_event("close", _params, socket) do
    notify_parent(socket, :close)
    {:noreply, socket}
  end

  def handle_event("choose_mode", %{"mode" => mode}, socket) when mode in ["depot", "cash"] do
    {:noreply,
     socket
     |> assign(:mode, mode)
     |> assign(:step, :form)
     |> assign(:form, @empty_form)
     |> assign(:errors, %{})
     |> assign(:bucket_error, nil)}
  end

  def handle_event("back", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :choose)
     |> assign(:mode, nil)
     |> assign(:errors, %{})
     |> assign(:bucket_error, nil)}
  end

  def handle_event("form_change", params, socket) do
    {:noreply, assign(socket, :form, normalize_form(socket.assigns.form, params["account"]))}
  end

  def handle_event("save", params, socket) do
    form = normalize_form(socket.assigns.form, params["account"])
    socket = assign(socket, :form, form)

    with {:ok, bucket_ids} <- resolve_initial_buckets(form),
         {:ok, records} <- create_records(socket.assigns.mode, form, socket),
         :ok <- assign_initial_buckets(records, bucket_ids) do
      notify_parent(socket, {:created, success_message(socket.assigns.mode)})
      {:noreply, socket}
    else
      {:error, :scope_conflict} ->
        {:noreply,
         assign(
           socket,
           :bucket_error,
           gettext("Only one scope bucket per account — pick at most one.")
         )}

      # `ensure_tag_bucket/2` refuses to reuse a scope bucket's name as a free
      # tag (fix round): tell the user instead of failing opaquely.
      {:error, :name_taken_by_scope_bucket} ->
        {:noreply,
         assign(
           socket,
           :bucket_error,
           gettext("That name belongs to a scope bucket — pick a different tag name.")
         )}

      {:error, {:field_errors, errors}} ->
        {:noreply, socket |> assign(:errors, errors) |> assign(:bucket_error, nil)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, assign(socket, :bucket_error, gettext("The new tag could not be created."))}
    end
  end

  # -- create flow ------------------------------------------------------------

  # Resolves the checked buckets plus the optional inline tag into one id set,
  # rejecting more than one exclusive scope bucket BEFORE anything is created —
  # the invariant fails loud and early, never after a partial write.
  defp resolve_initial_buckets(form) do
    selected = coerce_id_list(form["bucket_ids"])

    with {:ok, ids} <- add_new_tag(selected, form["new_tag"]) do
      known = Buckets.list_buckets() |> Map.new(&{&1.id, &1})
      buckets = ids |> Enum.uniq() |> Enum.map(&Map.get(known, &1)) |> Enum.reject(&is_nil/1)

      if Enum.count(buckets, &(&1.dimension == "scope")) > 1 do
        {:error, :scope_conflict}
      else
        {:ok, Enum.map(buckets, & &1.id)}
      end
    end
  end

  defp add_new_tag(ids, new_tag) do
    case String.trim(new_tag || "") do
      "" ->
        {:ok, ids}

      name ->
        with {:ok, bucket} <- Buckets.ensure_tag_bucket(Actor.owner_ui(), name) do
          {:ok, ids ++ [bucket.id]}
        end
    end
  end

  defp create_records("cash", form, _socket) do
    with {:ok, cash} <- create_cash_account(form) do
      {:ok, %{depot: nil, cash: cash, cash_created?: true}}
    end
  end

  defp create_records("depot", form, socket) do
    # The depot name is pre-validated so a blank one can never leave a freshly
    # created cash account dangling without its depot.
    with :ok <- require_field(form, "depot_name"),
         {:ok, cash, created?} <- resolve_cash_account(form, socket),
         {:ok, depot} <- create_depot(form, cash) do
      {:ok, %{depot: depot, cash: cash, cash_created?: created?}}
    end
  end

  defp resolve_cash_account(form, socket) do
    case form["cash_account_id"] do
      "" ->
        with {:ok, cash} <- create_cash_account(form), do: {:ok, cash, true}

      id ->
        existing =
          Enum.find(socket.assigns.cash_accounts, &(to_string(&1.id) == id))

        if existing do
          {:ok, existing, false}
        else
          {:error, {:field_errors, %{"cash_account_id" => gettext("no longer exists")}}}
        end
    end
  end

  defp create_cash_account(form) do
    # ADR-0024: the internal binding is resolved, never asked for.
    Portfolios.create_cash_account(Actor.owner_ui(), %{
      "name" => form["cash_name"],
      "currency_code" => form["currency_code"],
      "portfolio_id" => Portfolios.default_portfolio(Actor.owner_ui()).id
    })
    |> map_changeset_errors(%{"name" => "cash_name"})
  end

  defp create_depot(form, cash) do
    Portfolios.create_securities_account(Actor.owner_ui(), %{
      "name" => form["depot_name"],
      "cash_account_id" => cash.id,
      "portfolio_id" => Portfolios.default_portfolio(Actor.owner_ui()).id
    })
    |> map_changeset_errors(%{"name" => "depot_name"})
  end

  defp assign_initial_buckets(_records, []), do: :ok

  defp assign_initial_buckets(records, bucket_ids) do
    with :ok <- set_depot_buckets(records.depot, bucket_ids) do
      # Only a cash account this dialog created gets the initial tags; an
      # existing linked account keeps its membership untouched.
      if records.cash_created?,
        do: Buckets.set_cash_account_buckets(Actor.owner_ui(), records.cash, bucket_ids),
        else: :ok
    end
  end

  defp set_depot_buckets(nil, _bucket_ids), do: :ok

  defp set_depot_buckets(depot, bucket_ids),
    do: Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, bucket_ids)

  defp success_message("depot"), do: gettext("Depot and cash account created")
  defp success_message(_cash), do: gettext("Cash account created")

  # -- helpers ----------------------------------------------------------------

  defp normalize_form(form, nil), do: form

  defp normalize_form(form, params) when is_map(params) do
    form
    |> Map.merge(Map.take(params, Map.keys(@empty_form)))
    |> Map.put("bucket_ids", List.wrap(params["bucket_ids"]))
  end

  defp require_field(form, field) do
    if String.trim(form[field] || "") == "" do
      {:error, {:field_errors, %{field => gettext("can't be blank")}}}
    else
      :ok
    end
  end

  defp map_changeset_errors({:ok, record}, _mapping), do: {:ok, record}

  defp map_changeset_errors({:error, %Ecto.Changeset{} = changeset}, mapping) do
    errors =
      changeset.errors
      |> Map.new(fn {field, {message, _opts}} ->
        key = Atom.to_string(field)
        {Map.get(mapping, key, key), message}
      end)

    {:error, {:field_errors, errors}}
  end

  defp coerce_id_list(values) when is_list(values) do
    Enum.flat_map(values, fn value ->
      case Integer.parse(to_string(value)) do
        {id, ""} -> [id]
        _ -> []
      end
    end)
  end

  defp coerce_id_list(_values), do: []

  defp notify_parent(socket, message) do
    send(self(), {:dialog, socket.assigns.id, message})
  end
end
