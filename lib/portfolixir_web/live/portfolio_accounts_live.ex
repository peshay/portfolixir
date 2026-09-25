defmodule PortfolixirWeb.PortfolioAccountsLive do
  @moduledoc """
  Accounts & depots administration (ADR-0022 area, reshaped by ADR-0024,
  #491/#559, UAT fix round v2 "disciplined table"): one entity per row, one
  depot/cash pair per `<tbody>` band. A pair whose depot and cash account
  carry the same buckets shows ONE merged chip group ("Both") spanning both
  rows; "Tag separately" or diverged sets split it into per-entity groups.
  Bucket membership is editable as chips with a popover picker, creation runs
  through a single dialog (`PortfolixirWeb.PortfolioAccounts.AccountFormDialog`),
  and the minimal read-only list of every portfolio record stays (ADR-0024
  modification 1: no invisible writable resource). No portfolio decision
  appears anywhere — the internal compatibility binding resolves to one
  deterministic default portfolio.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.DecimalInput
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.PortfolioAccounts.AccountFormDialog

  @color_format ~r/^#[0-9a-fA-F]{3,8}$/

  # Chip overflow cap: the fifth and later chips collapse into a "+N" chip;
  # the full set stays reachable (and removable) inside the picker.
  @max_visible_chips 4

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> assign(:account_dialog?, false)
     |> assign(:account_menu_id, nil)
     |> assign(:balance_dialog, nil)
     |> assign(:balance_error, nil)
     |> assign(:picker, nil)
     # Session-only: bucket cells whose "+N" overflow is expanded in place
     # (issue 842, pick E2-A), keyed by {owner, owner_id}.
     |> assign(:overflow_open, MapSet.new())
     |> assign(:bucket_error, nil)
     # Session-only: pairs the user chose to tag separately. Never persisted —
     # a reload merges equal sets again.
     |> assign(:split_pairs, MapSet.new())
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
              <%= gettext("No accounts yet — add a first depot and cash account.") %>
            </p>
          <% else %>
            <div class="data-table-wrapper">
              <table id="accounts-table" class="data-table accounts-table" data-role="accounts-table">
                <thead>
                  <tr>
                    <th><%= gettext("Name") %></th>
                    <th><%= gettext("Currency") %></th>
                    <th><%= gettext("Liquidity role") %></th>
                    <th><%= gettext("Balance") %></th>
                    <th><%= gettext("Buckets") %></th>
                    <%!-- #806: row actions behind the kebab (Tables pattern);
                         "Tag separately" moved off the bucket cell, which held
                         four controls for one question. --%>
                    <th class="row-actions-head">
                      <span class="visually-hidden"><%= gettext("Actions") %></span>
                    </th>
                  </tr>
                </thead>
                <tbody
                  :for={row <- @rows}
                  class={["account-pair", is_nil(row.depot) && "account-pair--lone"]}
                  id={row_id(row)}
                  data-role="account-row"
                >
                  <%= if row.depot do %>
                    <tr class="account-row--depot">
                      <td class="cell-name cell-name--depot">
                        <span class="account-name"><%= row.depot.name %></span>
                      </td>
                      <td class="cell-currency cell-currency--empty"></td>
                      <td class="cell-role cell-role--empty"></td>
                      <td class="cell-balance cell-balance--empty"></td>
                      <%= if merged?(row, @split_pairs) do %>
                        <td class="cell-buckets cell-buckets--pair" rowspan="2">
                          <.bucket_chips
                            owner="pair"
                            owner_id={row.depot.id}
                            assigned={row.depot_buckets}
                            all_buckets={@buckets}
                            picker_open={@picker == {"pair", row.depot.id}}
                            overflow_open={MapSet.member?(@overflow_open, {"pair", row.depot.id})}
                            error={chip_error(@bucket_error, "pair", row.depot.id)}
                            scope_line={scope_line(:pair)}
                            picker_caption={gettext("Tags apply to depot & cash")}
                          />
                        </td>
                      <% else %>
                        <td class="cell-buckets">
                          <.bucket_chips
                            owner="depot"
                            owner_id={row.depot.id}
                            assigned={row.depot_buckets}
                            all_buckets={@buckets}
                            picker_open={@picker == {"depot", row.depot.id}}
                            overflow_open={MapSet.member?(@overflow_open, {"depot", row.depot.id})}
                            error={chip_error(@bucket_error, "depot", row.depot.id)}
                            scope_line={scope_line(:depot)}
                          />
                        </td>
                      <% end %>
                      <td class="row-actions">
                        <AppShell.row_kebab
                          :if={merged?(row, @split_pairs)}
                          id={"account-kebab-#{row.depot.id}"}
                          row={row.depot.name}
                          open={@account_menu_id == row.depot.id}
                          phx-click="open_account_menu"
                          phx-value-id={row.depot.id}
                        />
                      </td>
                    </tr>
                    <%= cond do %>
                      <% row.cash && row.cash_controls? -> %>
                        <tr class="account-row--cash">
                          <td class="cell-name cell-name--cash">
                            <span class="account-cash-name"><%= row.cash.name %></span>
                          </td>
                          <td class="cell-currency"><%= row.cash.currency_code %></td>
                          <td class="cell-role"><.liquidity_role_field cash={row.cash} /></td>
                          <td class="cell-balance">
                            <.cash_balance_cell
                              cash={row.cash}
                              balances={@cash_balances_by_id}
                              dates={@cash_balance_dates}
                              with_action
                            />
                          </td>
                          <td :if={not merged?(row, @split_pairs)} class="cell-buckets">
                            <.bucket_chips
                              owner="cash"
                              owner_id={row.cash.id}
                              assigned={row.cash_buckets}
                              all_buckets={@buckets}
                              picker_open={@picker == {"cash", row.cash.id}}
                              overflow_open={MapSet.member?(@overflow_open, {"cash", row.cash.id})}
                              error={chip_error(@bucket_error, "cash", row.cash.id)}
                              scope_line={scope_line(:cash)}
                            />
                          </td>
                          <td class="row-actions"></td>
                        </tr>
                      <% row.cash -> %>
                        <tr class="account-row--cash account-row--shared">
                          <td class="cell-name cell-name--cash">
                            <span class="account-cash-name"><%= row.cash.name %></span>
                            <span class="account-sub"><%= gettext("shared — managed above") %></span>
                          </td>
                          <td class="cell-currency"><%= row.cash.currency_code %></td>
                          <td class="cell-role"></td>
                          <td class="cell-balance"></td>
                          <td class="cell-buckets"></td>
                          <td class="row-actions"></td>
                        </tr>
                      <% true -> %>
                        <tr class="account-row--cash account-row--placeholder">
                          <td class="cell-name cell-name--cash">
                            <span class="account-sub account-sub--placeholder">
                              <%= gettext("No cash account linked") %>
                            </span>
                          </td>
                          <td class="cell-currency"></td>
                          <td class="cell-role"></td>
                          <td class="cell-balance"></td>
                          <td class="cell-buckets"></td>
                          <td class="row-actions"></td>
                        </tr>
                    <% end %>
                  <% else %>
                    <tr class="account-row--cash account-row--lone-cash">
                      <td class="cell-name cell-name--lone">
                        <span class="account-name"><%= row.cash.name %></span>
                        <span class="account-microtag"><%= gettext("Cash account") %></span>
                      </td>
                      <td class="cell-currency"><%= row.cash.currency_code %></td>
                      <td class="cell-role"><.liquidity_role_field cash={row.cash} /></td>
                      <td class="cell-balance">
                        <.cash_balance_cell
                          cash={row.cash}
                          balances={@cash_balances_by_id}
                          dates={@cash_balance_dates}
                          with_action
                        />
                      </td>
                      <td class="cell-buckets">
                        <.bucket_chips
                          owner="cash"
                          owner_id={row.cash.id}
                          assigned={row.cash_buckets}
                          all_buckets={@buckets}
                          picker_open={@picker == {"cash", row.cash.id}}
                          overflow_open={MapSet.member?(@overflow_open, {"cash", row.cash.id})}
                          error={chip_error(@bucket_error, "cash", row.cash.id)}
                          scope_line={scope_line(:cash)}
                        />
                      </td>
                      <td class="row-actions"></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>

            <% open_pair = @account_menu_id && Enum.find(@rows, &pair_row?(&1, @account_menu_id)) %>
            <AppShell.row_menu
              :if={open_pair}
              id={"account-row-menu-#{open_pair.depot.id}"}
              trigger={"account-kebab-#{open_pair.depot.id}"}
              label={gettext("Account actions")}
            >
              <button
                type="button"
                id={"split-pair-#{open_pair.depot.id}"}
                class="row-context-menu__item"
                role="menuitem"
                data-role="split-pair"
                phx-click="split_pair"
                phx-value-id={open_pair.depot.id}
              >
                <AppShell.icon name={:layers} />
                <%= gettext("Tag separately") %>
              </button>
            </AppShell.row_menu>
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
          <div class="data-table-wrapper">
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
                  <td><%= record.inserted_at |> NaiveDateTime.to_date() |> Format.date() %></td>
                  <td><%= source_label(record.source) %></td>
                  <td class="num"><%= record.depot_count %></td>
                  <td class="num"><%= record.cash_account_count %></td>
                </tr>
              </tbody>
            </table>
          </div>
        </details>

        <%= if @account_dialog? do %>
          <.live_component
            module={AccountFormDialog}
            id="account-form-dialog"
            buckets={@buckets}
            cash_accounts={@cash_accounts}
          />
        <% end %>

        <%!-- Set-balance dialog (#670, UX-DR3/UX-DR11): the account is
             pre-chosen by the row that opened it — never re-picked in the
             form. Native dialog per UX-DR9 (issue 646). --%>
        <%= if @balance_dialog do %>
          <dialog
            id="balance-dialog"
            class="modal"
            phx-hook="ModalDialog"
            data-close-event="close_balance_dialog"
            aria-labelledby="balance-dialog-title"
          >
            <header class="modal-head">
              <h2 id="balance-dialog-title">
                <%= gettext("Set balance — %{name}", name: @balance_dialog.name) %>
              </h2>
              <button
                type="button"
                class="icon-button"
                aria-label={gettext("Close")}
                phx-click="close_balance_dialog"
              >
                <AppShell.icon name={:x} />
              </button>
            </header>
            <div class="modal-body">
              <form phx-submit="set_balance" class="balance-dialog-form">
                <p
                  :if={@balance_error}
                  class="field-error"
                  data-role="balance-error"
                  role="alert"
                >
                  <%= @balance_error %>
                </p>
                <label>
                  <span><%= gettext("Date") %></span>
                  <input
                    type="text"
                    placeholder="YYYY-MM-DD"
                    pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                    maxlength="10"
                    name="balance[date]"
                    value={Date.to_iso8601(Clock.today())}
                  />
                </label>
                <label>
                  <span>
                    <%= gettext("Balance") %> (<%= @balance_dialog.currency_code %>)
                  </span>
                  <input
                    name="balance[amount]"
                    inputmode="decimal"
                    class="num"
                    required
                    placeholder={DecimalInput.value(Decimal.new("4250.00"))}
                  />
                </label>
                <p class="hint">
                  <%= gettext("State the balance the bank shows; only later bookings adjust it.") %>
                </p>
                <div class="modal-actions">
                  <button type="submit" class="button-primary" phx-disable-with={gettext("Saving…")}>
                    <%= gettext("Set balance") %>
                  </button>
                </div>
              </form>
            </div>
          </dialog>
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  # -- components --------------------------------------------------------------

  # The balance read surface per cash-account row (#670): the derived balance
  # with its as-of date (the newest cash-affecting booking), an em dash before
  # any booking, plus the set-balance trigger on rows that carry controls.
  attr(:cash, CashAccount, required: true)
  attr(:balances, :map, required: true)
  attr(:dates, :map, required: true)
  attr(:with_action, :boolean, default: false)

  defp cash_balance_cell(assigns) do
    ~H"""
    <span id={"cash-balance-#{@cash.id}"} class="cash-balance">
      <%= case Map.get(@balances, @cash.id) do %>
        <% nil -> %>
          <span class="cash-balance__empty">—</span>
        <% balance -> %>
          <span class="cash-balance__amount num">
            <%= Format.money(balance) %> <%= @cash.currency_code %>
          </span>
          <span :if={@dates[@cash.id]} class="cash-balance__asof">
            <%= gettext("as of %{date}", date: Format.date(@dates[@cash.id])) %>
          </span>
      <% end %>
    </span>
    <button
      :if={@with_action}
      type="button"
      id={"set-balance-#{@cash.id}"}
      class="cash-balance__action"
      phx-click="open_balance_dialog"
      phx-value-id={@cash.id}
    >
      <%= gettext("Set balance") %>
    </button>
    """
  end

  attr(:cash, CashAccount, required: true)

  defp liquidity_role_field(assigns) do
    ~H"""
    <form
      id={"liquidity-role-form-#{@cash.id}"}
      class="liquidity-role-field"
      phx-change="set_liquidity_role"
    >
      <input type="hidden" name="account_id" value={@cash.id} />
      <%!-- #806 (variant A): the column is already headed "Liquidity role",
           so the per-row label is for assistive technology only — printing
           it in every cell repeated the head once per account. --%>
      <label class="visually-hidden" for={"liquidity-role-#{@cash.id}"}>
        <%= gettext("Liquidity role") %>
      </label>
      <select id={"liquidity-role-#{@cash.id}"} name="liquidity_role">
        <option value="free_cash" selected={@cash.liquidity_role == "free_cash"}>
          <%= gettext("Free cash") %>
        </option>
        <option value="credit_line" selected={@cash.liquidity_role == "credit_line"}>
          <%= gettext("Credit line") %>
        </option>
        <option value="reserve" selected={@cash.liquidity_role == "reserve"}>
          <%= gettext("Reserve") %>
        </option>
      </select>
    </form>
    """
  end

  attr(:owner, :string, required: true, doc: ~s(the assignment side: "depot", "cash", or "pair"))
  attr(:owner_id, :integer, required: true)
  attr(:assigned, :list, required: true, doc: "the bucket structs assigned to this owner")
  attr(:all_buckets, :list, required: true)
  attr(:picker_open, :boolean, required: true)
  attr(:overflow_open, :boolean, default: false, doc: "the +N overflow is expanded in place")
  attr(:error, :string, default: nil)
  attr(:scope_line, :string, required: true, doc: "what this set applies to, as a sub-line")
  attr(:picker_caption, :string, default: nil)

  defp bucket_chips(assigns) do
    available =
      Enum.reject(assigns.all_buckets, fn bucket ->
        Enum.any?(assigns.assigned, &(&1.id == bucket.id))
      end)

    {_visible, overflow} =
      if length(assigns.assigned) > @max_visible_chips do
        Enum.split(assigns.assigned, @max_visible_chips)
      else
        {assigns.assigned, []}
      end

    # Expanded in place (issue 842): every assigned chip is ALWAYS in the DOM
    # and the overflow ones carry `hidden` while collapsed. Inserting them on
    # expand moved the focused toggle, and a moved node loses focus — the
    # closing act found keyboard focus dropped to <body> on Enter.
    assigns =
      assign(assigns,
        available: available,
        overflow: overflow,
        hidden_ids:
          if(assigns.overflow_open, do: MapSet.new(), else: MapSet.new(overflow, & &1.id))
      )

    ~H"""
    <div class="bucket-chip-group" id={"#{@owner}-buckets-#{@owner_id}"} data-role="bucket-chips">
      <span :if={@assigned == []} class="bucket-chip-group__empty" data-role="bucket-empty">
        <%= gettext("No bucket") %>
      </span>
      <.chip
        :for={bucket <- @assigned}
        bucket={bucket}
        owner={@owner}
        owner_id={@owner_id}
        hidden={MapSet.member?(@hidden_ids, bucket.id)}
      />
      <%!-- #842 (pick E2-A): the overflow is a disclosure that expands the
           cell in place. Its label says what a press does, so no title
           carries the hidden names. --%>
      <button
        :if={@overflow != []}
        type="button"
        id={"bucket-overflow-#{@owner}-#{@owner_id}"}
        class="bucket-chip bucket-chip--overflow"
        data-role="bucket-overflow"
        phx-click="toggle_bucket_overflow"
        phx-value-owner={@owner}
        phx-value-id={@owner_id}
        aria-expanded={to_string(@overflow_open)}
      ><%= if @overflow_open do %><%= gettext("Show fewer") %><span
            class="bucket-chip--overflow__caret"
            aria-hidden="true"
          >▲</span><% else %><%= ngettext("+%{count} more", "+%{count} more", length(@overflow)) %><% end %></button>
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
      <%!-- #806 (variant A): the scope is READABLE without interacting —
           which set this is and what it covers — instead of being a micro-
           label whose meaning lived in a title attribute. --%>
      <span class="bucket-chip-group__scope" data-role="bucket-scope"><%= @scope_line %></span>
      <p :if={@error} class="bucket-inline-error" data-role="bucket-error" role="alert">
        <%= @error %>
      </p>
      <div
        :if={@picker_open}
        id={"bucket-picker-#{@owner}-#{@owner_id}"}
        class="bucket-picker"
        data-role="bucket-picker"
      >
        <p :if={@picker_caption} class="bucket-picker__caption"><%= @picker_caption %></p>
        <%!-- The row truncates at four chips, so the picker carries the full
             assigned set — the overflowed chips stay removable here. --%>
        <div :if={@overflow != []} class="bucket-picker__assigned" data-role="bucket-picker-assigned">
          <.chip :for={bucket <- @assigned} bucket={bucket} owner={@owner} owner_id={@owner_id} />
        </div>
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

  attr(:bucket, :map, required: true)
  attr(:hidden, :boolean, default: false, doc: "an overflow chip while the cell is collapsed")
  attr(:owner, :string, required: true)
  attr(:owner_id, :integer, required: true)

  defp chip(assigns) do
    ~H"""
    <span
      hidden={@hidden}
      class={["bucket-chip", @bucket.dimension == "scope" && "bucket-chip--scope"]}
      style={chip_style(@bucket)}
      title={@bucket.name}
    >
      <span class="bucket-chip__name"><%= @bucket.name %></span>
      <button
        type="button"
        class="bucket-chip__remove"
        data-role="bucket-remove"
        phx-click="remove_bucket"
        phx-value-owner={@owner}
        phx-value-id={@owner_id}
        phx-value-bucket={@bucket.id}
        aria-label={gettext("Remove bucket %{name}", name: @bucket.name)}
        title={gettext("Remove bucket %{name}", name: @bucket.name)}
      >×</button>
    </span>
    """
  end

  # -- events -------------------------------------------------------------------

  @impl true
  def handle_event("open_balance_dialog", %{"id" => id}, socket) do
    with {:ok, parsed} <- LiveParam.fetch_id(id),
         %CashAccount{} = account <- Portfolios.get_cash_account(parsed) do
      {:noreply, assign(socket, balance_dialog: account, balance_error: nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_balance_dialog", _params, socket) do
    {:noreply, assign(socket, balance_dialog: nil, balance_error: nil)}
  end

  def handle_event("set_balance", %{"balance" => params}, socket) do
    case socket.assigns.balance_dialog do
      %CashAccount{} = account ->
        # #869: the balance is read by the one decimal-input rule, from a payload
        # read through the one reader of client input (E25 S4).
        with {:ok, read} <- DecimalInput.cast(LiveParam.map(params), ["amount"]),
             {:ok, _tx} <- Ledger.set_cash_balance(Actor.owner_ui(), account, read) do
          # Quiet feedback: the row's balance updating in place is the
          # confirmation — no toast, no success banner (#566 direction).
          {:noreply,
           socket
           |> assign(balance_dialog: nil, balance_error: nil)
           |> load_state()}
        else
          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :balance_error, changeset_error(changeset))}

          {:error, %{"amount" => message}} ->
            {:noreply, assign(socket, :balance_error, "#{gettext("Balance")} #{message}")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("open_account_dialog", _params, socket) do
    {:noreply, assign(socket, :account_dialog?, true)}
  end

  def handle_event(
        "set_liquidity_role",
        %{"account_id" => id, "liquidity_role" => role},
        socket
      ) do
    with {:ok, account_id} <- LiveParam.fetch_id(id),
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
      when owner in ["depot", "cash", "pair"] do
    case LiveParam.fetch_id(id) do
      {:ok, owner_id} ->
        {:noreply,
         socket
         |> assign(:picker, {owner, owner_id})
         |> assign(:bucket_error, nil)}

      :error ->
        {:noreply, socket}
    end
  end

  # Session-only split of a merged pair: from here on the depot and its cash
  # account carry their own chip groups (no write happens).
  def handle_event("open_account_menu", %{"id" => id_str}, socket) do
    case LiveParam.id(id_str) do
      nil -> {:noreply, socket}
      id -> {:noreply, assign(socket, :account_menu_id, id)}
    end
  end

  def handle_event("close_row_menu", _params, socket) do
    {:noreply, assign(socket, :account_menu_id, nil)}
  end

  def handle_event("split_pair", %{"id" => id}, socket) do
    case LiveParam.fetch_id(id) do
      {:ok, depot_id} ->
        {:noreply,
         socket
         |> assign(:split_pairs, MapSet.put(socket.assigns.split_pairs, depot_id))
         |> assign(:account_menu_id, nil)
         |> assign(:picker, nil)
         |> assign(:bucket_error, nil)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_bucket_overflow", %{"owner" => owner, "id" => id}, socket)
      when owner in ["depot", "cash", "pair"] do
    case LiveParam.fetch_id(id) do
      {:ok, owner_id} ->
        key = {owner, owner_id}
        open = socket.assigns.overflow_open

        open =
          if MapSet.member?(open, key), do: MapSet.delete(open, key), else: MapSet.put(open, key)

        {:noreply, assign(socket, :overflow_open, open)}

      :error ->
        {:noreply, socket}
    end
  end

  # A forged toggle (unknown owner, missing keys) changes nothing.
  def handle_event("toggle_bucket_overflow", _params, socket), do: {:noreply, socket}

  def handle_event("close_bucket_picker", _params, socket) do
    {:noreply, socket |> assign(:picker, nil) |> assign(:bucket_error, nil)}
  end

  def handle_event("add_bucket", %{"owner" => owner, "id" => id, "bucket" => bucket}, socket) do
    change_buckets(socket, owner, id, fn current ->
      case LiveParam.fetch_id(bucket) do
        {:ok, bucket_id} -> current ++ [bucket_id]
        :error -> current
      end
    end)
  end

  def handle_event("remove_bucket", %{"owner" => owner, "id" => id, "bucket" => bucket}, socket) do
    change_buckets(socket, owner, id, fn current ->
      case LiveParam.fetch_id(bucket) do
        {:ok, bucket_id} -> current -- [bucket_id]
        :error -> current
      end
    end)
  end

  def handle_event(
        "create_and_add_bucket",
        %{"owner" => owner, "owner_id" => id, "bucket_name" => name},
        socket
      )
      when is_binary(name) do
    case Buckets.ensure_tag_bucket(Actor.owner_ui(), name) do
      {:ok, bucket} ->
        change_buckets(socket, owner, id, fn current -> current ++ [bucket.id] end)

      # A scope bucket's name is never reused as a free tag (fix round).
      {:error, :name_taken_by_scope_bucket} ->
        {:noreply,
         bucket_failure(
           socket,
           owner,
           id,
           gettext("That name belongs to a scope bucket — pick a different tag name.")
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, bucket_failure(socket, owner, id, changeset_error(changeset))}
    end
  end

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

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
  #
  # A merged pair edit (owner "pair") resolves the depot's linked cash account
  # and applies the same target set to both, depot first. When the second
  # write fails the sets have diverged, so the reload auto-splits the band and
  # the error keys on the cash group that the split reveals.
  defp change_buckets(socket, "pair", id, fun) do
    with {:ok, depot_id} <- LiveParam.fetch_id(id),
         {:ok, %SecuritiesAccount{} = depot} <- fetch_owner("depot", depot_id),
         {:ok, %CashAccount{} = cash} <- paired_cash(depot) do
      current = Buckets.depot_default_bucket_ids(depot_id)
      target = Enum.uniq(fun.(current))

      case Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, target) do
        :ok ->
          write_pair_cash_side(socket, cash, target)

        {:error, reason} ->
          {:noreply, bucket_failure(socket, "pair", depot_id, bucket_write_error(reason))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp change_buckets(socket, owner, id, fun) when owner in ["depot", "cash"] do
    with {:ok, owner_id} <- LiveParam.fetch_id(id),
         {:ok, record} <- fetch_owner(owner, owner_id) do
      current = owner_bucket_ids(owner, owner_id)

      case write_owner_buckets(record, Enum.uniq(fun.(current))) do
        :ok ->
          {:noreply, socket |> assign(:bucket_error, nil) |> load_state()}

        {:error, reason} ->
          {:noreply, bucket_failure(socket, owner, owner_id, bucket_write_error(reason))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp change_buckets(socket, _owner, _id, _fun), do: {:noreply, socket}

  defp write_pair_cash_side(socket, cash, target) do
    case Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, target) do
      :ok ->
        {:noreply, socket |> assign(:bucket_error, nil) |> load_state()}

      {:error, reason} ->
        # Depot write landed, cash write did not: reload so the diverged sets
        # render split, with the error on the now-visible cash group.
        {:noreply,
         socket
         |> bucket_failure("cash", cash.id, bucket_write_error(reason))
         |> load_state()}
    end
  end

  defp bucket_write_error(:exclusive_bucket_conflict) do
    gettext("Only one scope bucket per account — remove its current scope bucket first.")
  end

  # The account was deleted before the write took its lock (E25 S6, G10).
  defp bucket_write_error(:not_found) do
    gettext("That account no longer exists. Refresh and try again.")
  end

  defp bucket_write_error(_reason) do
    gettext("That bucket no longer exists. Refresh and try again.")
  end

  defp paired_cash(%SecuritiesAccount{cash_account_id: nil}), do: :error
  defp paired_cash(%SecuritiesAccount{cash_account_id: cash_id}), do: fetch_owner("cash", cash_id)

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
    case LiveParam.fetch_id(id) do
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
      # Balance read surface per row (#670): derived balances plus the date
      # of the newest cash-affecting booking, in the account's own currency.
      cash_balances_by_id: Ledger.cash_balances(),
      cash_balance_dates: Ledger.cash_activity_dates(),
      portfolio_records: Portfolios.portfolio_admin_list()
    )
  end

  # One band per depot, paired with its linked cash account; cash accounts no
  # depot links to get their own single-row band appended. Depot bands sort by
  # case-insensitive name (id as tiebreak), lone cash accounts likewise. A
  # cash account shared by several depots renders its controls (liquidity
  # role, chips) only on its first band, so no DOM id appears twice.
  defp build_rows(cash_accounts, buckets_by_id) do
    depots =
      Portfolios.list_securities_accounts()
      |> Enum.sort_by(&{String.downcase(&1.name), &1.id})

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
      |> Enum.sort_by(&{String.downcase(&1.name), &1.id})
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

  # A pair renders ONE merged chip group ("Both") exactly when the depot and
  # its own (first-claimed) cash account carry the same bucket set and the
  # user has not chosen to tag them separately this session. Diverged sets —
  # however they diverged — always render split, so "Both" never lies.
  defp pair_row?(%{depot: %SecuritiesAccount{id: id}}, menu_id), do: id == menu_id
  defp pair_row?(_row, _menu_id), do: false

  # #806 (variant A): the scope of a chip set, as a sub-line that can be read
  # without interacting. Deliberately NOT the issue's "inherits from the
  # depot" wording for a cash account: in this model a cash account carries
  # its OWN bucket set and does not inherit one (ADR-0018 inheritance is
  # position -> depot), so writing "inherits" on a cash row would state
  # something the data does not say.
  defp scope_line(:pair), do: gettext("Applies to depot and cash account")
  defp scope_line(:depot), do: gettext("Applies to the depot")
  defp scope_line(:cash), do: gettext("Applies to the cash account")

  defp merged?(
         %{depot: %SecuritiesAccount{} = depot, cash: %CashAccount{}, cash_controls?: true} = row,
         split_pairs
       ) do
    not MapSet.member?(split_pairs, depot.id) and
      MapSet.equal?(bucket_id_set(row.depot_buckets), bucket_id_set(row.cash_buckets))
  end

  defp merged?(_row, _split_pairs), do: false

  defp bucket_id_set(buckets), do: MapSet.new(buckets, & &1.id)

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

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
