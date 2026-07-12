defmodule PortfolixirWeb.PortfolioAccountsLive do
  @moduledoc """
  Accounts & depots administration (ADR-0022 area, reshaped by ADR-0024,
  #491/#559): one paired table of depots with their linked cash accounts,
  bucket membership editable as chips on each row, a single creation dialog
  (`PortfolixirWeb.PortfolioAccounts.AccountFormDialog`), and the minimal
  read-only list of every portfolio record (ADR-0024 modification 1: no
  invisible writable resource). No portfolio decision appears anywhere — the
  internal compatibility binding resolves to one deterministic default
  portfolio.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.PortfolioAccounts.AccountFormDialog

  @color_format ~r/^#[0-9a-fA-F]{3,8}$/

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> assign(:account_dialog?, false)
     |> assign(:picker, nil)
     |> assign(:bucket_error, nil)
     |> load_state()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/portfolios"
      page_title={gettext("Accounts & depots")}
      page_subtitle={gettext("Depots, cash accounts, and their buckets")}
    >
      <div id="portfolios-workspace" class="workspace-page">
        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <section id="accounts-panel" class="workspace-section">
          <div class="section-head">
            <h2><%= gettext("Depots and cash accounts") %></h2>
            <button
              id="add-account-button"
              type="button"
              class="button-primary"
              phx-click="open_account_dialog"
            >
              <AppShell.icon name={:plus} size={14} /> <%= gettext("Add depot & account") %>
            </button>
          </div>

          <%= if @rows == [] do %>
            <p class="hint" data-role="accounts-empty">
              <%= gettext("No accounts yet — add your first depot and cash account.") %>
            </p>
          <% else %>
            <div class="data-table-wrapper">
              <table id="accounts-table" class="data-table accounts-table" data-role="accounts-table">
                <thead>
                  <tr>
                    <th><%= gettext("Name") %></th>
                    <th><%= gettext("Currency") %></th>
                    <th><%= gettext("Liquidity role") %></th>
                    <th><%= gettext("Buckets") %></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @rows} id={row_id(row)} data-role="account-row">
                    <td class="account-names">
                      <%= if row.depot do %>
                        <span class="account-name"><%= row.depot.name %></span>
                        <span :if={row.cash} class="account-sub"><%= row.cash.name %></span>
                        <span :if={is_nil(row.cash)} class="account-sub">
                          <%= gettext("No cash account linked") %>
                        </span>
                      <% else %>
                        <span class="account-name"><%= row.cash.name %></span>
                        <span class="account-sub"><%= gettext("Cash account") %></span>
                      <% end %>
                    </td>
                    <td><%= (row.cash && row.cash.currency_code) || "—" %></td>
                    <td>
                      <%= if row.cash && row.cash_controls? do %>
                        <label class="cash-quote-toggle">
                          <form id={"liquidity-role-form-#{row.cash.id}"} phx-change="set_liquidity_role">
                            <input type="hidden" name="account_id" value={row.cash.id} />
                            <select id={"liquidity-role-#{row.cash.id}"} name="liquidity_role">
                              <option value="free_cash" selected={row.cash.liquidity_role == "free_cash"}>
                                <%= gettext("Free cash") %>
                              </option>
                              <option
                                value="credit_line"
                                selected={row.cash.liquidity_role == "credit_line"}
                              >
                                <%= gettext("Credit line") %>
                              </option>
                              <option value="reserve" selected={row.cash.liquidity_role == "reserve"}>
                                <%= gettext("Reserve") %>
                              </option>
                            </select>
                          </form>
                        </label>
                      <% else %>
                        <span :if={row.cash} class="hint"><%= gettext("shared account") %></span>
                        <span :if={is_nil(row.cash)}>—</span>
                      <% end %>
                    </td>
                    <td class="account-buckets">
                      <.bucket_chips
                        :if={row.depot}
                        owner="depot"
                        owner_id={row.depot.id}
                        label={if row.cash, do: gettext("Depot")}
                        assigned={row.depot_buckets}
                        all_buckets={@buckets}
                        picker_open={@picker == {"depot", row.depot.id}}
                        error={chip_error(@bucket_error, "depot", row.depot.id)}
                      />
                      <.bucket_chips
                        :if={row.cash && row.cash_controls?}
                        owner="cash"
                        owner_id={row.cash.id}
                        label={if row.depot, do: gettext("Cash")}
                        assigned={row.cash_buckets}
                        all_buckets={@buckets}
                        picker_open={@picker == {"cash", row.cash.id}}
                        error={chip_error(@bucket_error, "cash", row.cash.id)}
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

        <%!-- ADR-0024 modification 1: every portfolio record — however it was
             created (UI, API/MCP, import, seed) — stays visible in this
             minimal read-only list, so no writable resource is invisible.
             Deliberately collapsed and without any create/edit control: the
             records are internal compatibility bindings, not a grouping. --%>
        <details :if={@portfolio_records != []} id="portfolio-admin" class="workspace-section">
          <summary>
            <%= gettext("Portfolio records (compatibility)") %>
          </summary>
          <p class="hint">
            <%= gettext(
              "Internal compatibility records kept for the deprecated API surface. Grouping happens through buckets and views."
            ) %>
          </p>
          <table class="data-table" data-role="portfolio-admin-table">
            <thead>
              <tr>
                <th><%= gettext("Name") %></th>
                <th><%= gettext("Base currency") %></th>
                <th><%= gettext("Created") %></th>
                <th><%= gettext("Source") %></th>
                <th class="num"><%= gettext("Depots") %></th>
                <th class="num"><%= gettext("Cash accounts") %></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={record <- @portfolio_records}>
                <td><%= record.name %></td>
                <td><%= record.base_currency_code %></td>
                <td><%= record.inserted_at |> NaiveDateTime.to_date() |> Date.to_iso8601() %></td>
                <td><%= source_label(record.source) %></td>
                <td class="num"><%= record.depot_count %></td>
                <td class="num"><%= record.cash_account_count %></td>
              </tr>
            </tbody>
          </table>
        </details>

        <%= if @account_dialog? do %>
          <.live_component
            module={AccountFormDialog}
            id="account-form-dialog"
            buckets={@buckets}
            cash_accounts={@cash_accounts}
          />
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  # -- components --------------------------------------------------------------

  attr(:owner, :string, required: true, doc: ~s(the assignment side: "depot" or "cash"))
  attr(:owner_id, :integer, required: true)
  attr(:label, :string, default: nil)
  attr(:assigned, :list, required: true, doc: "the bucket structs assigned to this owner")
  attr(:all_buckets, :list, required: true)
  attr(:picker_open, :boolean, required: true)
  attr(:error, :string, default: nil)

  defp bucket_chips(assigns) do
    assigns =
      assign(
        assigns,
        :available,
        Enum.reject(assigns.all_buckets, fn bucket ->
          Enum.any?(assigns.assigned, &(&1.id == bucket.id))
        end)
      )

    ~H"""
    <div class="bucket-chip-group" id={"#{@owner}-buckets-#{@owner_id}"} data-role="bucket-chips">
      <span :if={@label} class="bucket-chip-group__label"><%= @label %></span>
      <span
        :for={bucket <- @assigned}
        class={["bucket-chip", bucket.dimension == "scope" && "bucket-chip--scope"]}
        style={chip_style(bucket)}
        title={bucket.name}
      >
        <span class="bucket-chip__name"><%= bucket.name %></span>
        <button
          type="button"
          class="bucket-chip__remove"
          data-role="bucket-remove"
          phx-click="remove_bucket"
          phx-value-owner={@owner}
          phx-value-id={@owner_id}
          phx-value-bucket={bucket.id}
          aria-label={gettext("Remove bucket %{name}", name: bucket.name)}
          title={gettext("Remove bucket %{name}", name: bucket.name)}
        >×</button>
      </span>
      <button
        type="button"
        class="bucket-chip-add"
        data-role="bucket-add"
        phx-click={if @picker_open, do: "close_bucket_picker", else: "open_bucket_picker"}
        phx-value-owner={@owner}
        phx-value-id={@owner_id}
        aria-expanded={to_string(@picker_open)}
        aria-label={gettext("Add bucket")}
        title={gettext("Add bucket")}
      >+</button>
      <p :if={@error} class="bucket-inline-error" data-role="bucket-error" role="alert">
        <%= @error %>
      </p>
      <div
        :if={@picker_open}
        id={"bucket-picker-#{@owner}-#{@owner_id}"}
        class="bucket-picker"
        data-role="bucket-picker"
      >
        <ul :if={@available != []} class="bucket-picker__options">
          <li :for={bucket <- @available}>
            <button
              type="button"
              class={["bucket-chip", bucket.dimension == "scope" && "bucket-chip--scope"]}
              style={chip_style(bucket)}
              title={bucket.name}
              phx-click="add_bucket"
              phx-value-owner={@owner}
              phx-value-id={@owner_id}
              phx-value-bucket={bucket.id}
            >
              <span class="bucket-chip__name"><%= bucket.name %></span>
            </button>
          </li>
        </ul>
        <form
          id={"bucket-create-form-#{@owner}-#{@owner_id}"}
          class="bucket-picker__create"
          phx-submit="create_and_add_bucket"
        >
          <input type="hidden" name="owner" value={@owner} />
          <input type="hidden" name="owner_id" value={@owner_id} />
          <input
            name="bucket_name"
            autocomplete="off"
            placeholder={gettext("New tag")}
            aria-label={gettext("New tag")}
          />
          <button type="submit" class="button"><%= gettext("Create tag") %></button>
        </form>
      </div>
    </div>
    """
  end

  # -- events -------------------------------------------------------------------

  @impl true
  def handle_event("open_account_dialog", _params, socket) do
    {:noreply, assign(socket, :account_dialog?, true)}
  end

  def handle_event(
        "set_liquidity_role",
        %{"account_id" => id, "liquidity_role" => role},
        socket
      ) do
    with {account_id, ""} <- Integer.parse(id),
         %CashAccount{} = account <- Portfolios.get_cash_account(account_id),
         {:ok, _updated} <-
           Portfolios.update_cash_account(Actor.owner_ui(), account, %{liquidity_role: role}) do
      {:noreply,
       socket
       |> success(gettext("Cash account updated"))
       |> load_state()}
    else
      _ -> {:noreply, failure(socket, gettext("Could not update cash account"))}
    end
  end

  def handle_event("open_bucket_picker", %{"owner" => owner, "id" => id}, socket)
      when owner in ["depot", "cash"] do
    case coerce_id(id) do
      {:ok, owner_id} ->
        {:noreply,
         socket
         |> assign(:picker, {owner, owner_id})
         |> assign(:bucket_error, nil)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("close_bucket_picker", _params, socket) do
    {:noreply, socket |> assign(:picker, nil) |> assign(:bucket_error, nil)}
  end

  def handle_event("add_bucket", %{"owner" => owner, "id" => id, "bucket" => bucket}, socket) do
    change_buckets(socket, owner, id, fn current ->
      case coerce_id(bucket) do
        {:ok, bucket_id} -> current ++ [bucket_id]
        :error -> current
      end
    end)
  end

  def handle_event("remove_bucket", %{"owner" => owner, "id" => id, "bucket" => bucket}, socket) do
    change_buckets(socket, owner, id, fn current ->
      case coerce_id(bucket) do
        {:ok, bucket_id} -> current -- [bucket_id]
        :error -> current
      end
    end)
  end

  def handle_event(
        "create_and_add_bucket",
        %{"owner" => owner, "owner_id" => id, "bucket_name" => name},
        socket
      ) do
    case Buckets.ensure_tag_bucket(Actor.owner_ui(), name) do
      {:ok, bucket} ->
        change_buckets(socket, owner, id, fn current -> current ++ [bucket.id] end)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, bucket_failure(socket, owner, id, changeset_error(changeset))}
    end
  end

  @impl true
  def handle_info({:dialog, "account-form-dialog", :close}, socket) do
    {:noreply, assign(socket, :account_dialog?, false)}
  end

  def handle_info({:dialog, "account-form-dialog", {:created, message}}, socket) do
    {:noreply,
     socket
     |> assign(:account_dialog?, false)
     |> success(message)
     |> load_state()}
  end

  # -- bucket writes -------------------------------------------------------------

  # Every chip edit is a full-set replacement through the journaled Buckets
  # context, derived from the currently persisted set (never from the DOM).
  defp change_buckets(socket, owner, id, fun) when owner in ["depot", "cash"] do
    with {:ok, owner_id} <- coerce_id(id),
         {:ok, record} <- fetch_owner(owner, owner_id) do
      current = owner_bucket_ids(owner, owner_id)

      case write_owner_buckets(record, Enum.uniq(fun.(current))) do
        :ok ->
          {:noreply, socket |> assign(:bucket_error, nil) |> load_state()}

        {:error, :exclusive_bucket_conflict} ->
          {:noreply,
           bucket_failure(
             socket,
             owner,
             owner_id,
             gettext("Only one scope bucket per account — remove its current scope bucket first.")
           )}

        {:error, _reason} ->
          {:noreply,
           bucket_failure(
             socket,
             owner,
             owner_id,
             gettext("That bucket no longer exists. Refresh and try again.")
           )}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp fetch_owner("depot", id) do
    case Portfolios.get_securities_account(id) do
      %SecuritiesAccount{} = depot -> {:ok, depot}
      nil -> :error
    end
  end

  defp fetch_owner("cash", id) do
    case Portfolios.get_cash_account(id) do
      %CashAccount{} = cash -> {:ok, cash}
      nil -> :error
    end
  end

  defp owner_bucket_ids("depot", id), do: Buckets.depot_default_bucket_ids(id)
  defp owner_bucket_ids("cash", id), do: Buckets.cash_account_bucket_ids(id)

  defp write_owner_buckets(%SecuritiesAccount{} = depot, ids),
    do: Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, ids)

  defp write_owner_buckets(%CashAccount{} = cash, ids),
    do: Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, ids)

  defp bucket_failure(socket, owner, id, message) do
    case coerce_id(id) do
      {:ok, owner_id} -> assign(socket, :bucket_error, {owner, owner_id, message})
      :error -> socket
    end
  end

  # -- data loading ---------------------------------------------------------------

  defp load_state(socket) do
    buckets = Buckets.list_buckets()
    buckets_by_id = Map.new(buckets, &{&1.id, &1})
    cash_accounts = Portfolios.list_cash_accounts()

    assign(socket,
      buckets: buckets,
      cash_accounts: cash_accounts,
      rows: build_rows(cash_accounts, buckets_by_id),
      portfolio_records: Portfolios.portfolio_admin_list()
    )
  end

  # One row per depot, paired with its linked cash account; cash accounts no
  # depot links to get their own row. A cash account shared by several depots
  # renders its controls (liquidity role, chips) only on its first row, so no
  # DOM id appears twice.
  defp build_rows(cash_accounts, buckets_by_id) do
    depots = Portfolios.list_securities_accounts()

    {depot_rows, claimed} =
      Enum.map_reduce(depots, MapSet.new(), fn depot, seen ->
        cash = depot.cash_account
        first_claim? = cash != nil and not MapSet.member?(seen, cash.id)

        row = %{
          depot: depot,
          cash: cash,
          cash_controls?: first_claim?,
          depot_buckets:
            bucket_structs(Buckets.depot_default_bucket_ids(depot.id), buckets_by_id),
          cash_buckets:
            if(first_claim?,
              do: bucket_structs(Buckets.cash_account_bucket_ids(cash.id), buckets_by_id),
              else: []
            )
        }

        {row, if(cash, do: MapSet.put(seen, cash.id), else: seen)}
      end)

    lone_rows =
      cash_accounts
      |> Enum.reject(&MapSet.member?(claimed, &1.id))
      |> Enum.map(fn cash ->
        %{
          depot: nil,
          cash: cash,
          cash_controls?: true,
          depot_buckets: [],
          cash_buckets: bucket_structs(Buckets.cash_account_bucket_ids(cash.id), buckets_by_id)
        }
      end)

    depot_rows ++ lone_rows
  end

  # Scope chip first, then tags, alphabetical within each dimension.
  defp bucket_structs(bucket_ids, buckets_by_id) do
    bucket_ids
    |> Enum.map(&Map.get(buckets_by_id, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{&1.dimension != "scope", &1.name})
  end

  # -- helpers ----------------------------------------------------------------------

  defp row_id(%{depot: nil, cash: cash}), do: "account-row-cash-#{cash.id}"
  defp row_id(%{depot: depot}), do: "account-row-depot-#{depot.id}"

  # The bucket color rides in as a CSS custom property; anything that is not a
  # hex color is dropped so no attacker-shaped string reaches the style attr.
  defp chip_style(%{color: color}) when is_binary(color) do
    if Regex.match?(@color_format, color), do: "--chip-color: #{color}"
  end

  defp chip_style(_bucket), do: nil

  defp chip_error({owner, owner_id, message}, owner, owner_id), do: message
  defp chip_error(_error, _owner, _owner_id), do: nil

  defp source_label(:ui), do: gettext("UI")
  defp source_label(:api), do: gettext("API")
  defp source_label(:import), do: gettext("Import")
  defp source_label(_seeded), do: gettext("Seeded")

  defp success(socket, message), do: assign(socket, success: message, error: nil)
  defp failure(socket, message), do: assign(socket, error: message, success: nil)

  defp coerce_id(value) when is_integer(value), do: {:ok, value}

  defp coerce_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp coerce_id(_value), do: :error

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
