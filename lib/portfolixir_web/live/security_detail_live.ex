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
          |> assign(:quote_range, "ALL")
          |> assign(:quote_series, [])
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

        quote_range = "ALL"
        quote_series = quote_series_for_security(security.id, quote_range)
        chart_markers = build_chart_markers(transactions, security.id, params)

        socket =
          socket
          |> assign(:security_not_found, false)
          |> assign(:security, security)
          |> assign(:quote_range, quote_range)
          |> assign(:quote_series, quote_series)
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
          |> assign(:chart_markers, chart_markers)
          |> assign(:position_rows, positions)
          |> assign(:fund_documents, Catalog.list_fund_documents_for_security(security.id))

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("set_quote_range", %{"range" => range}, socket) do
    {:noreply,
     socket
     |> assign(:quote_range, range)
     |> assign(:quote_series, quote_series_for_security(socket.assigns.security.id, range))}
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

          <section id="security-price-chart" class="app-shell-section-card app-shell-workspace-stack" data-priority="secondary">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title"><%= gettext("Price chart") %></h2>
                <p><%= gettext("Stored close quotes with buy/sell/dividend markers.") %></p>
              </div>
            </div>

            <div class="app-shell-toolbar" role="group" aria-label={gettext("Quote range") }>
              <button id="security-price-range-1m" type="button" phx-click="set_quote_range" phx-value-range="1M">1M</button>
              <button id="security-price-range-3m" type="button" phx-click="set_quote_range" phx-value-range="3M">3M</button>
              <button id="security-price-range-6m" type="button" phx-click="set_quote_range" phx-value-range="6M">6M</button>
              <button id="security-price-range-1y" type="button" phx-click="set_quote_range" phx-value-range="1Y">1Y</button>
              <button id="security-price-range-ytd" type="button" phx-click="set_quote_range" phx-value-range="YTD">YTD</button>
              <button id="security-price-range-all" type="button" phx-click="set_quote_range" phx-value-range="ALL">ALL</button>
            </div>

            <%= if Enum.empty?(@quote_series) do %>
              <div id="security-price-chart-empty" class="app-shell-empty-state">
                <h3><%= gettext("No quotes yet") %></h3>
                <p><%= gettext("No stored quotes are available for this security yet.") %></p>
              </div>
            <% else %>
              <div class="app-shell-table-wrapper">
                <div id="security-price-chart-series"><%= Enum.map_join(@quote_series, ",", &Date.to_iso8601(&1.date)) %></div>
                <svg id="security-price-chart-svg" viewBox="0 0 600 220" role="img" aria-label={gettext("Security close price chart")}>
                  <polyline
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    points={chart_points(@quote_series)}
                  />
                  <%= for {marker, index} <- Enum.with_index(@chart_markers) do %>
                    <circle
                      id={"security-chart-marker-#{index}"}
                      cx={marker_chart_x(marker, @quote_series)}
                      cy={marker_chart_y(marker, @quote_series)}
                      r="5"
                      data-type={marker.type}
                      data-date={Date.to_iso8601(marker.date)}
                      data-quantity={decimal_data(marker.quantity)}
                      data-price={decimal_data(marker.price)}
                      data-amount={decimal_data(marker.amount)}
                      data-notes={marker.notes || ""}
                    />
                  <% end %>
                </svg>
              </div>

              <%= if Enum.empty?(@chart_markers) do %>
                <div id="security-chart-markers-empty-state" class="app-shell-empty-state">
                  <h3><%= gettext("No markers in selected range") %></h3>
                  <p><%= gettext("No buy, sell, or dividend markers are available for this selection.") %></p>
                </div>
              <% end %>
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

  defp quote_series_for_security(security_id, "ALL"),
    do: Catalog.list_security_quotes(security_id)

  defp quote_series_for_security(security_id, range) do
    case Catalog.get_latest_security_quote(security_id) do
      nil ->
        []

      %{date: latest_date} ->
        Catalog.list_security_quotes(security_id, from: range_from_date(range, latest_date))
    end
  end

  defp range_from_date("1M", latest_date), do: Date.add(latest_date, -30)
  defp range_from_date("3M", latest_date), do: Date.add(latest_date, -90)
  defp range_from_date("6M", latest_date), do: Date.add(latest_date, -180)
  defp range_from_date("1Y", latest_date), do: Date.add(latest_date, -365)
  defp range_from_date("YTD", latest_date), do: Date.new!(latest_date.year, 1, 1)
  defp range_from_date(_, _latest_date), do: ~D[0001-01-01]

  defp chart_points([single]) do
    close = decimal_to_float(single.close)

    "40,180 560,180"
    |> normalize_single_point(close)
  end

  defp chart_points(series) do
    closes = Enum.map(series, &decimal_to_float(&1.close))
    min_close = Enum.min(closes)
    max_close = Enum.max(closes)
    span = if max_close == min_close, do: 1.0, else: max_close - min_close
    step = if length(series) == 1, do: 0.0, else: 520.0 / (length(series) - 1)

    series
    |> Enum.with_index()
    |> Enum.map(fn {%{close: close}, index} ->
      x = 40.0 + step * index
      y = 180.0 - (decimal_to_float(close) - min_close) / span * 140.0
      "#{Float.round(x, 2)},#{Float.round(y, 2)}"
    end)
    |> Enum.join(" ")
  end

  defp normalize_single_point(points, _close), do: points

  defp marker_chart_x(marker, quote_series) do
    all_dates = Enum.map(quote_series, & &1.date)

    first_date = Enum.min([marker.date | all_dates])
    last_date = Enum.max([marker.date | all_dates])
    total_days = max(Date.diff(last_date, first_date), 1)
    day_offset = Date.diff(marker.date, first_date)

    Float.round(40.0 + day_offset / total_days * 520.0, 2)
  end

  defp marker_chart_y(marker, quote_series) do
    quote_by_date = Map.new(quote_series, &{&1.date, &1.close})

    closes = Enum.map(quote_series, &decimal_to_float(&1.close))
    min_close = Enum.min(closes)
    max_close = Enum.max(closes)
    span = if max_close == min_close, do: 1.0, else: max_close - min_close

    case Map.get(quote_by_date, marker.date) do
      nil ->
        180.0

      close ->
        Float.round(180.0 - (decimal_to_float(close) - min_close) / span * 140.0, 2)
    end
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

  defp decimal_data(nil), do: ""
  defp decimal_data(value), do: Decimal.to_string(value, :normal)

  defp decimal_to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
end
