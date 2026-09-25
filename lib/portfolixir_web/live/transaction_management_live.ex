defmodule PortfolixirWeb.TransactionManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ChangedSince
  alias PortfolixirWeb.ColumnPicker
  alias PortfolixirWeb.DecimalInput
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.TransactionKindLabel
  alias PortfolixirWeb.Transactions.SettlementForm

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
  # The amount rides in the defaults (#786): a dividend row shows what was
  # paid, not only its quantity. The currency is the amount's suffix, so its
  # own column stays in the picker rather than in the defaults.
  @tx_column_defaults ["date", "type", "security", "quantity", "price", "gross_amount"]
  @tx_column_keys @tx_column_defaults ++ ["currency", "fees", "taxes", "notes"]
  @numeric_columns ["quantity", "price", "gross_amount", "fees", "taxes"]

  # The drawer's decimal fields, read by the one decimal-input rule (#869).
  @decimal_fields ~w(quantity price fees taxes settlement_amount settlement_fx_rate)

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
     |> assign(:column_picker_open?, false)
     |> assign(:booking_open?, false)
     |> assign(:editing_id, nil)
     |> assign(:editing_split, nil)
     |> assign(:row_menu_id, nil)
     |> assign(:filter_sheet_open?, false)
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
        <%= if @securities_accounts == [] do %>
          <section id="transaction-setup-empty" class="empty-state" role="status">
            <p><%= gettext("Bookings need a depot with a cash account.") %></p>
            <.link navigate="/portfolios" class="button"><%= gettext("Create a depot and cash account") %></.link>
          </section>
        <% end %>

        <%!-- #803 (review C6, variant C): the page opens on the history; the
             booking form lives in a side drawer opened from the section
             head — a bottom sheet under 720 px — and the holdings table left
             the route (it is Wealth → Holdings). --%>
        <div class={["transactions-columns", @booking_open? && "transactions-columns--drawer"]}>
        <section id="transaction-list-panel" class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Transaction history") %></h2>
            <div class="section-head-controls">
              <button
                :if={@transactions != []}
                type="button"
                id="transaction-filter-sheet-toggle"
                class="filter-sheet-toggle"
                phx-click="open_filter_sheet"
                aria-haspopup="dialog"
                aria-expanded={to_string(@filter_sheet_open?)}
                aria-controls={@filter_sheet_open? && "transaction-filter-sheet"}
              >
                <AppShell.icon name={:filter} />
                <%= gettext("Filter") %>
                <span
                  :if={active_chip_count(assigns) > 0}
                  class="badge"
                  data-role="filter-sheet-count"
                >
                  <%= active_chip_count(assigns) %>
                </span>
              </button>

              <button
                :if={@securities_accounts != []}
                type="button"
                id="open-booking"
                class="button-primary"
                phx-click="open_booking"
                aria-haspopup="dialog"
                aria-expanded={to_string(@booking_open?)}
                aria-controls={@booking_open? && "booking-drawer"}
              >
                <AppShell.icon name={:plus} size={14} />
                <%= gettext("Record transaction") %>
              </button>
            </div>
          </header>
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
            <.chip_families
              prefix="tx"
              layout={:row}
              filters={@filters}
              cash_accounts={@cash_accounts}
              transactions={@transactions}
              since={@since}
            />

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

            <.more_filters
              id="transaction-more-filters"
              form_id="transaction-filters"
              filters={@filters}
              transactions={@transactions}
              more_filters_count={@more_filters_count}
            />

            <%!-- #816: under 560 px the three chip families and the "More
                 filters" disclosure sit behind this control in a bottom
                 sheet — the mechanism #800 built for the securities toolbar,
                 reused as it stands. Above 560 px the control is hidden
                 (CSS) and the row above is unchanged. --%>
            <%= if @filter_sheet_open? do %>
              <dialog
                id="transaction-filter-sheet"
                class="filter-sheet"
                phx-hook="ModalDialog"
                data-close-event="close_filter_sheet"
                aria-labelledby="transaction-filter-sheet-title"
              >
                <header class="filter-sheet__head">
                  <h2 id="transaction-filter-sheet-title"><%= gettext("Filter") %></h2>
                  <button
                    type="button"
                    class="icon-button"
                    aria-label={gettext("Close")}
                    phx-click="close_filter_sheet"
                  >
                    <AppShell.icon name={:x} />
                  </button>
                </header>
                <.chip_families
                  prefix="sheet"
                  layout={:sheet}
                  filters={@filters}
                  cash_accounts={@cash_accounts}
                  transactions={@transactions}
                  since={@since}
                />
                <div class="filter-sheet__family">
                  <.more_filters
                    id="sheet-more-filters"
                    form_id="sheet-transaction-filters"
                    filters={@filters}
                    transactions={@transactions}
                    more_filters_count={@more_filters_count}
                  />
                </div>
                <footer class="filter-sheet__foot">
                  <button
                    type="button"
                    id="transaction-filter-sheet-reset"
                    class="button"
                    phx-click="reset_filters"
                  >
                    <%= gettext("Reset") %>
                  </button>
                  <button
                    type="button"
                    id="transaction-filter-sheet-done"
                    class="button-primary"
                    phx-click="close_filter_sheet"
                  >
                    <%= gettext("Done") %>
                  </button>
                </footer>
              </dialog>
            <% end %>

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
              <%!-- #850: the shared grouped popover on its toggle (DESIGN.md →
                    Overlays, pick E3) — it opens over the table instead of
                    pushing it down, as the <details> it replaces did. --%>
              <div class="column-picker-bar popover-container">
                <ColumnPicker.toggle
                  id="tx-column-toggle"
                  open={@column_picker_open?}
                  on_toggle="toggle_column_picker"
                />
                <ColumnPicker.picker
                  :if={@column_picker_open?}
                  id="tx-column-picker"
                  form_id="tx-column-form"
                  on_change="set_tx_columns"
                  on_close="close_column_picker"
                  toggle_id="tx-column-toggle"
                  groups={tx_column_groups()}
                  selected={@tx_columns}
                />
              </div>
              <div
                id="transaction-table-wrapper"
                class="data-table-wrapper"
                phx-hook="ColumnPrefs"
                data-storage-key="transactions.columns"
                data-restore-event="set_tx_columns"
                data-current-columns={Jason.encode!(@tx_columns)}
              >
                <table id="transaction-list">
                  <thead>
                    <tr>
                      <th :for={key <- @tx_columns} {num_attrs(key)}><%= tx_column_label(key) %></th>
                      <%!-- The running balance is only meaningful for ONE
                            account, so the column appears exactly when the
                            chips narrow to one and not before — never via the
                            picker. --%>
                      <th :if={@balance_account} class="col-subject">
                        <%= gettext("Balance") %>
                        <small><%= @balance_account.currency_code %></small>
                      </th>
                      <%!-- #809: row actions behind the kebab, never as
                            standing buttons on every row (Tables pattern). --%>
                      <th class="row-actions-head">
                        <span class="visually-hidden"><%= gettext("Actions") %></span>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for group <- grouped_by_month(@filtered_transactions) do %>
                      <tr class="tx-group-head" data-month-group={group.id}>
                        <th
                          colspan={length(@tx_columns) + if(@balance_account, do: 2, else: 1)}
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
                                  <td class="num"><%= format_quantity(transaction.quantity) %></td>
                                <% end %>
                              <% "price" -> %>
                                <%= if transaction.type == "split" do %>
                                  <td class="num">—</td>
                                <% else %>
                                  <td class="num"><%= PortfolixirWeb.Format.decimal(transaction.price, 2) %></td>
                                <% end %>
                              <% "gross_amount" -> %>
                                <%!-- The booking's money as the cash account sees it,
                                      the currency as the value's suffix (value-slot
                                      rule, 2026-09-12). --%>
                                <%= case tx_money(transaction) do %>
                                  <% nil -> %>
                                    <td class="num" data-role="amount">—</td>
                                  <% amount -> %>
                                    <td class="num" data-role="amount">
                                      <%= signed_money(transaction.type, amount) %><small class="value-suffix"><%= money_currency(transaction) %></small>
                                    </td>
                                <% end %>
                              <% _other -> %>
                                <td {num_attrs(key)}><%= tx_cell(transaction, key) %></td>
                            <% end %>
                          <% end %>
                          <td :if={@balance_account} class="numeric col-subject" data-role="running-balance">
                            <%!-- Absent, never repeated: a row that does not
                                  move this account carries no balance, because
                                  the previous row's figure would read as
                                  "nothing happened here". --%>
                            <%= running_balance(@running_balances, transaction) %>
                          </td>
                          <td class="row-actions">
                            <.row_kebab id={"tx-kebab-#{transaction.id}"} transaction={transaction} open?={@row_menu_id == transaction.id} />
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
              </div>
              <%!-- #799 (UX-DR27): under 560 px the history gives way to
                   these two-line rows — the month heads stay; date · kind
                   over the subject, the signed amount over the size the
                   journal never showed. --%>
              <ul id="transaction-phone-rows" class="phone-rows" aria-label={gettext("Transactions")}>
                <%= for group <- grouped_by_month(@filtered_transactions) do %>
                  <li class="phone-rows__group" data-month-group={group.id}>
                    <span class="tx-group-month"><%= group.label %></span>
                    <span class="tx-group-subtotal">
                      <%= ngettext("%{count} transaction", "%{count} transactions", group.count,
                        count: group.count) %> · <.currency_totals totals={group.totals} />
                    </span>
                  </li>
                  <li
                    :for={transaction <- group.transactions}
                    class="phone-row"
                    data-role="phone-row"
                    data-transaction={transaction.id}
                  >
                    <span class="phone-row__body">
                      <span class="phone-row__name">
                        <%= PortfolixirWeb.Format.date(transaction.date) %> · <%= tx_type_label(
                          transaction.type
                        ) %>
                      </span>
                      <span :if={phone_subject(transaction)} class="phone-row__ids">
                        <%= phone_subject(transaction) %>
                      </span>
                    </span>
                    <span class="phone-row__figures">
                      <span class="phone-row__figure"><%= phone_amount(transaction) %></span>
                      <span :if={phone_size(transaction)} class="phone-row__figure2">
                        <%= phone_size(transaction) %>
                      </span>
                      <span
                        :if={@balance_account}
                        class="phone-row__figure2"
                        data-role="running-balance"
                      >
                        <%= gettext("Balance") %> <%= running_balance(@running_balances, transaction) %><small class="value-suffix"><%= @balance_account.currency_code %></small>
                      </span>
                    </span>
                    <.row_kebab
                      id={"tx-phone-kebab-#{transaction.id}"}
                      transaction={transaction}
                      open?={@row_menu_id == transaction.id}
                    />
                  </li>
                <% end %>
              </ul>
            <% end %>
          <% end %>
          <%!-- #809: one open menu at a time, rendered outside the table so
               the popover is never clipped by the scroller — and AFTER the
               triggers, the way the securities, accounts and classifications
               menus already do. Since #858 the shared PositionedMenu hook
               moves the focus into the menu on open and back to the kebab on
               Escape or Tab, so document order no longer carries the
               keyboard path on its own. `trigger` names the kebab that is
               visible at this width: the table one above 560 px, the phone
               one below it. --%>
          <% open_menu_transaction =
            @row_menu_id && Enum.find(@filtered_transactions, &(&1.id == @row_menu_id)) %>
          <AppShell.row_menu
            :if={open_menu_transaction}
            id={"tx-row-menu-#{open_menu_transaction.id}"}
            trigger={"tx-kebab-#{open_menu_transaction.id}"}
            label={gettext("Transaction actions")}
          >
            <button
              type="button"
              id={"tx-edit-#{open_menu_transaction.id}"}
              class="row-context-menu__item"
              role="menuitem"
              phx-click="edit_transaction"
              phx-value-id={open_menu_transaction.id}
            >
              <AppShell.icon name={:edit} />
              <%= gettext("Edit") %>
            </button>
          </AppShell.row_menu>
        </section>
        <.split_drawer
          :if={@booking_open? and @editing_split != nil}
          split={@editing_split}
          securities={@securities}
          form_errors={@form_errors}
        />
        <.booking_drawer
          :if={@booking_open? and @editing_split == nil}
          editing?={@editing_id != nil}
          transaction_form={@transaction_form}
          form_errors={@form_errors}
          securities_accounts={@securities_accounts}
          securities={@securities}
          sell_preview={@sell_preview}
        />
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
    {:noreply, failure(socket, gettext("A booking needs a depot with a cash account."))}
  end

  # #803: the drawer's state is socket state; Cancel and the hook's close
  # event discard the draft, and a recorded booking closes it.
  def handle_event("open_booking", _params, socket) do
    {:noreply, assign(socket, :booking_open?, true)}
  end

  def handle_event("close_booking", _params, socket) do
    {:noreply,
     socket
     |> assign(:booking_open?, false)
     |> assign(:editing_id, nil)
     |> assign(:editing_split, nil)
     |> assign(:transaction_form, @transaction_form)
     |> assign(:form_errors, %{})
     |> assign(:sell_preview, nil)}
  end

  def handle_event("form_changed", %{"transaction" => params} = event, socket) do
    # The drawer's inputs send strings only; anything else is not a field
    # (E25 S4, F17).
    params = LiveParam.form(params)

    # #395: a cross-currency trade's settlement amount and rate derive each
    # other from whichever the operator just typed (the event's `_target`).
    target = event |> Map.get("_target", []) |> List.wrap() |> List.last() |> LiveParam.string()

    # Which settlement figure was typed last travels in the form's hidden
    # field; an event that omits it keeps the drawer's last known one.
    params =
      case socket.assigns.transaction_form["settlement_source"] do
        nil -> params
        source -> Map.put_new(params, "settlement_source", source)
      end

    params = SettlementForm.derive(params, target, settlement_pair(params, socket.assigns))

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

    fields =
      filters |> LiveParam.form() |> Map.take(Map.keys(default_filters()) -- @chip_families)

    {:noreply,
     socket
     |> assign(:filters, default_filters() |> Map.merge(fields) |> Map.merge(chips))
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
      when family in ["type", "account"] and is_binary(option) do
    key = if family == "type", do: "types", else: "account_ids"
    active = Map.fetch!(socket.assigns.filters, key)
    toggled = if option in active, do: List.delete(active, option), else: [option | active]

    {:noreply,
     socket
     |> assign(:filters, Map.put(socket.assigns.filters, key, Enum.sort(toggled)))
     |> apply_current_filters()}
  end

  # #809: one row menu open at a time; click-away and Escape close it.
  def handle_event("open_row_menu", %{"id" => id_str}, socket) do
    case LiveParam.id(id_str) do
      nil -> {:noreply, socket}
      id -> {:noreply, assign(socket, :row_menu_id, id)}
    end
  end

  def handle_event("close_row_menu", _params, socket) do
    {:noreply, assign(socket, :row_menu_id, nil)}
  end

  # #809: the human view for `Ledger.update_transaction/3`, which has existed
  # since before the two-way coverage rule. The drawer #803 built for
  # recording is the same drawer: same fields, same validation, same sell-lot
  # preview — only pre-filled, and `editing_id` is what tells the save which
  # of the two ledger calls to make.
  def handle_event("edit_transaction", %{"id" => id_str}, socket) do
    with {:ok, id} <- LiveParam.fetch_id(id_str),
         %Transaction{} = transaction <- Ledger.get_transaction(id) do
      {:noreply,
       socket
       |> assign(:row_menu_id, nil)
       |> assign(:editing_id, id)
       # E25 S6 (G07, pick G12.3 = A): a split row opens its own drawer
       # state — the facts fixed, only the note editable.
       |> assign(:editing_split, if(transaction.type == "split", do: transaction))
       |> assign(:transaction_form, form_from_transaction(transaction, socket.assigns.securities))
       |> assign(:form_errors, %{})
       |> assign(:sell_preview, nil)
       |> assign(:booking_open?, true)}
    else
      _ -> {:noreply, assign(socket, :row_menu_id, nil)}
    end
  end

  # #816: the phone sheet, reusing #800's mechanism as it stands. The chips
  # inside it drive the same events as the row, so opening the sheet changes
  # where the families are rendered and nothing about what they do.
  def handle_event("open_filter_sheet", _params, socket) do
    {:noreply, assign(socket, :filter_sheet_open?, true)}
  end

  def handle_event("close_filter_sheet", _params, socket) do
    {:noreply, assign(socket, :filter_sheet_open?, false)}
  end

  # Reset clears every family the sheet shows — the chips AND the demoted
  # conditions — because a Reset that leaves a hidden condition standing is
  # the state-hiding defect the counted control exists to prevent. The sheet
  # stays open: the operator is still filtering.
  def handle_event("reset_filters", _params, socket) do
    socket = assign(socket, :filters, default_filters())

    if socket.assigns.since do
      {:noreply, push_patch(socket, to: "/transactions")}
    else
      {:noreply, apply_current_filters(socket)}
    end
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

  def handle_event("toggle_column_picker", _params, socket) do
    {:noreply, update(socket, :column_picker_open?, &(not &1))}
  end

  def handle_event("close_column_picker", _params, socket) do
    {:noreply, assign(socket, :column_picker_open?, false)}
  end

  def handle_event("save_transaction", %{"transaction" => params}, socket) do
    params = LiveParam.form(params)

    # The currency is authoritative from the chosen depot's cash account, never a
    # free-text field the user could mistype (#473).
    currency =
      derived_currency(socket.assigns.securities_accounts, params["securities_account_id"])

    params =
      params
      |> put_portfolio_from_depot(socket.assigns.securities_accounts)
      |> maybe_put_currency(currency)

    # #869: the figures are read by the one decimal-input rule; the form keeps
    # them exactly as typed, so a refusal never rewrites "2,5" into "2.5".
    # #395: a cross-currency trade is booked in the security's currency with
    # its settlement; a missing settlement amount is named on its field.
    with {:figures, {:ok, figures}} <- {:figures, DecimalInput.cast(params, @decimal_fields)},
         {:ok, prepared} <-
           SettlementForm.prepare(figures, settlement_pair(params, socket.assigns)) do
      save_booking(socket, params, prepared)
    else
      {:figures, {:error, errors}} ->
        {:noreply,
         refuse(socket, params, errors, gettext("A figure cannot be read; its field says why."))}

      {:error, errors} ->
        {:noreply, refuse(socket, params, errors, gettext("The settlement amount is missing."))}
    end
  end

  # E25 S6 (G07): the split drawer's one write, the note. The ledger refuses
  # every other change to a split row, so nothing else is sent.
  def handle_event("save_split_note", %{"split" => %{"notes" => notes}}, socket)
      when is_binary(notes) do
    case socket.assigns.editing_split do
      %Transaction{id: id} -> save_split_note(socket, id, notes)
      nil -> {:noreply, socket}
    end
  end

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp save_split_note(socket, id, notes) do
    case book(id, %{"notes" => notes}) do
      {:ok, _transaction} ->
        {:noreply,
         socket
         |> assign(:transaction_form, @transaction_form)
         |> assign(:form_errors, %{})
         |> assign(:booking_open?, false)
         |> assign(:editing_id, nil)
         |> assign(:editing_split, nil)
         |> success(gettext("Note saved"))
         |> load_state()}

      # The drawer keeps what was typed (E25 S6 review round, R4): a refusal
      # names what to correct, never what to type again (board 11's rule).
      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:editing_split, %{socket.assigns.editing_split | notes: notes})
         |> assign(:form_errors, field_errors(changeset))
         |> failure(changeset_error(changeset))}

      :gone ->
        {:noreply,
         socket
         |> assign(:booking_open?, false)
         |> assign(:editing_id, nil)
         |> assign(:editing_split, nil)
         |> failure(gettext("That transaction no longer exists."))
         |> load_state()}
    end
  end

  defp refuse(socket, params, errors, message) do
    socket
    |> assign(:transaction_form, params)
    |> assign(:form_errors, errors)
    |> failure(message)
  end

  defp save_booking(socket, params, prepared) do
    case book(socket.assigns.editing_id, prepared) do
      {:ok, _transaction} ->
        {:noreply,
         socket
         |> assign(:transaction_form, @transaction_form)
         |> assign(:form_errors, %{})
         |> assign(:sell_preview, nil)
         |> assign(:booking_open?, false)
         |> success(saved_message(socket.assigns.editing_id))
         |> assign(:editing_id, nil)
         |> assign(:editing_split, nil)
         |> load_state()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:transaction_form, params)
         |> assign(:form_errors, field_errors(changeset))
         |> failure(changeset_error(changeset))}

      :gone ->
        {:noreply,
         socket
         |> assign(:booking_open?, false)
         |> assign(:editing_id, nil)
         |> failure(gettext("That transaction no longer exists."))
         |> load_state()}
    end
  end

  # #809: the one place the two ledger calls diverge. A booking that vanished
  # between opening the drawer and saving is a plain message, never a crash.
  defp book(nil, params), do: Ledger.create_transaction(Actor.owner_ui(), params)

  defp book(id, params) do
    case Ledger.get_transaction(id) do
      %Transaction{} = transaction ->
        # Deleted between this read and the write's lock (E25 S6, F49).
        case Ledger.update_transaction(Actor.owner_ui(), transaction, params) do
          {:error, :not_found} -> :gone
          result -> result
        end

      nil ->
        :gone
    end
  end

  defp settlement_pair(params, assigns),
    do: SettlementForm.pair(params, assigns.securities_accounts, assigns.securities)

  defp saved_message(nil), do: gettext("Transaction recorded")
  defp saved_message(_id), do: gettext("Transaction updated")

  # The drawer's fields, filled from a stored booking. Decimals travel as the
  # strings the inputs carry; a nil field is the empty string the form uses,
  # never "nil" on the screen.
  defp form_from_transaction(%Transaction{} = transaction, securities) do
    %{
      "type" => transaction.type,
      "date" => transaction.date && Date.to_iso8601(transaction.date),
      "securities_account_id" => to_form_value(transaction.securities_account_id),
      "security_id" => to_form_value(transaction.security_id),
      "quantity" => to_form_value(transaction.quantity),
      "price" => to_form_value(transaction.price),
      "fees" => to_form_value(transaction.fees),
      "taxes" => to_form_value(transaction.taxes),
      "currency_code" => transaction.currency_code || "EUR",
      "notes" => transaction.notes || ""
    }
    |> Map.merge(SettlementForm.from_transaction(transaction, securities))
  end

  defp to_form_value(nil), do: ""

  # #869: a stored figure opens in the page's locale ("45,6" on a German
  # page), its digits as stored.
  defp to_form_value(%Decimal{} = value),
    do: value |> Decimal.normalize() |> DecimalInput.value()

  defp to_form_value(value), do: to_string(value)

  # ADR-0024: the ledger surface spans every depot at once. The internal
  # portfolio records are only iterated as the mechanism behind the
  # portfolio-bound positions read; depot ids are globally unique, so the
  # concatenated position keys never collide.
  defp load_state(socket) do
    # A benchmark security is never offered for booking (ADR-0046 §1); the
    # history filter builds its own list from the transactions present.
    securities = Catalog.list_securities(is_benchmark: false)
    securities_accounts = Portfolios.list_securities_accounts()
    cash_accounts = Portfolios.list_cash_accounts()
    transactions = Ledger.list_transactions()

    socket
    |> assign(
      securities_accounts: securities_accounts,
      cash_accounts: cash_accounts,
      securities: securities,
      transactions: transactions
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
    case BoundedDate.parse(str) do
      {:ok, date} -> Date.compare(tx.date, date) != :lt
      _ -> true
    end
  end

  defp to_match?(_tx, blank) when blank in ["", nil], do: true

  defp to_match?(tx, str) do
    case BoundedDate.parse(str) do
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
  # #809: the row's kebab, on the table row and on the phone row. The menu
  # itself is rendered once at the page level so its popover is never clipped
  # by the table scroller.
  attr(:id, :string, required: true)
  attr(:transaction, :map, required: true)
  attr(:open?, :boolean, required: true)

  # #870: named for its row through the shared trigger, the booking composed
  # from its kind, its subject and its date.
  defp row_kebab(assigns) do
    ~H"""
    <AppShell.row_kebab
      id={@id}
      row={row_name(@transaction)}
      open={@open?}
      phx-click="open_row_menu"
      phx-value-id={@transaction.id}
    />
    """
  end

  defp row_name(transaction) do
    AppShell.row_name([
      tx_type_label(transaction.type),
      phone_subject(transaction),
      PortfolixirWeb.Format.date(transaction.date)
    ])
  end

  # #816: the three chip families, rendered twice — once as the desktop row
  # and once stacked inside the phone sheet. `prefix` keeps the two copies'
  # ids apart; both drive the same `toggle_filter` event, so the filter
  # vocabulary is learned once and works in both places.
  attr(:prefix, :string, required: true)
  attr(:layout, :atom, required: true)
  attr(:filters, :map, required: true)
  attr(:cash_accounts, :list, required: true)
  attr(:transactions, :list, required: true)
  attr(:since, :any, default: nil)

  defp chip_families(assigns) do
    ~H"""
    <div
      :if={@layout == :row}
      id="transaction-chips"
      class="filter-chips"
      role="group"
      aria-label={gettext("Filter the history")}
    >
      <.chip_family_content {assigns} />
    </div>
    <div
      :if={@layout == :sheet}
      class="filter-sheet__families"
      role="group"
      aria-label={gettext("Filter the history")}
    >
      <.chip_family_content {assigns} />
    </div>
    """
  end

  attr(:prefix, :string, required: true)
  attr(:layout, :atom, required: true)
  attr(:filters, :map, required: true)
  attr(:cash_accounts, :list, required: true)
  attr(:transactions, :list, required: true)
  attr(:since, :any, default: nil)

  # Chips are toggles, so they carry aria-pressed rather than aria-current,
  # and the pressed state shows on the border as well as the tint so it
  # survives forced colours (UX-DR7).
  defp chip_family_content(assigns) do
    ~H"""
    <span class={@layout == :sheet && "filter-sheet__family"}>
      <span class="filter-chips__family"><%= gettext("Account") %></span>
      <%= for account <- filter_account_options(@cash_accounts, @transactions) do %>
        <button
          type="button"
          id={"#{@prefix}-chip-account-#{account.id}"}
          class={["filter-chip", to_string(account.id) in @filters["account_ids"] && "is-active"]}
          aria-pressed={to_string(to_string(account.id) in @filters["account_ids"])}
          phx-click="toggle_filter"
          phx-value-family="account"
          phx-value-option={account.id}
        >
          <%= account.name %>
        </button>
      <% end %>
    </span>

    <span class={@layout == :sheet && "filter-sheet__family"}>
      <span class="filter-chips__family"><%= gettext("Type") %></span>
      <%= for type <- filter_type_options(@transactions) do %>
        <button
          type="button"
          id={"#{@prefix}-chip-type-#{type}"}
          class={["filter-chip", type in @filters["types"] && "is-active"]}
          aria-pressed={to_string(type in @filters["types"])}
          phx-click="toggle_filter"
          phx-value-family="type"
          phx-value-option={type}
        >
          <%= tx_type_label(type) %>
        </button>
      <% end %>
    </span>

    <%!-- The desktop row keeps the id it has always had; only the sheet copy
          is prefixed, so #816 adds a surface without renaming one. --%>
    <ChangedSince.chips
      id={if @layout == :row, do: "changed-since-chips", else: "#{@prefix}-changed-since-chips"}
      since={@since}
    />
    """
  end

  # The demoted conditions, rendered twice like the chips. The DESKTOP copy
  # keeps the ids it has always had — "the desktop chip row untouched above
  # 560 px" (#816) — and only the sheet copy is prefixed.
  attr(:id, :string, required: true)
  attr(:form_id, :string, required: true)
  attr(:filters, :map, required: true)
  attr(:transactions, :list, required: true)
  attr(:more_filters_count, :integer, required: true)

  defp more_filters(assigns) do
    ~H"""
    <details id={@id} class="more-filters">
      <summary>
        <AppShell.icon name={:filter} />
        <%= gettext("More filters") %>
        <%!-- A demoted control that hides active state is a worse defect
              than the builder it replaces, so the count comes out to the
              summary. --%>
        <span :if={@more_filters_count > 0} class="badge" data-role="more-filters-count">
          <%= @more_filters_count %>
        </span>
      </summary>
      <form id={@form_id} phx-change="filter_changed" class="transaction-filters">
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
    """
  end

  # The count the Filter control carries: the active chips of the three
  # families, so a demoted control never hides state (#800's reason, #816's
  # surface).
  defp active_chip_count(assigns) do
    filters = assigns.filters

    length(Map.get(filters, "account_ids", [])) +
      length(Map.get(filters, "types", [])) +
      if(assigns[:since], do: 1, else: 0)
  end

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
    |> Enum.group_by(&money_currency/1)
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

  # -- #732 column registries -------------------------------------------------

  # #850: the picker's groups, every key of `@tx_column_keys` in exactly one
  # (the picker test pins that none is dropped).
  defp tx_column_groups do
    [
      {gettext("Booking"), ~w(date type security)},
      {gettext("Amounts"), ~w(quantity price gross_amount fees taxes)},
      {gettext("Other"), ~w(currency notes)}
    ]
    |> Enum.map(fn {legend, keys} -> {legend, Enum.map(keys, &{&1, tx_column_label(&1)})} end)
  end

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
  defp tx_column_label("gross_amount"), do: gettext("Amount")
  defp tx_column_label("fees"), do: gettext("Fees")
  defp tx_column_label("taxes"), do: gettext("Taxes")
  defp tx_column_label("notes"), do: gettext("Notes")

  # The date reads under the locale like every other figure in this table
  # (#786 localized the numbers and left this one; the phone row beside it has
  # read German since #799, so the two disagreed on one route).
  defp tx_cell(transaction, "date"), do: PortfolixirWeb.Format.date(transaction.date)
  defp tx_cell(transaction, "type"), do: tx_type_label(transaction.type)
  defp tx_cell(transaction, "security"), do: transaction.security && transaction.security.name
  defp tx_cell(transaction, "currency"), do: transaction.currency_code
  defp tx_cell(transaction, "fees"), do: PortfolixirWeb.Format.money(transaction.fees)
  defp tx_cell(transaction, "taxes"), do: PortfolixirWeb.Format.money(transaction.taxes)
  defp tx_cell(transaction, "notes"), do: transaction.notes

  # Human, localized labels for the stored type enum; the form value and the
  # ledger keep the machine "buy"/"sell". One shared table for both
  # transaction surfaces, every kind covered, no fallback (#785).
  defp tx_type_label(kind), do: TransactionKindLabel.label(kind)

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
    with {:ok, security_id} <- LiveParam.fetch_id(params["security_id"]),
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

  # A finite decimal only (E25 S4, F17): `NaN` or `Infinity` typed into the
  # drawer is not a quantity, and would raise in the comparison below. Read by
  # the one decimal-input rule (#869), which parses through the same bounded
  # parser.
  defp parse_form_decimal(value) do
    case DecimalInput.parse(value) do
      {:ok, decimal} -> if Decimal.compare(decimal, 0) == :gt, do: {:ok, decimal}, else: :error
      _blank_or_refused -> :error
    end
  end

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

  defp num_attrs(key) when key in @numeric_columns, do: %{class: "num"}
  defp num_attrs(_key), do: %{}

  # The quantity in its own scale under the locale's separators (#786):
  # "0,05", "30", "1.000" — never the stored twelve-place scale.
  defp format_quantity(nil), do: ""

  defp format_quantity(%Decimal{} = quantity) do
    normalized = Decimal.normalize(quantity)
    places = normalized.exp |> Kernel.-() |> max(0) |> min(8)
    PortfolixirWeb.Format.decimal(normalized, places)
  end

  @outflow_kinds ~w(buy removal fee tax cash_transfer)

  # The phone row's lines (#799): the subject the booking touched, the money
  # as the cash account sees it with its currency, and the size — quantity ×
  # price, the quantity alone, a split's ratio — where the booking has one.
  defp phone_subject(%{security: %{name: name}}) when is_binary(name), do: name
  defp phone_subject(%{cash_account: %{name: name}}) when is_binary(name), do: name
  defp phone_subject(%{securities_account: %{name: name}}) when is_binary(name), do: name
  defp phone_subject(_transaction), do: nil

  defp phone_amount(transaction) do
    case tx_money(transaction) do
      nil -> "—"
      amount -> signed_money(transaction.type, amount) <> " " <> money_currency(transaction)
    end
  end

  defp phone_size(%{type: "split"} = transaction), do: split_ratio_label(transaction)

  defp phone_size(%{quantity: %Decimal{} = quantity, price: %Decimal{} = price}),
    do: "#{format_quantity(quantity)} × #{PortfolixirWeb.Format.decimal(price, 2)}"

  defp phone_size(%{quantity: %Decimal{} = quantity}),
    do: gettext("%{quantity} units", quantity: format_quantity(quantity))

  defp phone_size(_transaction), do: nil

  # The booking's money on the same basis as the month subtotal (the stored
  # gross amount, else quantity × price); a split or a transfer without a
  # price has none.
  # The currency a booking's money is in: a recorded cash amount moves through
  # the cash account, so it is in the account's currency — for a cross-
  # currency trade (ADR-0015) that is not the booking's currency, which is the
  # security's (closing act, UAT: a EUR debit read "CHF"). Without a recorded
  # cash amount the figure is quantity × price, in the booking's currency.
  defp money_currency(%{gross_amount: %Decimal{}, cash_account: %{currency_code: code}})
       when is_binary(code),
       do: code

  defp money_currency(transaction), do: transaction.currency_code

  defp tx_money(%{type: "split"}), do: nil
  defp tx_money(%{gross_amount: %Decimal{} = gross}), do: gross

  defp tx_money(%{quantity: %Decimal{} = quantity, price: %Decimal{} = price}),
    do: Decimal.mult(quantity, price)

  defp tx_money(_transaction), do: nil

  # Signed as the cash account sees it: what leaves the account is negative,
  # what arrives is positive. A balance snapshot is a level, not a flow, and
  # keeps its stored sign.
  defp signed_money(type, %Decimal{} = amount) when type in @outflow_kinds,
    do: PortfolixirWeb.Format.money(Decimal.negate(amount))

  defp signed_money(_type, %Decimal{} = amount), do: PortfolixirWeb.Format.money(amount)

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

  # E25 S6 (G07), pick G12.3 = A (board 12): a booked split in the drawer.
  # A split is a fact about the security, booked through "Record split"
  # (`Splits.book_split/2`); its type, effective date, security and ratio are
  # shown with that flow's words, disabled, and only the note is a field. No
  # depot: the row has none. The help line states the limit where the
  # correction is tried, without a link, because no screen deletes a booking
  # yet (UX-DR26; DESIGN.md, "The booking drawer's split state").
  attr(:split, Transaction, required: true)
  attr(:securities, :list, required: true)
  attr(:form_errors, :map, required: true)

  defp split_drawer(assigns) do
    assigns =
      assign(
        assigns,
        :security,
        Enum.find(assigns.securities, &(&1.id == assigns.split.security_id))
      )

    ~H"""
    <dialog
      id="booking-drawer"
      class="detail-pane booking-drawer"
      phx-hook="ModalDialog"
      data-close-event="close_booking"
      data-sheet-below="720"
      aria-labelledby="booking-drawer-title"
    >
      <header class="detail-pane-head">
        <div class="detail-pane-head__title">
          <div>
            <h2 id="booking-drawer-title"><%= gettext("Edit transaction") %></h2>
            <p class="detail-pane-sub">
              <%= gettext(
                "A split is a fact about the security; only the note changes here, and the change is journaled."
              ) %>
            </p>
          </div>
        </div>
        <div class="detail-pane-head__actions">
          <button
            type="button"
            class="icon-button"
            aria-label={gettext("Close")}
            phx-click="close_booking"
          >
            <AppShell.icon name={:x} />
          </button>
        </div>
      </header>
      <form id="split-note-form" phx-submit="save_split_note">
        <div id="split-facts" class="form-grid">
          <label>
            <span><%= gettext("Type") %></span>
            <select name="split[type]" disabled>
              <option value="split" selected><%= tx_type_label("split") %></option>
            </select>
          </label>
          <label>
            <span><%= gettext("Effective date") %></span>
            <input type="text" name="split[date]" value={Date.to_iso8601(@split.date)} disabled />
          </label>
          <label>
            <span><%= gettext("Security") %></span>
            <select name="split[security_id]" disabled>
              <option value={@split.security_id} selected>
                <%= if @security, do: security_option_label(@security), else: "—" %>
              </option>
            </select>
          </label>
          <label>
            <span><%= gettext("Ratio (new:old shares)") %></span>
            <input type="text" name="split[ratio]" value={split_ratio_label(@split)} disabled />
          </label>
        </div>
        <p id="split-edit-help" class="form-help">
          <%= gettext(
            "The effective date, ratio and security of a booked split are fixed. A wrong split cannot be corrected here; it is deleted over the API or MCP and then recorded again on the security with “Record split”."
          ) %>
        </p>
        <label>
          <span><%= gettext("Notes") %></span>
          <textarea
            name="split[notes]"
            aria-invalid={@form_errors["notes"] && "true"}
            aria-describedby={@form_errors["notes"] && "tx-error-notes"}
          ><%= @split.notes %></textarea>
          <.field_error errors={@form_errors} field="notes" />
        </label>
        <div class="booking-drawer__foot">
          <button type="submit" class="button-primary"><%= gettext("Save note") %></button>
          <button type="button" id="booking-cancel" class="button-ghost" phx-click="close_booking">
            <%= gettext("Cancel") %>
          </button>
        </div>
      </form>
    </dialog>
    """
  end

  defp security_option_label(%{ticker_symbol: ticker} = security) when ticker in [nil, ""],
    do: security.name

  defp security_option_label(security), do: "#{security.name} (#{security.ticker_symbol})"

  # The booking drawer (#803, review C6 pick C): the securities detail pane's
  # shape — an elevated panel headed by its title with a close control — as a
  # native dialog the ModalDialog hook opens beside the history on the desktop
  # and as a bottom sheet under 720 px (`data-sheet-below`). Built for creating
  # a booking; shaped as one panel of stacked, pre-fillable fields so the edit
  # view (#809) can reuse it without a second form.
  attr(:transaction_form, :map, required: true)
  attr(:form_errors, :map, required: true)
  attr(:securities_accounts, :list, required: true)
  attr(:securities, :list, required: true)
  attr(:sell_preview, :any, required: true)
  attr(:editing?, :boolean, default: false)

  defp booking_drawer(assigns) do
    assigns =
      assign(
        assigns,
        :settlement_pair,
        SettlementForm.pair(
          assigns.transaction_form,
          assigns.securities_accounts,
          assigns.securities
        )
      )

    ~H"""
    <dialog
      id="booking-drawer"
      class="detail-pane booking-drawer"
      phx-hook="ModalDialog"
      data-close-event="close_booking"
      data-sheet-below="720"
      aria-labelledby="booking-drawer-title"
    >
      <header class="detail-pane-head">
        <div class="detail-pane-head__title">
          <div>
            <h2 id="booking-drawer-title">
              <%= if @editing?,
                do: gettext("Edit transaction"),
                else: gettext("Record transaction") %>
            </h2>
            <p class="detail-pane-sub">
              <%= if @editing?,
                do:
                  gettext(
                    "Corrects the booking in place; the derived holdings follow and the change is journaled."
                  ),
                else:
                  gettext("Books against the chosen depot; the cash moves in its cash account's currency.") %>
            </p>
          </div>
        </div>
        <div class="detail-pane-head__actions">
          <button
            type="button"
            class="icon-button"
            aria-label={gettext("Close")}
            phx-click="close_booking"
          >
            <AppShell.icon name={:x} />
          </button>
        </div>
      </header>
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
            <%!-- Part 4 of the 2026-08-18 amendment: the depot select
                 says where a booking lands, and is labelled as such. --%>
            <span><%= gettext("Books to depot") %></span>
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
                    <%= security.name %><%= if security.ticker_symbol not in [nil, ""], do: " (#{security.ticker_symbol})" %>
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
              class="num"
              required
              aria-invalid={@form_errors["quantity"] && "true"}
              aria-describedby={@form_errors["quantity"] && "tx-error-quantity"}
            />
            <.field_error errors={@form_errors} field="quantity" />
          </label>
          <label>
            <span>
              <%= if @settlement_pair,
                do: gettext("Price (%{currency})", currency: @settlement_pair.security),
                else: gettext("Price") %>
            </span>
            <input
              name="transaction[price]"
              value={@transaction_form["price"]}
              inputmode="decimal"
              class="num"
              required
              aria-invalid={@form_errors["price"] && "true"}
              aria-describedby={@form_errors["price"] && "tx-error-price"}
            />
            <.field_error errors={@form_errors} field="price" />
          </label>
        </div>

        <input
          :if={@transaction_form["settlement_mode"]}
          type="hidden"
          name="transaction[settlement_mode]"
          value={@transaction_form["settlement_mode"]}
        />
        <%!-- The importer's form keeps its settlement; the cash amount of a
             corrected fee follows it (SettlementForm.prepare/2). --%>
        <input
          :if={@transaction_form["settlement_mode"] == "account"}
          type="hidden"
          name="transaction[settlement_amount]"
          value={@transaction_form["settlement_amount"]}
        />
        <SettlementForm.fieldset
          :if={@settlement_pair}
          pair={@settlement_pair}
          form={@transaction_form}
          errors={@form_errors}
        />

        <p class="form-help" data-role="derived-currency">
          <%= case {@settlement_pair, derived_currency(@securities_accounts, @transaction_form["securities_account_id"])} do %>
            <% {%{security: security, account: account}, _currency} -> %>
              <%= gettext("Price in %{security} · cash in %{account}",
                security: security,
                account: account
              ) %>
            <% {nil, nil} -> %>
              <%= gettext("Currency is set by the selected depot.") %>
            <% {nil, currency} -> %>
              <%= gettext("Currency: %{currency}", currency: currency) %>
          <% end %>
        </p>

        <%!-- A refused fee or tax opens the costs (#869): an error the reader
             cannot see is no answer. The hook keeps them open, by whoever
             opened them, across the patch each keystroke brings. --%>
        <details
          id="transaction-costs"
          class="transaction-costs"
          phx-hook="DisclosureState"
          open={(@form_errors["fees"] || @form_errors["taxes"]) && true}
        >
          <summary class="disclosure-summary">
            <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
            <%= gettext("Costs and note") %>
          </summary>
          <div class="form-grid">
            <label>
              <span><%= gettext("Fees") %></span>
              <input
                name="transaction[fees]"
                value={@transaction_form["fees"]}
                inputmode="decimal"
                class="num"
                aria-invalid={@form_errors["fees"] && "true"}
                aria-describedby={@form_errors["fees"] && "tx-error-fees"}
              />
              <.field_error errors={@form_errors} field="fees" />
            </label>
            <label>
              <span><%= gettext("Taxes") %></span>
              <input
                name="transaction[taxes]"
                value={@transaction_form["taxes"]}
                inputmode="decimal"
                class="num"
                aria-invalid={@form_errors["taxes"] && "true"}
                aria-describedby={@form_errors["taxes"] && "tx-error-taxes"}
              />
              <.field_error errors={@form_errors} field="taxes" />
            </label>
          </div>
        <label>
          <span><%= gettext("Notes") %></span>
          <textarea name="transaction[notes]"><%= @transaction_form["notes"] %></textarea>
        </label>
        </details>

        <div class="booking-drawer__foot">
          <button type="submit" class="button-primary">
            <%= if @editing?, do: gettext("Save changes"), else: gettext("Record transaction") %>
          </button>
          <button type="button" id="booking-cancel" class="button-ghost" phx-click="close_booking">
            <%= gettext("Cancel") %>
          </button>
        </div>
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
        <details class="metric-tooltip metric-tooltip--inline metric-tooltip--labelled" data-role="gross-gain-info">
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
        <div class="data-table-wrapper">
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
        </div>
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
    </dialog>
    """
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
