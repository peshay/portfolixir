defmodule PortfolixirWeb.TransactionManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ChangedSince

  # Two chip families (#707 D2, Part 4) plus the conditions the "More filters"
  # disclosure holds. Chips within a family compose as OR -- two accounts means
  # "either of these" -- and the families compose as AND with each other and
  # with the disclosure.
  @chip_families ["types", "account_ids"]

  # #732: the pickable columns — the human half of the API's `fields=` sparse
  # fieldset (FR-37). Keys follow the serializers' field names where a field
  # exists there; `depot`/`security` are the human joins over the id fields.
  # The running-balance column is deliberately NOT here: it stays governed by
  # its own rule (exactly one account narrowed), because a picker that can
  # summon it outside that narrowing would fake a meaningless balance.
  @tx_column_defaults ["date", "type", "security", "quantity", "price", "currency"]
  @tx_column_keys @tx_column_defaults ++ ["gross_amount", "fees", "taxes", "notes"]

  @holdings_column_defaults ["depot", "security", "quantity"]
  @holdings_column_keys @holdings_column_defaults ++
                          [
                            "isin",
                            "wkn",
                            "currency",
                            "avg_cost",
                            "latest_price",
                            "market_value",
                            "unrealized_pnl_abs",
                            "unrealized_pnl_pct"
                          ]

  @transaction_form %{
    "type" => "buy",
    "date" => "",
    "securities_account_id" => "",
    "security_id" => "",
    "quantity" => "",
    "price" => "",
    "fees" => "0",
    "taxes" => "0",
    "currency_code" => "EUR",
    "notes" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:transaction_form, @transaction_form)
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> assign(:form_errors, %{})
     |> assign(:sell_preview, nil)
     |> assign(:tx_columns, @tx_column_defaults)
     |> assign(:holdings_columns, @holdings_column_defaults)
     |> load_state()}
  end

  # `since` is the one URL-driven filter on this page (#731): it mirrors the
  # API's `?since=` parameter so a link an agent hands over opens the exact
  # slice it read. The other filters stay socket state deliberately — they
  # have no agent-side counterpart to mirror.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:since, ChangedSince.parse(params))
     |> apply_current_filters()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/transactions"
      page_title={gettext("Transactions")}
      page_subtitle={gettext("Manual buy and sell ledger")}
    >
      <div id="transactions-workspace" class="workspace-page">
        <AppShell.area_tabs tabs={AppShell.transactions_tabs(:history)} />

        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <%!-- ADR-0024: no portfolio strip — the depot choice alone decides
             where a transaction books; every depot is offered together. --%>
        <%= if @securities_accounts != [] do %>
          <section id="transaction-create" class="workspace-section">
            <h2><%= gettext("Record transaction") %></h2>
            <form id="transaction-form" phx-change="form_changed" phx-submit="save_transaction">
              <div class="form-grid">
                <label>
                  <span><%= gettext("Type") %></span>
                  <select name="transaction[type]">
                    <%= for type <- ["buy", "sell"] do %>
                      <option value={type} selected={type == @transaction_form["type"]}>
                        <%= tx_type_label(type) %>
                      </option>
                    <% end %>
                  </select>
                </label>
                <label>
                  <span><%= gettext("Date") %></span>
                  <input
                    type="text"
                    placeholder="YYYY-MM-DD"
                    pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                    maxlength="10"
                    name="transaction[date]"
                    value={@transaction_form["date"]}
                    required
                    aria-invalid={@form_errors["date"] && "true"}
                    aria-describedby={@form_errors["date"] && "tx-error-date"}
                  />
                  <.field_error errors={@form_errors} field="date" />
                </label>
                <label>
                  <span><%= gettext("Depot") %></span>
                  <select
                    name="transaction[securities_account_id]"
                    required
                    aria-invalid={@form_errors["securities_account_id"] && "true"}
                    aria-describedby={
                      @form_errors["securities_account_id"] && "tx-error-securities_account_id"
                    }
                  >
                    <option value=""><%= gettext("Select depot") %></option>
                    <%= for account <- bookable_depots(@securities_accounts) do %>
                      <option
                        value={account.id}
                        selected={to_string(account.id) == @transaction_form["securities_account_id"]}
                      >
                        <%= depot_option_label(account) %>
                      </option>
                    <% end %>
                  </select>
                  <.field_error errors={@form_errors} field="securities_account_id" />
                </label>
                <label>
                  <span><%= gettext("Security") %></span>
                  <%= if @securities == [] do %>
                    <%!-- A security must exist before any transaction can be
                          booked. Rather than a dead, unselectable dropdown that
                          silently blocks submit, name the missing prerequisite
                          at the point of pain and link to where it is fixed. --%>
                    <p id="transaction-no-securities" class="form-help" role="status">
                      <%= gettext("No securities yet.") %>
                      <.link navigate="/securities"><%= gettext("Create a security first") %></.link>
                    </p>
                  <% else %>
                    <select name="transaction[security_id]" required>
                      <option value=""><%= gettext("Select security") %></option>
                      <%= for security <- @securities do %>
                        <option
                          value={security.id}
                          selected={to_string(security.id) == @transaction_form["security_id"]}
                        >
                          <%= security.name %> (<%= security.ticker_symbol %>)
                        </option>
                      <% end %>
                    </select>
                  <% end %>
                  <.field_error errors={@form_errors} field="security_id" />
                </label>
                <label>
                  <span><%= gettext("Quantity") %></span>
                  <input
                    name="transaction[quantity]"
                    value={@transaction_form["quantity"]}
                    inputmode="decimal"
                    required
                    aria-invalid={@form_errors["quantity"] && "true"}
                    aria-describedby={@form_errors["quantity"] && "tx-error-quantity"}
                  />
                  <.field_error errors={@form_errors} field="quantity" />
                </label>
                <label>
                  <span><%= gettext("Price") %></span>
                  <input
                    name="transaction[price]"
                    value={@transaction_form["price"]}
                    inputmode="decimal"
                    required
                    aria-invalid={@form_errors["price"] && "true"}
                    aria-describedby={@form_errors["price"] && "tx-error-price"}
                  />
                  <.field_error errors={@form_errors} field="price" />
                </label>
              </div>

              <p class="form-help" data-role="derived-currency">
                <%= case derived_currency(@securities_accounts, @transaction_form["securities_account_id"]) do %>
                  <% nil -> %>
                    <%= gettext("Currency is set by the selected depot.") %>
                  <% currency -> %>
                    <%= gettext("Currency: %{currency}", currency: currency) %>
                <% end %>
              </p>

              <details id="transaction-costs" class="transaction-costs">
                <summary><%= gettext("Add costs") %></summary>
                <div class="form-grid">
                  <label>
                    <span><%= gettext("Fees") %></span>
                    <input name="transaction[fees]" value={@transaction_form["fees"]} inputmode="decimal" />
                  </label>
                  <label>
                    <span><%= gettext("Taxes") %></span>
                    <input name="transaction[taxes]" value={@transaction_form["taxes"]} inputmode="decimal" />
                  </label>
                </div>
              </details>

              <label>
                <span><%= gettext("Notes") %></span>
                <textarea name="transaction[notes]"><%= @transaction_form["notes"] %></textarea>
              </label>
              <button type="submit"><%= gettext("Record transaction") %></button>
            </form>

            <%!-- Issue #620: which FIFO purchase tranches this sale would
                 consume, shown where the sale is decided. A GROSS gain —
                 deliberately never a tax figure (ADR-0031 correction 1) —
                 on the ADR-0033 currency basis, so this panel and the
                 trades surface cannot disagree. --%>
            <section
              :if={@sell_preview && @sell_preview.lots != []}
              id="sell-lot-preview"
              class="workspace-section"
              data-role="sell-lot-preview"
            >
              <h3><%= gettext("Lots consumed by this sale (FIFO)") %></h3>
              <details class="metric-tooltip" data-role="gross-gain-info">
                <summary aria-label={gettext("About the gross gain")}>ⓘ <%= gettext("Gross gain") %></summary>
                <p role="tooltip">
                  <%= gettext(
                    "Gross gain if the sale executes at the given price: sale proceeds minus the FIFO purchase cost of the consumed lots, before fees. Lots are matched first-in, first-out across all depots. Indicative only — not a net figure; the stored cost basis does not change."
                  ) %>
                </p>
              </details>
              <p
                :if={@sell_preview.price_source == :latest}
                class="form-help"
                data-role="preview-price-hint"
              >
                <%= gettext("Priced at the latest stored price: %{price}.",
                  price: format_decimal(@sell_preview.sell_price)
                ) %>
              </p>
              <table id="sell-lot-preview-table">
                <thead>
                  <tr>
                    <th><%= gettext("Open date") %></th>
                    <th><%= gettext("Quantity used") %></th>
                    <th><%= gettext("Buy price") %></th>
                    <th><%= gettext("Gross gain") %></th>
                    <%= if sell_preview_cross_currency?(@sell_preview) do %>
                      <th><%= gettext("Price return") %></th>
                      <th><%= gettext("Currency return") %></th>
                      <th><%= gettext("Total (base)") %></th>
                    <% end %>
                  </tr>
                </thead>
                <tbody>
                  <%= for lot <- @sell_preview.lots do %>
                    <tr>
                      <td><%= Date.to_iso8601(lot.open_date) %></td>
                      <td><%= format_decimal(lot.quantity) %></td>
                      <td data-role="preview-buy-price">
                        <%= if lot.buy_price_native do %>
                          <%= format_decimal(lot.buy_price_native) %>
                          <small><%= @sell_preview.security_currency %></small>
                        <% else %>
                          —
                        <% end %>
                      </td>
                      <td class={gain_class(lot.gross_gain)} title={sell_preview_hint(lot)}>
                        <%= signed_or_dash(lot.gross_gain) %>
                        <small :if={lot.gross_gain}><%= @sell_preview.security_currency %></small>
                      </td>
                      <%= if sell_preview_cross_currency?(@sell_preview) do %>
                        <td class={gain_class(lot.price_return_abs)}>
                          <%= signed_or_dash(lot.price_return_abs) %>
                        </td>
                        <td class={gain_class(lot.currency_return_abs)}>
                          <%= signed_or_dash(lot.currency_return_abs) %>
                        </td>
                        <td class={gain_class(lot.total_return_base_abs)}>
                          <%= signed_or_dash(lot.total_return_base_abs) %>
                          <small :if={lot.decomposed}><%= lot.base_currency %></small>
                        </td>
                      <% end %>
                    </tr>
                  <% end %>
                </tbody>
                <tfoot>
                  <tr class="totals-row">
                    <td colspan="3"><%= gettext("Total") %></td>
                    <td class={gain_class(@sell_preview.total_gross_gain)} data-role="preview-total">
                      <%= signed_or_dash(@sell_preview.total_gross_gain) %>
                      <small :if={@sell_preview.total_gross_gain}>
                        <%= @sell_preview.security_currency %>
                      </small>
                    </td>
                    <td :if={sell_preview_cross_currency?(@sell_preview)} colspan="3"></td>
                  </tr>
                </tfoot>
              </table>
              <p
                :if={Decimal.compare(@sell_preview.shortfall, 0) == :gt}
                class="alert-error"
                role="alert"
                data-role="sell-shortfall"
              >
                <%= gettext("%{quantity} of the entered quantity is not covered by open lots.",
                  quantity: format_decimal(@sell_preview.shortfall)
                ) %>
              </p>
            </section>
          </section>
        <% else %>
          <section id="transaction-setup-empty" class="empty-state" role="status">
            <%= gettext("Create a depot and its cash account before recording transactions.") %>
          </section>
        <% end %>

        <div class="transaction-secondary">
        <section id="holdings-panel" class="workspace-section">
          <h2><%= gettext("Current holdings") %></h2>
          <%= if Enum.empty?(@holding_rows) do %>
            <div id="no-holdings" class="empty-state" role="status">
              <%= gettext("No holdings yet") %>
            </div>
          <% else %>
            <%!-- #732: the panel renders the API's own holdings projection
                  (Ledger.holdings_for_portfolio/1), so the picker can offer
                  the valuation columns the agent reads over fields= — one
                  projection, two surfaces. --%>
            <details id="holdings-column-picker" class="more-filters">
              <summary>
                <AppShell.icon name={:columns} />
                <%= gettext("Columns") %>
              </summary>
              <form id="holdings-column-form" phx-change="set_holdings_columns">
                <%= for key <- holdings_column_keys() do %>
                  <label class="checkbox-row">
                    <input
                      type="checkbox"
                      name="columns[]"
                      value={key}
                      checked={key in @holdings_columns}
                    />
                    <span><%= holdings_column_label(key) %></span>
                  </label>
                <% end %>
                <input type="hidden" name="columns[]" value="" />
              </form>
            </details>
            <div
              id="holdings-table-wrapper"
              phx-hook="ColumnPrefs"
              data-storage-key="transactions.holdings.columns"
              data-restore-event="set_holdings_columns"
              data-current-columns={Jason.encode!(@holdings_columns)}
            >
              <table id="holdings-table">
                <thead>
                  <tr>
                    <%= for key <- @holdings_columns do %>
                      <th><%= holdings_column_label(key) %></th>
                    <% end %>
                  </tr>
                </thead>
                <tbody>
                  <%= for row <- @holding_rows do %>
                    <tr>
                      <%= for key <- @holdings_columns do %>
                        <td><%= holdings_cell(row, key) %></td>
                      <% end %>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

        <section id="transaction-list-panel" class="workspace-section">
          <h2><%= gettext("Transaction history") %></h2>
          <%= if Enum.empty?(@transactions) do %>
            <div id="no-transactions" class="empty-state" role="status">
              <%= gettext("No transactions yet") %>
            </div>
          <% else %>
            <%!-- The common filters are one-tap chips; the rest is demoted
                  behind a counted disclosure (#707 D2 and Part 4). Chips are
                  toggles, so they carry aria-pressed rather than aria-current,
                  and the pressed state shows on the border as well as the tint
                  so it survives forced colours (UX-DR7). --%>
            <div
              id="transaction-chips"
              class="filter-chips"
              role="group"
              aria-label={gettext("Filter the history")}
            >
              <span class="filter-chips__family"><%= gettext("Account") %></span>
              <%= for account <- filter_account_options(@cash_accounts, @transactions) do %>
                <button
                  type="button"
                  class={["filter-chip", to_string(account.id) in @filters["account_ids"] && "is-active"]}
                  aria-pressed={to_string(to_string(account.id) in @filters["account_ids"])}
                  phx-click="toggle_filter"
                  phx-value-family="account"
                  phx-value-option={account.id}
                >
                  <%= account.name %>
                </button>
              <% end %>

              <span class="filter-chips__family"><%= gettext("Type") %></span>
              <%= for type <- filter_type_options(@transactions) do %>
                <button
                  type="button"
                  class={["filter-chip", type in @filters["types"] && "is-active"]}
                  aria-pressed={to_string(type in @filters["types"])}
                  phx-click="toggle_filter"
                  phx-value-family="type"
                  phx-value-option={type}
                >
                  <%= tx_type_label(type) %>
                </button>
              <% end %>
            </div>

            <ChangedSince.chips id="changed-since-chips" since={@since} />

            <p
              :if={@since}
              id="transaction-since-note"
              class="summary-basis"
              role="status"
              data-role="since-note"
            >
              <%= gettext(
                "Changed since %{cut} (UTC): only transactions created or changed after this instant are shown — by record change, not booking date. Deletions are not shown; clear the filter for the complete history.",
                cut: @since.raw
              ) %>
            </p>

            <details id="transaction-more-filters" class="more-filters">
              <summary>
                <AppShell.icon name={:filter} />
                <%= gettext("More filters") %>
                <%!-- A demoted control that hides active state is a worse
                      defect than the builder it replaces, so the count comes
                      out to the summary. --%>
                <span :if={@more_filters_count > 0} class="badge" data-role="more-filters-count">
                  <%= @more_filters_count %>
                </span>
              </summary>
            <form id="transaction-filters" phx-change="filter_changed" class="transaction-filters">
              <label>
                <span><%= gettext("Security") %></span>
                <select name="filters[security_id]">
                  <option value=""><%= gettext("All securities") %></option>
                  <%= for {id, name} <- filter_security_options(@transactions) do %>
                    <option value={id} selected={@filters["security_id"] == id}><%= name %></option>
                  <% end %>
                </select>
              </label>
              <label>
                <span><%= gettext("From") %></span>
                <input type="text" placeholder="YYYY-MM-DD" pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}" maxlength="10" name="filters[from]" value={@filters["from"]} />
              </label>
              <label>
                <span><%= gettext("To") %></span>
                <input type="text" placeholder="YYYY-MM-DD" pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}" maxlength="10" name="filters[to]" value={@filters["to"]} />
              </label>
              <label class="transaction-filters-search">
                <span><%= gettext("Search") %></span>
                <input
                  type="text"
                  name="filters[query]"
                  value={@filters["query"]}
                  phx-debounce="200"
                  placeholder={gettext("Security, type, notes…")}
                />
              </label>
            </form>
            </details>

            <div id="transaction-summary" class="transaction-summary" role="status">
              <span class="summary-total">
                <strong data-role="summary-total"><%= @summary.total %></strong>
                <%= gettext("transactions") %>
              </span>
              <%= for row <- @summary.by_type do %>
                <span class="summary-type" data-type={row.type}>
                  <%= tx_type_label(row.type) %>:
                  <strong data-role="summary-count"><%= row.count %></strong>
                  · <.currency_totals totals={row.totals} />
                </span>
              <% end %>
              <p class="summary-basis" data-role="summary-basis">
                <%= gettext("Counts and gross booked amounts of the transactions this filter selects, summed per currency and not converted.") %>
              </p>
            </div>

            <%= if Enum.empty?(@filtered_transactions) do %>
              <div id="transaction-no-match" class="empty-state" role="status">
                <%= gettext("No transactions match the current filter.") %>
              </div>
            <% else %>
              <%!-- #732: the pickable columns are the human half of the
                    API's fields= sparse fieldset — fees, taxes, gross amount
                    and notes exist in every row and were never showable. --%>
              <details id="tx-column-picker" class="more-filters">
                <summary>
                  <AppShell.icon name={:columns} />
                  <%= gettext("Columns") %>
                </summary>
                <form id="tx-column-form" phx-change="set_tx_columns">
                  <%= for key <- tx_column_keys() do %>
                    <label class="checkbox-row">
                      <input
                        type="checkbox"
                        name="columns[]"
                        value={key}
                        checked={key in @tx_columns}
                      />
                      <span><%= tx_column_label(key) %></span>
                    </label>
                  <% end %>
                  <input type="hidden" name="columns[]" value="" />
                </form>
              </details>
              <div
                id="transaction-table-wrapper"
                phx-hook="ColumnPrefs"
                data-storage-key="transactions.columns"
                data-restore-event="set_tx_columns"
                data-current-columns={Jason.encode!(@tx_columns)}
              >
                <table id="transaction-list">
                  <thead>
                    <tr>
                      <th :for={key <- @tx_columns}><%= tx_column_label(key) %></th>
                      <%!-- The running balance is only meaningful for ONE
                            account, so the column appears exactly when the
                            chips narrow to one and not before — never via the
                            picker. --%>
                      <th :if={@balance_account}>
                        <%= gettext("Balance") %>
                        <small><%= @balance_account.currency_code %></small>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for group <- grouped_by_month(@filtered_transactions) do %>
                      <tr class="tx-group-head" data-month-group={group.id}>
                        <th
                          colspan={length(@tx_columns) + if(@balance_account, do: 1, else: 0)}
                          scope="colgroup"
                        >
                          <span class="tx-group-month"><%= group.label %></span>
                          <span class="tx-group-subtotal">
                            <%= ngettext("%{count} transaction", "%{count} transactions", group.count,
                              count: group.count) %> · <.currency_totals totals={group.totals} />
                          </span>
                        </th>
                      </tr>
                      <%= for transaction <- group.transactions do %>
                        <tr data-transaction={transaction.id}>
                          <%= for key <- @tx_columns do %>
                            <%= case key do %>
                              <% "quantity" -> %>
                                <%= if transaction.type == "split" do %>
                                  <%!-- A split carries no quantity/price of
                                        its own: show the ratio where the
                                        quantity would be (E17 review,
                                        finding 7). --%>
                                  <td data-role="split-ratio">
                                    <%= split_ratio_label(transaction) %>
                                  </td>
                                <% else %>
                                  <td><%= format_decimal(transaction.quantity) %></td>
                                <% end %>
                              <% "price" -> %>
                                <%= if transaction.type == "split" do %>
                                  <td>—</td>
                                <% else %>
                                  <td><%= format_decimal(transaction.price) %></td>
                                <% end %>
                              <% _other -> %>
                                <td><%= tx_cell(transaction, key) %></td>
                            <% end %>
                          <% end %>
                          <td :if={@balance_account} class="numeric" data-role="running-balance">
                            <%!-- Absent, never repeated: a row that does not
                                  move this account carries no balance, because
                                  the previous row's figure would read as
                                  "nothing happened here". --%>
                            <%= running_balance(@running_balances, transaction) %>
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          <% end %>
        </section>
        </div>
      </div>
    </AppShell.shell>
    """
  end

  @impl true
  def handle_event(
        "save_transaction",
        %{"transaction" => _params},
        %{assigns: %{securities_accounts: []}} = socket
      ) do
    {:noreply, failure(socket, gettext("Create a depot and its cash account first"))}
  end

  def handle_event("form_changed", %{"transaction" => params}, socket) do
    # Clear stale field errors as the user edits, so a corrected field stops
    # reading as invalid before the next submit.
    {:noreply,
     socket
     |> assign(:transaction_form, params)
     |> assign(:form_errors, %{})
     |> assign(:sell_preview, compute_sell_preview(params))}
  end

  def handle_event("filter_changed", %{"filters" => filters}, socket) do
    # The disclosure's form carries only its own fields, so the chip families
    # are carried over rather than reset -- a date entered in "More filters"
    # must not silently release the account the reader narrowed to.
    chips = Map.take(socket.assigns.filters, @chip_families)

    {:noreply,
     socket
     |> assign(:filters, default_filters() |> Map.merge(filters) |> Map.merge(chips))
     |> apply_current_filters()}
  end

  # The payload key is `option`, NOT `value`: LiveView's client overwrites
  # `meta.value` with the DOM element's own `value` property after collecting
  # the `phx-value-*` attributes, and a <button> without a value attribute has
  # `""`. `phx-value-value` on a button therefore always arrives empty --
  # silently, and invisibly to `render_click`, which reads the attributes
  # directly. Found by the Sprint 7 UAT walkthrough in a real browser; pinned
  # by test/invariants/phx_value_value_test.exs.
  def handle_event("toggle_filter", %{"family" => family, "option" => option}, socket)
      when family in ["type", "account"] do
    key = if family == "type", do: "types", else: "account_ids"
    active = Map.fetch!(socket.assigns.filters, key)
    toggled = if option in active, do: List.delete(active, option), else: [option | active]

    {:noreply,
     socket
     |> assign(:filters, Map.put(socket.assigns.filters, key, Enum.sort(toggled)))
     |> apply_current_filters()}
  end

  def handle_event("set_changed_since", %{"preset" => preset}, socket) do
    case ChangedSince.toggle_value(socket.assigns.since, preset) do
      nil -> {:noreply, push_patch(socket, to: "/transactions")}
      iso -> {:noreply, push_patch(socket, to: "/transactions?since=#{iso}")}
    end
  end

  # #732: raw key strings from the picker form or the ColumnPrefs hook's
  # restore; validated against the registry, registry order kept. An empty
  # selection is a broken table rather than a preference, so it falls back to
  # the defaults (the securities picker's precedent).
  def handle_event("set_tx_columns", %{"columns" => columns}, socket) when is_list(columns) do
    chosen = safe_columns(columns, @tx_column_keys, @tx_column_defaults)

    {:noreply,
     socket
     |> assign(:tx_columns, chosen)
     |> push_event("column-prefs-changed", %{key: "transactions.columns", columns: chosen})}
  end

  def handle_event("set_tx_columns", _params, socket), do: {:noreply, socket}

  def handle_event("set_holdings_columns", %{"columns" => columns}, socket)
      when is_list(columns) do
    chosen = safe_columns(columns, @holdings_column_keys, @holdings_column_defaults)

    {:noreply,
     socket
     |> assign(:holdings_columns, chosen)
     |> push_event("column-prefs-changed", %{
       key: "transactions.holdings.columns",
       columns: chosen
     })}
  end

  def handle_event("set_holdings_columns", _params, socket), do: {:noreply, socket}

  def handle_event("save_transaction", %{"transaction" => params}, socket) do
    # The currency is authoritative from the chosen depot's cash account, never a
    # free-text field the user could mistype (#473).
    currency =
      derived_currency(socket.assigns.securities_accounts, params["securities_account_id"])

    params =
      params
      |> normalize_decimal_inputs()
      |> put_portfolio_from_depot(socket.assigns.securities_accounts)
      |> maybe_put_currency(currency)

    case Ledger.create_transaction(Actor.owner_ui(), params) do
      {:ok, _transaction} ->
        {:noreply,
         socket
         |> assign(:transaction_form, @transaction_form)
         |> assign(:form_errors, %{})
         |> assign(:sell_preview, nil)
         |> success(gettext("Transaction recorded"))
         |> load_state()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:transaction_form, params)
         |> assign(:form_errors, field_errors(changeset))
         |> failure(changeset_error(changeset))}
    end
  end

  # ADR-0024: the ledger surface spans every depot at once. The internal
  # portfolio records are only iterated as the mechanism behind the
  # portfolio-bound positions read; depot ids are globally unique, so the
  # concatenated position keys never collide.
  defp load_state(socket) do
    securities = Catalog.list_securities()
    securities_accounts = Portfolios.list_securities_accounts()
    cash_accounts = Portfolios.list_cash_accounts()
    transactions = Ledger.list_transactions()

    # #732: the panel shows the API's own holdings projection
    # (Ledger.holdings_for_portfolio/1) — one projection, two surfaces — so
    # the picker's valuation columns are the figures the agent reads, not a
    # second calculation.
    holding_rows =
      Portfolios.list_portfolios()
      |> Enum.flat_map(&Ledger.holdings_for_portfolio(&1.id))
      |> holding_rows(securities_accounts)

    socket
    |> assign(
      securities_accounts: securities_accounts,
      cash_accounts: cash_accounts,
      securities: securities,
      transactions: transactions,
      holding_rows: holding_rows
    )
    |> apply_current_filters()
  end

  # The overview filters (#414) run in memory over the already-loaded history:
  # the local ledger is bounded, so a client-side narrow is instant and keeps
  # the query path simple. The summary always reflects the current filter.
  defp default_filters,
    do: %{
      "types" => [],
      "account_ids" => [],
      "security_id" => "",
      "from" => "",
      "to" => "",
      "query" => ""
    }

  defp apply_current_filters(socket) do
    filters = Map.merge(default_filters(), socket.assigns[:filters] || %{})

    filtered =
      socket.assigns.transactions
      |> filter_transactions(filters)
      |> filter_changed_since(socket.assigns[:since])

    assign(socket,
      filters: filters,
      filtered_transactions: filtered,
      summary: summarise(filtered),
      more_filters_count: more_filters_count(filters)
    )
    |> assign_running_balances(filters)
  end

  # The running balance is a property of the ACCOUNT, not of the current view,
  # so it is folded over the whole history and merely displayed on the rows the
  # filter leaves standing. Folding it over the filtered slice would restate the
  # opening balance as zero every time a date filter moved.
  defp assign_running_balances(socket, %{"account_ids" => [account_id]}) do
    account = Enum.find(socket.assigns.cash_accounts, &(to_string(&1.id) == account_id))

    assign(socket,
      balance_account: account,
      running_balances:
        account && Projection.cash_balance_series(socket.assigns.transactions, account.id)
    )
  end

  defp assign_running_balances(socket, _filters),
    do: assign(socket, balance_account: nil, running_balances: nil)

  defp filter_transactions(transactions, filters) do
    transactions
    |> Enum.filter(&type_match?(&1, filters["types"]))
    |> Enum.filter(&account_match?(&1, filters["account_ids"]))
    |> Enum.filter(&security_match?(&1, filters["security_id"]))
    |> Enum.filter(&from_match?(&1, filters["from"]))
    |> Enum.filter(&to_match?(&1, filters["to"]))
    |> Enum.filter(&query_match?(&1, filters["query"]))
  end

  # The in-memory mirror of the contexts' `updated_at > cut` delta cut
  # (`updated_since:` in Ledger/Catalog): strictly after, by record change.
  # Mirrored rather than re-queried because the running balance folds over
  # the FULL history (see assign_running_balances) — narrowing the load
  # would restate opening balances as zero. Parity with the query is pinned
  # in changed_since_view_test.exs.
  defp filter_changed_since(transactions, nil), do: transactions

  defp filter_changed_since(transactions, %{cut: cut}),
    do: Enum.filter(transactions, &(NaiveDateTime.compare(&1.updated_at, cut) == :gt))

  defp type_match?(_tx, []), do: true
  defp type_match?(tx, types), do: tx.type in types

  # An account chip selects the rows that MOVE that account's money -- both legs
  # of a cash transfer, and nothing that has no cash leg at all (a delivery, a
  # split). Those rows are not this account's ledger, so they leave with it.
  defp account_match?(_tx, []), do: true

  defp account_match?(tx, ids) do
    to_string(tx.cash_account_id) in ids or
      to_string(Map.get(tx, :counter_cash_account_id)) in ids
  end

  defp more_filters_count(filters) do
    ["security_id", "from", "to", "query"]
    |> Enum.count(&(Map.get(filters, &1) not in ["", nil]))
  end

  defp security_match?(_tx, blank) when blank in ["", nil], do: true
  defp security_match?(tx, id), do: to_string(tx.security_id) == id

  defp from_match?(_tx, blank) when blank in ["", nil], do: true

  defp from_match?(tx, str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> Date.compare(tx.date, date) != :lt
      _ -> true
    end
  end

  defp to_match?(_tx, blank) when blank in ["", nil], do: true

  defp to_match?(tx, str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> Date.compare(tx.date, date) != :gt
      _ -> true
    end
  end

  defp query_match?(_tx, blank) when blank in ["", nil], do: true

  defp query_match?(tx, query) do
    needle = query |> String.trim() |> String.downcase()

    haystack =
      [tx.security && tx.security.name, tx.type, tx.notes, tx.currency_code]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    needle == "" or String.contains?(haystack, needle)
  end

  # Section the (already date-desc) history into month chunks with a subtotal
  # each (#414 follow-up). chunk_by works because the list is pre-sorted, so
  # consecutive same-month rows are adjacent and order is preserved.
  # One figure per currency, so a total always names the money it is in.
  attr(:totals, :list, required: true)

  defp currency_totals(assigns) do
    ~H"""
    <span :for={{entry, index} <- Enum.with_index(@totals)} class="currency-total">
      <%= if index > 0, do: " · " %><%= PortfolixirWeb.Format.money(entry.total) %>
      <small><%= entry.currency %></small>
    </span>
    """
  end

  defp running_balance(nil, _transaction), do: "—"

  defp running_balance(balances, transaction) do
    case Map.get(balances, transaction.id) do
      %Decimal{} = balance -> PortfolixirWeb.Format.money(balance)
      nil -> "—"
    end
  end

  defp grouped_by_month(transactions) do
    transactions
    |> Enum.chunk_by(fn tx -> {tx.date.year, tx.date.month} end)
    |> Enum.map(fn chunk ->
      first = hd(chunk)

      %{
        id: month_group_id(first.date),
        label: month_group_label(first.date),
        transactions: chunk,
        count: length(chunk),
        totals: totals_by_currency(chunk)
      }
    end)
  end

  defp month_group_id(date) do
    "#{date.year}-#{date.month |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  # Month names through gettext (fix round), so the German history reads
  # "März 2026" instead of leaking strftime's English %B — same precedent as
  # the income matrix month abbreviations (Steve UAT, reconsolidation).
  defp month_group_label(date), do: "#{month_name(date.month)} #{date.year}"

  defp month_name(1), do: gettext("January")
  defp month_name(2), do: gettext("February")
  defp month_name(3), do: gettext("March")
  defp month_name(4), do: gettext("April")
  defp month_name(5), do: gettext("May")
  defp month_name(6), do: gettext("June")
  defp month_name(7), do: gettext("July")
  defp month_name(8), do: gettext("August")
  defp month_name(9), do: gettext("September")
  defp month_name(10), do: gettext("October")
  defp month_name(11), do: gettext("November")
  defp month_name(12), do: gettext("December")

  defp summarise(transactions) do
    by_type =
      transactions
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, list} ->
        %{type: type, count: length(list), totals: totals_by_currency(list)}
      end)
      |> Enum.sort_by(& &1.type)

    %{total: length(transactions), by_type: by_type}
  end

  # Booked amounts are summed **per currency** and never across them. A single
  # figure adding dollars to euros is not a smaller lie for being one number,
  # and UX-DR21 asks a surface to name what it aggregates -- which a
  # currency-less total cannot do. No conversion happens here: the summary
  # counts what was booked, and converting it would make it a different figure
  # that would then need its own rate basis.
  defp totals_by_currency(transactions) do
    transactions
    |> Enum.group_by(& &1.currency_code)
    |> Enum.map(fn {currency, list} -> %{currency: currency, total: sum_amount(list)} end)
    |> Enum.sort_by(& &1.currency)
  end

  defp sum_amount(transactions) do
    Enum.reduce(transactions, Decimal.new(0), fn tx, acc ->
      Decimal.add(acc, tx_amount(tx))
    end)
  end

  defp tx_amount(%{gross_amount: %Decimal{} = gross}), do: gross

  defp tx_amount(%{quantity: %Decimal{} = qty, price: %Decimal{} = price}),
    do: Decimal.mult(qty, price)

  defp tx_amount(_tx), do: Decimal.new(0)

  # The distinct types / securities actually present in the history drive the
  # filter dropdowns, so the controls never offer a value that matches nothing.
  defp filter_type_options(transactions) do
    transactions |> Enum.map(& &1.type) |> Enum.uniq() |> Enum.sort()
  end

  defp filter_account_options(cash_accounts, transactions) do
    used =
      transactions
      |> Enum.flat_map(&[&1.cash_account_id, Map.get(&1, :counter_cash_account_id)])
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    Enum.filter(cash_accounts, &MapSet.member?(used, &1.id))
  end

  defp filter_security_options(transactions) do
    transactions
    |> Enum.filter(& &1.security)
    |> Enum.map(&{to_string(&1.security_id), &1.security.name})
    |> Enum.uniq()
    |> Enum.sort_by(&elem(&1, 1))
  end

  # ADR-0024: the internal portfolio binding follows the chosen depot — no
  # user-facing portfolio decision. An unknown/blank depot id adds nothing and
  # lets the changeset report the missing depot.
  defp put_portfolio_from_depot(params, securities_accounts) do
    depot_id = params["securities_account_id"]

    case Enum.find(securities_accounts, &(to_string(&1.id) == to_string(depot_id))) do
      %{portfolio_id: portfolio_id} -> Map.put(params, "portfolio_id", portfolio_id)
      _ -> params
    end
  end

  defp holding_rows(holdings, securities_accounts) do
    names = Map.new(securities_accounts, &{&1.id, &1.name})

    holdings
    |> Enum.map(fn row ->
      Map.put(
        row,
        :securities_account_name,
        Map.get(names, row.securities_account_id, gettext("Unknown depot"))
      )
    end)
    |> Enum.sort_by(fn row -> {row.securities_account_name, row.security_name} end)
  end

  # -- #732 column registries -------------------------------------------------

  defp tx_column_keys, do: @tx_column_keys
  defp holdings_column_keys, do: @holdings_column_keys

  defp safe_columns(requested, all_keys, defaults) do
    case Enum.filter(all_keys, &(&1 in requested)) do
      [] -> defaults
      chosen -> chosen
    end
  end

  defp tx_column_label("date"), do: gettext("Date")
  defp tx_column_label("type"), do: gettext("Type")
  defp tx_column_label("security"), do: gettext("Security")
  defp tx_column_label("quantity"), do: gettext("Quantity")
  defp tx_column_label("price"), do: gettext("Price")
  defp tx_column_label("currency"), do: gettext("Currency")
  defp tx_column_label("gross_amount"), do: gettext("Gross amount")
  defp tx_column_label("fees"), do: gettext("Fees")
  defp tx_column_label("taxes"), do: gettext("Taxes")
  defp tx_column_label("notes"), do: gettext("Notes")

  defp tx_cell(transaction, "date"), do: transaction.date
  defp tx_cell(transaction, "type"), do: tx_type_label(transaction.type)
  defp tx_cell(transaction, "security"), do: transaction.security && transaction.security.name
  defp tx_cell(transaction, "currency"), do: transaction.currency_code
  defp tx_cell(transaction, "gross_amount"), do: format_decimal(transaction.gross_amount)
  defp tx_cell(transaction, "fees"), do: format_decimal(transaction.fees)
  defp tx_cell(transaction, "taxes"), do: format_decimal(transaction.taxes)
  defp tx_cell(transaction, "notes"), do: transaction.notes

  defp holdings_column_label("depot"), do: gettext("Depot")
  defp holdings_column_label("security"), do: gettext("Security")
  defp holdings_column_label("quantity"), do: gettext("Quantity")
  defp holdings_column_label("isin"), do: gettext("ISIN")
  defp holdings_column_label("wkn"), do: gettext("WKN")
  defp holdings_column_label("currency"), do: gettext("Currency")
  defp holdings_column_label("avg_cost"), do: gettext("Avg cost")
  defp holdings_column_label("latest_price"), do: gettext("Latest price")
  defp holdings_column_label("market_value"), do: gettext("Market value")
  defp holdings_column_label("unrealized_pnl_abs"), do: gettext("P&L")
  defp holdings_column_label("unrealized_pnl_pct"), do: gettext("P&L %")

  defp holdings_cell(row, "depot"), do: row.securities_account_name
  defp holdings_cell(row, "security"), do: row.security_name
  defp holdings_cell(row, "quantity"), do: format_decimal(row.quantity)
  defp holdings_cell(row, "isin"), do: row.isin
  defp holdings_cell(row, "wkn"), do: row.wkn
  defp holdings_cell(row, "currency"), do: row.currency_code
  defp holdings_cell(row, "avg_cost"), do: format_decimal(row.avg_cost)
  defp holdings_cell(row, "latest_price"), do: format_decimal(row.latest_price)
  defp holdings_cell(row, "market_value"), do: format_decimal(row.market_value)
  defp holdings_cell(row, "unrealized_pnl_abs"), do: format_decimal(row.unrealized_pnl_abs)
  defp holdings_cell(row, "unrealized_pnl_pct"), do: format_decimal(row.unrealized_pnl_pct)

  # Human, localized labels for the stored type enum; the form value and the
  # ledger keep the machine "buy"/"sell". Mirrors securities_live.ex so the two
  # transaction surfaces read identically.
  # Every PP transaction kind gets a translated label, so the summary strip
  # never mixes raw type keys into the localized UI (Steve UAT,
  # reconsolidation).
  defp tx_type_label("buy"), do: gettext("Buy")
  defp tx_type_label("sell"), do: gettext("Sell")
  defp tx_type_label("deposit"), do: gettext("Deposit")
  defp tx_type_label("removal"), do: gettext("Removal")
  defp tx_type_label("dividend"), do: gettext("Dividend")
  defp tx_type_label("interest"), do: gettext("Interest")
  defp tx_type_label("fee"), do: gettext("Fee")
  defp tx_type_label("tax"), do: gettext("Tax")
  defp tx_type_label("tax_refund"), do: gettext("Tax refund")
  defp tx_type_label("cash_transfer"), do: gettext("Cash transfer")
  defp tx_type_label("inbound_delivery"), do: gettext("Inbound delivery")
  defp tx_type_label("outbound_delivery"), do: gettext("Outbound delivery")
  defp tx_type_label("security_transfer"), do: gettext("Security transfer")
  defp tx_type_label("balance"), do: gettext("Balance snapshot")
  defp tx_type_label("split"), do: gettext("Split")
  defp tx_type_label(other), do: to_string(other)

  defp split_ratio_label(%{split_ratio_numerator: p, split_ratio_denominator: q})
       when is_integer(p) and is_integer(q),
       do: "#{p}:#{q}"

  defp split_ratio_label(_transaction), do: "—"

  # Issue #620: the FIFO consumption preview for the sell being entered.
  # Computed on every form change once type=sell, a security and a positive
  # quantity are set; the price is optional (the ledger falls back to the
  # latest stored close). The entered price is read as the security's own
  # currency — the same currency a bookable manual sell is priced in.
  defp compute_sell_preview(%{"type" => "sell"} = params) do
    with {:ok, security_id} <- parse_form_int(params["security_id"]),
         {:ok, quantity} <- parse_form_decimal(params["quantity"]) do
      opts =
        case parse_form_decimal(params["price"]) do
          {:ok, price} -> [price: price]
          _no_price -> []
        end

      Ledger.sell_consumption_preview(security_id, quantity, opts)
    else
      _incomplete -> nil
    end
  end

  defp compute_sell_preview(_params), do: nil

  defp parse_form_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _invalid -> :error
    end
  end

  defp parse_form_int(_value), do: :error

  defp parse_form_decimal(value) when is_binary(value) do
    case value |> normalize_decimal_comma() |> String.trim() |> Decimal.parse() do
      {%Decimal{} = decimal, ""} ->
        if Decimal.compare(decimal, 0) == :gt, do: {:ok, decimal}, else: :error

      _invalid ->
        :error
    end
  end

  defp parse_form_decimal(_value), do: :error

  # The decomposition columns appear only when a tranche's settlement leg is
  # denominated in another currency than the security — the same-currency
  # majority keeps the compact four-column table.
  defp sell_preview_cross_currency?(%{lots: lots, security_currency: security_currency}) do
    Enum.any?(lots, fn lot ->
      lot.base_currency != nil and lot.base_currency != security_currency
    end)
  end

  defp signed_or_dash(value), do: PortfolixirWeb.Format.signed_decimal(value, 2)

  defp gain_class(%Decimal{} = value) do
    case Decimal.compare(value, 0) do
      :gt -> "is-positive"
      :lt -> "is-negative"
      :eq -> nil
    end
  end

  defp gain_class(_value), do: nil

  # Why a tranche shows no figure — terse, impersonal (mirrors the security
  # detail's ADR-0033 hints).
  defp sell_preview_hint(%{gross_gain: nil, undecomposed_reason: :missing_native_cost}),
    do:
      gettext(
        "No security-currency cost is derivable from the recorded booking (no settlement legs, no stored rate at the booking date)."
      )

  defp sell_preview_hint(%{gross_gain: nil, undecomposed_reason: :no_price}),
    do: gettext("No price is available for this security.")

  defp sell_preview_hint(_lot), do: nil

  # Normalized, so holdings show "200" instead of the stored scale
  # ("200.000000000000"); nil stays blank.
  defp format_decimal(nil), do: ""

  defp format_decimal(decimal) do
    decimal |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  # Only offer depots that have a usable linked cash account; a depot without one
  # can never form a valid transaction, so it must not be a selectable dead end.
  defp bookable_depots(accounts) do
    Enum.filter(accounts, fn account -> match?(%{cash_account: %{}}, account) end)
  end

  # "Depot name (Cash account)" — the linked cash account reads as a quiet
  # parenthetical caption rather than an arrow with a separate footnote.
  defp depot_option_label(%{name: name, cash_account: %{name: cash_name}}) do
    "#{name} (#{cash_name})"
  end

  # The transaction currency follows the chosen depot's linked cash account.
  defp derived_currency(accounts, depot_id) when is_binary(depot_id) and depot_id != "" do
    case Enum.find(accounts, &(to_string(&1.id) == depot_id)) do
      %{cash_account: %{currency_code: code}} -> code
      _ -> nil
    end
  end

  defp derived_currency(_accounts, _depot_id), do: nil

  defp maybe_put_currency(params, nil), do: params
  defp maybe_put_currency(params, currency), do: Map.put(params, "currency_code", currency)

  defp success(socket, message), do: assign(socket, success: message, error: nil)
  defp failure(socket, message), do: assign(socket, error: message, success: nil)

  # German decimal commas (fix round, UAT): "10,50" means 10.50 to a German
  # user. Normalized ONLY at this form boundary — a single comma becomes a dot
  # when the string carries no dot; anything else (thousands separators,
  # already-dotted input) passes through untouched for the changeset to judge.
  # Persisted parsing elsewhere is deliberately not changed.
  @comma_decimal_fields ~w(quantity price fees taxes)

  defp normalize_decimal_inputs(params) do
    Enum.reduce(@comma_decimal_fields, params, fn field, acc ->
      case Map.get(acc, field) do
        value when is_binary(value) -> Map.put(acc, field, normalize_decimal_comma(value))
        _ -> acc
      end
    end)
  end

  defp normalize_decimal_comma(value) do
    trimmed = String.trim(value)

    if not String.contains?(trimmed, ".") and
         length(String.split(trimmed, ",")) == 2 do
      String.replace(trimmed, ",", ".")
    else
      value
    end
  end

  # Per-field changeset errors keyed by the form field name, so each input can
  # carry aria-invalid + an associated message (UX-DR13, #412 follow-up).
  # Messages run through the "errors" Gettext domain (fix round), so a German
  # user reads "ist ungültig" instead of the raw "is invalid".
  defp field_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Map.new(fn {field, messages} -> {to_string(field), Enum.join(messages, ", ")} end)
  end

  defp translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(PortfolixirWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(PortfolixirWeb.Gettext, "errors", msg, opts)
    end
  end

  attr(:errors, :map, required: true)
  attr(:field, :string, required: true)

  defp field_error(assigns) do
    ~H"""
    <p :if={@errors[@field]} id={"tx-error-#{@field}"} class="field-error" role="alert">
      <%= @errors[@field] %>
    </p>
    """
  end

  # The submit flash: localized field label + translated message (fix round),
  # so the German UI never mixes "price is invalid" into a translated page.
  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, error} -> "#{field_label(field)} #{translate_error(error)}" end)
    |> Enum.join(", ")
  end

  # The same labels the form inputs carry; unknown fields fall back to the
  # schema field name.
  defp field_label(:quantity), do: gettext("Quantity")
  defp field_label(:price), do: gettext("Price")
  defp field_label(:fees), do: gettext("Fees")
  defp field_label(:taxes), do: gettext("Taxes")
  defp field_label(:date), do: gettext("Date")
  defp field_label(:type), do: gettext("Type")
  defp field_label(:security_id), do: gettext("Security")
  defp field_label(:securities_account_id), do: gettext("Depot")
  defp field_label(:cash_account_id), do: gettext("Cash account")
  defp field_label(:gross_amount), do: gettext("Amount")
  defp field_label(:currency_code), do: gettext("Currency")
  defp field_label(other), do: to_string(other)
end
