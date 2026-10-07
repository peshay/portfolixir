defmodule PortfolixirWeb.TransactionManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.Text
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ChangedSince
  alias PortfolixirWeb.ColumnPicker
  alias PortfolixirWeb.DecimalInput
  alias PortfolixirWeb.FieldLabel
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.SecurityNames
  alias PortfolixirWeb.TransactionKindLabel
  alias PortfolixirWeb.Transactions.BookingDeleteDialog
  alias PortfolixirWeb.Transactions.SettlementForm

  # Two chip families (#707 D2, Part 4) plus the conditions the "More filters"
  # disclosure holds. Chips within a family compose as OR -- two accounts means
  # "either of these" -- and the families compose as AND with each other and
  # with the disclosure.
  @chip_families ["types", "account_ids"]

  # #732: the pickable columns — the human half of the API's `fields=` sparse
  # fieldset (FR-37). Keys follow the serializers' field names where a field
  # exists there; `security` and `account` are the human joins over the id
  # fields — `account` over `cash_account_id` (and a transfer's
  # `counter_cash_account_id`), else `securities_account_id` (#1084).
  # The running-balance column is deliberately NOT here: it stays governed by
  # its own rule (exactly one account narrowed), because a picker that can
  # summon it outside that narrowing would fake a meaningless balance.
  # The amount rides in the defaults (#786): a dividend row shows what was
  # paid, not only its quantity. The currency is the amount's suffix, so its
  # own column stays in the picker rather than in the defaults. The account
  # rides in them too (#1084, pick J3.2 A): the amount beside it is that
  # account's view, and a cash booking names nothing else.
  @tx_column_defaults [
    "date",
    "type",
    "security",
    "account",
    "quantity",
    "price",
    "gross_amount"
  ]
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
     |> assign(:editing_fixed, nil)
     |> assign(:deleting, nil)
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
      page_subtitle={gettext("Every booking across accounts and depots")}
    >
      <div id="transactions-workspace" class="workspace-page">
        <AppShell.area_tabs tabs={AppShell.transactions_tabs(:history)} />

        <%= if @error do %>
          <p class="alert-error" role="alert" data-role="page-result"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status" data-role="page-result"><%= @success %></p>
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
            <%!-- U1 (#912): where the focus goes when the delete dialog
                 closes — its opener, the row menu, is gone by then, and
                 after a delete the row is too (WCAG 2.4.3). --%>
            <h2 id="transaction-history-heading" tabindex="-1"><%= gettext("Transaction history") %></h2>
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
                      <th :if={@balance_account} class="num col-subject">
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
                          <%!-- #1083 (pick J3 A): the count alone. The sums
                                per kind and currency are the summary's,
                                above, under their basis line. --%>
                          <span class="tx-group-month"><%= group.label %></span>
                          <span class="tx-group-subtotal">
                            <%= ngettext("%{count} transaction", "%{count} transactions", group.count,
                              count: group.count) %>
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
                                        finding 7), in the column's `.num`
                                        alignment (#913). --%>
                                  <td class="num" data-role="split-ratio">
                                    <%= split_ratio_label(transaction) %>
                                  </td>
                                <% else %>
                                  <td class="num"><%= format_quantity(transaction.quantity) %></td>
                                <% end %>
                              <% "price" -> %>
                                <%!-- #1073: the price with the digits it was
                                      stored with (R10c), as the notes drawer
                                      shows it. --%>
                                <%= if transaction.type == "split" do %>
                                  <td class="num" data-role="price">—</td>
                                <% else %>
                                  <td class="num" data-role="price"><%= stored_figure(transaction.price) %></td>
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
                                      <%= signed_money(transaction, amount, @filters["account_ids"]) %><small class="value-suffix"><%= money_currency(transaction) %></small>
                                    </td>
                                <% end %>
                              <% "account" -> %>
                                <%!-- #1084 (pick J3.2 A): the account the
                                      amount moved through, each stored name
                                      in its own <bdi> (H8.8). A name that
                                      wraps (U1 review). --%>
                                <td class="cell-name" data-role="account"><.arrow_names names={tx_accounts(transaction, @account_names)} /></td>
                              <% _other -> %>
                                <td {cell_attrs(key)}><%= tx_cell(transaction, key) %></td>
                            <% end %>
                          <% end %>
                          <td :if={@balance_account} class="num col-subject" data-role="running-balance">
                            <%!-- Absent, never repeated: a row that does not
                                  move this account carries no balance, because
                                  the previous row's figure would read as
                                  "nothing happened here". --%>
                            <%= running_balance(@running_balances, transaction) %>
                          </td>
                          <td class="row-actions">
                            <.row_kebab id={"tx-kebab-#{transaction.id}"} transaction={transaction} open?={@row_menu_id == transaction.id} twin_tags={@twin_tags} />
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
                        count: group.count) %>
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
                      <%!-- The Konto cell's names where the booking has no
                            security: a transfer names both of its accounts
                            (U1 review), one span so they flow as one line. --%>
                      <span :if={phone_subject(transaction, @account_names) != []} class="phone-row__ids">
                        <span><.arrow_names names={phone_subject(transaction, @account_names)} /></span>
                      </span>
                    </span>
                    <span class="phone-row__figures">
                      <span class="phone-row__figure"><%= phone_amount(transaction, @filters["account_ids"]) %></span>
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
                      twin_tags={@twin_tags}
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
          <%!-- U1 (#912), pick H2-A: Edit, then Delete… last, in the
               danger colour, on every row of every kind; the ellipsis says
               a dialog follows. Under 720 px the sheet names its row. --%>
          <AppShell.row_menu
            :if={open_menu_transaction}
            id={"tx-row-menu-#{open_menu_transaction.id}"}
            trigger={"tx-kebab-#{open_menu_transaction.id}"}
            label={gettext("Transaction actions")}
            caption_name={row_name(open_menu_transaction, @twin_tags)}
            caption_kind={gettext("Transaction")}
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
            <button
              type="button"
              id={"tx-delete-#{open_menu_transaction.id}"}
              class="row-context-menu__item row-context-menu__item--danger"
              role="menuitem"
              phx-click="ask_delete"
              phx-value-id={open_menu_transaction.id}
            >
              <AppShell.icon name={:trash} />
              <%= gettext("Delete…") %>
            </button>
          </AppShell.row_menu>
        </section>
        <%!-- U1 (#912), the closing act R3: an Edit drawer opened from a
             row's menu returns the focus to that row's kebab on every exit,
             the heading only when the row is gone (WCAG 2.4.3). --%>
        <.notes_drawer
          :if={@booking_open? and @editing_fixed != nil}
          focus_return={row_kebabs(@editing_id)}
          transaction={@editing_fixed}
          securities={@securities}
          cash_accounts={@cash_accounts}
          securities_accounts={@securities_accounts}
          form_errors={@form_errors}
        />
        <.booking_drawer
          :if={@booking_open? and @editing_fixed == nil}
          focus_return={row_kebabs(@editing_id)}
          editing?={@editing_id != nil}
          transaction_form={@transaction_form}
          form_errors={@form_errors}
          securities_accounts={@securities_accounts}
          securities={@securities}
          sell_preview={@sell_preview}
        />
        </div>
        <BookingDeleteDialog.dialog
          :if={@deleting}
          deleting={@deleting}
          focus_fallback="#transaction-history-heading"
          focus_return={row_kebabs(@deleting.opened_from)}
          focus_result="[data-role='page-result']"
        />
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

  # U1 (#912), H2b-A: the notes-only drawer has no booking form, so a
  # booking save pushed at it changes nothing.
  def handle_event(
        "save_transaction",
        _params,
        %{assigns: %{editing_fixed: %Transaction{}}} = socket
      ),
      do: {:noreply, socket}

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
     |> assign(:editing_fixed, nil)
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
       # E25 S6 (G07, pick G12.3 = A), generalised by U1 (#912, pick
       # H2b = A): every kind the drawer does not book — all but buy and
       # sell — opens the notes-only state, the facts fixed and only the
       # note editable.
       |> assign(:editing_fixed, fixed_booking(transaction, socket.assigns.transactions))
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

  # E25 S6 (G07), U1 (#912, H2b-A): the notes-only drawer's one write, the
  # note. Nothing else is sent: the drawer books no other field.
  def handle_event("save_note", %{"note" => %{"notes" => notes}}, socket)
      when is_binary(notes) do
    case socket.assigns.editing_fixed do
      %Transaction{id: id} -> save_note(socket, id, notes)
      nil -> {:noreply, socket}
    end
  end

  # U1 (#912), pick H2-A: "Delete…" from a row's menu, or from the
  # notes-only drawer's help line (A7), which closes the drawer first — no
  # dialog opens from a dialog (UX-DR9). The dialog is built from the row as
  # it is stored now, as Edit reads it (the closing act, R6); a row gone
  # since is said so at once (A6).
  def handle_event("ask_delete", %{"id" => id_str}, socket) do
    socket =
      socket
      |> assign(:row_menu_id, nil)
      |> close_drawer()

    with {:ok, id} <- LiveParam.fetch_id(id_str),
         %Transaction{} = transaction <- stored_row(id, socket.assigns),
         %{} = deleting <- BookingDeleteDialog.prepare(transaction, delete_context(socket)) do
      {:noreply, assign(socket, :deleting, deleting)}
    else
      _gone -> {:noreply, socket |> failure(gone_message()) |> load_state()}
    end
  end

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, :deleting, nil)}

  # The one confirmation (EXPERIENCE.md: a destructive action confirms once).
  # Only the dialog's own booking is deleted: a stale confirm changes nothing.
  def handle_event("confirm_delete", %{"id" => id_str}, socket) do
    with %{id: id} = deleting <- socket.assigns.deleting,
         {:ok, ^id} <- LiveParam.fetch_id(id_str) do
      socket = assign(socket, :deleting, nil)

      case BookingDeleteDialog.delete(Actor.owner_ui(), deleting) do
        {:ok, message} -> {:noreply, socket |> success(message) |> load_state()}
        {:changed, fresh} -> {:noreply, socket |> assign(:deleting, fresh) |> load_state()}
        :gone -> {:noreply, socket |> failure(gone_message()) |> load_state()}
      end
    else
      _stale -> {:noreply, socket}
    end
  end

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp save_note(socket, id, notes) do
    case book(id, %{"notes" => notes}) do
      {:ok, _transaction} ->
        {:noreply,
         socket
         |> close_drawer()
         |> success(gettext("Note saved"))
         |> load_state()}

      # The drawer keeps what was typed (E25 S6 review round, R4): a refusal
      # names what to correct, never what to type again (board 11's rule).
      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:editing_fixed, %{socket.assigns.editing_fixed | notes: notes})
         |> assign(:form_errors, field_errors(changeset))
         |> failure(changeset_error(changeset))}

      :gone ->
        {:noreply,
         socket
         |> close_drawer()
         |> failure(gone_message())
         |> load_state()}
    end
  end

  defp close_drawer(socket) do
    socket
    |> assign(:transaction_form, @transaction_form)
    |> assign(:form_errors, %{})
    |> assign(:sell_preview, nil)
    |> assign(:booking_open?, false)
    |> assign(:editing_id, nil)
    |> assign(:editing_fixed, nil)
  end

  defp gone_message, do: gettext("That transaction no longer exists.")

  # The kinds the drawer books are buy and sell (AGENTS.md goal 4); every
  # other row opens notes-only: the row as stored now (its note current),
  # with the security the history loaded for it, which may be one the
  # booking form does not offer (a benchmark).
  defp fixed_booking(%Transaction{type: type}, _loaded)
       when type in ["buy", "sell"],
       do: nil

  defp fixed_booking(%Transaction{} = transaction, loaded) do
    case Enum.find(loaded, &(&1.id == transaction.id)) do
      %Transaction{security_id: id, security: security} when id == transaction.security_id ->
        %{transaction | security: security}

      _not_loaded ->
        transaction
    end
  end

  # The row as stored now (R6), with the accounts and the security the
  # history names it by — an account from the page's lists carries its
  # currency, the security a loaded row of it — so the dialog says the row
  # back in the list's words. `nil` when it is gone.
  defp stored_row(id, assigns) do
    case Ledger.get_transaction(id) do
      nil ->
        nil

      %Transaction{} = row ->
        %{
          row
          | cash_account: Enum.find(assigns.cash_accounts, &(&1.id == row.cash_account_id)),
            securities_account:
              Enum.find(assigns.securities_accounts, &(&1.id == row.securities_account_id)),
            security: loaded_security(row.security_id, assigns.transactions)
        }
    end
  end

  defp loaded_security(nil, _loaded), do: nil

  defp loaded_security(id, loaded) do
    Enum.find_value(loaded, fn
      %Transaction{security: %{id: ^id} = security} -> security
      _other -> nil
    end) || Catalog.get_security(id)
  end

  # The row's two kebabs, the table's and the phone row's; the hook takes
  # the one that is visible at this width.
  defp row_kebabs(nil), do: nil
  defp row_kebabs(id), do: "#tx-kebab-#{id}, #tx-phone-kebab-#{id}"

  # `account_ids`: the chips in view, so the box signs a transfer as its row
  # does (board 03, found while drawing, item 1).
  defp delete_context(socket) do
    %{
      account_ids: socket.assigns.filters["account_ids"],
      cash_accounts: socket.assigns.cash_accounts,
      securities_accounts: socket.assigns.securities_accounts,
      transactions: socket.assigns.transactions,
      twin_tags: socket.assigns.twin_tags
    }
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
         |> assign(:editing_fixed, nil)
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
         |> failure(gone_message())
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
      # The Konto column names a transfer's receiving account or depot from
      # here: the rows preload only the sending one (#1084, U1 review).
      account_names: %{
        cash: Map.new(cash_accounts, &{&1.id, &1.name}),
        depots: Map.new(securities_accounts, &{&1.id, &1.name})
      },
      securities: securities,
      transactions: transactions,
      twin_tags: twin_tags(transactions)
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

  # #809: the row's kebab, on the table row and on the phone row. The menu
  # itself is rendered once at the page level so its popover is never clipped
  # by the table scroller.
  attr(:id, :string, required: true)
  attr(:transaction, :map, required: true)
  attr(:open?, :boolean, required: true)
  attr(:twin_tags, :map, default: %{})

  # #870: named for its row through the shared trigger, the booking composed
  # from its kind, its subject and its date — a twin security's subject with
  # its ISIN (the closing act, UAT-13), so two twins' bookings of one day
  # never share a name.
  defp row_kebab(assigns) do
    ~H"""
    <AppShell.row_kebab
      id={@id}
      row={row_name(@transaction, @twin_tags)}
      open={@open?}
      phx-click="open_row_menu"
      phx-value-id={@transaction.id}
    />
    """
  end

  defp row_name(transaction, twin_tags) do
    AppShell.row_name([
      tx_type_label(transaction.type),
      kebab_subject(transaction, twin_tags),
      PortfolixirWeb.Format.date(transaction.date)
    ])
  end

  defp kebab_subject(%{security: %{name: name} = security}, twin_tags) when is_binary(name),
    do: SecurityNames.label(twin_tags, security)

  defp kebab_subject(transaction, _twin_tags),
    do: account_name(transaction.cash_account) || account_name(transaction.securities_account)

  defp twin_tags(transactions) do
    transactions
    |> Enum.flat_map(fn
      %{security: %{id: _, name: name} = security} when is_binary(name) -> [security]
      _other -> []
    end)
    |> SecurityNames.tags()
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

  # Section the (already date-desc) history into month chunks (#414
  # follow-up). chunk_by works because the list is pre-sorted, so consecutive
  # same-month rows are adjacent and order is preserved. A head carries its
  # month's count and no sum (#1083, pick J3 A): an unsigned sum across kinds
  # is neither a cash flow nor a turnover, and the summary above already
  # states the sums per kind and currency under its basis line.
  defp grouped_by_month(transactions) do
    transactions
    |> Enum.chunk_by(fn tx -> {tx.date.year, tx.date.month} end)
    |> Enum.map(fn chunk ->
      first = hd(chunk)

      %{
        id: month_group_id(first.date),
        label: month_group_label(first.date),
        transactions: chunk,
        count: length(chunk)
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
      {gettext("Booking"), ~w(date type security account)},
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
  # The chips' word for the same accounts (#1084): a booking the chip
  # "Demo Cash" selects reads "Demo Cash" in this column.
  defp tx_column_label("account"), do: gettext("Account")
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

  # The Konto column's names (#1084, pick J3.2 A): the cash account the
  # amount moved through — the account whose view the Betrag is — both of a
  # cash transfer's, sender first; both depots of a security transfer, the
  # sending one first, as the delete dialog's box names them (U1 review);
  # without a cash account the depot (a delivery); a split names none.
  # `phone_subject/2`'s order without the security, so the phone row stays
  # the table condensed (UX-DR27). A receiving account or depot the page's
  # lists do not carry is left out rather than named by id.
  defp tx_accounts(%{type: "cash_transfer"} = transaction, names) do
    [
      account_name(transaction.cash_account),
      Map.get(names.cash, transaction.counter_cash_account_id)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp tx_accounts(%{type: "security_transfer"} = transaction, names) do
    [
      account_name(transaction.securities_account),
      Map.get(names.depots, transaction.counter_securities_account_id)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp tx_accounts(transaction, _names) do
    case account_name(transaction.cash_account) ||
           account_name(transaction.securities_account) do
      nil -> []
      name -> [name]
    end
  end

  defp account_name(%{name: name}) when is_binary(name), do: name
  defp account_name(_not_loaded_or_nil), do: nil

  # Stored names joined by the app's arrow, each in its own <bdi> (H8.8) and
  # the " → " outside them: the Konto cell and the phone row's subject.
  attr(:names, :list, required: true)

  defp arrow_names(assigns) do
    ~H"""
    <%= for {name, index} <- Enum.with_index(@names) do %><%= if index > 0, do: " → " %><bdi><%= name %></bdi><% end %>
    """
  end

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

  # A body cell's class (U1 review): the history is a reading table that
  # fits its wrapper, so the names wrap (`.cell-name`), the date and the kind
  # stay on one line, and a figure is `.num`, which never wraps.
  defp cell_attrs("date"), do: %{class: "cell-date"}
  defp cell_attrs("type"), do: %{class: "cell-kind"}
  defp cell_attrs("security"), do: %{class: "cell-name"}
  defp cell_attrs(key), do: num_attrs(key)

  # The quantity in its own scale under the locale's separators (#786):
  # "0,05", "30", "1.000" — never the stored twelve-place scale.
  defp format_quantity(nil), do: ""

  defp format_quantity(%Decimal{} = quantity) do
    normalized = Decimal.normalize(quantity)
    places = normalized.exp |> Kernel.-() |> max(0) |> min(8)
    PortfolixirWeb.Format.decimal(normalized, places)
  end

  # A cash transfer is not here: its sign is the account in view's
  # (`signed_money/3`).
  @outflow_kinds ~w(buy removal fee tax)

  # The phone row's lines (#799): the subject the booking touched, the money
  # as the cash account sees it with its currency, and the size — quantity ×
  # price, the quantity alone, a split's ratio — where the booking has one.
  # The subject is the security, else the Konto cell's names: a cash
  # transfer names both of its accounts, sender first, so a row that reads
  # as arriving in the receiver's view still says where the money came from
  # (U1 review).
  defp phone_subject(%{security: %{name: name}}, _names) when is_binary(name), do: [name]
  defp phone_subject(transaction, names), do: tx_accounts(transaction, names)

  @doc """
  The booking's money as the history's phone row shows it — signed as the
  cash account sees it, with its currency — or "—" (#799). The delete
  dialog names a booking with it (U1, #912). `account_ids` are the account
  chips in view: a cash transfer reads from its receiving side when they
  select that account and not its sender (board 03, found while drawing).
  """
  def phone_amount(transaction, account_ids \\ []) do
    case tx_money(transaction) do
      nil ->
        "—"

      amount ->
        signed_money(transaction, amount, account_ids) <> " " <> money_currency(transaction)
    end
  end

  @doc """
  The booking's size as the history's phone row shows it — quantity × price,
  the quantity alone, a split's ratio — or `nil` (#799); the delete dialog's
  second figure (U1, #912). The price keeps its stored digits, as the Price
  column does (#1073).
  """
  def phone_size(%{type: "split"} = transaction), do: split_ratio_label(transaction)

  def phone_size(%{quantity: %Decimal{} = quantity, price: %Decimal{} = price}),
    do: "#{format_quantity(quantity)} × #{stored_figure(price)}"

  def phone_size(%{quantity: %Decimal{} = quantity}),
    do:
      ngettext("%{quantity} unit", "%{quantity} units", plural_count(quantity),
        quantity: format_quantity(quantity)
      )

  def phone_size(_transaction), do: nil

  @doc """
  The count a quantity's plural follows: one unit is a unit, any other
  quantity — a fraction included — is units (U1 closing act, R10b).
  """
  def plural_count(%Decimal{} = quantity),
    do: if(Decimal.equal?(quantity, 1), do: 1, else: 2)

  # The booking's money on the same basis as the summary's sums (the stored
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
  # keeps its stored sign. A cash transfer has two accounts, and the sign is
  # the one in view's (board 03, found while drawing, item 1): with the
  # account chips selecting its receiving account and not its sender, the
  # money arrives — as the running balance beside it says. Otherwise, the
  # sender first as the Konto cell names it, it leaves.
  defp signed_money(%{type: "cash_transfer"} = transaction, %Decimal{} = amount, account_ids) do
    if receiving_view?(transaction, account_ids),
      do: PortfolixirWeb.Format.money(amount),
      else: PortfolixirWeb.Format.money(Decimal.negate(amount))
  end

  defp signed_money(%{type: type}, %Decimal{} = amount, _account_ids)
       when type in @outflow_kinds,
       do: PortfolixirWeb.Format.money(Decimal.negate(amount))

  defp signed_money(_transaction, %Decimal{} = amount, _account_ids),
    do: PortfolixirWeb.Format.money(amount)

  defp receiving_view?(transaction, account_ids) do
    to_string(transaction.counter_cash_account_id) in account_ids and
      to_string(transaction.cash_account_id) not in account_ids
  end

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
    |> Ecto.Changeset.traverse_errors(&FieldLabel.translate_error/1)
    |> Map.new(fn {field, messages} -> {to_string(field), Enum.join(messages, ", ")} end)
  end

  # The notes-only drawer: E25 S6 (G07), pick G12.3 = A (board 12) for a
  # booked split, generalised by U1 (#912, pick H2b = A, board
  # `ux-design-2026-10-02/02-booking-delete`) to every kind the drawer does
  # not book — all but buy and sell. The booking's facts are shown with the
  # words the history and the drawer already use, disabled, the fields
  # following the kind (a dividend its security, cash account, amount and
  # taxes; a transfer both accounts; a delivery its depot, quantity and
  # price); only the note is a field. The help line states the limit where
  # the correction is tried and carries its remedy, "Delete…" (UX-DR26;
  # DESIGN.md, "The booking drawer's split state" and "Deleting a booking").
  attr(:transaction, Transaction, required: true)
  attr(:securities, :list, required: true)
  attr(:cash_accounts, :list, required: true)
  attr(:securities_accounts, :list, required: true)
  attr(:form_errors, :map, required: true)
  attr(:focus_return, :string, default: nil)

  defp notes_drawer(assigns) do
    assigns =
      assign(assigns,
        facts: booking_facts(assigns.transaction, assigns),
        kind: assigns.transaction.type
      )

    ~H"""
    <dialog
      id="booking-drawer"
      class="detail-pane booking-drawer"
      phx-hook="ModalDialog"
      data-close-event="close_booking"
      data-sheet-below="720"
      data-focus-return={@focus_return}
      data-focus-fallback="#transaction-history-heading"
      data-focus-result="[data-role='page-result']"
      aria-labelledby="booking-drawer-title"
    >
      <header class="detail-pane-head">
        <div class="detail-pane-head__title">
          <div>
            <h2 id="booking-drawer-title"><%= gettext("Edit transaction") %></h2>
            <p class="detail-pane-sub"><%= notes_drawer_sub(@kind) %></p>
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
      <form id="note-form" phx-submit="save_note">
        <div id="booking-facts" class="form-grid">
          <label :for={fact <- @facts}>
            <span><%= fact.label %></span>
            <%= if fact.control == :select do %>
              <select name={"note[#{fact.field}]"} disabled>
                <option selected><%= fact.value %></option>
              </select>
            <% else %>
              <input
                type="text"
                name={"note[#{fact.field}]"}
                value={fact.value}
                class={fact.num? && "num"}
                disabled
              />
            <% end %>
          </label>
        </div>
        <p id="booking-edit-help" class="form-help">
          <%= notes_drawer_help(@transaction) %>
          <button
            type="button"
            class="link-button"
            phx-click="ask_delete"
            phx-value-id={@transaction.id}
          >
            <%= if @kind == "split", do: gettext("Delete split…"), else: gettext("Delete…") %>
          </button>
        </p>
        <%!-- G12.2-B in the notes-only state: a note stored before invisible
             characters were refused is marked above the field that holds
             it — this drawer has no "Costs and note" disclosure, its Notes
             field stands open (the closing act, DC-9). --%>
        <AppShell.invisible_text_note texts={[@transaction.notes]}>
          <%= gettext("Typed in anew, it is clean.") %>
        </AppShell.invisible_text_note>
        <label>
          <span><%= gettext("Notes") %></span>
          <textarea
            name="note[notes]"
            aria-invalid={@form_errors["notes"] && "true"}
            aria-describedby={@form_errors["notes"] && "tx-error-notes"}
          ><%= @transaction.notes %></textarea>
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

  # The closing act, R10a and R10d: the kind named as a kind, never with an
  # article that fits no label ("a “Interest”"), and the journal named in
  # plain words, never "journaled".
  defp notes_drawer_sub("split"),
    do:
      gettext(
        "A split is a fact about the security; only the note changes here, and the journal records the change."
      )

  defp notes_drawer_sub("balance_adjustment"),
    do:
      gettext(
        "A balance is set under Accounts & depots; only the note changes here, and the journal records the change."
      )

  defp notes_drawer_sub(kind),
    do:
      gettext(
        "The screen does not book the kind “%{kind}”; only the note changes here, and the journal records the change.",
        kind: tx_type_label(kind)
      )

  defp notes_drawer_help(%Transaction{type: "split"}),
    do:
      gettext(
        "The effective date, ratio and security of a booked split are fixed. A wrong split is deleted and then recorded again on the security with “Record split”."
      )

  defp notes_drawer_help(%Transaction{type: "balance_adjustment"}),
    do:
      gettext(
        "The date, balance and account of a set balance are fixed here. It is corrected over the API or MCP, or it is deleted and set again under Accounts & depots."
      )

  # The way back through the import exists only for a booking an import
  # brought in; any other came over the API or MCP, and is booked again
  # there (the closing act, R10e).
  defp notes_drawer_help(%Transaction{import_hash: hash}) when is_binary(hash),
    do:
      gettext(
        "The date, amounts and accounts of this booking are fixed here; the screen books only buys and sells. The booking is corrected over the API or MCP, or it is deleted and imported again."
      )

  defp notes_drawer_help(%Transaction{}),
    do:
      gettext(
        "The date, amounts and accounts of this booking are fixed here; the screen books only buys and sells. The booking is corrected over the API or MCP, or it is deleted and booked again there."
      )

  # The facts a kind stores, in the drawer's order: type and date, then the
  # security, the accounts and the figures the kind carries (the per-kind
  # required fields of `Transaction`), each as the disabled control the
  # booking form uses for it.
  defp booking_facts(%Transaction{} = tx, assigns) do
    cash = &account_label(&1, assigns.cash_accounts)
    depot = &account_label(&1, assigns.securities_accounts)

    [
      fact(gettext("Type"), "type", :select, tx_type_label(tx.type)),
      fact(date_label(tx.type), "date", :input, Date.to_iso8601(tx.date))
    ] ++
      security_fact(tx, assigns.securities) ++
      kind_facts(tx, cash, depot)
  end

  defp date_label("split"), do: gettext("Effective date")
  defp date_label(_kind), do: gettext("Date")

  defp security_fact(%Transaction{security_id: nil}, _securities), do: []

  defp security_fact(%Transaction{} = tx, securities) do
    security =
      case tx.security do
        %{name: _} = loaded -> loaded
        _not_loaded -> Enum.find(securities, &(&1.id == tx.security_id))
      end

    label = if security, do: security_option_label(security), else: "—"
    [fact(gettext("Security"), "security_id", :select, label)]
  end

  defp kind_facts(%Transaction{type: "split"} = tx, _cash, _depot),
    do: [fact(gettext("Ratio (new:old shares)"), "ratio", :input, split_ratio_label(tx))]

  defp kind_facts(%Transaction{type: "cash_transfer"} = tx, cash, _depot) do
    [
      fact(gettext("From account"), "cash_account_id", :select, cash.(tx.cash_account_id)),
      fact(
        gettext("To account"),
        "counter_cash_account_id",
        :select,
        cash.(tx.counter_cash_account_id)
      ),
      amount_fact(gettext("Amount (%{currency})", currency: tx.currency_code), tx.gross_amount)
    ]
  end

  defp kind_facts(%Transaction{type: "balance_adjustment"} = tx, cash, _depot) do
    [
      fact(gettext("Cash account"), "cash_account_id", :select, cash.(tx.cash_account_id)),
      amount_fact(gettext("Balance (%{currency})", currency: tx.currency_code), tx.gross_amount)
    ]
  end

  defp kind_facts(%Transaction{type: type} = tx, _cash, depot)
       when type in ["inbound_delivery", "outbound_delivery"] do
    [
      fact(gettext("Depot"), "securities_account_id", :select, depot.(tx.securities_account_id)),
      quantity_fact(tx.quantity)
    ] ++ if(tx.price, do: [amount_fact(gettext("Price"), tx.price, "price")], else: [])
  end

  defp kind_facts(%Transaction{type: "security_transfer"} = tx, _cash, depot) do
    [
      fact(
        gettext("From depot"),
        "securities_account_id",
        :select,
        depot.(tx.securities_account_id)
      ),
      fact(
        gettext("To depot"),
        "counter_securities_account_id",
        :select,
        depot.(tx.counter_securities_account_id)
      ),
      quantity_fact(tx.quantity)
    ]
  end

  # The cash kinds: dividend, interest, deposit, removal, fee, tax and tax
  # refund — the account and the amount, and the taxes a dividend or
  # interest withheld.
  defp kind_facts(%Transaction{} = tx, cash, _depot) do
    [
      fact(gettext("Cash account"), "cash_account_id", :select, cash.(tx.cash_account_id)),
      amount_fact(gettext("Amount (%{currency})", currency: tx.currency_code), tx.gross_amount)
    ] ++
      if(tx.type in ["dividend", "interest"],
        do: [amount_fact(gettext("Taxes"), tx.taxes, "taxes")],
        else: []
      )
  end

  defp fact(label, field, control, value),
    do: %{label: label, field: field, control: control, value: value, num?: false}

  defp amount_fact(label, value, field \\ "gross_amount"),
    do: %{fact(label, field, :input, stored_figure(value)) | num?: true}

  @doc """
  A stored figure with the digits it was stored with, up to four decimal
  places — trailing zeros trimmed, at least two places — never rounded to
  two (the closing act, R10c): a price of 41.1234 reads 41.1234, an amount
  of 1500 1,500.00. *Amended 2026-10-07 (the γ closing act, edge-case
  hunter #2):* at most four places, so a price the PP JSON importer derived
  as amount ÷ shares at the column's scale 6 reads 72.6212, not 72.621176.

  *Amended again 2026-10-07 (the closing act's cascade, layer 2):* a figure
  under 1 keeps at least three significant digits — its stored digits up to
  two places past its first non-zero one, never fewer than four — so a
  stored 0.000045 reads 0.000045, not "0.0000", and 0.001234 reads
  0.00123. No non-zero figure prints as zero.

  The notes drawer's facts, the history's Price column, the phone row's size
  and the security's Transaktionen tab read it (#1073). Decimal throughout:
  the scale comes from the normalized value, and only a place past the
  cap is rounded.
  """
  def stored_figure(%Decimal{} = value) do
    %Decimal{coef: coef, exp: exp} = Decimal.normalize(value)
    stored = max(-exp, 0)

    # The first non-zero decimal place of a figure under 1 (5 for 0.000045),
    # else 0: the cap reaches two places past it.
    first =
      if coef != 0 and Decimal.lt?(Decimal.abs(value), 1),
        do: -(exp + length(Integer.digits(coef))) + 1,
        else: 0

    PortfolixirWeb.Format.decimal(value, max(2, min(stored, max(4, first + 2))))
  end

  def stored_figure(value), do: PortfolixirWeb.Format.decimal(value, 2)

  defp quantity_fact(quantity),
    do: %{fact(gettext("Quantity"), "quantity", :input, format_quantity(quantity)) | num?: true}

  defp account_label(nil, _accounts), do: "—"

  defp account_label(id, accounts),
    do: Enum.find_value(accounts, "—", fn account -> account.id == id && account.name end)

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
  attr(:focus_return, :string, default: nil)

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
      data-focus-return={@focus_return}
      data-focus-fallback="#transaction-history-heading"
      data-focus-result="[data-role='page-result']"
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
                    "Corrects the booking in place; the derived holdings follow, and the journal records the change."
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
                <%!-- Twins are told apart by their ISIN (the closing act, UAT-13). --%>
                <% twin_tags = SecurityNames.tags(@securities) %>
                <%= for security <- @securities do %>
                  <option
                    value={security.id}
                    selected={to_string(security.id) == @transaction_form["security_id"]}
                  >
                    <%= security.name %><%= if security.ticker_symbol not in [nil, ""], do: " (#{security.ticker_symbol})" %><%= SecurityNames.suffix(twin_tags, security) %>
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

        <%!-- E25 S7, G20; pick G12.2 = B: notes stored before the refusal
             that carry characters the operator cannot see are marked above
             the disclosure that holds them, which then stands open. --%>
        <AppShell.invisible_text_note texts={[@transaction_form["notes"]]}>
          <%= gettext("Typed in anew, it is clean.") %>
        </AppShell.invisible_text_note>

        <%!-- A refused fee or tax opens the costs (#869): an error the reader
             cannot see is no answer. The hook keeps them open, by whoever
             opened them, across the patch each keystroke brings. --%>
        <details
          id="transaction-costs"
          class="transaction-costs"
          phx-hook="DisclosureState"
          open={
            (@form_errors["fees"] || @form_errors["taxes"] ||
               Text.invisible_count(@transaction_form["notes"]) > 0) && true
          }
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
  # One sentence, labelled and joined as the Imports page states a refusal
  # (`PortfolixirWeb.FieldLabel.changeset_message/1`).
  defp changeset_error(changeset), do: FieldLabel.changeset_message(changeset)
end
