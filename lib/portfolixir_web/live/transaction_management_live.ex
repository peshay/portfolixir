defmodule PortfolixirWeb.TransactionManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

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
     |> load_state()}
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
                    type="date"
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
          </section>
        <% else %>
          <section id="transaction-setup-empty" class="empty-state" role="status">
            <%= gettext("Create a depot and its cash account before recording transactions.") %>
          </section>
        <% end %>

        <div class="transaction-secondary">
        <section id="holdings-panel" class="workspace-section">
          <h2><%= gettext("Current holdings") %></h2>
          <%= if Enum.empty?(@position_rows) do %>
            <div id="no-holdings" class="empty-state" role="status">
              <%= gettext("No holdings yet") %>
            </div>
          <% else %>
            <table id="holdings-table">
              <thead>
                <tr>
                  <th><%= gettext("Depot") %></th>
                  <th><%= gettext("Security") %></th>
                  <th><%= gettext("Quantity") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @position_rows do %>
                  <tr>
                    <td><%= row.securities_account_name %></td>
                    <td><%= row.security_name %></td>
                    <td><%= format_decimal(row.quantity) %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </section>

        <section id="transaction-list-panel" class="workspace-section">
          <h2><%= gettext("Transaction history") %></h2>
          <%= if Enum.empty?(@transactions) do %>
            <div id="no-transactions" class="empty-state" role="status">
              <%= gettext("No transactions yet") %>
            </div>
          <% else %>
            <form id="transaction-filters" phx-change="filter_changed" class="transaction-filters">
              <label>
                <span><%= gettext("Type") %></span>
                <select name="filters[type]">
                  <option value=""><%= gettext("All types") %></option>
                  <%= for type <- filter_type_options(@transactions) do %>
                    <option value={type} selected={@filters["type"] == type}>
                      <%= tx_type_label(type) %>
                    </option>
                  <% end %>
                </select>
              </label>
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
                <input type="date" name="filters[from]" value={@filters["from"]} />
              </label>
              <label>
                <span><%= gettext("To") %></span>
                <input type="date" name="filters[to]" value={@filters["to"]} />
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

            <div id="transaction-summary" class="transaction-summary" role="status">
              <span class="summary-total">
                <strong data-role="summary-total"><%= @summary.total %></strong>
                <%= gettext("transactions") %>
              </span>
              <%= for row <- @summary.by_type do %>
                <span class="summary-type" data-type={row.type}>
                  <%= tx_type_label(row.type) %>:
                  <strong data-role="summary-count"><%= row.count %></strong>
                  · <%= PortfolixirWeb.Format.money(row.total) %>
                </span>
              <% end %>
            </div>

            <%= if Enum.empty?(@filtered_transactions) do %>
              <div id="transaction-no-match" class="empty-state" role="status">
                <%= gettext("No transactions match the current filter.") %>
              </div>
            <% else %>
              <table id="transaction-list">
                <thead>
                  <tr>
                    <th><%= gettext("Date") %></th>
                    <th><%= gettext("Type") %></th>
                    <th><%= gettext("Security") %></th>
                    <th><%= gettext("Quantity") %></th>
                    <th><%= gettext("Price") %></th>
                    <th><%= gettext("Currency") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for group <- grouped_by_month(@filtered_transactions) do %>
                    <tr class="tx-group-head" data-month-group={group.id}>
                      <th colspan="6" scope="colgroup">
                        <span class="tx-group-month"><%= group.label %></span>
                        <span class="tx-group-subtotal">
                          <%= ngettext("%{count} transaction", "%{count} transactions", group.count,
                            count: group.count) %> · <%= format_decimal(group.total) %>
                        </span>
                      </th>
                    </tr>
                    <%= for transaction <- group.transactions do %>
                      <tr>
                        <td><%= transaction.date %></td>
                        <td><%= tx_type_label(transaction.type) %></td>
                        <td><%= transaction.security && transaction.security.name %></td>
                        <td><%= format_decimal(transaction.quantity) %></td>
                        <td><%= format_decimal(transaction.price) %></td>
                        <td><%= transaction.currency_code %></td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
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
    {:noreply, socket |> assign(:transaction_form, params) |> assign(:form_errors, %{})}
  end

  def handle_event("filter_changed", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(:filters, Map.merge(default_filters(), filters))
     |> apply_current_filters()}
  end

  def handle_event("save_transaction", %{"transaction" => params}, socket) do
    # The currency is authoritative from the chosen depot's cash account, never a
    # free-text field the user could mistype (#473).
    currency =
      derived_currency(socket.assigns.securities_accounts, params["securities_account_id"])

    params =
      params
      |> put_portfolio_from_depot(socket.assigns.securities_accounts)
      |> maybe_put_currency(currency)

    case Ledger.create_transaction(Actor.owner_ui(), params) do
      {:ok, _transaction} ->
        {:noreply,
         socket
         |> assign(:transaction_form, @transaction_form)
         |> assign(:form_errors, %{})
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
    transactions = Ledger.list_transactions()

    position_rows =
      Portfolios.list_portfolios()
      |> Enum.flat_map(&Map.to_list(Ledger.positions_for_portfolio(&1.id)))
      |> position_rows(securities_accounts, securities)

    socket
    |> assign(
      securities_accounts: securities_accounts,
      securities: securities,
      transactions: transactions,
      position_rows: position_rows
    )
    |> apply_current_filters()
  end

  # The overview filters (#414) run in memory over the already-loaded history:
  # the local ledger is bounded, so a client-side narrow is instant and keeps
  # the query path simple. The summary always reflects the current filter.
  defp default_filters,
    do: %{"type" => "", "security_id" => "", "from" => "", "to" => "", "query" => ""}

  defp apply_current_filters(socket) do
    filters = Map.merge(default_filters(), socket.assigns[:filters] || %{})
    filtered = filter_transactions(socket.assigns.transactions, filters)

    assign(socket,
      filters: filters,
      filtered_transactions: filtered,
      summary: summarise(filtered)
    )
  end

  defp filter_transactions(transactions, filters) do
    transactions
    |> Enum.filter(&type_match?(&1, filters["type"]))
    |> Enum.filter(&security_match?(&1, filters["security_id"]))
    |> Enum.filter(&from_match?(&1, filters["from"]))
    |> Enum.filter(&to_match?(&1, filters["to"]))
    |> Enum.filter(&query_match?(&1, filters["query"]))
  end

  defp type_match?(_tx, blank) when blank in ["", nil], do: true
  defp type_match?(tx, type), do: tx.type == type

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
        total: sum_amount(chunk)
      }
    end)
  end

  defp month_group_id(date) do
    "#{date.year}-#{date.month |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp month_group_label(date) do
    {:ok, first_of_month} = Date.new(date.year, date.month, 1)
    Calendar.strftime(first_of_month, "%B %Y")
  end

  defp summarise(transactions) do
    by_type =
      transactions
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, list} ->
        %{type: type, count: length(list), total: sum_amount(list)}
      end)
      |> Enum.sort_by(& &1.type)

    %{total: length(transactions), by_type: by_type}
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

  defp position_rows(positions, securities_accounts, securities) do
    securities_account_names = Map.new(securities_accounts, &{&1.id, &1.name})
    security_names = Map.new(securities, &{&1.id, "#{&1.name} (#{&1.ticker_symbol})"})

    positions
    |> Enum.map(fn {{securities_account_id, security_id}, quantity} ->
      %{
        securities_account_name:
          Map.get(securities_account_names, securities_account_id, gettext("Unknown depot")),
        security_name: Map.get(security_names, security_id, gettext("Unknown security")),
        quantity: quantity
      }
    end)
    |> Enum.sort_by(fn row -> {row.securities_account_name, row.security_name} end)
  end

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
  defp tx_type_label(other), do: to_string(other)

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
  defp field_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Map.new(fn {field, messages} -> {to_string(field), Enum.join(messages, ", ")} end)
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

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
