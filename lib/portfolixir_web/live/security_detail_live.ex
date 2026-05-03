defmodule PortfolixirWeb.SecurityDetailLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @impl true
  def mount(%{"id" => id_param} = params, _session, socket) do
    case Catalog.get_security(id_param) do
      nil ->
        socket =
          socket
          |> assign(:security_not_found, true)
          |> assign(:security, nil)
          |> assign(:position_rows, [])
          |> assign(:transaction_rows, [])

        {:ok, socket}

      security ->
        current_portfolio = Portfolios.first_portfolio()
        deposit_account_names = account_names(current_portfolio, :deposit)
        securities_account_names = account_names(current_portfolio, :securities)

        transactions =
          if current_portfolio do
            Ledger.list_transactions_for_security(current_portfolio.id, security.id)
          else
            []
          end

        positions =
          if current_portfolio do
            Ledger.positions_for_portfolio(current_portfolio.id)
            |> Enum.filter(fn {{_account_id, security_id}, _quantity} ->
              security_id == security.id
            end)
            |> Enum.map(fn {{account_id, _security_id}, quantity} ->
              %{
                securities_account_name: Map.get(securities_account_names, account_id, "—"),
                quantity: quantity
              }
            end)
            |> Enum.sort_by(& &1.securities_account_name)
          else
            []
          end

        socket =
          socket
          |> assign(:security_not_found, false)
          |> assign(:security, security)
          |> assign(
            :transaction_rows,
            Enum.map(transactions, fn transaction ->
              %{
                date: transaction.date,
                type: transaction.type,
                account:
                  account_name(transaction, deposit_account_names, securities_account_names),
                quantity: transaction.quantity,
                price: transaction.price,
                amount: transaction.amount,
                currency_code: transaction.currency_code,
                notes: transaction.notes
              }
            end)
          )
          |> assign(:chart_markers, build_chart_markers(transactions, security.id, params))
          |> assign(:position_rows, positions)
          |> assign(:fund_documents, Catalog.list_fund_documents_for_security(security.id))

        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/securities">
      <%= if @security_not_found do %>
        <header class="app-shell-page-header">
          <div>
            <p class="app-shell-page-kicker"><%= gettext("Securities") %></p>
            <h1><%= gettext("Security not found") %></h1>
          </div>
        </header>

        <section id="security-detail-not-found" class="app-shell-section-card app-shell-empty-state">
          <h2><%= gettext("Security not found") %></h2>
          <p><%= gettext("The selected security does not exist.") %></p>
          <p><a href="/securities"><%= gettext("Back to all securities") %></a></p>
        </section>
      <% end %>

      <%= if !@security_not_found do %>
        <header class="app-shell-page-header">
          <div>
            <p class="app-shell-page-kicker"><%= gettext("Security detail") %></p>
            <h1 id="security-detail-title"><%= @security.name %> (<%= @security.symbol %>)</h1>
          </div>
        </header>

        <div class="app-shell-workspace-grid">
          <section class="app-shell-section-card app-shell-workspace-stack" data-priority="primary">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title"><%= gettext("Master data") %></h2>
                <p><%= gettext("Read-only security information and identifiers.") %></p>
              </div>
            </div>

            <div id="security-master-data" class="app-shell-table-wrapper">
              <table>
                <tbody>
                  <tr>
                    <th><%= gettext("Name") %></th>
                    <td><%= @security.name %></td>
                  </tr>
                  <tr>
                    <th><%= gettext("Symbol") %></th>
                    <td><%= @security.symbol %></td>
                  </tr>
                  <tr>
                    <th>ISIN</th>
                    <td><%= @security.isin || "—" %></td>
                  </tr>
                  <tr>
                    <th>WKN</th>
                    <td><%= @security.wkn || "—" %></td>
                  </tr>
                  <tr>
                    <th><%= gettext("Currency") %></th>
                    <td><%= @security.currency_code %></td>
                  </tr>
                  <tr>
                    <th><%= gettext("Provider symbol") %></th>
                    <td><%= @security.provider_symbol || "—" %></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section id="security-fund-documents" class="app-shell-section-card app-shell-workspace-stack" data-priority="secondary">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title"><%= gettext("Fund documents") %></h2>
                <p><%= gettext("Read-only factsheet attachments for this security.") %></p>
              </div>
            </div>

            <%= if Enum.empty?(@fund_documents) do %>
              <div id="security-fund-documents-empty-state" class="app-shell-empty-state">
                <h3><%= gettext("No factsheets attached yet.") %></h3>
                <p><a href="/documents/new"><%= gettext("Attach a new factsheet") %></a></p>
              </div>
            <% else %>
              <div class="app-shell-table-wrapper">
                <table id="security-fund-document-list">
                  <thead>
                    <tr>
                      <th><%= gettext("Original filename") %></th>
                      <th><%= gettext("Document type") %></th>
                      <th><%= gettext("Source") %></th>
                      <th><%= gettext("Content type") %></th>
                      <th><%= gettext("Extraction status") %></th>
                      <th><%= gettext("Extraction error") %></th>
                      <th><%= gettext("Created") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for document <- @fund_documents do %>
                      <tr>
                        <td>
                          <a href={"/fund-documents/#{document.id}/allocations/review"}>
                            <%= document.original_filename %>
                          </a>
                        </td>
                        <td><%= document.document_type %></td>
                        <td><%= document.source %></td>
                        <td><%= document.content_type %></td>
                        <td><span class="app-shell-badge"><%= document.extraction_status %></span></td>
                        <td><%= document.extraction_error || gettext("—") %></td>
                        <td><%= format_datetime(document.inserted_at) %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </section>

          <section class="app-shell-section-card app-shell-workspace-stack" data-priority="secondary">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title"><%= gettext("Current position") %></h2>
                <p><%= gettext("Derived position per securities account.") %></p>
              </div>
            </div>

            <%= if Enum.empty?(@position_rows) do %>
              <div id="no-security-positions" class="app-shell-empty-state">
                <h3><%= gettext("No positions yet") %></h3>
                <p><%= gettext("No trades for this security in the selected portfolio yet.") %></p>
              </div>
            <% else %>
              <div class="app-shell-table-wrapper">
                <table id="security-position-list">
                  <thead>
                    <tr>
                      <th><%= gettext("Securities account") %></th>
                      <th><%= gettext("Quantity") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for row <- @position_rows do %>
                      <tr>
                        <td><%= row.securities_account_name %></td>
                        <td><%= format_quantity(row.quantity) %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </section>

          <section id="security-transactions-section" class="app-shell-section-card app-shell-workspace-stack" data-priority="secondary">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title"><%= gettext("Transaction history") %></h2>
                <p><%= gettext("Buy, sell and dividend entries for this security.") %></p>
              </div>
            </div>

            <%= if Enum.empty?(@transaction_rows) do %>
              <div id="no-security-transactions" class="app-shell-empty-state">
                <h3><%= gettext("No transactions yet") %></h3>
                <p><%= gettext("No transactions are recorded for this security yet.") %></p>
              </div>
            <% else %>
              <div class="app-shell-table-wrapper">
                <table id="security-transactions">
                  <thead>
                    <tr>
                      <th><%= gettext("Date") %></th>
                      <th><%= gettext("Type") %></th>
                      <th><%= gettext("Account") %></th>
                      <th><%= gettext("Quantity") %></th>
                      <th><%= gettext("Price") %></th>
                      <th><%= gettext("Amount") %></th>
                      <th><%= gettext("Currency") %></th>
                      <th><%= gettext("Notes") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for transaction <- @transaction_rows do %>
                      <tr>
                        <td><%= transaction.date %></td>
                        <td><span class="app-shell-badge"><%= transaction_type_label(transaction.type) %></span></td>
                        <td><%= transaction.account %></td>
                        <td><%= format_quantity(transaction.quantity) %></td>
                        <td><%= format_money(transaction.price) %></td>
                        <td><%= format_money(transaction.amount) %></td>
                        <td><%= transaction.currency_code %></td>
                        <td><%= transaction.notes || "—" %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </section>

          <section id="security-chart-markers" class="app-shell-section-card app-shell-workspace-stack" data-priority="secondary">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title"><%= gettext("Chart markers") %></h2>
                <p><%= gettext("Buy, sell and dividend markers derived from stored transactions.") %></p>
              </div>
            </div>

            <%= if Enum.empty?(@chart_markers) do %>
              <div id="security-chart-markers-empty-state" class="app-shell-empty-state">
                <h3><%= gettext("No markers in selected range") %></h3>
                <p><%= gettext("No buy, sell, or dividend markers are available for this selection.") %></p>
              </div>
            <% else %>
              <div class="app-shell-table-wrapper">
                <table id="security-chart-marker-list">
                  <thead>
                    <tr>
                      <th><%= gettext("Date") %></th>
                      <th><%= gettext("Type") %></th>
                      <th><%= gettext("Quantity") %></th>
                      <th><%= gettext("Price") %></th>
                      <th><%= gettext("Amount") %></th>
                      <th><%= gettext("Notes") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for marker <- @chart_markers do %>
                      <tr>
                        <td><%= marker.date %></td>
                        <td><span class="app-shell-badge"><%= transaction_type_label(marker.type) %></span></td>
                        <td><%= format_quantity(marker.quantity) %></td>
                        <td><%= format_money(marker.price) %></td>
                        <td><%= format_money(marker.amount) %></td>
                        <td><%= marker.notes || "—" %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </section>
        </div>
      <% end %>
    </AppShell.shell>
    """
  end

  defp account_names(nil, _type), do: %{}

  defp account_names(portfolio, :deposit) do
    portfolio
    |> Map.fetch!(:id)
    |> Portfolios.list_deposit_accounts_for_portfolio()
    |> Map.new(&{&1.id, &1.name})
  end

  defp account_names(portfolio, :securities) do
    portfolio
    |> Map.fetch!(:id)
    |> Portfolios.list_securities_accounts_for_portfolio()
    |> Map.new(&{&1.id, &1.name})
  end

  defp account_name(transaction, deposit_account_names, securities_account_names) do
    cond do
      transaction.deposit_account_id ->
        Map.get(deposit_account_names, transaction.deposit_account_id, "—")

      transaction.securities_account_id ->
        Map.get(securities_account_names, transaction.securities_account_id, "—")

      true ->
        "—"
    end
  end

  defp transaction_type_label("buy"), do: gettext("Buy")
  defp transaction_type_label("sell"), do: gettext("Sell")
  defp transaction_type_label("dividend"), do: gettext("Dividend")
  defp transaction_type_label("deposit"), do: gettext("Deposit")
  defp transaction_type_label("withdrawal"), do: gettext("Withdrawal")
  defp transaction_type_label(type), do: type

  defp format_money(nil), do: "—"

  defp format_money(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  defp format_quantity(nil), do: "—"

  defp format_quantity(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_string(datetime)
  defp format_datetime(_), do: gettext("—")

  defp build_chart_markers(transactions, security_id, params) do
    from_date = parse_date(Map.get(params, "from"))
    to_date = parse_date(Map.get(params, "to"))

    transactions
    |> Enum.filter(fn transaction ->
      transaction.security_id == security_id and transaction.type in ["buy", "sell", "dividend"] and
        in_date_range?(transaction.date, from_date, to_date)
    end)
    |> Enum.map(fn transaction ->
      %{
        date: transaction.date,
        type: transaction.type,
        quantity: transaction.quantity,
        price: transaction.price,
        amount: transaction.amount,
        notes: transaction.notes
      }
    end)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  defp parse_date(nil), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp in_date_range?(date, nil, nil), do: not is_nil(date)
  defp in_date_range?(nil, _from_date, _to_date), do: false
  defp in_date_range?(date, from_date, nil), do: Date.compare(date, from_date) != :lt
  defp in_date_range?(date, nil, to_date), do: Date.compare(date, to_date) != :gt

  defp in_date_range?(date, from_date, to_date) do
    Date.compare(date, from_date) != :lt and Date.compare(date, to_date) != :gt
  end
end
